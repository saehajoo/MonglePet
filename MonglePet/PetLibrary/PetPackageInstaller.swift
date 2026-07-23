import Foundation

nonisolated struct PetPackageImportReview: Equatable, Identifiable, Sendable {
    let sourceURL: URL
    let metadata: PetPackageMetadata
    let definition: PetDefinition
    let containsRecommendedProfile: Bool
    let recommendedProfile: RecommendedPetProfile?
    let recommendedProfileIssue: RecommendedPetProfileError?

    var id: URL {
        sourceURL
    }

    var applicationBundleIdentifiers: [String] {
        guard let recommendedProfile else {
            return []
        }
        return Array(
            Set(
                recommendedProfile.automaticRules.compactMap { rule in
                    if case let .application(bundleIdentifier) = rule.condition {
                        return bundleIdentifier
                    }
                    return nil
                }
            )
        ).sorted()
    }

    func hasSameReviewedContent(as other: PetPackageImportReview) -> Bool {
        metadata == other.metadata
            && definition == other.definition
            && containsRecommendedProfile == other.containsRecommendedProfile
            && recommendedProfile == other.recommendedProfile
            && recommendedProfileIssue == other.recommendedProfileIssue
    }
}

nonisolated struct PetPackageInstallationResult: Equatable, Sendable {
    let installedPackage: InstalledPetPackage
    let importReview: PetPackageImportReview
}

nonisolated enum PetPackageImportError: Error, Equatable, Sendable {
    case recommendedProfileFileTooLarge
    case recommendedProfileUnavailable
    case reviewedContentChanged
}

extension PetPackageImportError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .recommendedProfileFileTooLarge:
            "권장 설정 파일이 1 MiB 보안 제한을 초과하여 패키지를 가져올 수 없습니다."
        case .recommendedProfileUnavailable:
            "이 패키지의 권장 설정은 적용할 수 없습니다. 펫만 설치해 주세요."
        case .reviewedContentChanged:
            "확인한 뒤 패키지 내용이 변경되었습니다. 다시 가져와 내용을 확인해 주세요."
        }
    }
}

