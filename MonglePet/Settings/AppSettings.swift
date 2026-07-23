import Foundation

nonisolated enum AppSettingsLimits {
    static let schemaVersion = 4
    static let maximumFileSize = 5 * 1_024 * 1_024
    static let defaultOverlayWidth = 192.0
    static let minimumOverlayWidth = 96.0
    static let maximumOverlayWidth = 384.0
    static let minimumPlaybackSpeed = 0.25
    static let maximumPlaybackSpeed = 4.0
    static let maximumSequences = 100
    static let maximumStepsPerSequence = 100
    static let maximumAutomaticRules = 100
    static let maximumBehaviorProfiles = 1_000
    static let maximumRepeatCount = 100_000
    static let maximumDurationMilliseconds: Int64 = 86_400_000
    static let defaultMovementSpeed = 160.0
    static let minimumMovementSpeed = 20.0
    static let maximumMovementSpeed = 1_000.0
    static let defaultCursorDistance = 96.0
    static let minimumCursorDistance = 0.0
    static let maximumCursorDistance = 512.0
    static let defaultMovementStopRadius = 16.0
    static let minimumMovementStopRadius = 0.0
    static let maximumMovementStopRadius = 128.0
    static let defaultFreeRoamingDwellMilliseconds: Int64 = 6_000
    static let minimumFreeRoamingDwellMilliseconds: Int64 = 500
    static let maximumFreeRoamingDwellMilliseconds: Int64 = 300_000
    static let defaultOverlayOpacity = 1.0
    static let minimumOverlayOpacity = 0.1
    static let maximumOverlayOpacity = 1.0
    static let defaultPointerOverlapOpacity = 0.2
    static let minimumPointerOverlapOpacity = 0.05
    static let maximumPointerOverlapOpacity = 1.0
}

nonisolated enum MovementBoundaryMode: Hashable, Sendable {
    case allDisplays
    case selectedDisplay
    case customArea
}

nonisolated struct NormalizedMovementRect: Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    static let recommended = NormalizedMovementRect(
        x: 0.1,
        y: 0.1,
        width: 0.8,
        height: 0.8
    )

    var isValid: Bool {
        x.isFinite && y.isFinite && width.isFinite && height.isFinite
            && x >= 0 && y >= 0
            && width > 0 && height > 0
            && x + width <= 1
            && y + height <= 1
    }
}

nonisolated struct MovementBoundarySettings: Equatable, Sendable {
    let mode: MovementBoundaryMode
    let screenIdentifier: String?
    let normalizedRect: NormalizedMovementRect?

    static let `default` = MovementBoundarySettings(
        mode: .allDisplays,
        screenIdentifier: nil,
        normalizedRect: nil
    )

    var isValid: Bool {
        let hasValidScreenIdentifier = screenIdentifier.map {
            let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && trimmed == $0
        } ?? false
        switch mode {
        case .allDisplays:
            return (screenIdentifier == nil || hasValidScreenIdentifier)
                && (normalizedRect?.isValid ?? true)
        case .selectedDisplay:
            return hasValidScreenIdentifier
                && (normalizedRect?.isValid ?? true)
        case .customArea:
            return hasValidScreenIdentifier
                && normalizedRect?.isValid == true
        }
    }
}

nonisolated enum PetMovementMode: Hashable, Sendable {
    case fixed
    case cursorFollowing
    case freeRoaming
}

