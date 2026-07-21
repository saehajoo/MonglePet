import Foundation

nonisolated enum PetPackageInstallationMode: Equatable, Sendable {
    case rejectDuplicate
    case installSeparately
    case replace(installationID: UUID)
}

nonisolated struct InstalledPetPackage: Equatable, Sendable {
    let installationID: UUID
    let rootURL: URL
    let package: LoadedPetPackage
}

nonisolated enum PetLibraryError: Error, Equatable, Sendable {
    case unavailableApplicationSupport
    case duplicatePackage(packageID: String, installationIDs: [UUID])
    case missingInstallation(UUID)
    case packageIdentifierMismatch(expected: String, actual: String)
    case stagingValidationFailed(PetPackageLoadingError)
    case fileOperationFailed
}

extension PetLibraryError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unavailableApplicationSupport:
            "Application Support 경로를 찾을 수 없습니다."
        case let .duplicatePackage(packageID, _):
            "같은 패키지가 이미 설치되어 있습니다: \(packageID)"
        case let .missingInstallation(installationID):
            "교체할 설치 항목을 찾을 수 없습니다: \(installationID.uuidString)"
        case let .packageIdentifierMismatch(expected, actual):
            "다른 펫 패키지로 기존 설치를 교체할 수 없습니다: \(expected), \(actual)"
        case let .stagingValidationFailed(error):
            "복사된 패키지 검증에 실패했습니다: \(error.localizedDescription)"
        case .fileOperationFailed:
            "펫 라이브러리 파일 작업을 완료하지 못했습니다."
        }
    }
}