nonisolated struct PetPackageInstaller {
    private let loader: PetPackageLoader
    private let archiveExtractor: PetPackageArchiveExtractor
    private let libraryStore: PetLibraryStore
    private let securityScopedAccess: SecurityScopedResourceAccess
    private let fileManager: FileManager
    private let temporaryDirectoryURL: URL

    init(
        loader: PetPackageLoader = PetPackageLoader(),
        archiveExtractor: PetPackageArchiveExtractor = PetPackageArchiveExtractor(),
        libraryStore: PetLibraryStore,
        securityScopedAccess: SecurityScopedResourceAccess = SecurityScopedResourceAccess(),
        fileManager: FileManager = .default,
        temporaryDirectoryURL: URL? = nil
    ) {
        self.loader = loader
        self.archiveExtractor = archiveExtractor
        self.libraryStore = libraryStore
        self.securityScopedAccess = securityScopedAccess
        self.fileManager = fileManager
        self.temporaryDirectoryURL = temporaryDirectoryURL ?? fileManager.temporaryDirectory
    }

    func install(
        from sourceURL: URL,
        mode: PetPackageInstallationMode = .rejectDuplicate
    ) throws -> InstalledPetPackage {
        try installReviewed(
            from: sourceURL,
            mode: mode,
            expectedReview: nil
        ).installedPackage
    }

    func review(from sourceURL: URL) throws -> PetPackageImportReview {
        try securityScopedAccess.withAccess(to: sourceURL) {
            try withPreparedPackage(from: sourceURL) { packageRootURL in
                let package = try loader.loadPackage(at: packageRootURL)
                return try makeReview(
                    sourceURL: sourceURL,
                    packageRootURL: packageRootURL,
                    package: package
                )
            }
        }
    }

    func installReviewed(
        from sourceURL: URL,
        mode: PetPackageInstallationMode,
        expectedReview: PetPackageImportReview?
    ) throws -> PetPackageInstallationResult {
        try securityScopedAccess.withAccess(to: sourceURL) {
            try withPreparedPackage(from: sourceURL) { packageRootURL in
                let validatedPackage = try loader.loadPackage(at: packageRootURL)
                let currentReview = try makeReview(
                    sourceURL: sourceURL,
                    packageRootURL: packageRootURL,
                    package: validatedPackage
                )
                if let expectedReview,
                   !currentReview.hasSameReviewedContent(as: expectedReview) {
                    throw PetPackageImportError.reviewedContentChanged
                }

                let installedPackage = try libraryStore.install(
                    packageAt: packageRootURL,
                    validatedPackage: validatedPackage,
                    mode: mode
                )
                return PetPackageInstallationResult(
                    installedPackage: installedPackage,
                    importReview: currentReview
                )
            }
        }
    }

    private func withPreparedPackage<Result>(
        from sourceURL: URL,
        operation: (URL) throws -> Result
    ) throws -> Result {
        let workspaceURL = temporaryDirectoryURL
            .appendingPathComponent(
                "MonglePetImport-\(UUID().uuidString)",
                isDirectory: true
            )
        try createWorkspace(at: workspaceURL)
        defer {
            try? fileManager.removeItem(at: workspaceURL)
        }

        let packageRootURL: URL
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            packageRootURL = workspaceURL.appendingPathComponent(
                "Imported.monglepet",
                isDirectory: true
            )
            do {
                try fileManager.copyItem(at: sourceURL, to: packageRootURL)
            } catch {
                throw PetLibraryError.fileOperationFailed
            }
        } else {
            packageRootURL = try archiveExtractor.extractArchive(
                at: sourceURL,
                into: workspaceURL
            )
        }

        try removeEditingMarker(from: packageRootURL)
        return try operation(packageRootURL)
    }

    private func makeReview(
        sourceURL: URL,
        packageRootURL: URL,
        package: LoadedPetPackage
    ) throws -> PetPackageImportReview {
        let profileURL = packageRootURL.appendingPathComponent(
            "recommended-profile.json",
            isDirectory: false
        )
        guard fileManager.fileExists(atPath: profileURL.path) else {
            return PetPackageImportReview(
                sourceURL: sourceURL,
                metadata: package.metadata,
                definition: package.definition,
                containsRecommendedProfile: false,
                recommendedProfile: nil,
                recommendedProfileIssue: nil
            )
        }

        let fileSize: Int
        do {
            fileSize = try profileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        } catch {
            throw PetLibraryError.fileOperationFailed
        }
        guard fileSize <= RecommendedPetProfileCodec.maximumFileSize else {
            throw PetPackageImportError.recommendedProfileFileTooLarge
        }

        let data: Data
        do {
            data = try Data(contentsOf: profileURL, options: .mappedIfSafe)
        } catch {
            return PetPackageImportReview(
                sourceURL: sourceURL,
                metadata: package.metadata,
                definition: package.definition,
                containsRecommendedProfile: true,
                recommendedProfile: nil,
                recommendedProfileIssue: .unreadable
            )
        }

        do {
            return PetPackageImportReview(
                sourceURL: sourceURL,
                metadata: package.metadata,
                definition: package.definition,
                containsRecommendedProfile: true,
                recommendedProfile: try RecommendedPetProfileCodec.decode(
                    data,
                    for: package.definition
                ),
                recommendedProfileIssue: nil
            )
        } catch let error as RecommendedPetProfileError {
            if error == .fileTooLarge {
                throw PetPackageImportError.recommendedProfileFileTooLarge
            }
            return PetPackageImportReview(
                sourceURL: sourceURL,
                metadata: package.metadata,
                definition: package.definition,
                containsRecommendedProfile: true,
                recommendedProfile: nil,
                recommendedProfileIssue: error
            )
        }
    }

    private func createWorkspace(at workspaceURL: URL) throws {
        do {
            try fileManager.createDirectory(
                at: workspaceURL,
                withIntermediateDirectories: false
            )
        } catch {
            throw PetLibraryError.fileOperationFailed
        }
    }

    private func removeEditingMarker(from packageRootURL: URL) throws {
        let markerURL = packageRootURL.appendingPathComponent(
            UserPetPackageEditor.markerFileName,
            isDirectory: false
        )
        guard fileManager.fileExists(atPath: markerURL.path) else {
            return
        }
        do {
            try fileManager.removeItem(at: markerURL)
        } catch {
            throw PetLibraryError.fileOperationFailed
        }
    }
}
