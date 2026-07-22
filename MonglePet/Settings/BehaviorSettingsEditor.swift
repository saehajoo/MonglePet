import Foundation

nonisolated enum BehaviorSettingsEditError: Error, Equatable, Sendable {
    case invalidSequenceName
    case duplicateSequenceName
    case sequenceLimitReached
    case sequenceNotFound
    case protectedSequence
    case stepLimitReached
    case cannotRemoveLastStep
    case invalidStep
    case invalidStepIndex
    case ruleLimitReached
    case ruleNotFound
    case invalidRule
}

extension BehaviorSettingsEditError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidSequenceName:
            "행동 루틴 이름을 입력해 주세요."
        case .duplicateSequenceName:
            "같은 이름의 행동 루틴이 이미 있습니다."
        case .sequenceLimitReached:
            "행동 루틴은 최대 100개까지 만들 수 있습니다."
        case .sequenceNotFound:
            "행동 루틴을 찾을 수 없습니다."
        case .protectedSequence:
            "기본 행동 루틴은 삭제할 수 없습니다."
        case .stepLimitReached:
            "행동 단계는 목록마다 최대 100개까지 추가할 수 있습니다."
        case .cannotRemoveLastStep:
            "행동 루틴에는 애니메이션 단계가 하나 이상 필요합니다."
        case .invalidStep:
            "펫 애니메이션, 실행 시간 또는 재생 속도가 올바르지 않습니다."
        case .invalidStepIndex:
            "편집할 행동 단계를 찾을 수 없습니다."
        case .ruleLimitReached:
            "자동 규칙은 최대 100개까지 추가할 수 있습니다."
        case .ruleNotFound:
            "자동 규칙을 찾을 수 없습니다."
        case .invalidRule:
            "자동 규칙의 조건 또는 행동 루틴이 올바르지 않습니다."
        }
    }
}

