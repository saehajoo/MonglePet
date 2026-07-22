import Combine
import Foundation

nonisolated enum PetLibrarySelection: Hashable, Sendable {
    case builtIn
    case installed(UUID)

    var installationID: UUID? {
        switch self {
        case .builtIn:
            nil
        case let .installed(installationID):
            installationID
        }
    }
}

nonisolated struct PetLibraryItem: Equatable, Identifiable, Sendable {
    let selection: PetLibrarySelection
    let metadata: PetPackageMetadata
    let previewURL: URL?
    let definition: PetDefinition
    let installedPackage: InstalledPetPackage?
    let isEditable: Bool

    init(
        selection: PetLibrarySelection,
        metadata: PetPackageMetadata,
        previewURL: URL?,
        definition: PetDefinition,
        installedPackage: InstalledPetPackage?,
        isEditable: Bool = false
    ) {
        self.selection = selection
        self.metadata = metadata
        self.previewURL = previewURL
        self.definition = definition
        self.installedPackage = installedPackage
        self.isEditable = isEditable
    }

    var id: PetLibrarySelection {
        selection
    }

    var isBuiltIn: Bool {
        selection == .builtIn
    }
}

nonisolated struct DuplicatePetInstallRequest: Equatable, Identifiable, Sendable {
    let sourceURL: URL
    let packageID: String
    let installationIDs: [UUID]

    var id: URL {
        sourceURL
    }

    var replacementInstallationID: UUID? {
        installationIDs.first
    }
}

@MainActor
final class PetLibrarySession: ObservableObject {
    @Published private(set) var items: [PetLibraryItem]
    @Published private(set) var selection: PetLibrarySelection = .builtIn
    @Published private(set) var errorMessage: String?
    @Published private(set) var duplicateInstallRequest: DuplicatePetInstallRequest?
    @Published private(set) var isImporting = false

    var onSelectionChange: ((PetLibraryItem) -> Void)?

    private let builtInItem: PetLibraryItem
    private let installedPackagesProvider: () -> [InstalledPetPackage]
    private let installationRemover: (UUID) throws -> Void
    private let packageInstaller: (URL, PetPackageInstallationMode) throws
        -> InstalledPetPackage
    private let editablePackageProvider: (InstalledPetPackage) -> Bool
    private let userPetCreator: (UserPetCreationRequest) throws -> InstalledPetPackage
    private let animationAdder: (
        UserPetAnimationRequest,
        InstalledPetPackage
    ) throws -> InstalledPetPackage
    private let detailsUpdater: (
        UserPetDetailsRequest,
        InstalledPetPackage
    ) throws -> InstalledPetPackage

    convenience init(
        store: PetLibraryStore,
        builtInDefinition: PetDefinition
    ) {
        let editor = UserPetPackageEditor(store: store)
        self.init(
            builtInDefinition: builtInDefinition,
            installedPackagesProvider: store.installedPackages,
            installationRemover: store.removeInstallation,
            packageInstaller: PetPackageInstaller(libraryStore: store).install,
            editablePackageProvider: editor.isEditable,
            userPetCreator: editor.createPet,
            animationAdder: editor.addAnimation,
            detailsUpdater: editor.updateDetails
        )
    }

    init(
        builtInDefinition: PetDefinition,
        installedPackagesProvider: @escaping () -> [InstalledPetPackage],
        installationRemover: @escaping (UUID) throws -> Void,
        packageInstaller: @escaping (
            URL,
            PetPackageInstallationMode
        ) throws -> InstalledPetPackage = { _, _ in
            throw PetLibraryError.fileOperationFailed
        },
        editablePackageProvider: @escaping (InstalledPetPackage) -> Bool = { _ in false },
        userPetCreator: @escaping (UserPetCreationRequest) throws
            -> InstalledPetPackage = { _ in
                throw PetLibraryError.fileOperationFailed
            },
        animationAdder: @escaping (
            UserPetAnimationRequest,
            InstalledPetPackage
        ) throws -> InstalledPetPackage = { _, _ in
            throw PetLibraryError.fileOperationFailed
        },
        detailsUpdater: @escaping (
            UserPetDetailsRequest,
            InstalledPetPackage
        ) throws -> InstalledPetPackage = { _, _ in
            throw PetLibraryError.fileOperationFailed
        }
    ) {
        let builtInItem = PetLibraryItem(
            selection: .builtIn,
            metadata: PetPackageMetadata(
                id: builtInDefinition.id,
                displayName: builtInDefinition.displayName,
                version: "내장",
                author: "MonglePet",
                license: "Bundled with MonglePet",
                description: "MonglePet에 기본으로 포함된 펫입니다."
            ),
            previewURL: nil,
            definition: builtInDefinition,
            installedPackage: nil
        )
        self.builtInItem = builtInItem
        self.installedPackagesProvider = installedPackagesProvider
        self.installationRemover = installationRemover
        self.packageInstaller = packageInstaller
        self.editablePackageProvider = editablePackageProvider
        self.userPetCreator = userPetCreator
        self.animationAdder = animationAdder
        self.detailsUpdater = detailsUpdater
        items = [builtInItem]
    }

