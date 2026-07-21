import Foundation

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
        try securityScopedAccess.withAccess(to: sourceURL) {
            let workspaceURL = temporaryDirectoryURL
                .appendingPathComponent("MonglePetImport-\(UUID().uuidString)", isDirectory: true)
            try createWorkspace(at: workspaceURL)
            defer {
                try? fileManager.removeItem(at: workspaceURL)
            }

            let packageRootURL: URL
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                packageRootURL = sourceURL
            } else {
                packageRootURL = try archiveExtractor.extractArchive(
                    at: sourceURL,
                    into: workspaceURL
                )
            }

            let validatedPackage = try loader.loadPackage(at: packageRootURL)
            return try libraryStore.install(
                packageAt: packageRootURL,
                validatedPackage: validatedPackage,
                mode: mode
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
}
