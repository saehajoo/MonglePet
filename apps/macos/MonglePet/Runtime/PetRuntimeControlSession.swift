import Combine
import Foundation

@MainActor
final class PetRuntimeControlSession: ObservableObject {
    @Published private(set) var isAllPaused = false
    @Published private(set) var pendingRecoveryInstanceID: UUID?
    @Published private(set) var isUserRequestedSafeMode = false
    @Published private(set) var restoredInstanceIDs: Set<UUID> = []
    @Published private(set) var resourceWarning: PetResourceWarning?

    var onSetAllPaused: ((Bool) -> Void)?
    var onRestoreInstance: ((UUID) -> Void)?
    var onRestoreAll: (() -> Void)?
    var onRestoreAllExceptPending: (() -> Void)?

    func setAllPaused(_ isPaused: Bool) {
        onSetAllPaused?(isPaused)
    }

    func restoreInstance(_ instanceID: UUID) {
        onRestoreInstance?(instanceID)
    }

    func restoreAll() {
        onRestoreAll?()
    }

    func restoreAllExceptPending() {
        onRestoreAllExceptPending?()
    }

    func updateAllPaused(_ isPaused: Bool) {
        isAllPaused = isPaused
    }

    func updateRecovery(
        pendingInstanceID: UUID?,
        isUserRequestedSafeMode: Bool,
        restoredInstanceIDs: Set<UUID>
    ) {
        pendingRecoveryInstanceID = pendingInstanceID
        self.isUserRequestedSafeMode = isUserRequestedSafeMode
        self.restoredInstanceIDs = restoredInstanceIDs
    }

    func updateResourceWarning(_ warning: PetResourceWarning?) {
        resourceWarning = warning
    }
}
