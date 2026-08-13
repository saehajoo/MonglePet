import AppKit

nonisolated enum PetOverlayApplicationReason: Equatable, Sendable {
    case initialLoad(shouldRestorePosition: Bool)
    case settingsChange

    var shouldRestorePosition: Bool {
        switch self {
        case let .initialLoad(shouldRestorePosition):
            shouldRestorePosition
        case .settingsChange:
            false
        }
    }

    var isInitialLoad: Bool {
        if case .initialLoad = self {
            return true
        }
        return false
    }
}

nonisolated struct PetRuntimeStatus: Equatable, Sendable {
    let instanceID: UUID
    let isAwake: Bool
    let currentBehaviorSequenceID: String?
    let currentPlaybackSequenceID: String?
    let currentSpeechText: String?
    let movementMode: PetMovementMode
    let movementState: PetMovementControllerState
    let movementActivity: PetMovementActivity
    let isPettingInteractionActive: Bool
}

@MainActor
protocol PetRuntimeContextType: AnyObject {
    var instanceID: UUID { get }
    var activeInstallationID: UUID? { get }
    var isAwake: Bool { get }
    var currentMotionID: String? { get }
    var isMovementAllowed: Bool { get }
    var latestMovementActivity: PetMovementActivity { get }
    var currentSettings: AppSettings? { get }
    var runtimeStatus: PetRuntimeStatus { get }

    func replacePet(_ item: PetLibraryItem) throws
    func apply(settings: AppSettings, reason: PetOverlayApplicationReason)
    func updateActivitySnapshot(_ snapshot: ActivitySnapshot)
    func setUserPaused(_ isPaused: Bool)
    func setReduceMotion(_ shouldReduceMotion: Bool)
    func desktopEnvironmentDidChange()
    @discardableResult
    func requestPettingInteraction() -> Bool
    func orderFront()
    func moveToVisibleFrame(_ visibleFrame: NSRect)
    func stop()
}

@MainActor
final class PetRuntimeContext: PetRuntimeContextType {
    let instanceID: UUID

    private let petWindowController: PetWindowController
    private let playbackCoordinator: PetPlaybackCoordinator
    private let behaviorRuntime: PetBehaviorRuntime
    private let speechRuntime: PetSpeechRuntime
    private let movementController: PetMovementController
    private let movementLifecycle: PetMovementLifecycle
    private let onOverlayGeometryDidChange: (UUID, OverlaySettings) -> Void
    private let onOverlayGeometryDidSynchronize: (UUID, OverlaySettings) -> Void
    private var latestActivitySnapshot: ActivitySnapshot?
    private var isSystemSuspended = false
    private var isUserPaused = false
    private(set) var latestMovementActivity = PetMovementActivity.stationary
    private(set) var currentSettings: AppSettings?

