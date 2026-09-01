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


nonisolated enum PetAnimationReferenceChange: Equatable, Sendable {
    case renamed(from: String, to: String)
    case removed(String)
}

nonisolated enum NewUserPetInstallationPurpose: Equatable, Sendable {
    case newPet
    case editableCopy(sourcePetKey: PetBehaviorKey)
    case editableReplacement(
        sourcePetKey: PetBehaviorKey,
        instanceID: UUID
    )
    case imported(recommendedProfile: RecommendedPetProfile?)
}

@MainActor
final class PetLibrarySession: ObservableObject {
    @Published private(set) var items: [PetLibraryItem]
    @Published private(set) var selection: PetLibrarySelection = .builtIn
    @Published private(set) var errorMessage: String?
    @Published private(set) var isImporting = false
    @Published private(set) var isExporting = false

    var onInstalledContentChange: ((PetLibraryItem) -> Void)?
    var onInstallationContentRemoved: ((UUID) -> Void)?
    var onInstallationRemoved: ((UUID) -> Void)?
    var onAnimationReferenceChange: ((PetAnimationReferenceChange) -> Void)?
    var onNewUserPetInstallation: (
        (InstalledPetPackage, NewUserPetInstallationPurpose) throws -> Void
    )?

    private let builtInItem: PetLibraryItem
    private var itemsBySelection: [PetLibrarySelection: PetLibraryItem]
    private let installedPackagesProvider: () -> [InstalledPetPackage]
    private let installationRemover: (UUID) throws -> Void
    private let packageInstaller: (URL, PetPackageInstallationMode) throws
        -> InstalledPetPackage
    private let packageImportReviewer: (URL) throws -> PetPackageImportReview
    private let reviewedPackageInstaller: (
        URL,
        PetPackageInstallationMode,
        PetPackageImportReview?
    ) throws -> PetPackageInstallationResult
    private let editablePackageProvider: (InstalledPetPackage) -> Bool
    private let editablePackageConverter: (InstalledPetPackage) throws
        -> InstalledPetPackage
    private let userPetCreator: (UserPetCreationRequest) throws -> InstalledPetPackage
    private let editableCopyCreator: (
        InstalledPetPackage,
        String
    ) throws -> InstalledPetPackage
    private let builtInEditableCopyCreator: (String) throws
        -> InstalledPetPackage
    private let animationAdder: (
        UserPetAnimationRequest,
        InstalledPetPackage
    ) throws -> InstalledPetPackage
    private let animationDuplicator: (
        String,
        String,
        InstalledPetPackage
    ) throws -> InstalledPetPackage
    private let detailsUpdater: (
        UserPetDetailsRequest,
        InstalledPetPackage
    ) throws -> InstalledPetPackage
    private let animationUpdater: (
        UserPetAnimationDetailsRequest,
        InstalledPetPackage
    ) throws -> InstalledPetPackage
    private let animationRemover: (
        String,
        InstalledPetPackage
    ) throws -> InstalledPetPackage
    private let packageShareReviewer: (
        InstalledPetPackage,
        BehaviorProfile?,
        OverlaySettings?
    ) throws -> PetPackageShareReview
    private let packageShareExporter: (
        InstalledPetPackage,
        PetPackageShareReview,
        PetPackageShareOptions,
        Bool,
        URL
    ) throws -> URL

