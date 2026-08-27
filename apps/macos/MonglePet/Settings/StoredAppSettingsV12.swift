import Foundation

/// schema-v12 makes behaviors the reusable unit selected by automatic,
/// movement and petting contexts. Motions remain frame assets referenced only
/// by behavior steps.
nonisolated struct StoredAppSettingsV12: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let selectedPetInstanceID: String
    let activePetInstances: [StoredPetInstanceV11]
    let behaviorProfiles: [StoredPetProfileV12]
}

nonisolated struct StoredPetProfileV12: Codable, Equatable, Sendable {
    let profileID: String
    let petKey: StoredPetBehaviorKeyV2
    let mode: String
    let manualSequenceID: String?
    let sequences: [StoredBehaviorSequenceV12]
    let automaticRules: [StoredAutomaticRule]
    let automaticRulePriorityOrder: [String]
    let movement: StoredPetMovementSettingsV12
    let pettingBehaviorID: String?
    let speech: StoredPetSpeechSettingsV10
}

nonisolated struct StoredBehaviorSequenceV12:
    Codable,
    Equatable,
    Sendable
{
    let id: String
    let displayName: String
    let steps: [StoredBehaviorStepV2]
    let repeats: Bool
}

nonisolated struct StoredPetMovementSettingsV12:
    Codable,
    Equatable,
    Sendable
{
    let mode: String
    let speed: Double
    let cursorDistance: Double
    let stopRadius: Double
    let freeRoamingDwellMilliseconds: Int64
    let prefersFrontmostWindow: Bool
    let cursorFollowingBehavior: StoredMovementBehaviorSettingsV12
    let freeRoamingBehavior: StoredMovementBehaviorSettingsV12
    let cursorAvoidingIdleBehavior: String
    let cursorAvoidingDetectionDistance: Double
    let cursorAvoidingSpeed: Double
    let cursorAvoidingBehavior: StoredMovementBehaviorSettingsV12
}

nonisolated struct StoredMovementBehaviorSettingsV12:
    Codable,
    Equatable,
    Sendable
{
    let fallbackBehaviorID: String?
    let usesDirectionalBehaviors: Bool
    let usesDiagonalBehaviors: Bool
    let directionBehaviorIDs: StoredDirectionalBehaviorIDsV12
}

nonisolated struct StoredDirectionalBehaviorIDsV12:
    Codable,
    Equatable,
    Sendable
{
    let left: String?
    let right: String?
    let up: String?
    let down: String?
    let upLeft: String?
    let upRight: String?
    let downLeft: String?
    let downRight: String?
}

nonisolated struct AppSettingsV11ToV12MigrationResult:
    Equatable,
    Sendable
{
    let settings: StoredAppSettingsV12
    let issues: [SettingsRecoveryIssue]
}

nonisolated enum AppSettingsV11ToV12MigrationError:
    Error,
    Equatable,
    Sendable
{
    case unsupportedSourceSchema(Int)
}