nonisolated struct PetMovementSettings: Equatable, Sendable {
    let mode: PetMovementMode
    let speed: Double
    let cursorDistance: Double
    let stopRadius: Double
    let freeRoamingDwellMilliseconds: Int64
    let prefersFrontmostWindow: Bool
    let cursorFollowingMotionID: String?
    let freeRoamingMotionID: String?

    init(
        mode: PetMovementMode,
        speed: Double,
        cursorDistance: Double,
        stopRadius: Double,
        freeRoamingDwellMilliseconds: Int64,
        prefersFrontmostWindow: Bool,
        cursorFollowingMotionID: String? = nil,
        freeRoamingMotionID: String? = nil
    ) {
        self.mode = mode
        self.speed = speed
        self.cursorDistance = cursorDistance
        self.stopRadius = stopRadius
        self.freeRoamingDwellMilliseconds = freeRoamingDwellMilliseconds
        self.prefersFrontmostWindow = prefersFrontmostWindow
        self.cursorFollowingMotionID = cursorFollowingMotionID
        self.freeRoamingMotionID = freeRoamingMotionID
    }

    static let `default` = PetMovementSettings(
        mode: .fixed,
        speed: AppSettingsLimits.defaultMovementSpeed,
        cursorDistance: AppSettingsLimits.defaultCursorDistance,
        stopRadius: AppSettingsLimits.defaultMovementStopRadius,
        freeRoamingDwellMilliseconds: AppSettingsLimits.defaultFreeRoamingDwellMilliseconds,
        prefersFrontmostWindow: true,
        cursorFollowingMotionID: nil,
        freeRoamingMotionID: nil
    )

    var isValid: Bool {
        speed.isFinite
            && (AppSettingsLimits.minimumMovementSpeed...AppSettingsLimits.maximumMovementSpeed)
                .contains(speed)
            && cursorDistance.isFinite
            && (AppSettingsLimits.minimumCursorDistance...AppSettingsLimits.maximumCursorDistance)
                .contains(cursorDistance)
            && stopRadius.isFinite
            && (AppSettingsLimits.minimumMovementStopRadius...AppSettingsLimits.maximumMovementStopRadius)
                .contains(stopRadius)
            && (AppSettingsLimits.minimumFreeRoamingDwellMilliseconds
                ... AppSettingsLimits.maximumFreeRoamingDwellMilliseconds)
                .contains(freeRoamingDwellMilliseconds)
            && Self.isValidOptionalMotionID(cursorFollowingMotionID)
            && Self.isValidOptionalMotionID(freeRoamingMotionID)
    }

    private static func isValidOptionalMotionID(_ motionID: String?) -> Bool {
        guard let motionID else {
            return true
        }
        let trimmed = motionID.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed == motionID
    }
}

nonisolated enum PetBehaviorKey: Hashable, Sendable {
    case builtIn
    case installed(UUID)

    init(installationID: UUID?) {
        self = installationID.map(Self.installed) ?? .builtIn
    }

    var installationID: UUID? {
        guard case let .installed(installationID) = self else {
            return nil
        }
        return installationID
    }
}

nonisolated struct BehaviorProfile: Equatable, Identifiable, Sendable {
    var id: PetBehaviorKey { petKey }

    let petKey: PetBehaviorKey
    let mode: BehaviorMode
    let manualSequenceID: String?
    let sequences: [BehaviorSequence]
    let automaticRules: [AutomaticRule]
    let movement: PetMovementSettings
    let pettingMotionID: String?

    init(
        petKey: PetBehaviorKey,
        mode: BehaviorMode,
        manualSequenceID: String?,
        sequences: [BehaviorSequence],
        automaticRules: [AutomaticRule],
        movement: PetMovementSettings = .default,
        pettingMotionID: String? = nil
    ) {
        self.petKey = petKey
        self.mode = mode
        self.manualSequenceID = manualSequenceID
        self.sequences = sequences
        self.automaticRules = automaticRules
        self.movement = movement
        self.pettingMotionID = pettingMotionID
    }
}

nonisolated struct OverlaySettings: Equatable, Sendable {
    let screenIdentifier: String?
    let originX: Double
    let originY: Double
    let width: Double
    let clickThrough: Bool
    let opacity: Double
    let pointerOverlapFadeEnabled: Bool
    let pointerOverlapOpacity: Double
    let movementBoundary: MovementBoundarySettings

    init(
        screenIdentifier: String?,
        originX: Double,
        originY: Double,
        width: Double,
        clickThrough: Bool,
        opacity: Double = AppSettingsLimits.defaultOverlayOpacity,
        pointerOverlapFadeEnabled: Bool = false,
        pointerOverlapOpacity: Double =
            AppSettingsLimits.defaultPointerOverlapOpacity,
        movementBoundary: MovementBoundarySettings = .default
    ) {
        self.screenIdentifier = screenIdentifier
        self.originX = originX
        self.originY = originY
        self.width = width
        self.clickThrough = clickThrough
        self.opacity = opacity
        self.pointerOverlapFadeEnabled = pointerOverlapFadeEnabled
        self.pointerOverlapOpacity = pointerOverlapOpacity
        self.movementBoundary = movementBoundary
    }

    static let `default` = OverlaySettings(
        screenIdentifier: nil,
        originX: 0,
        originY: 0,
        width: AppSettingsLimits.defaultOverlayWidth,
        clickThrough: false,
        opacity: AppSettingsLimits.defaultOverlayOpacity,
        pointerOverlapFadeEnabled: false,
        pointerOverlapOpacity: AppSettingsLimits.defaultPointerOverlapOpacity,
        movementBoundary: .default
    )
}

