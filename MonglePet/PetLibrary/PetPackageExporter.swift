import Foundation
import ZIPFoundation

nonisolated enum PetPackageExportError: Error, Equatable, Sendable {
    case invalidDestination
    case sourcePackageChanged
    case packageValidationFailed(PetPackageLoadingError)
    case recommendedProfileInvalid(RecommendedPetProfileError)
    case archiveValidationFailed(PetPackageArchiveError)
    case archiveTooLarge
    case fileOperationFailed
}

extension PetPackageExportError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidDestination:
            "내보내기 위치는 심볼릭 링크가 아닌 `.monglepet` 파일이어야 합니다."
        case .sourcePackageChanged:
            "설치된 펫이 변경되어 내보내기를 안전하게 완료할 수 없습니다."
        case let .packageValidationFailed(error):
            "내보내기 전 펫 패키지 검증에 실패했습니다: \(error.localizedDescription)"
        case let .recommendedProfileInvalid(error):
            "함께 공유할 권장 설정을 검증하지 못했습니다: \(error.localizedDescription)"
        case let .archiveValidationFailed(error):
            "만든 공유 패키지 검증에 실패했습니다: \(error.localizedDescription)"
        case .archiveTooLarge:
            "만든 공유 패키지가 20 MiB 제한을 초과합니다."
        case .fileOperationFailed:
            "펫 공유 파일을 저장하지 못했습니다."
        }
    }
}

