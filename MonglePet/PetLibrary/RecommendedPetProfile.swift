import Foundation

nonisolated struct RecommendedPetProfile: Equatable, Sendable {
    let mode: BehaviorMode
    let manualSequenceID: String?
    let sequences: [BehaviorSequence]
    let automaticRules: [AutomaticRule]
    let movement: PetMovementSettings
    let pettingMotionID: String?

    func behaviorProfile(for petKey: PetBehaviorKey) -> BehaviorProfile {
        BehaviorProfile(
            petKey: petKey,
            mode: mode,
            manualSequenceID: manualSequenceID,
            sequences: sequences,
            automaticRules: automaticRules,
            movement: movement,
            pettingMotionID: pettingMotionID
        )
    }
}

nonisolated enum RecommendedPetProfileError: Error, Equatable, Sendable {
    case fileTooLarge
    case unreadable
    case unsupportedSchemaVersion(Int)
    case invalidField(String)
}

extension RecommendedPetProfileError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            "권장 설정 파일이 1 MiB 제한을 초과합니다."
        case .unreadable:
            "권장 설정 파일 형식을 읽을 수 없습니다."
        case let .unsupportedSchemaVersion(version):
            "지원하지 않는 권장 설정 스키마 버전입니다: \(version)"
        case let .invalidField(field):
            "권장 설정 값 또는 참조가 올바르지 않습니다: \(field)"
        }
    }
}

