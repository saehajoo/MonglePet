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

nonisolated struct DuplicatePetInstallationCandidate: Equatable, Identifiable, Sendable {
    let installationID: UUID
    let metadata: PetPackageMetadata
    let isEditable: Bool
    let isCurrentlySelected: Bool

    var id: UUID {
        installationID
    }
}

nonisolated struct DuplicatePetInstallRequest: Equatable, Identifiable, Sendable {
    let sourceURL: URL
    let incomingMetadata: PetPackageMetadata
    let candidates: [DuplicatePetInstallationCandidate]
    let importReview: PetPackageImportReview?
    let appliesRecommendedProfileToNewInstallation: Bool

    var id: URL {
        sourceURL
    }

    var packageID: String {
        incomingMetadata.id
    }

    var preferredReplacementInstallationID: UUID? {
        candidates.first(where: \.isCurrentlySelected)?.installationID
            ?? candidates.first?.installationID
    }
}

nonisolated enum PetAnimationReferenceChange: Equatable, Sendable {
    case renamed(from: String, to: String)
    case removed(String)
}

nonisolated enum NewUserPetInstallationPurpose: Equatable, Sendable {
    case newPet
    case editableCopy(sourcePetKey: PetBehaviorKey)
}

@MainActor
final class PetLibrarySession: ObservableObject {
    @Published private(set) var items: [PetLibraryItem]
    @Published private(set) var selection: PetLibrarySelection = .builtIn
    @Published private(set) var errorMessage: String?
    @Published private(set) var duplicateInstallRequest: DuplicatePetInstallRequest?
    @Published private(set) var isImporting = false
    @Published private(set) var isExporting = false

    var onSelectionChange: ((PetLibraryItem) -> Void)?
    var onInstallationRemoved: ((UUID) -> Void)?
    var onAnimationReferenceChange: ((PetAnimationReferenceChange) -> Void)?
    var onRecommendedProfileApplied: ((UUID, RecommendedPetProfile) -> Void)?
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
        guard let item = itemsBySelection[requestedSelection] else {
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
        performPackageInstallation(
            from: sourceURL,
            mode: mode,
            reviewedImport: nil,
            appliesRecommendedProfile: false
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
        appliesRecommendedProfile: Bool
    ) -> Bool {
        if appliesRecommendedProfile, review.recommendedProfile == nil {
            errorMessage = PetPackageImportError
                .recommendedProfileUnavailable
                .localizedDescription
            return false
        }
        return performPackageInstallation(
            from: review.sourceURL,
            mode: .rejectDuplicate,
            reviewedImport: review,
            appliesRecommendedProfile: appliesRecommendedProfile
        )
    }

    @discardableResult
    private func performPackageInstallation(
        from sourceURL: URL,
        mode: PetPackageInstallationMode,
        reviewedImport: PetPackageImportReview?,
        appliesRecommendedProfile: Bool
    ) -> Bool {
        guard !isImporting else {
            return false
        }
        isImporting = true
        defer { isImporting = false }

        do {
            let result: PetPackageInstallationResult?
            let installed: InstalledPetPackage
            if let reviewedImport {
                let reviewedResult = try reviewedPackageInstaller(
                    sourceURL,
                    mode,
                    reviewedImport
                )
                result = reviewedResult
                installed = reviewedResult.installedPackage
            } else {
                result = nil
                installed = try packageInstaller(sourceURL, mode)
            }
            duplicateInstallRequest = nil
            errorMessage = nil
            _ = reload(preferredInstallationID: installed.installationID)
            onSelectionChange?(selectedItem)
            if appliesRecommendedProfile,
               let profile = result?.importReview.recommendedProfile {
                onRecommendedProfileApplied?(installed.installationID, profile)
            }
            return true
        } catch let error as PetLibraryError {
            if case let .duplicatePackage(incomingMetadata, installationIDs) = error {
                let preferredInstallationID = selectedInstallationID.flatMap { selectedID in
                    installationIDs.contains(selectedID) ? selectedID : nil
                }
                let orderedInstallationIDs = preferredInstallationID.map { preferredID in
                    [preferredID] + installationIDs.filter { $0 != preferredID }
                } ?? installationIDs
                let installedPackagesByID = Dictionary(
                    uniqueKeysWithValues: installedPackagesProvider().map {
                        ($0.installationID, $0)
                    }
                )
                let candidates = orderedInstallationIDs.compactMap { installationID in
                    installedPackagesByID[installationID].map { installedPackage in
                        DuplicatePetInstallationCandidate(
                            installationID: installationID,
                            metadata: installedPackage.package.metadata,
                            isEditable: editablePackageProvider(installedPackage),
                            isCurrentlySelected: installationID == selectedInstallationID
                        )
                    }
                }
                duplicateInstallRequest = DuplicatePetInstallRequest(
                    sourceURL: sourceURL,
                    incomingMetadata: incomingMetadata,
                    candidates: candidates,
                    importReview: reviewedImport,
                    appliesRecommendedProfileToNewInstallation:
                        appliesRecommendedProfile
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
        _ = performPackageInstallation(
            from: request.sourceURL,
            mode: .installSeparately,
            reviewedImport: request.importReview,
            appliesRecommendedProfile:
                request.appliesRecommendedProfileToNewInstallation
        )
    }

    func replaceDuplicateInstallation(
        _ installationID: UUID,
        appliesRecommendedProfile: Bool = false
    ) {
        guard
            let request = duplicateInstallRequest,
            request.candidates.contains(where: { $0.installationID == installationID })
        else {
            return
        }
        if appliesRecommendedProfile,
           request.importReview?.recommendedProfile == nil {
            errorMessage = PetPackageImportError
                .recommendedProfileUnavailable
                .localizedDescription
            return
        }
        _ = performPackageInstallation(
            from: request.sourceURL,
            mode: .replace(installationID: installationID),
            reviewedImport: request.importReview,
            appliesRecommendedProfile: appliesRecommendedProfile
        )
    }

    func cancelDuplicateInstallation() {
        duplicateInstallRequest = nil
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
            onSelectionChange?(builtInItem)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
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
            onSelectionChange?(selectedItem)
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
                    errorMessage = "\(settingsError) 새 펫 설치를 정리하지 못했습니다: \(cleanupError) 펫 보관함에서 비활성 설치 항목을 확인해 주세요."
                } else {
                    errorMessage = "\(settingsError) 새 펫 설치는 되돌렸습니다."
                }
                return false
            }

            errorMessage = nil
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
