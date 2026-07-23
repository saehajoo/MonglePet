import Foundation

@MainActor
final class PetMovementLifecycle {
    private let controller: any PetMovementControlling
    private var settings: PetMovementSettings = .default
    private var isAwake = false
    private var isSystemSuspended = true
    private var isUserDragging = false
    private var shouldReduceMotion = false

    init(controller: any PetMovementControlling) {
        self.controller = controller
    }

    var isMovementAllowed: Bool {
        isAwake
            && !isSystemSuspended
            && !isUserDragging
            && !shouldReduceMotion
    }

    func setSettings(_ settings: PetMovementSettings) {
        self.settings = settings
        apply()
    }

    func setAwake(_ isAwake: Bool) {
        self.isAwake = isAwake
        apply()
    }

    func setSystemSuspended(_ isSystemSuspended: Bool) {
        self.isSystemSuspended = isSystemSuspended
        apply()
    }

    func setUserDragging(_ isUserDragging: Bool) {
        self.isUserDragging = isUserDragging
        apply()
    }

    func setReduceMotion(_ shouldReduceMotion: Bool) {
        self.shouldReduceMotion = shouldReduceMotion
        apply()
    }

    func invalidateEnvironment() {
        controller.invalidateEnvironment()
    }

    func stop() {
        controller.stop()
    }

    private func apply() {
        controller.update(
            settings: settings,
            isMovementAllowed: isMovementAllowed
        )
    }
}