nonisolated enum RecommendedPetProfileCodec {
    static let schemaVersion = 1
    static let maximumFileSize = 1 * 1_024 * 1_024

    static func encode(
        _ profile: RecommendedPetProfile,
        for definition: PetDefinition
    ) throws -> Data {
        try validate(profile, for: definition)
        let stored = StoredRecommendedPetProfileV1(
            schemaVersion: schemaVersion,
            behavior: StoredRecommendedBehaviorV1(
                mode: storedMode(profile.mode),
                manualSequenceID: profile.manualSequenceID,
                sequences: profile.sequences.map(storedSequence)
            ),
            movement: storedMovement(profile.movement),
            pettingMotionID: profile.pettingMotionID,
            automaticRules: profile.automaticRules.map(storedRule)
        )

        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [
                .prettyPrinted,
                .sortedKeys,
                .withoutEscapingSlashes
            ]
            data = try encoder.encode(stored)
        } catch {
            throw RecommendedPetProfileError.unreadable
        }
        guard data.count <= maximumFileSize else {
            throw RecommendedPetProfileError.fileTooLarge
        }
        return data
    }

    static func decode(
        _ data: Data,
        for definition: PetDefinition
    ) throws -> RecommendedPetProfile {
        guard data.count <= maximumFileSize else {
            throw RecommendedPetProfileError.fileTooLarge
        }

        let decoder = JSONDecoder()
        let envelope: StoredRecommendedPetProfileEnvelope
        do {
            envelope = try decoder.decode(
                StoredRecommendedPetProfileEnvelope.self,
                from: data
            )
        } catch {
            throw RecommendedPetProfileError.unreadable
        }
        guard envelope.schemaVersion == schemaVersion else {
            throw RecommendedPetProfileError.unsupportedSchemaVersion(
                envelope.schemaVersion
            )
        }

        let stored: StoredRecommendedPetProfileV1
        do {
            stored = try decoder.decode(StoredRecommendedPetProfileV1.self, from: data)
        } catch {
            throw RecommendedPetProfileError.unreadable
        }

        let profile = try domainProfile(from: stored)
        try validate(profile, for: definition)
        return profile
    }

    private static func domainProfile(
        from stored: StoredRecommendedPetProfileV1
    ) throws -> RecommendedPetProfile {
        let mode: BehaviorMode = switch stored.behavior.mode {
        case "automatic": .automatic
        case "manual": .manual
        default:
            throw RecommendedPetProfileError.invalidField("behavior.mode")
        }

        let sequences = stored.behavior.sequences.map { sequence in
            BehaviorSequence(
                id: sequence.id,
                steps: sequence.steps.map {
                    BehaviorStep(
                        motionID: $0.motionID,
                        repeatCount: $0.repeatCount
                    )
                },
                repeats: sequence.repeats
            )
        }
        let movementMode: PetMovementMode = switch stored.movement.mode {
        case "fixed": .fixed
        case "cursorFollowing": .cursorFollowing
        case "freeRoaming": .freeRoaming
        default:
            throw RecommendedPetProfileError.invalidField("movement.mode")
        }
        let automaticRules = try stored.automaticRules.enumerated().map { index, rule in
            guard let id = UUID(uuidString: rule.id) else {
                throw RecommendedPetProfileError.invalidField(
                    "automaticRules.\(index).id"
                )
            }
            let condition: RuleCondition = switch rule.condition {
            case let .application(bundleIdentifier):
                .application(bundleIdentifier: bundleIdentifier)
            case let .idleAtLeast(milliseconds):
                .idleAtLeast(milliseconds: milliseconds)
            case let .unsupported(type):
                .unsupported(type: type)
            }
            return AutomaticRule(
                id: id,
                isEnabled: rule.isEnabled,
                priority: rule.priority,
                condition: condition,
                sequenceID: rule.sequenceID
            )
        }

        return RecommendedPetProfile(
            mode: mode,
            manualSequenceID: stored.behavior.manualSequenceID,
            sequences: sequences,
            automaticRules: automaticRules,
            movement: PetMovementSettings(
                mode: movementMode,
                speed: stored.movement.speed,
                cursorDistance: stored.movement.cursorDistance,
                stopRadius: stored.movement.stopRadius,
                freeRoamingDwellMilliseconds:
                    stored.movement.freeRoamingDwellMilliseconds,
                prefersFrontmostWindow: stored.movement.prefersFrontmostWindow,
                cursorFollowingMotionID:
                    stored.movement.cursorFollowingMotionID,
                freeRoamingMotionID: stored.movement.freeRoamingMotionID
            ),
            pettingMotionID: stored.pettingMotionID
        )
    }

    private static func validate(
        _ profile: RecommendedPetProfile,
        for definition: PetDefinition
    ) throws {
        guard
            !profile.sequences.isEmpty,
            profile.sequences.count <= AppSettingsLimits.maximumSequences
        else {
            throw RecommendedPetProfileError.invalidField("behavior.sequences")
        }

        var sequenceIDs: Set<String> = []
        for (sequenceIndex, sequence) in profile.sequences.enumerated() {
            let sequencePath = "behavior.sequences.\(sequenceIndex)"
            guard
                isNormalizedIdentifier(sequence.id),
                sequenceIDs.insert(sequence.id).inserted,
                !sequence.steps.isEmpty,
                sequence.steps.count <= AppSettingsLimits.maximumStepsPerSequence
            else {
                throw RecommendedPetProfileError.invalidField(sequencePath)
            }
            for (stepIndex, step) in sequence.steps.enumerated() {
                guard
                    isKnownBehaviorMotion(step.motionID, in: definition),
                    step.legacyTiming == nil,
                    (1...AppSettingsLimits.maximumRepeatCount)
                        .contains(step.repeatCount)
                else {
                    throw RecommendedPetProfileError.invalidField(
                        "\(sequencePath).steps.\(stepIndex)"
                    )
                }
            }
        }

        if let manualSequenceID = profile.manualSequenceID {
            guard
                isNormalizedIdentifier(manualSequenceID),
                sequenceIDs.contains(manualSequenceID)
            else {
                throw RecommendedPetProfileError.invalidField(
                    "behavior.manualSequenceID"
                )
            }
        } else if profile.mode == .manual {
            throw RecommendedPetProfileError.invalidField(
                "behavior.manualSequenceID"
            )
        }

        guard profile.automaticRules.count <= AppSettingsLimits.maximumAutomaticRules else {
            throw RecommendedPetProfileError.invalidField("automaticRules")
        }
        var ruleIDs: Set<UUID> = []
        for (ruleIndex, rule) in profile.automaticRules.enumerated() {
            let rulePath = "automaticRules.\(ruleIndex)"
            guard
                ruleIDs.insert(rule.id).inserted,
                isNormalizedIdentifier(rule.sequenceID),
                sequenceIDs.contains(rule.sequenceID)
            else {
                throw RecommendedPetProfileError.invalidField(rulePath)
            }
            switch rule.condition {
            case let .application(bundleIdentifier):
                guard isNormalizedIdentifier(bundleIdentifier) else {
                    throw RecommendedPetProfileError.invalidField(
                        "\(rulePath).condition"
                    )
                }
            case let .idleAtLeast(milliseconds):
                guard
                    (1...AppSettingsLimits.maximumDurationMilliseconds)
                        .contains(milliseconds)
                else {
                    throw RecommendedPetProfileError.invalidField(
                        "\(rulePath).condition"
                    )
                }
            case .unsupported:
                throw RecommendedPetProfileError.invalidField(
                    "\(rulePath).condition"
                )
            }
        }

        guard profile.movement.isValid else {
            throw RecommendedPetProfileError.invalidField("movement")
        }
        try validateOptionalMotion(
            profile.movement.cursorFollowingMotionID,
            field: "movement.cursorFollowingMotionID",
            definition: definition
        )
        try validateOptionalMotion(
            profile.movement.freeRoamingMotionID,
            field: "movement.freeRoamingMotionID",
            definition: definition
        )
        try validateOptionalMotion(
            profile.pettingMotionID,
            field: "pettingMotionID",
            definition: definition
        )
    }

    private static func validateOptionalMotion(
        _ motionID: String?,
        field: String,
        definition: PetDefinition
    ) throws {
        guard let motionID else {
            return
        }
        guard isConcreteMotion(motionID, in: definition) else {
            throw RecommendedPetProfileError.invalidField(field)
        }
    }

    private static func isKnownBehaviorMotion(
        _ motionID: String,
        in definition: PetDefinition
    ) -> Bool {
        motionID == PetMotionReference.currentPetDefault
            || isConcreteMotion(motionID, in: definition)
    }

    private static func isConcreteMotion(
        _ motionID: String,
        in definition: PetDefinition
    ) -> Bool {
        isNormalizedIdentifier(motionID)
            && definition.motion(id: motionID) != nil
    }

    private static func isNormalizedIdentifier(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed == value
    }

    private static func storedMode(_ mode: BehaviorMode) -> String {
        switch mode {
        case .automatic: "automatic"
        case .manual: "manual"
        }
    }

    private static func storedMovement(
        _ movement: PetMovementSettings
    ) -> StoredRecommendedMovementV1 {
        let mode: String = switch movement.mode {
        case .fixed: "fixed"
        case .cursorFollowing: "cursorFollowing"
        case .freeRoaming: "freeRoaming"
        }
        return StoredRecommendedMovementV1(
            mode: mode,
            speed: movement.speed,
            cursorDistance: movement.cursorDistance,
            stopRadius: movement.stopRadius,
            freeRoamingDwellMilliseconds:
                movement.freeRoamingDwellMilliseconds,
            prefersFrontmostWindow: movement.prefersFrontmostWindow,
            cursorFollowingMotionID: movement.cursorFollowingMotionID,
            freeRoamingMotionID: movement.freeRoamingMotionID
        )
    }

    private static func storedSequence(
        _ sequence: BehaviorSequence
    ) -> StoredRecommendedBehaviorSequenceV1 {
        StoredRecommendedBehaviorSequenceV1(
            id: sequence.id,
            steps: sequence.steps.map {
                StoredRecommendedBehaviorStepV1(
                    motionID: $0.motionID,
                    repeatCount: $0.repeatCount
                )
            },
            repeats: sequence.repeats
        )
    }

    private static func storedRule(
        _ rule: AutomaticRule
    ) -> StoredRecommendedAutomaticRuleV1 {
        let condition: StoredRecommendedRuleConditionV1 = switch rule.condition {
        case let .application(bundleIdentifier):
            .application(bundleIdentifier: bundleIdentifier)
        case let .idleAtLeast(milliseconds):
            .idleAtLeast(milliseconds: milliseconds)
        case let .unsupported(type):
            .unsupported(type: type)
        }
        return StoredRecommendedAutomaticRuleV1(
            id: rule.id.uuidString,
            isEnabled: rule.isEnabled,
            priority: rule.priority,
            condition: condition,
            sequenceID: rule.sequenceID
        )
    }
}