    var selectedItem: PetLibraryItem {
        items.first(where: { $0.selection == selection }) ?? builtInItem
    }

    var selectedInstallationID: UUID? {
        selection.installationID
    }

    @discardableResult
    func reload(preferredInstallationID: UUID?) -> UUID? {
        let installedItems = installedPackagesProvider()
            .map(item(from:))
            .sorted(by: Self.itemSort)
        items = [builtInItem] + installedItems

        if let preferredInstallationID,
           items.contains(where: {
               $0.selection == .installed(preferredInstallationID)
           }) {
            selection = .installed(preferredInstallationID)
        } else {
            selection = .builtIn
        }
        errorMessage = nil
        return selectedInstallationID
    }

    @discardableResult
    func select(_ requestedSelection: PetLibrarySelection) -> Bool {
        guard let item = items.first(where: { $0.selection == requestedSelection }) else {
            return false
        }
        guard selection != requestedSelection else {
            return true
        }

        selection = requestedSelection
        errorMessage = nil
        onSelectionChange?(item)
        return true
    }

    @discardableResult
    func installPackage(
        from sourceURL: URL,
        mode: PetPackageInstallationMode = .rejectDuplicate
    ) -> Bool {
        guard !isImporting else {
            return false
        }
        isImporting = true
        defer { isImporting = false }

        do {
            let installed = try packageInstaller(sourceURL, mode)
            duplicateInstallRequest = nil
            errorMessage = nil
            _ = reload(preferredInstallationID: installed.installationID)
            onSelectionChange?(selectedItem)
            return true
        } catch let error as PetLibraryError {
            if case let .duplicatePackage(packageID, installationIDs) = error {
                let preferredInstallationID = selectedInstallationID.flatMap { selectedID in
                    installationIDs.contains(selectedID) ? selectedID : nil
                }
                let orderedInstallationIDs = preferredInstallationID.map { preferredID in
                    [preferredID] + installationIDs.filter { $0 != preferredID }
                } ?? installationIDs
                duplicateInstallRequest = DuplicatePetInstallRequest(
                    sourceURL: sourceURL,
                    packageID: packageID,
                    installationIDs: orderedInstallationIDs
                )
                errorMessage = nil
            } else {
                errorMessage = error.localizedDescription
            }
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func installDuplicateSeparately() {
        guard let request = duplicateInstallRequest else {
            return
        }
        _ = installPackage(from: request.sourceURL, mode: .installSeparately)
    }

    func replaceDuplicateInstallation() {
        guard
            let request = duplicateInstallRequest,
            let replacementInstallationID = request.replacementInstallationID
        else {
            return
        }
        _ = installPackage(
            from: request.sourceURL,
            mode: .replace(installationID: replacementInstallationID)
        )
    }

    func cancelDuplicateInstallation() {
        duplicateInstallRequest = nil
    }

    @discardableResult
    func removeSelectedInstallation() -> Bool {
        guard let installationID = selectedInstallationID else {
            return false
        }

        do {
            try installationRemover(installationID)
            _ = reload(preferredInstallationID: nil)
            onSelectionChange?(builtInItem)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func createUserPet(_ request: UserPetCreationRequest) -> Bool {
        performUserPetChange {
            try userPetCreator(request)
        }
    }

    @discardableResult
    func addAnimationToSelectedPet(_ request: UserPetAnimationRequest) -> Bool {
        guard let installedPackage = selectedItem.installedPackage,
              selectedItem.isEditable else {
            errorMessage = UserPetEditingError.importedPackageIsReadOnly.localizedDescription
            return false
        }
        return performUserPetChange {
            try animationAdder(request, installedPackage)
        }
    }

    @discardableResult
    func updateSelectedPetDetails(_ request: UserPetDetailsRequest) -> Bool {
        guard let installedPackage = selectedItem.installedPackage,
              selectedItem.isEditable else {
            errorMessage = UserPetEditingError.importedPackageIsReadOnly.localizedDescription
            return false
        }
        return performUserPetChange {
            try detailsUpdater(request, installedPackage)
        }
    }

    private func performUserPetChange(
        _ operation: () throws -> InstalledPetPackage
    ) -> Bool {
        guard !isImporting else {
            return false
        }
        isImporting = true
        defer { isImporting = false }

        do {
            let installed = try operation()
            errorMessage = nil
            _ = reload(preferredInstallationID: installed.installationID)
            onSelectionChange?(selectedItem)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func item(from installed: InstalledPetPackage) -> PetLibraryItem {
        PetLibraryItem(
            selection: .installed(installed.installationID),
            metadata: installed.package.metadata,
            previewURL: installed.package.previewURL,
            definition: installed.package.definition,
            installedPackage: installed,
            isEditable: editablePackageProvider(installed)
        )
    }

    private static func itemSort(_ lhs: PetLibraryItem, _ rhs: PetLibraryItem) -> Bool {
        let comparison = lhs.metadata.displayName.localizedStandardCompare(
            rhs.metadata.displayName
        )
        if comparison != .orderedSame {
            return comparison == .orderedAscending
        }
        return (lhs.selection.installationID?.uuidString ?? "")
            < (rhs.selection.installationID?.uuidString ?? "")
    }
}