nonisolated enum BehaviorSettingsEditor {
    static let protectedSequenceIDs: Set<String> = [
        BuiltInBehaviorPresets.defaultSequenceID
    ]

    static func addingSequence(
        named name: String,
        to settings: AppSettings
    ) throws -> AppSettings {
        guard settings.sequences.count < AppSettingsLimits.maximumSequences else {
            throw BehaviorSettingsEditError.sequenceLimitReached
        }
        guard let sequenceID = normalizedIdentifier(name) else {
            throw BehaviorSettingsEditError.invalidSequenceName
        }
        guard !settings.sequences.contains(where: {
            $0.id.compare(sequenceID, options: .caseInsensitive) == .orderedSame
        }) else {
            throw BehaviorSettingsEditError.duplicateSequenceName
        }

        let sequence = BehaviorSequence(
            id: sequenceID,
            steps: [defaultStep],
            repeats: true
        )
        return replacing(
            settings,
            sequences: settings.sequences + [sequence],
            manualSequenceID: settings.manualSequenceID ?? sequenceID,
            automaticRules: settings.automaticRules
        )
    }

    static func replacingSequence(
        _ sequence: BehaviorSequence,
        in settings: AppSettings
    ) throws -> AppSettings {
        guard let index = settings.sequences.firstIndex(where: { $0.id == sequence.id }) else {
            throw BehaviorSettingsEditError.sequenceNotFound
        }
        guard isValid(sequence) else {
            throw BehaviorSettingsEditError.invalidStep
        }

        var sequences = settings.sequences
        sequences[index] = sequence
        return replacing(
            settings,
            sequences: sequences,
            manualSequenceID: settings.manualSequenceID,
            automaticRules: settings.automaticRules
        )
    }

    static func removingSequence(
        id sequenceID: String,
        from settings: AppSettings
    ) throws -> AppSettings {
        guard settings.sequences.contains(where: { $0.id == sequenceID }) else {
            throw BehaviorSettingsEditError.sequenceNotFound
        }
        guard !protectedSequenceIDs.contains(sequenceID) else {
            throw BehaviorSettingsEditError.protectedSequence
        }

        let sequences = settings.sequences.filter { $0.id != sequenceID }
        let fallbackSequenceID = sequences.first(where: {
            $0.id == BuiltInBehaviorPresets.defaultSequenceID
        })?.id
            ?? sequences.first?.id
        let manualSequenceID = settings.manualSequenceID == sequenceID
            ? fallbackSequenceID
            : settings.manualSequenceID
        let automaticRules = settings.automaticRules.filter {
            $0.sequenceID != sequenceID
        }
        return replacing(
            settings,
            sequences: sequences,
            manualSequenceID: manualSequenceID,
            automaticRules: automaticRules
        )
    }

    static func addingStep(
        to sequenceID: String,
        in settings: AppSettings
    ) throws -> AppSettings {
        let sequence = try requiredSequence(id: sequenceID, in: settings)
        guard sequence.steps.count < AppSettingsLimits.maximumStepsPerSequence else {
            throw BehaviorSettingsEditError.stepLimitReached
        }
        return try replacingSequence(
            BehaviorSequence(
                id: sequence.id,
                steps: sequence.steps + [defaultStep],
                repeats: sequence.repeats
            ),
            in: settings
        )
    }

    static func replacingStep(
        in sequenceID: String,
        at index: Int,
        with step: BehaviorStep,
        settings: AppSettings
    ) throws -> AppSettings {
        let sequence = try requiredSequence(id: sequenceID, in: settings)
        guard sequence.steps.indices.contains(index) else {
            throw BehaviorSettingsEditError.invalidStepIndex
        }
        guard isValid(step) else {
            throw BehaviorSettingsEditError.invalidStep
        }

        var steps = sequence.steps
        steps[index] = step
        return try replacingSequence(
            BehaviorSequence(id: sequence.id, steps: steps, repeats: sequence.repeats),
            in: settings
        )
    }

    static func removingStep(
        from sequenceID: String,
        at index: Int,
        settings: AppSettings
    ) throws -> AppSettings {
        let sequence = try requiredSequence(id: sequenceID, in: settings)
        guard sequence.steps.indices.contains(index) else {
            throw BehaviorSettingsEditError.invalidStepIndex
        }
        guard sequence.steps.count > 1 else {
            throw BehaviorSettingsEditError.cannotRemoveLastStep
        }

        var steps = sequence.steps
        steps.remove(at: index)
        return try replacingSequence(
            BehaviorSequence(id: sequence.id, steps: steps, repeats: sequence.repeats),
            in: settings
        )
    }

    static func movingStep(
        in sequenceID: String,
        from sourceIndex: Int,
        to destinationIndex: Int,
        settings: AppSettings
    ) throws -> AppSettings {
        let sequence = try requiredSequence(id: sequenceID, in: settings)
        guard
            sequence.steps.indices.contains(sourceIndex),
            sequence.steps.indices.contains(destinationIndex)
        else {
            throw BehaviorSettingsEditError.invalidStepIndex
        }
        guard sourceIndex != destinationIndex else {
            return settings
        }

        var steps = sequence.steps
        let step = steps.remove(at: sourceIndex)
        steps.insert(step, at: destinationIndex)
        return try replacingSequence(
            BehaviorSequence(id: sequence.id, steps: steps, repeats: sequence.repeats),
            in: settings
        )
    }

    static func settingRepeats(
        _ repeats: Bool,
        for sequenceID: String,
        in settings: AppSettings
    ) throws -> AppSettings {
        let sequence = try requiredSequence(id: sequenceID, in: settings)
        return try replacingSequence(
            BehaviorSequence(
                id: sequence.id,
                steps: sequence.steps,
                repeats: repeats
            ),
            in: settings
        )
    }

    static func addingApplicationRule(
        bundleIdentifier: String,
        sequenceID: String,
        id: UUID = UUID(),
        to settings: AppSettings
    ) throws -> AppSettings {
        let condition = RuleCondition.application(bundleIdentifier: bundleIdentifier)
        return try addingRule(
            id: id,
            condition: condition,
            sequenceID: sequenceID,
            to: settings
        )
    }

    static func addingIdleRule(
        minutes: Int,
        sequenceID: String,
        id: UUID = UUID(),
        to settings: AppSettings
    ) throws -> AppSettings {
        guard (1...1_440).contains(minutes) else {
            throw BehaviorSettingsEditError.invalidRule
        }
        return try addingRule(
            id: id,
            condition: .idleAtLeast(milliseconds: Int64(minutes) * 60_000),
            sequenceID: sequenceID,
            to: settings
        )
    }

    static func replacingRule(
        _ rule: AutomaticRule,
        in settings: AppSettings
    ) throws -> AppSettings {
        guard let index = settings.automaticRules.firstIndex(where: { $0.id == rule.id }) else {
            throw BehaviorSettingsEditError.ruleNotFound
        }
        guard isValid(rule, sequenceIDs: Set(settings.sequences.map(\.id))) else {
            throw BehaviorSettingsEditError.invalidRule
        }

        var rules = settings.automaticRules
        rules[index] = rule
        return replacing(
            settings,
            sequences: settings.sequences,
            manualSequenceID: settings.manualSequenceID,
            automaticRules: rules
        )
    }

    static func removingRule(
        id: UUID,
        from settings: AppSettings
    ) throws -> AppSettings {
        guard settings.automaticRules.contains(where: { $0.id == id }) else {
            throw BehaviorSettingsEditError.ruleNotFound
        }
        return replacing(
            settings,
            sequences: settings.sequences,
            manualSequenceID: settings.manualSequenceID,
            automaticRules: settings.automaticRules.filter { $0.id != id }
        )
    }

    static func replacingMotionReferences(
        from oldMotionID: String,
        with newMotionID: String,
        in settings: AppSettings
    ) throws -> AppSettings {
        guard
            let oldMotionID = normalizedIdentifier(oldMotionID),
            let newMotionID = normalizedIdentifier(newMotionID)
        else {
            throw BehaviorSettingsEditError.invalidStep
        }
        let sequences = settings.sequences.map { sequence in
            BehaviorSequence(
                id: sequence.id,
                steps: sequence.steps.map { step in
                    guard step.motionID == oldMotionID else {
                        return step
                    }
                    return BehaviorStep(
                        motionID: newMotionID,
                        duration: step.duration,
                        playbackSpeed: step.playbackSpeed
                    )
                },
                repeats: sequence.repeats
            )
        }
        guard sequences.allSatisfy(isValid) else {
            throw BehaviorSettingsEditError.invalidStep
        }
        return replacing(
            settings,
            sequences: sequences,
            manualSequenceID: settings.manualSequenceID,
            automaticRules: settings.automaticRules
        )
    }

    static func durationSeconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }

    private static let defaultStep = BehaviorStep(
        motionID: PetMotionReference.currentPetDefault,
        duration: BuiltInBehaviorPresets.stepDuration,
        playbackSpeed: 1
    )

    private static func addingRule(
        id: UUID,
        condition: RuleCondition,
        sequenceID: String,
        to settings: AppSettings
    ) throws -> AppSettings {
        guard settings.automaticRules.count < AppSettingsLimits.maximumAutomaticRules else {
            throw BehaviorSettingsEditError.ruleLimitReached
        }
        guard !settings.automaticRules.contains(where: { $0.id == id }) else {
            throw BehaviorSettingsEditError.invalidRule
        }
        let maximumPriority = settings.automaticRules.map(\.priority).max() ?? -1
        let nextPriority = maximumPriority == Int.max
            ? Int.max
            : maximumPriority + 1
        let rule = AutomaticRule(
            id: id,
            isEnabled: true,
            priority: nextPriority,
            condition: condition,
            sequenceID: sequenceID
        )
        guard isValid(rule, sequenceIDs: Set(settings.sequences.map(\.id))) else {
            throw BehaviorSettingsEditError.invalidRule
        }
        return replacing(
            settings,
            sequences: settings.sequences,
            manualSequenceID: settings.manualSequenceID,
            automaticRules: settings.automaticRules + [rule]
        )
    }

    private static func requiredSequence(
        id: String,
        in settings: AppSettings
    ) throws -> BehaviorSequence {
        guard let sequence = settings.sequences.first(where: { $0.id == id }) else {
            throw BehaviorSettingsEditError.sequenceNotFound
        }
        return sequence
    }

    private static func isValid(_ sequence: BehaviorSequence) -> Bool {
        normalizedIdentifier(sequence.id) == sequence.id
            && !sequence.steps.isEmpty
            && sequence.steps.count <= AppSettingsLimits.maximumStepsPerSequence
            && sequence.steps.allSatisfy(isValid)
    }

    private static func isValid(_ step: BehaviorStep) -> Bool {
        guard
            normalizedIdentifier(step.motionID) == step.motionID,
            step.duration > .zero,
            step.duration <= .milliseconds(AppSettingsLimits.maximumDurationMilliseconds),
            step.playbackSpeed.isFinite
        else {
            return false
        }
        return (AppSettingsLimits.minimumPlaybackSpeed
            ... AppSettingsLimits.maximumPlaybackSpeed)
            .contains(step.playbackSpeed)
    }

    private static func isValid(
        _ rule: AutomaticRule,
        sequenceIDs: Set<String>
    ) -> Bool {
        guard sequenceIDs.contains(rule.sequenceID) else {
            return false
        }
        switch rule.condition {
        case let .application(bundleIdentifier):
            guard let normalized = normalizedIdentifier(bundleIdentifier) else {
                return false
            }
            return normalized == bundleIdentifier
                && !bundleIdentifier.contains(where: { $0.isWhitespace })
        case let .idleAtLeast(milliseconds):
            return (60_000...AppSettingsLimits.maximumDurationMilliseconds)
                .contains(milliseconds)
        case let .unsupported(type):
            return !rule.isEnabled && normalizedIdentifier(type) == type
        }
    }

    private static func normalizedIdentifier(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func replacing(
        _ settings: AppSettings,
        sequences: [BehaviorSequence],
        manualSequenceID: String?,
        automaticRules: [AutomaticRule]
    ) -> AppSettings {
        AppSettings(
            selectedPetInstallationID: settings.selectedPetInstallationID,
            lastUserPresentation: settings.lastUserPresentation,
            behaviorMode: settings.behaviorMode,
            overlay: settings.overlay,
            manualSequenceID: manualSequenceID,
            sequences: sequences,
            automaticRules: automaticRules
        )
    }
}