nonisolated struct PetLibraryStore {
    let libraryRootURL: URL

    private let loader: PetPackageLoader
    private let fileManager: FileManager
    private let installationIDGenerator: () -> UUID

    init(
        libraryRootURL: URL,
        loader: PetPackageLoader = PetPackageLoader(),
        fileManager: FileManager = .default,
        installationIDGenerator: @escaping () -> UUID = UUID.init
    ) {
        self.libraryRootURL = libraryRootURL
        self.loader = loader
        self.fileManager = fileManager
        self.installationIDGenerator = installationIDGenerator
    }

    static func defaultLibraryRootURL(fileManager: FileManager = .default) throws -> URL {
        guard let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw PetLibraryError.unavailableApplicationSupport
        }
        return applicationSupportURL
            .appendingPathComponent("MonglePet", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
    }

    func install(
        packageAt sourcePackageURL: URL,
        validatedPackage: LoadedPetPackage,
        mode: PetPackageInstallationMode
    ) throws -> InstalledPetPackage {
        try createLibraryIfNeeded()
        let matchingInstallations = installedPackages()
            .filter { $0.package.metadata.id == validatedPackage.metadata.id }
            .sorted { $0.installationID.uuidString < $1.installationID.uuidString }

        let installationID: UUID
        switch mode {
        case .rejectDuplicate:
            guard matchingInstallations.isEmpty else {
                throw PetLibraryError.duplicatePackage(
                    packageID: validatedPackage.metadata.id,
                    installationIDs: matchingInstallations.map(\.installationID)
                )
            }
            installationID = installationIDGenerator()
        case .installSeparately:
            installationID = installationIDGenerator()
        case let .replace(requestedInstallationID):
            let existing = try installedPackage(installationID: requestedInstallationID)
            guard existing.package.metadata.id == validatedPackage.metadata.id else {
                throw PetLibraryError.packageIdentifierMismatch(
                    expected: existing.package.metadata.id,
                    actual: validatedPackage.metadata.id
                )
            }
            installationID = requestedInstallationID
        }

        let destinationURL = libraryRootURL
            .appendingPathComponent(installationID.uuidString, isDirectory: true)
        let stagingURL = libraryRootURL
            .appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        defer {
            if fileManager.fileExists(atPath: stagingURL.path) {
                try? fileManager.removeItem(at: stagingURL)
            }
        }

        do {
            try fileManager.copyItem(at: sourcePackageURL, to: stagingURL)
        } catch {
            throw PetLibraryError.fileOperationFailed
        }

        do {
            let stagedPackage = try loader.loadPackage(at: stagingURL)
            guard stagedPackage.metadata.id == validatedPackage.metadata.id else {
                throw PetLibraryError.packageIdentifierMismatch(
                    expected: validatedPackage.metadata.id,
                    actual: stagedPackage.metadata.id
                )
            }
        } catch let error as PetLibraryError {
            throw error
        } catch let error as PetPackageLoadingError {
            throw PetLibraryError.stagingValidationFailed(error)
        } catch {
            throw PetLibraryError.fileOperationFailed
        }

        let replacementBackupURL: URL?
        switch mode {
        case .replace:
            replacementBackupURL = try replaceItem(at: destinationURL, with: stagingURL)
        case .rejectDuplicate, .installSeparately:
            replacementBackupURL = nil
            guard !fileManager.fileExists(atPath: destinationURL.path) else {
                throw PetLibraryError.fileOperationFailed
            }
            do {
                try fileManager.moveItem(at: stagingURL, to: destinationURL)
            } catch {
                throw PetLibraryError.fileOperationFailed
            }
        }

        do {
            let installedPackage = try loader.loadPackage(at: destinationURL)
            if let replacementBackupURL {
                try? fileManager.removeItem(at: replacementBackupURL)
            }
            return InstalledPetPackage(
                installationID: installationID,
                rootURL: destinationURL,
                package: installedPackage
            )
        } catch let error as PetPackageLoadingError {
            rollbackInstallation(
                destinationURL: destinationURL,
                replacementBackupURL: replacementBackupURL
            )
            throw PetLibraryError.stagingValidationFailed(error)
        } catch {
            rollbackInstallation(
                destinationURL: destinationURL,
                replacementBackupURL: replacementBackupURL
            )
            throw PetLibraryError.fileOperationFailed
        }
    }

    func installedPackages() -> [InstalledPetPackage] {
        guard let children = try? fileManager.contentsOfDirectory(
            at: libraryRootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return children.compactMap { childURL in
            guard
                let installationID = UUID(uuidString: childURL.lastPathComponent),
                (try? childURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                let package = try? loader.loadPackage(at: childURL)
            else {
                return nil
            }
            return InstalledPetPackage(
                installationID: installationID,
                rootURL: childURL,
                package: package
            )
        }
    }

    private func installedPackage(installationID: UUID) throws -> InstalledPetPackage {
        guard let installed = installedPackages().first(where: {
            $0.installationID == installationID
        }) else {
            throw PetLibraryError.missingInstallation(installationID)
        }
        return installed
    }

    private func createLibraryIfNeeded() throws {
        do {
            try fileManager.createDirectory(
                at: libraryRootURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw PetLibraryError.fileOperationFailed
        }
    }

    private func replaceItem(at destinationURL: URL, with stagingURL: URL) throws -> URL {
        guard let installationID = UUID(uuidString: destinationURL.lastPathComponent) else {
            throw PetLibraryError.fileOperationFailed
        }
        guard fileManager.fileExists(atPath: destinationURL.path) else {
            throw PetLibraryError.missingInstallation(installationID)
        }
        let backupName = ".backup-\(UUID().uuidString)"
        let backupURL = libraryRootURL.appendingPathComponent(backupName, isDirectory: true)
        do {
            _ = try fileManager.replaceItemAt(
                destinationURL,
                withItemAt: stagingURL,
                backupItemName: backupName,
                options: []
            )
            return backupURL
        } catch {
            throw PetLibraryError.fileOperationFailed
        }
    }

    private func rollbackInstallation(
        destinationURL: URL,
        replacementBackupURL: URL?
    ) {
        guard let replacementBackupURL else {
            try? fileManager.removeItem(at: destinationURL)
            return
        }
        guard fileManager.fileExists(atPath: replacementBackupURL.path) else {
            return
        }
        _ = try? fileManager.replaceItemAt(
            destinationURL,
            withItemAt: replacementBackupURL
        )
    }
}