nonisolated enum AppSettingsV11ToV12Migrator {
    static func migrate(
        _ stored: StoredAppSettingsV11
    ) throws -> AppSettingsV11ToV12MigrationResult {
        guard stored.schemaVersion == 11 else {
            throw AppSettingsV11ToV12MigrationError
                .unsupportedSourceSchema(stored.schemaVersion)
        }

        var issues: [SettingsRecoveryIssue] = []
        let profiles = stored.behaviorProfiles.enumerated().map {
            index, profile in
            migrateProfile(
                profile,
                field: "behaviorProfiles.\(index)",
                issues: &issues
            )
        }
        return AppSettingsV11ToV12MigrationResult(
            settings: StoredAppSettingsV12(
                schemaVersion: 12,
                selectedPetInstanceID: stored.selectedPetInstanceID,
                activePetInstances: stored.activePetInstances,
                behaviorProfiles: profiles
            ),
            issues: issues
        )
    }

    private static func migrateProfile(
        _ profile: StoredPetProfileV11,
        field: String,
        issues: inout [SettingsRecoveryIssue]
    ) -> StoredPetProfileV12 {
        var sequences = profile.sequences.map {
            StoredBehaviorSequenceV12(
                id: $0.id,
                displayName: legacyDisplayName(for: $0.id),
                steps: $0.steps,
                repeats: $0.repeats
            )
        }
        var motionBehaviorIDs: [String: String] = [:]

        func behaviorID(for motionID: String?) -> String? {
            guard let motionID else {
                return nil
            }
            if let existing = motionBehaviorIDs[motionID] {
                return existing
            }
            if let existing = sequences.first(where: {
                $0.steps.count == 1
                    && $0.steps[0].motionID == motionID
                    && $0.steps[0].repeatCount == 1
            }) {
                motionBehaviorIDs[motionID] = existing.id
                return existing.id
            }

            let encoded = Data(motionID.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            let baseID = "__monglepet_motion_behavior__\(encoded)"
            var candidate = baseID
            var suffix = 2
            let usedIDs = Set(sequences.map(\.id))
            while usedIDs.contains(candidate) {
                candidate = "\(baseID)-\(suffix)"
                suffix += 1
            }
            sequences.append(
                StoredBehaviorSequenceV12(
                    id: candidate,
                    displayName: motionID
                        == PetMotionReference.currentPetDefault
                        ? "기본 애니메이션"
                        : motionID,
                    steps: [
                        StoredBehaviorStepV2(
                            motionID: motionID,
                            repeatCount: 1
                        )
                    ],
                    repeats: true
                )
            )
            motionBehaviorIDs[motionID] = candidate
            return candidate
        }

        let movement = profile.movement
        let migratedMovement = StoredPetMovementSettingsV12(
            mode: movement.mode,
            speed: movement.speed,
            cursorDistance: movement.cursorDistance,
            stopRadius: movement.stopRadius,
            freeRoamingDwellMilliseconds:
                movement.freeRoamingDwellMilliseconds,
            prefersFrontmostWindow: movement.prefersFrontmostWindow,
            cursorFollowingBehavior: migrateMovementBehavior(
                movement.cursorFollowingAnimation,
                behaviorID: behaviorID
            ),
            freeRoamingBehavior: migrateMovementBehavior(
                movement.freeRoamingAnimation,
                behaviorID: behaviorID
            ),
            cursorAvoidingIdleBehavior:
                movement.cursorAvoidingIdleBehavior,
            cursorAvoidingDetectionDistance:
                movement.cursorAvoidingDetectionDistance,
            cursorAvoidingSpeed: movement.cursorAvoidingSpeed,
            cursorAvoidingBehavior: migrateMovementBehavior(
                movement.cursorAvoidingAnimation,
                behaviorID: behaviorID
            )
        )
        let rules = normalizedRules(
            profile.automaticRules,
            field: field,
            issues: &issues
        )
        let pettingBehaviorID = behaviorID(for: profile.pettingMotionID)
        return StoredPetProfileV12(
            profileID: profile.profileID,
            petKey: profile.petKey,
            mode: profile.mode,
            manualSequenceID: profile.manualSequenceID,
            sequences: sequences,
            automaticRules: rules,
            automaticRulePriorityOrder: priorityOrder(for: rules),
            movement: migratedMovement,
            pettingBehaviorID: pettingBehaviorID,
            speech: profile.speech
        )
    }

    private static func migrateMovementBehavior(
        _ animation: StoredMovementAnimationSettingsV5,
        behaviorID: (String?) -> String?
    ) -> StoredMovementBehaviorSettingsV12 {
        let directions = animation.directionMotionIDs
        return StoredMovementBehaviorSettingsV12(
            fallbackBehaviorID: behaviorID(animation.fallbackMotionID),
            usesDirectionalBehaviors: animation.usesDirectionalMotions,
            usesDiagonalBehaviors: animation.usesDiagonalMotions,
            directionBehaviorIDs: StoredDirectionalBehaviorIDsV12(
                left: behaviorID(directions.left),
                right: behaviorID(directions.right),
                up: behaviorID(directions.up),
                down: behaviorID(directions.down),
                upLeft: behaviorID(directions.upLeft),
                upRight: behaviorID(directions.upRight),
                downLeft: behaviorID(directions.downLeft),
                downRight: behaviorID(directions.downRight)
            )
        )
    }

    private static func normalizedRules(
        _ rules: [StoredAutomaticRule],
        field: String,
        issues: inout [SettingsRecoveryIssue]
    ) -> [StoredAutomaticRule] {
        var idleCandidates: [(Int, StoredAutomaticRule)] = []
        var applicationCandidates:
            [String: (index: Int, rule: StoredAutomaticRule)] = [:]
        var unsupportedIndices: Set<Int> = []

        for (index, rule) in rules.enumerated() {
            switch rule.condition {
            case .idleAtLeast:
                idleCandidates.append((index, rule))
            case let .application(bundleIdentifier):
                if let current = applicationCandidates[bundleIdentifier] {
                    if precedes((index, rule), (current.index, current.rule)) {
                        applicationCandidates[bundleIdentifier] = (index, rule)
                        issues.append(
                            .droppedRule(
                                "\(field).automaticRules.\(current.index)"
                            )
                        )
                    } else {
                        issues.append(
                            .droppedRule(
                                "\(field).automaticRules.\(index)"
                            )
                        )
                    }
                } else {
                    applicationCandidates[bundleIdentifier] = (index, rule)
                }
            case .unsupported:
                unsupportedIndices.insert(index)
            }
        }

        let idle = idleCandidates.sorted { precedes($0, $1) }.first
        if idleCandidates.count > 1 {
            for candidate in idleCandidates where candidate.0 != idle?.0 {
                issues.append(
                    .droppedRule(
                        "\(field).automaticRules.\(candidate.0)"
                    )
                )
            }
        }
        var keptIndices = unsupportedIndices
        if let idle { keptIndices.insert(idle.0) }
        keptIndices.formUnion(applicationCandidates.values.map(\.index))
        return rules.enumerated().compactMap { index, rule in
            keptIndices.contains(index) ? rule : nil
        }
    }

    private static func precedes(
        _ lhs: (Int, StoredAutomaticRule),
        _ rhs: (Int, StoredAutomaticRule)
    ) -> Bool {
        lhs.1.priority == rhs.1.priority
            ? lhs.0 < rhs.0
            : lhs.1.priority > rhs.1.priority
    }

    private static func priorityOrder(
        for rules: [StoredAutomaticRule]
    ) -> [String] {
        let bestIdle = rules.compactMap { rule -> Int? in
            if case .idleAtLeast = rule.condition { return rule.priority }
            return nil
        }.max() ?? Int.min
        let bestApplication = rules.compactMap { rule -> Int? in
            if case .application = rule.condition { return rule.priority }
            return nil
        }.max() ?? Int.min
        return bestApplication > bestIdle
            ? ["movement", "application", "idle"]
            : ["movement", "idle", "application"]
    }

    private static func legacyDisplayName(for id: String) -> String {
        id == BuiltInBehaviorPresets.defaultSequenceID ? "기본" : id
    }
}