private nonisolated struct StoredRecommendedPetProfileEnvelope: Decodable {
    let schemaVersion: Int
}

private nonisolated struct StoredRecommendedPetProfileV1: Codable {
    let schemaVersion: Int
    let behavior: StoredRecommendedBehaviorV1
    let movement: StoredRecommendedMovementV1
    let pettingMotionID: String?
    let automaticRules: [StoredRecommendedAutomaticRuleV1]
}

private nonisolated struct StoredRecommendedBehaviorV1: Codable {
    let mode: String
    let manualSequenceID: String?
    let sequences: [StoredRecommendedBehaviorSequenceV1]
}

private nonisolated struct StoredRecommendedBehaviorSequenceV1: Codable {
    let id: String
    let steps: [StoredRecommendedBehaviorStepV1]
    let repeats: Bool
}

private nonisolated struct StoredRecommendedBehaviorStepV1: Codable {
    let motionID: String
    let repeatCount: Int
}

private nonisolated struct StoredRecommendedMovementV1: Codable {
    let mode: String
    let speed: Double
    let cursorDistance: Double
    let stopRadius: Double
    let freeRoamingDwellMilliseconds: Int64
    let prefersFrontmostWindow: Bool
    let cursorFollowingMotionID: String?
    let freeRoamingMotionID: String?
}

private nonisolated struct StoredRecommendedAutomaticRuleV1: Codable {
    let id: String
    let isEnabled: Bool
    let priority: Int
    let condition: StoredRecommendedRuleConditionV1
    let sequenceID: String
}

private nonisolated enum StoredRecommendedRuleConditionV1: Equatable {
    case application(bundleIdentifier: String)
    case idleAtLeast(milliseconds: Int64)
    case unsupported(type: String)
}

extension StoredRecommendedRuleConditionV1: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case bundleIdentifier
        case milliseconds
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "application":
            self = .application(
                bundleIdentifier: try container.decode(
                    String.self,
                    forKey: .bundleIdentifier
                )
            )
        case "idleAtLeast":
            self = .idleAtLeast(
                milliseconds: try container.decode(
                    Int64.self,
                    forKey: .milliseconds
                )
            )
        default:
            self = .unsupported(type: type)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .application(bundleIdentifier):
            try container.encode("application", forKey: .type)
            try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
        case let .idleAtLeast(milliseconds):
            try container.encode("idleAtLeast", forKey: .type)
            try container.encode(milliseconds, forKey: .milliseconds)
        case let .unsupported(type):
            try container.encode(type, forKey: .type)
        }
    }
}