nonisolated struct AppSettings: Equatable, Sendable {
    let selectedPetInstallationID: UUID?
    let lastUserPresentation: PetPresentation
    let overlay: OverlaySettings
    let behaviorProfiles: [BehaviorProfile]

    init(
        selectedPetInstallationID: UUID?,
        lastUserPresentation: PetPresentation,
        overlay: OverlaySettings,
        behaviorProfiles: [BehaviorProfile]
    ) {
        self.selectedPetInstallationID = selectedPetInstallationID
        self.lastUserPresentation = lastUserPresentation
        self.overlay = overlay
        self.behaviorProfiles = behaviorProfiles
    }

    init(
        selectedPetInstallationID: UUID?,
        lastUserPresentation: PetPresentation,
        behaviorMode: BehaviorMode,
        overlay: OverlaySettings,
        movement: PetMovementSettings = .default,
        pettingMotionID: String? = nil,
        manualSequenceID: String?,
        sequences: [BehaviorSequence],
        automaticRules: [AutomaticRule]
    ) {
        self.init(
            selectedPetInstallationID: selectedPetInstallationID,
            lastUserPresentation: lastUserPresentation,
            overlay: overlay,
            behaviorProfiles: [
                BehaviorProfile(
                    petKey: PetBehaviorKey(
                        installationID: selectedPetInstallationID
                    ),
                    mode: behaviorMode,
                    manualSequenceID: manualSequenceID,
                    sequences: sequences,
                    automaticRules: automaticRules,
                    movement: movement,
                    pettingMotionID: pettingMotionID
                )
            ]
        )
    }

    var selectedPetKey: PetBehaviorKey {
        PetBehaviorKey(installationID: selectedPetInstallationID)
    }

    var activeBehaviorProfile: BehaviorProfile? {
        behaviorProfile(for: selectedPetKey)
    }

    var behaviorMode: BehaviorMode {
        activeBehaviorProfile?.mode ?? .automatic
    }

    var manualSequenceID: String? {
        activeBehaviorProfile?.manualSequenceID
    }

    var sequences: [BehaviorSequence] {
        activeBehaviorProfile?.sequences ?? []
    }

    var automaticRules: [AutomaticRule] {
        activeBehaviorProfile?.automaticRules ?? []
    }

    var movementSettings: PetMovementSettings {
        activeBehaviorProfile?.movement ?? .default
    }

    var pettingMotionID: String? {
        activeBehaviorProfile?.pettingMotionID
    }

    func behaviorProfile(for key: PetBehaviorKey) -> BehaviorProfile? {
        behaviorProfiles.first { $0.petKey == key }
    }

    func replacingActiveBehaviorProfile(
        _ profile: BehaviorProfile
    ) -> AppSettings {
        precondition(profile.petKey == selectedPetKey)
        var profiles = behaviorProfiles
        if let index = profiles.firstIndex(where: { $0.petKey == profile.petKey }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        return AppSettings(
            selectedPetInstallationID: selectedPetInstallationID,
            lastUserPresentation: lastUserPresentation,
            overlay: overlay,
            behaviorProfiles: profiles
        )
    }

    static let `default` = AppSettings(
        selectedPetInstallationID: nil,
        lastUserPresentation: .awake,
        overlay: .default,
        behaviorProfiles: []
    )
}

nonisolated enum SettingsRecoveryIssue: Equatable, Sendable {
    case invalidField(String)
    case droppedSequence(String)
    case droppedRule(String)
    case disabledRule(String)
    case truncatedCollection(String)
    case corruptFileQuarantined(String)
    case newerSchemaVersion(Int)
}

nonisolated enum AppSettingsLoadSource: Equatable, Sendable {
    case defaults
    case file
    case recovered
    case newerSchema(Int)
}

nonisolated struct AppSettingsLoadResult: Equatable, Sendable {
    let settings: AppSettings
    let issues: [SettingsRecoveryIssue]
    let source: AppSettingsLoadSource
    let isWritingEnabled: Bool
}
