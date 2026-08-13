import Foundation

/// Creates an isolated, repeatable workload for Release performance QA.
/// The configuration is intentionally unavailable without `--ui-testing`, so
/// normal launches can never replace the user's settings.
nonisolated struct MultiPetQALaunchConfiguration: Equatable, Sendable {
    static let maximumActivePetCount = 64
    static let maximumDuration: TimeInterval = 7_200

    let activePetCount: Int
    let movementMode: PetMovementMode
    let duration: TimeInterval?

    init?(arguments: [String]) {
        guard
            arguments.contains("--ui-testing"),
            let countText = Self.value(
                after: "--qa-active-pet-count",
                in: arguments
            ),
            let activePetCount = Int(countText),
            (1...Self.maximumActivePetCount).contains(activePetCount)
        else {
            return nil
        }

        let movementMode: PetMovementMode
        switch Self.value(after: "--qa-movement-mode", in: arguments) ?? "fixed" {
        case "fixed":
            movementMode = .fixed
        case "cursor-following":
            movementMode = .cursorFollowing
        case "free-roaming":
            movementMode = .freeRoaming
        case "cursor-avoiding":
            movementMode = .cursorAvoiding
        default:
            return nil
        }

        let duration: TimeInterval?
        if let durationText = Self.value(
            after: "--qa-duration-seconds",
            in: arguments
        ) {
            guard
                let parsedDuration = TimeInterval(durationText),
                parsedDuration >= 1,
                parsedDuration <= Self.maximumDuration
            else {
                return nil
            }
            duration = parsedDuration
        } else {
            duration = nil
        }

        self.activePetCount = activePetCount
        self.movementMode = movementMode
        self.duration = duration
    }

    func makeSettings() -> AppSettings {
        var settings = AppSettings.default
        var sourceID = settings.selectedPetInstanceID

        for _ in 1..<activePetCount {
            settings = settings.addingPetInstance(
                for: .builtIn,
                copyingSettingsFrom: sourceID
            )
            sourceID = settings.selectedPetInstanceID
        }

        let instanceIDs = settings.activePetInstances.map(\.instanceID)
        for instanceID in instanceIDs {
            settings = settings.selectingPetInstance(instanceID)
            guard let profile = settings.activeBehaviorProfile else {
                continue
            }
            settings = settings.replacingActiveBehaviorProfile(
                BehaviorProfile(
                    petKey: profile.petKey,
                    mode: profile.mode,
                    manualSequenceID: profile.manualSequenceID,
                    sequences: profile.sequences,
                    automaticRules: profile.automaticRules,
                    movement: movementSettings(
                        from: profile.movement,
                        mode: movementMode
                    ),
                    pettingMotionID: profile.pettingMotionID,
                    speech: profile.speech
                )
            )
        }

        if let firstID = instanceIDs.first {
            settings = settings.selectingPetInstance(firstID)
        }
        return settings
    }

    private func movementSettings(
        from movement: PetMovementSettings,
        mode: PetMovementMode
    ) -> PetMovementSettings {
        PetMovementSettings(
            mode: mode,
            speed: movement.speed,
            cursorDistance: movement.cursorDistance,
            stopRadius: movement.stopRadius,
            freeRoamingDwellMilliseconds:
                movement.freeRoamingDwellMilliseconds,
            prefersFrontmostWindow: movement.prefersFrontmostWindow,
            cursorFollowingAnimation: movement.cursorFollowingAnimation,
            freeRoamingAnimation: movement.freeRoamingAnimation,
            cursorAvoidingIdleBehavior: movement.cursorAvoidingIdleBehavior,
            cursorAvoidingDetectionDistance:
                movement.cursorAvoidingDetectionDistance,
            cursorAvoidingSpeed: movement.cursorAvoidingSpeed,
            cursorAvoidingAnimation: movement.cursorAvoidingAnimation
        )
    }

    private static func value(
        after option: String,
        in arguments: [String]
    ) -> String? {
        guard
            let index = arguments.firstIndex(of: option),
            arguments.indices.contains(index + 1)
        else {
            return nil
        }
        return arguments[index + 1]
    }
}