    convenience init(
        store: PetLibraryStore,
        builtInDefinition: PetDefinition
    ) {
        let editor = UserPetPackageEditor(store: store)
        let sharingService = PetPackageSharingService()
        let packageInstaller = PetPackageInstaller(libraryStore: store)
        self.init(
            builtInDefinition: builtInDefinition,
            installedPackagesProvider: store.installedPackages,
            installationRemover: store.removeInstallation,
            packageInstaller: packageInstaller.install,
            packageImportReviewer: packageInstaller.review,
            reviewedPackageInstaller: packageInstaller.installReviewed,
            editablePackageProvider: editor.isEditable,
            editablePackageConverter: editor.makeEditable,
            userPetCreator: editor.createPet,
            editableCopyCreator: editor.createEditableCopy,
            builtInEditableCopyCreator: { displayName in
                try editor.createEditableCopy(
                    of: builtInDefinition,
                    metadata: PetPackageMetadata(
                        id: BuiltInPet.id,
                        displayName: BuiltInPet.displayName,
                        version: BuiltInPet.version,
                        author: BuiltInPet.author,
                        description: BuiltInPet.description
                    ),
                    atlasImages:
                        try PetPresentationResourceLoader.loadBuiltInAtlases(),
                    displayName: displayName
                )
            },
            animationAdder: editor.addAnimation,
            animationDuplicator: editor.duplicateAnimation,
            detailsUpdater: editor.updateDetails,
            animationUpdater: editor.updateAnimation,
            animationRemover: editor.removeAnimation,
            packageShareReviewer: sharingService.review,
            packageShareExporter: sharingService.export
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
        packageImportReviewer: @escaping (URL) throws
            -> PetPackageImportReview = { _ in
                throw PetLibraryError.fileOperationFailed
            },
        reviewedPackageInstaller: @escaping (
            URL,
            PetPackageInstallationMode,
            PetPackageImportReview?
        ) throws -> PetPackageInstallationResult = { _, _, _ in
            throw PetLibraryError.fileOperationFailed
        },
        editablePackageProvider: @escaping (InstalledPetPackage) -> Bool = { _ in false },
        editablePackageConverter: @escaping (InstalledPetPackage) throws
            -> InstalledPetPackage = { _ in
                throw PetLibraryError.fileOperationFailed
            },
        userPetCreator: @escaping (UserPetCreationRequest) throws
            -> InstalledPetPackage = { _ in
                throw PetLibraryError.fileOperationFailed
            },
        editableCopyCreator: @escaping (
            InstalledPetPackage,
            String
        ) throws -> InstalledPetPackage = { _, _ in
            throw PetLibraryError.fileOperationFailed
        },
        builtInEditableCopyCreator: @escaping (String) throws
            -> InstalledPetPackage = { _ in
                throw PetLibraryError.fileOperationFailed
            },
        animationAdder: @escaping (
            UserPetAnimationRequest,
            InstalledPetPackage
        ) throws -> InstalledPetPackage = { _, _ in
            throw PetLibraryError.fileOperationFailed
        },
        animationDuplicator: @escaping (
            String,
            String,
            InstalledPetPackage
        ) throws -> InstalledPetPackage = { _, _, _ in
            throw PetLibraryError.fileOperationFailed
        },
        detailsUpdater: @escaping (
            UserPetDetailsRequest,
            InstalledPetPackage
        ) throws -> InstalledPetPackage = { _, _ in
            throw PetLibraryError.fileOperationFailed
        },
        animationUpdater: @escaping (
            UserPetAnimationDetailsRequest,
            InstalledPetPackage
        ) throws -> InstalledPetPackage = { _, _ in
            throw PetLibraryError.fileOperationFailed
        },
        animationRemover: @escaping (
            String,
            InstalledPetPackage
        ) throws -> InstalledPetPackage = { _, _ in
            throw PetLibraryError.fileOperationFailed
        },
        packageShareReviewer: @escaping (
            InstalledPetPackage,
            BehaviorProfile?,
            OverlaySettings?
        ) throws -> PetPackageShareReview = { _, _, _ in
            throw PetLibraryError.fileOperationFailed
        },
        packageShareExporter: @escaping (
            InstalledPetPackage,
            PetPackageShareReview,
            PetPackageShareOptions,
            Bool,
            URL
        ) throws -> URL = { _, _, _, _, _ in
            throw PetLibraryError.fileOperationFailed
        }
    ) {
        let builtInItem = PetLibraryItem(
            selection: .builtIn,
            metadata: PetPackageMetadata(
                id: builtInDefinition.id,
                displayName: builtInDefinition.displayName,
                version: BuiltInPet.version,
                author: BuiltInPet.author,
                description: BuiltInPet.description
            ),
            previewURL: nil,
            definition: builtInDefinition,
            installedPackage: nil
        )
        self.builtInItem = builtInItem
        self.installedPackagesProvider = installedPackagesProvider
        self.installationRemover = installationRemover
        self.packageInstaller = packageInstaller
        self.packageImportReviewer = packageImportReviewer
        self.reviewedPackageInstaller = reviewedPackageInstaller
        self.editablePackageProvider = editablePackageProvider
        self.editablePackageConverter = editablePackageConverter
        self.userPetCreator = userPetCreator
        self.editableCopyCreator = editableCopyCreator
        self.builtInEditableCopyCreator = builtInEditableCopyCreator
        self.animationAdder = animationAdder
        self.animationDuplicator = animationDuplicator
        self.detailsUpdater = detailsUpdater
        self.animationUpdater = animationUpdater
        self.animationRemover = animationRemover
        self.packageShareReviewer = packageShareReviewer
        self.packageShareExporter = packageShareExporter
        items = [builtInItem]
        itemsBySelection = [.builtIn: builtInItem]
    }

    var selectedItem: PetLibraryItem {
        itemsBySelection[selection] ?? builtInItem
    }

    var selectedInstallationID: UUID? {
        selection.installationID
    }

    func item(for petKey: PetBehaviorKey) -> PetLibraryItem? {
        switch petKey {
        case .builtIn:
            itemsBySelection[.builtIn]
        case let .installed(installationID):
            itemsBySelection[.installed(installationID)]
        }
    }

    func libraryDisplayLabel(for item: PetLibraryItem) -> String {
        guard !item.isBuiltIn else { return item.metadata.displayName }
        let matchingItems = items.filter {
            !$0.isBuiltIn && $0.metadata.id == item.metadata.id
        }
        guard matchingItems.count > 1,
              let index = matchingItems.firstIndex(where: {
                  $0.selection == item.selection
              }) else {
            return item.metadata.displayName
        }
        return "\(item.metadata.displayName) · \(item.metadata.version) · 설치 \(index + 1)"
    }

    @discardableResult
    func reload(preferredInstallationID: UUID?) -> UUID? {
        let installedItems = installedPackagesProvider()
            .map(item(from:))
            .sorted(by: Self.itemSort)
        items = [builtInItem] + installedItems
        itemsBySelection = Dictionary(
            uniqueKeysWithValues: items.map { ($0.selection, $0) }
        )

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
        guard itemsBySelection[requestedSelection] != nil else {
            return false
        }
        guard selection != requestedSelection else {
            return true
        }

        selection = requestedSelection
        errorMessage = nil
        return true
    }

    @discardableResult
    func installPackage(from sourceURL: URL) -> Bool {
        performPackageInstallation(
            from: sourceURL,
            mode: .installSeparately,
            reviewedImport: nil,
            purpose: .imported(recommendedProfile: nil)
        )
    }

    func reviewPackageForImport(from sourceURL: URL) -> PetPackageImportReview? {
        guard !isImporting, !isExporting else {
            return nil
        }
        isImporting = true
        defer { isImporting = false }

        do {
            let review = try packageImportReviewer(sourceURL)
            errorMessage = nil
            return review
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func installReviewedPackage(
        _ review: PetPackageImportReview,
        appliesRecommendedProfile: Bool = false
    ) -> Bool {
        if appliesRecommendedProfile, review.recommendedProfile == nil {
            errorMessage = PetPackageImportError
                .recommendedProfileUnavailable
                .localizedDescription
            return false
        }

        return performPackageInstallation(
            from: review.sourceURL,
            mode: .installSeparately,
            reviewedImport: review,
            purpose: .imported(
                recommendedProfile: appliesRecommendedProfile
                    ? review.recommendedProfile
                    : nil
            )
        )
    }

    @discardableResult
    private func performPackageInstallation(
        from sourceURL: URL,
        mode: PetPackageInstallationMode,
        reviewedImport: PetPackageImportReview?,
        purpose: NewUserPetInstallationPurpose
    ) -> Bool {
        guard !isImporting else {
            return false
        }
        isImporting = true
        defer { isImporting = false }

        let previousSelection = selection
        do {
            let installed: InstalledPetPackage
            if let reviewedImport {
                let reviewedResult = try reviewedPackageInstaller(
                    sourceURL,
                    mode,
                    reviewedImport
                )
                installed = reviewedResult.installedPackage
            } else {
                installed = try packageInstaller(sourceURL, mode)
            }
            _ = reload(preferredInstallationID: installed.installationID)
            do {
                try onNewUserPetInstallation?(installed, purpose)
            } catch {
                let settingsError = error.localizedDescription
                var cleanupError: String?
                do {
                    try installationRemover(installed.installationID)
                } catch {
                    cleanupError = error.localizedDescription
                }
                _ = reload(
                    preferredInstallationID: previousSelection.installationID
                )
                if let cleanupError {
                    errorMessage = "\(settingsError) 가져온 펫 설치를 정리하지 못했습니다: \(cleanupError) 앱을 다시 시작한 뒤 내 펫에서 확인해 주세요."
                } else {
                    errorMessage = "\(settingsError) 가져온 펫 추가는 되돌렸습니다."
                }
                return false
            }
            errorMessage = nil
            onInstalledContentChange?(selectedItem)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }


    func reviewSelectedPetForSharing(
        behaviorProfile: BehaviorProfile? = nil,
        overlay: OverlaySettings? = nil
    ) -> PetPackageShareReview? {
        guard let installedPackage = selectedItem.installedPackage else {
            return nil
        }
        guard !isImporting, !isExporting else {
            return nil
        }

        do {
            let review = try packageShareReviewer(
                installedPackage,
                behaviorProfile,
                overlay
            )
            errorMessage = nil
            return review
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func recommendedProfileForSelectedPet() -> RecommendedPetProfile? {
        guard let rootURL = selectedItem.installedPackage?.rootURL else {
            return nil
        }
        do {
            return try packageImportReviewer(rootURL).recommendedProfile
        } catch {
            return nil
        }
    }

    @discardableResult
    func exportSelectedPet(
        reviewed review: PetPackageShareReview,
        options: PetPackageShareOptions = .standard,
        isConfirmed: Bool,
        to destinationURL: URL
    ) -> Bool {
        guard let installedPackage = selectedItem.installedPackage else {
            return false
        }
        guard !isImporting, !isExporting else {
            return false
        }
        isExporting = true
        defer { isExporting = false }

        do {
            _ = try packageShareExporter(
                installedPackage,
                review,
                options,
                isConfirmed,
                destinationURL
            )
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func removeSelectedInstallation() -> Bool {
        guard let installationID = selectedInstallationID else {
            return false
        }

        do {
            try installationRemover(installationID)
            _ = reload(preferredInstallationID: nil)
            onInstallationRemoved?(installationID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func removeInstallationForDeletedPet(_ installationID: UUID) throws {
        do {
            try installationRemover(installationID)
            _ = reload(preferredInstallationID: nil)
            errorMessage = nil
            onInstallationContentRemoved?(installationID)
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    func createUserPet(_ request: UserPetCreationRequest) -> Bool {
        performNewUserPetInstallation(purpose: .newPet) {
            try userPetCreator(request)
        }
    }

    @discardableResult
    func createEditableCopyOfSelectedPet(displayName: String) -> Bool {
        if selectedItem.isBuiltIn {
            return performNewUserPetInstallation(
                purpose: .editableCopy(sourcePetKey: .builtIn)
            ) {
                try builtInEditableCopyCreator(displayName)
            }
        }
        guard let installedPackage = selectedItem.installedPackage else {
            return false
        }
        return performNewUserPetInstallation(
            purpose: .editableCopy(
                sourcePetKey: .installed(installedPackage.installationID)
            )
        ) {
            try editableCopyCreator(installedPackage, displayName)
        }
    }

    @discardableResult
    func prepareSelectedPetForEditing(
        displayName: String,
        instanceID: UUID,
        requiresIndependentCopy: Bool
    ) -> Bool {
        if !selectedItem.isBuiltIn,
           !requiresIndependentCopy,
           let installedPackage = selectedItem.installedPackage {
            if selectedItem.isEditable {
                return true
            }
            return performUserPetChange {
                try editablePackageConverter(installedPackage)
            }
        }

        let sourcePetKey = PetBehaviorKey(
            installationID: selectedInstallationID
        )
        if selectedItem.isBuiltIn {
            return performNewUserPetInstallation(
                purpose: .editableReplacement(
                    sourcePetKey: .builtIn,
                    instanceID: instanceID
                )
            ) {
                try builtInEditableCopyCreator(displayName)
            }
        }
        guard let installedPackage = selectedItem.installedPackage else {
            return false
        }
        return performNewUserPetInstallation(
            purpose: .editableReplacement(
                sourcePetKey: sourcePetKey,
                instanceID: instanceID
            )
        ) {
            try editableCopyCreator(installedPackage, displayName)
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
    func duplicateSelectedPetAnimation(id animationID: String) -> String? {
        guard let installedPackage = selectedItem.installedPackage,
              selectedItem.isEditable else {
            errorMessage = UserPetEditingError.importedPackageIsReadOnly
                .localizedDescription
            return nil
        }
        guard selectedItem.definition.motion(id: animationID) != nil else {
            errorMessage = UserPetEditingError.animationNotFound(animationID)
                .localizedDescription
            return nil
        }
        let duplicateID = Self.duplicateAnimationID(
            for: animationID,
            existingIDs: selectedItem.definition.motions.map(\.id)
        )
        let succeeded = performUserPetChange {
            try animationDuplicator(
                animationID,
                duplicateID,
                installedPackage
            )
        }
        return succeeded ? duplicateID : nil
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

    @discardableResult
    func updateSelectedPetAnimation(
        _ request: UserPetAnimationDetailsRequest
    ) -> Bool {
        guard let installedPackage = selectedItem.installedPackage,
              selectedItem.isEditable else {
            errorMessage = UserPetEditingError.importedPackageIsReadOnly.localizedDescription
            return false
        }
        let newAnimationID = request.animationName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let succeeded = performUserPetChange {
            try animationUpdater(request, installedPackage)
        }
        if succeeded, request.animationID != newAnimationID {
            onAnimationReferenceChange?(
                .renamed(from: request.animationID, to: newAnimationID)
            )
        }
        return succeeded
    }

    @discardableResult
    func removeSelectedPetAnimation(id animationID: String) -> Bool {
        guard let installedPackage = selectedItem.installedPackage,
              selectedItem.isEditable else {
            errorMessage = UserPetEditingError.importedPackageIsReadOnly.localizedDescription
            return false
        }
        let succeeded = performUserPetChange {
            try animationRemover(animationID, installedPackage)
        }
        if succeeded {
            onAnimationReferenceChange?(.removed(animationID))
        }
        return succeeded
    }

    private func performUserPetChange(
        _ operation: () throws -> InstalledPetPackage
    ) -> Bool {
        guard !isImporting, !isExporting else {
            return false
        }
        isImporting = true
        defer { isImporting = false }

        do {
            let installed = try operation()
            errorMessage = nil
            _ = reload(preferredInstallationID: installed.installationID)
            onInstalledContentChange?(selectedItem)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func performNewUserPetInstallation(
        purpose: NewUserPetInstallationPurpose,
        _ operation: () throws -> InstalledPetPackage
    ) -> Bool {
        guard !isImporting, !isExporting else {
            return false
        }
        isImporting = true
        defer { isImporting = false }

        let previousSelection = selection
        do {
            let installed = try operation()
            _ = reload(preferredInstallationID: installed.installationID)
            do {
                try onNewUserPetInstallation?(installed, purpose)
            } catch {
                let settingsError = error.localizedDescription
                var cleanupError: String?
                do {
                    try installationRemover(installed.installationID)
                } catch {
                    cleanupError = error.localizedDescription
                }
                _ = reload(
                    preferredInstallationID: previousSelection.installationID
                )
                if let cleanupError {
                    errorMessage = "\(settingsError) 새 펫 설치를 정리하지 못했습니다: \(cleanupError) 앱을 다시 시작한 뒤 내 펫에서 확인해 주세요."
                } else {
                    errorMessage = "\(settingsError) 새 펫 설치는 되돌렸습니다."
                }
                return false
            }

            errorMessage = nil
            onInstalledContentChange?(selectedItem)
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

    private static func duplicateAnimationID(
        for sourceID: String,
        existingIDs: [String]
    ) -> String {
        let marker = " 복사본"
        let baseName: String
        if let markerRange = sourceID.range(of: marker, options: .backwards) {
            let tail = sourceID[markerRange.upperBound...]
            let isCopySuffix = tail.isEmpty
                || (tail.first == " " && Int(tail.dropFirst()) != nil)
            baseName = isCopySuffix
                ? String(sourceID[..<markerRange.lowerBound]) + marker
                : sourceID + marker
        } else {
            baseName = sourceID + marker
        }

        func contains(_ candidate: String) -> Bool {
            existingIDs.contains {
                $0.localizedCaseInsensitiveCompare(candidate) == .orderedSame
            }
        }
        guard contains(baseName) else {
            return baseName
        }
        var suffix = 2
        while contains("\(baseName) \(suffix)") {
            suffix += 1
        }
        return "\(baseName) \(suffix)"
    }
}