    init(
        instanceID: UUID,
        petWindowController: PetWindowController = PetWindowController(),
        environmentProvider: any PetDesktopEnvironmentProviding =
            StaticPetDesktopEnvironmentProvider(),
        frontmostWindowProvider: any FrontmostWindowProviding =
            FrontmostWindowProvider(),
        onOverlayGeometryDidChange: @escaping (
            UUID,
            OverlaySettings
        ) -> Void = { _, _ in },
        onOverlayGeometryDidSynchronize: @escaping (
            UUID,
            OverlaySettings
        ) -> Void = { _, _ in }
    ) {
        self.instanceID = instanceID
        self.petWindowController = petWindowController
        self.onOverlayGeometryDidChange = onOverlayGeometryDidChange
        self.onOverlayGeometryDidSynchronize =
            onOverlayGeometryDidSynchronize

        let playbackCoordinator = PetPlaybackCoordinator(
            petDefinition: petWindowController.petDefinition
        ) { [weak petWindowController] playback in
            petWindowController?.setScheduledMotion(playback)
        }
        self.playbackCoordinator = playbackCoordinator

        let speechRuntime = PetSpeechRuntime {
            [weak petWindowController] presentation in
            if let presentation {
                petWindowController?.showSpeechBubble(presentation)
            } else {
                petWindowController?.hideSpeechBubble()
            }
        }
        self.speechRuntime = speechRuntime

        behaviorRuntime = PetBehaviorRuntime(
            petDefinition: petWindowController.petDefinition
        ) { [weak playbackCoordinator, weak speechRuntime] playback in
            playbackCoordinator?.setBehaviorPlayback(playback)
            if playback?.isInteraction != true {
                speechRuntime?.behaviorSequenceDidChange(
                    playback?.sequenceID
                )
            }
        }

        let movementController = PetMovementController(
            originProvider: { [weak petWindowController] in
                petWindowController?.movementOrigin
            },
            petSizeProvider: { [weak petWindowController] in
                petWindowController?.movementSize
            },
            applyOrigin: { [weak petWindowController] origin in
                petWindowController?.setMovementOrigin(origin)
            },
            frontmostWindowProvider: frontmostWindowProvider,
            screensProvider: { [weak environmentProvider] in
                environmentProvider?.currentSnapshot.movementScreens ?? []
            },
            movementBoundaryProvider: { [weak petWindowController] in
                petWindowController?.currentOverlaySettings()?
                    .movementBoundary ?? .default
            },
            pointerProvider: { [weak environmentProvider] in
                environmentProvider?.currentSnapshot.pointerLocation
            }
        )
        self.movementController = movementController
        movementLifecycle = PetMovementLifecycle(
            controller: movementController
        )

        movementController.setActivityChangeHandler { [weak self] activity in
            self?.latestMovementActivity = activity
            self?.playbackCoordinator.setMovementActivity(activity)
        }
        petWindowController.onOverlayGeometryDidChange = { [weak self] in
            self?.persistCurrentOverlayGeometry()
        }
        petWindowController.onUserDragStateDidChange = {
            [weak movementLifecycle] isDragging in
            movementLifecycle?.setUserDragging(isDragging)
        }
        petWindowController.onMovementEnvironmentDidChange = { [weak self] in
            self?.movementEnvironmentDidChange()
        }
        petWindowController.onPettingRequested = { [weak self] in
            _ = self?.requestPettingInteraction()
        }
    }

    var activeInstallationID: UUID? {
        petWindowController.activeInstallationID
    }

    var isAwake: Bool {
        petWindowController.isAwake
    }

    var currentMotionID: String? {
        petWindowController.currentMotionID
    }

    var isMovementAllowed: Bool {
        movementLifecycle.isMovementAllowed
    }

    var runtimeStatus: PetRuntimeStatus {
        PetRuntimeStatus(
            instanceID: instanceID,
            isAwake: isAwake,
            currentBehaviorSequenceID:
                behaviorRuntime.currentPlayback?.sequenceID,
            currentPlaybackSequenceID:
                playbackCoordinator.currentPlayback?.sequenceID,
            currentSpeechText: speechRuntime.currentPresentation?.text,
            movementMode: currentSettings?.movementSettings.mode ?? .fixed,
            movementState: movementController.state,
            movementActivity: latestMovementActivity,
            isPettingInteractionActive:
                behaviorRuntime.currentPlayback?.isInteraction == true
        )
    }

    func replacePet(_ item: PetLibraryItem) throws {
        try petWindowController.applyPet(item)
        speechRuntime.prepareForPetChange()
        playbackCoordinator.replacePetDefinition(item.definition)
        behaviorRuntime.replacePetDefinition(item.definition)
        movementLifecycle.invalidateEnvironment()
    }