nonisolated struct PetPackageExporter {
    private let loader: PetPackageLoader
    private let archiveExtractor: PetPackageArchiveExtractor
    private let archiveLimits: PetPackageArchiveLimits
    private let securityScopedAccess: SecurityScopedResourceAccess
    private let fileManager: FileManager
    private let temporaryDirectoryURL: URL

    init(
        loader: PetPackageLoader = PetPackageLoader(),
        archiveLimits: PetPackageArchiveLimits = .standard,
        securityScopedAccess: SecurityScopedResourceAccess = SecurityScopedResourceAccess(),
        fileManager: FileManager = .default,
        temporaryDirectoryURL: URL? = nil
    ) {
        self.loader = loader
        self.archiveLimits = archiveLimits
        archiveExtractor = PetPackageArchiveExtractor(
            limits: archiveLimits,
            fileManager: fileManager
        )
        self.securityScopedAccess = securityScopedAccess
        self.fileManager = fileManager
        self.temporaryDirectoryURL = temporaryDirectoryURL
            ?? fileManager.temporaryDirectory
    }

    @discardableResult
    func export(
        _ installedPackage: InstalledPetPackage,
        recommendedProfile: RecommendedPetProfile? = nil,
        to destinationURL: URL
    ) throws -> URL {
        try validateDestination(destinationURL)

        return try securityScopedAccess.withAccess(to: destinationURL) {
            let workspaceURL = temporaryDirectoryURL.appendingPathComponent(
                "MonglePetExport-\(UUID().uuidString)",
                isDirectory: true
            )
            try createDirectory(at: workspaceURL)
            defer {
                try? fileManager.removeItem(at: workspaceURL)
            }

            let sourcePackage = try loadPackage(at: installedPackage.rootURL)
            guard
                sourcePackage.metadata == installedPackage.package.metadata,
                sourcePackage.definition == installedPackage.package.definition
            else {
                throw PetPackageExportError.sourcePackageChanged
            }

            let payloadURL = workspaceURL.appendingPathComponent(
                "payload.monglepet",
                isDirectory: true
            )
            try createDirectory(at: payloadURL)
            try createSanitizedPackage(
                from: sourcePackage,
                recommendedProfile: recommendedProfile,
                at: payloadURL
            )

            let sanitizedPackage = try loadPackage(at: payloadURL)
            guard
                sanitizedPackage.metadata == sourcePackage.metadata,
                sanitizedPackage.definition == sourcePackage.definition
            else {
                throw PetPackageExportError.sourcePackageChanged
            }

            let archiveURL = workspaceURL.appendingPathComponent(
                "export.monglepet",
                isDirectory: false
            )
            do {
                try fileManager.zipItem(
                    at: payloadURL,
                    to: archiveURL,
                    shouldKeepParent: false,
                    compressionMethod: .deflate
                )
            } catch {
                throw PetPackageExportError.fileOperationFailed
            }
            try validateArchiveSize(at: archiveURL)
            try validateArchiveRoundTrip(
                at: archiveURL,
                expectedPackage: sanitizedPackage,
                expectedRecommendedProfile: recommendedProfile,
                workspaceURL: workspaceURL
            )
            try writeArchiveAtomically(
                at: archiveURL,
                to: destinationURL
            )
            return destinationURL
        }
    }

    private func createSanitizedPackage(
        from sourcePackage: LoadedPetPackage,
        recommendedProfile: RecommendedPetProfile?,
        at destinationRootURL: URL
    ) throws {
        let sourceManifestURL = sourcePackage.packageRootURL.appendingPathComponent(
            "pet.json",
            isDirectory: false
        )
        let manifest: PetPackageManifest
        do {
            manifest = try JSONDecoder().decode(
                PetPackageManifest.self,
                from: Data(contentsOf: sourceManifestURL)
            )
        } catch {
            throw PetPackageExportError.sourcePackageChanged
        }

        let manifestData: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [
                .prettyPrinted,
                .sortedKeys,
                .withoutEscapingSlashes
            ]
            manifestData = try encoder.encode(manifest)
        } catch {
            throw PetPackageExportError.fileOperationFailed
        }
        try write(
            manifestData,
            to: destinationRootURL.appendingPathComponent("pet.json")
        )
        try copyFile(
            at: sourcePackage.previewURL,
            toRelativePath: manifest.previewPath,
            in: destinationRootURL
        )

        let resourcesByID = Dictionary(
            uniqueKeysWithValues: sourcePackage.atlases.map { ($0.id, $0) }
        )
        for atlas in manifest.atlases {
            guard let resource = resourcesByID[atlas.id] else {
                throw PetPackageExportError.sourcePackageChanged
            }
            try copyFile(
                at: resource.fileURL,
                toRelativePath: atlas.path,
                in: destinationRootURL
            )
        }

        if let recommendedProfile {
            let profileData: Data
            do {
                profileData = try RecommendedPetProfileCodec.encode(
                    recommendedProfile,
                    for: sourcePackage.definition
                )
            } catch let error as RecommendedPetProfileError {
                throw PetPackageExportError.recommendedProfileInvalid(error)
            } catch {
                throw PetPackageExportError.fileOperationFailed
            }
            try write(
                profileData,
                to: destinationRootURL.appendingPathComponent(
                    "recommended-profile.json",
                    isDirectory: false
                )
            )
        }
    }

    private func validateArchiveRoundTrip(
        at archiveURL: URL,
        expectedPackage: LoadedPetPackage,
        expectedRecommendedProfile: RecommendedPetProfile?,
        workspaceURL: URL
    ) throws {
        let verificationURL = workspaceURL.appendingPathComponent(
            "verification",
            isDirectory: true
        )
        try createDirectory(at: verificationURL)
        let extractedRootURL: URL
        do {
            extractedRootURL = try archiveExtractor.extractArchive(
                at: archiveURL,
                into: verificationURL
            )
        } catch let error as PetPackageArchiveError {
            throw PetPackageExportError.archiveValidationFailed(error)
        } catch {
            throw PetPackageExportError.fileOperationFailed
        }

        let roundTrippedPackage = try loadPackage(at: extractedRootURL)
        guard
            roundTrippedPackage.metadata == expectedPackage.metadata,
            roundTrippedPackage.definition == expectedPackage.definition
        else {
            throw PetPackageExportError.sourcePackageChanged
        }
        try validateRecommendedProfileRoundTrip(
            at: extractedRootURL,
            definition: roundTrippedPackage.definition,
            expected: expectedRecommendedProfile
        )
    }

    private func validateRecommendedProfileRoundTrip(
        at packageRootURL: URL,
        definition: PetDefinition,
        expected: RecommendedPetProfile?
    ) throws {
        let profileURL = packageRootURL.appendingPathComponent(
            "recommended-profile.json",
            isDirectory: false
        )
        guard let expected else {
            guard !fileManager.fileExists(atPath: profileURL.path) else {
                throw PetPackageExportError.sourcePackageChanged
            }
            return
        }

        let data: Data
        do {
            data = try Data(contentsOf: profileURL, options: .mappedIfSafe)
        } catch {
            throw PetPackageExportError.sourcePackageChanged
        }
        let decoded: RecommendedPetProfile
        do {
            decoded = try RecommendedPetProfileCodec.decode(
                data,
                for: definition
            )
        } catch let error as RecommendedPetProfileError {
            throw PetPackageExportError.recommendedProfileInvalid(error)
        } catch {
            throw PetPackageExportError.fileOperationFailed
        }
        guard decoded == expected else {
            throw PetPackageExportError.sourcePackageChanged
        }
    }

    private func loadPackage(at rootURL: URL) throws -> LoadedPetPackage {
        do {
            return try loader.loadPackage(at: rootURL)
        } catch let error as PetPackageLoadingError {
            throw PetPackageExportError.packageValidationFailed(error)
        } catch {
            throw PetPackageExportError.fileOperationFailed
        }
    }

    private func validateDestination(_ destinationURL: URL) throws {
        guard destinationURL.pathExtension.lowercased() == "monglepet" else {
            throw PetPackageExportError.invalidDestination
        }
        guard fileManager.fileExists(atPath: destinationURL.path) else {
            return
        }
        do {
            let values = try destinationURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard
                values.isRegularFile == true,
                values.isSymbolicLink != true
            else {
                throw PetPackageExportError.invalidDestination
            }
        } catch let error as PetPackageExportError {
            throw error
        } catch {
            throw PetPackageExportError.invalidDestination
        }
    }

    private func validateArchiveSize(at archiveURL: URL) throws {
        do {
            let byteCount = UInt64(
                try archiveURL.resourceValues(forKeys: [.fileSizeKey])
                    .fileSize ?? 0
            )
            guard byteCount <= archiveLimits.maximumArchiveByteCount else {
                throw PetPackageExportError.archiveTooLarge
            }
        } catch let error as PetPackageExportError {
            throw error
        } catch {
            throw PetPackageExportError.fileOperationFailed
        }
    }

    private func writeArchiveAtomically(
        at archiveURL: URL,
        to destinationURL: URL
    ) throws {
        try validateDestination(destinationURL)
        do {
            try Data(contentsOf: archiveURL).write(
                to: destinationURL,
                options: .atomic
            )
        } catch {
            throw PetPackageExportError.fileOperationFailed
        }
    }

    private func copyFile(
        at sourceURL: URL,
        toRelativePath relativePath: String,
        in destinationRootURL: URL
    ) throws {
        let destinationURL = destinationRootURL.appendingPathComponent(
            relativePath,
            isDirectory: false
        )
        try createDirectory(at: destinationURL.deletingLastPathComponent())
        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            throw PetPackageExportError.fileOperationFailed
        }
    }

    private func write(_ data: Data, to destinationURL: URL) throws {
        do {
            try data.write(to: destinationURL, options: .atomic)
        } catch {
            throw PetPackageExportError.fileOperationFailed
        }
    }

    private func createDirectory(at directoryURL: URL) throws {
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw PetPackageExportError.fileOperationFailed
        }
    }
}