    func apply(
        settings: AppSettings,
        reason: PetOverlayApplicationReason
    ) {
        guard settings.selectedPetInstanceID == instanceID else {
            return
        }
        currentSettings = settings
        petWindowController.applyOverlaySettings(
            settings.overlay,
            restorePosition: reason.shouldRestorePosition
        )
        speechRuntime.update(settings: settings.speechSettings)
        let pettingMotionExists = settings.pettingMotionID.flatMap {
            petWindowController.petDefinition.motion(id: $0)
        } != nil
        petWindowController.setPettingEnabled(
            pettingMotionExists
                && settings.movementSettings.mode != .cursorAvoiding
        )
        switch settings.lastUserPresentation {
        case .awake:
            if !petWindowController.isAwake {
                petWindowController.wake()
            }
        case .tuckedAway:
            if petWindowController.isAwake {
                petWindowController.sleep()
            }
        case .suspended:
            break
        }
        movementLifecycle.setSettings(settings.movementSettings)
        movementLifecycle.setAwake(petWindowController.isAwake)
        speechRuntime.setAwake(petWindowController.isAwake)
        movementLifecycle.invalidateEnvironment()
        if settings.movementSettings.mode == .fixed,
           let appliedOverlay = petWindowController.currentOverlaySettings() {
            onOverlayGeometryDidSynchronize(instanceID, appliedOverlay)
        }
        if let latestActivitySnapshot {
            behaviorRuntime.update(
                settings: settings,
                snapshot: effectiveSnapshot(latestActivitySnapshot)
            )
        }
    }

    func updateActivitySnapshot(_ snapshot: ActivitySnapshot) {
        latestActivitySnapshot = snapshot
        isSystemSuspended = snapshot.isScreenLocked
            || snapshot.isSystemSleeping
        applyEffectiveSuspension()
        if let currentSettings {
            behaviorRuntime.update(
                settings: currentSettings,
                snapshot: effectiveSnapshot(snapshot)
            )
        }
    }

    func setUserPaused(_ isPaused: Bool) {
        guard isPaused != isUserPaused else {
            return
        }
        isUserPaused = isPaused
        applyEffectiveSuspension()
        if let currentSettings, let latestActivitySnapshot {
            behaviorRuntime.update(
                settings: currentSettings,
                snapshot: effectiveSnapshot(latestActivitySnapshot)
            )
        }
    }

    func setReduceMotion(_ shouldReduceMotion: Bool) {
        movementLifecycle.setReduceMotion(shouldReduceMotion)
        petWindowController.setReduceMotion(shouldReduceMotion)
    }

    func desktopEnvironmentDidChange() {
        petWindowController.desktopEnvironmentDidChange()
    }

    @discardableResult
    func requestPettingInteraction() -> Bool {
        guard
            !isUserPaused,
            let currentSettings,
            currentSettings.movementSettings.mode != .cursorAvoiding,
            let motionID = currentSettings.pettingMotionID,
            petWindowController.petDefinition.motion(id: motionID) != nil
        else {
            return false
        }
        return behaviorRuntime.triggerInteraction(motionID: motionID)
    }

    func orderFront() {
        petWindowController.orderFront()
    }

    func moveToVisibleFrame(_ visibleFrame: NSRect) {
        petWindowController.moveToVisibleFrame(visibleFrame)
        movementLifecycle.invalidateEnvironment()
        persistCurrentOverlayGeometry()
    }

    func stop() {
        behaviorRuntime.stop()
        speechRuntime.stop()
        movementLifecycle.setAwake(false)
        movementLifecycle.setSystemSuspended(true)
        movementLifecycle.stop()
        petWindowController.sleep()
    }

    private func persistCurrentOverlayGeometry() {
        guard let overlay = petWindowController.currentOverlaySettings() else {
            return
        }
        onOverlayGeometryDidChange(instanceID, overlay)
    }

    private func movementEnvironmentDidChange() {
        movementLifecycle.invalidateEnvironment()
        guard currentSettings?.movementSettings.mode == .fixed else {
            return
        }
        persistCurrentOverlayGeometry()
    }

    private func applyEffectiveSuspension() {
        let isSuspended = isSystemSuspended || isUserPaused
        petWindowController.setSystemSuspended(isSuspended)
        speechRuntime.setSystemSuspended(isSuspended)
        movementLifecycle.setSystemSuspended(isSuspended)
    }

    private func effectiveSnapshot(
        _ snapshot: ActivitySnapshot
    ) -> ActivitySnapshot {
        ActivitySnapshot(
            capturedAt: snapshot.capturedAt,
            idleDuration: snapshot.idleDuration,
            frontmostApplicationID: snapshot.frontmostApplicationID,
            isScreenLocked: snapshot.isScreenLocked || isUserPaused,
            isSystemSleeping: snapshot.isSystemSleeping
        )
    }
}
