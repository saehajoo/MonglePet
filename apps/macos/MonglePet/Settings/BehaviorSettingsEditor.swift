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
            "행동 이름을 입력해 주세요."
        case .duplicateSequenceName:
            "같은 이름의 행동이 이미 있습니다."
        case .sequenceLimitReached:
            "행동은 최대 100개까지 만들 수 있습니다."
        case .sequenceNotFound:
            "행동을 찾을 수 없습니다."
        case .protectedSequence:
            "기본 행동은 삭제할 수 없습니다."
        case .stepLimitReached:
            "행동 단계는 목록마다 최대 100개까지 추가할 수 있습니다."
        case .cannotRemoveLastStep:
            "행동에는 애니메이션 단계가 하나 이상 필요합니다."
        case .invalidStep:
            "펫 애니메이션 또는 반복 횟수가 올바르지 않습니다."
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
        initialMotionID: String = PetMotionReference.currentPetDefault,
        repeats: Bool = false,
        to settings: AppSettings
    ) throws -> AppSettings {
        guard settings.sequences.count < AppSettingsLimits.maximumSequences else {
            throw BehaviorSettingsEditError.sequenceLimitReached
        }
        guard let displayName = normalizedIdentifier(name) else {
            throw BehaviorSettingsEditError.invalidSequenceName
        }
        guard !settings.sequences.contains(where: {
            $0.displayName.compare(displayName, options: .caseInsensitive) == .orderedSame
        }) else {
            throw BehaviorSettingsEditError.duplicateSequenceName
        }
        guard normalizedIdentifier(initialMotionID) == initialMotionID else {
            throw BehaviorSettingsEditError.invalidStep
        }

        let sequenceID = UUID().uuidString.lowercased()
        let sequence = BehaviorSequence(
            id: sequenceID,
            displayName: displayName,
            steps: [BehaviorStep(motionID: initialMotionID, repeatCount: 1)],
            repeats: repeats
        )
        return replacing(
            settings,
            sequences: settings.sequences + [sequence],
            manualSequenceID: settings.manualSequenceID ?? sequenceID,
            automaticRules: settings.automaticRules
        )
    }

    static func renamingSequence(
        id sequenceID: String,
        to name: String,
        in settings: AppSettings
    ) throws -> AppSettings {
        let sequence = try requiredSequence(id: sequenceID, in: settings)
        guard let displayName = normalizedIdentifier(name) else {
            throw BehaviorSettingsEditError.invalidSequenceName
        }
        guard !settings.sequences.contains(where: {
            $0.id != sequenceID
                && $0.displayName.compare(
                    displayName,
                    options: .caseInsensitive
                ) == .orderedSame
        }) else {
            throw BehaviorSettingsEditError.duplicateSequenceName
        }
        return try replacingSequence(
            BehaviorSequence(
                id: sequence.id,
                displayName: displayName,
                steps: sequence.steps,
                repeats: sequence.repeats
            ),
            in: settings
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
        guard !settings.sequences.contains(where: {
            $0.id != sequence.id
                && $0.displayName.compare(
                    sequence.displayName,
                    options: .caseInsensitive
                ) == .orderedSame
        }) else {
            throw BehaviorSettingsEditError.duplicateSequenceName
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
        let movement = PetMovementSettings(
            mode: settings.movementSettings.mode,
            speed: settings.movementSettings.speed,
            cursorDistance: settings.movementSettings.cursorDistance,
            stopRadius: settings.movementSettings.stopRadius,
            freeRoamingDwellMilliseconds:
                settings.movementSettings.freeRoamingDwellMilliseconds,
            prefersFrontmostWindow:
                settings.movementSettings.prefersFrontmostWindow,
            cursorFollowingAnimation: replacingMotionReferences(
                in: settings.movementSettings.cursorFollowingAnimation,
                oldMotionID: sequenceID,
                replacementMotionID: nil
            ),
            freeRoamingAnimation: replacingMotionReferences(
                in: settings.movementSettings.freeRoamingAnimation,
                oldMotionID: sequenceID,
                replacementMotionID: nil
            ),
            cursorAvoidingIdleBehavior:
                settings.movementSettings.cursorAvoidingIdleBehavior,
            cursorAvoidingDetectionDistance:
                settings.movementSettings.cursorAvoidingDetectionDistance,
            cursorAvoidingSpeed:
                settings.movementSettings.cursorAvoidingSpeed,
            cursorAvoidingAnimation: replacingMotionReferences(
                in: settings.movementSettings.cursorAvoidingAnimation,
                oldMotionID: sequenceID,
                replacementMotionID: nil
            ),
            randomizesFreeRoamingDwell:
                settings.movementSettings.randomizesFreeRoamingDwell,
            freeRoamingDwellMinimumMilliseconds:
                settings.movementSettings.freeRoamingDwellMinimumMilliseconds
        )
        let speech = PetSpeechSettings(
            isEnabled: settings.speechSettings.isEnabled,
            periodicIsEnabled:
                settings.speechSettings.periodicIsEnabled,
            periodicIntervalMilliseconds:
                settings.speechSettings.periodicIntervalMilliseconds,
            periodicOrder: settings.speechSettings.periodicOrder,
            behaviorChangePolicy:
                settings.speechSettings.behaviorChangePolicy,
            phrases: settings.speechSettings.phrases.filter { phrase in
                guard case let .sequence(triggerSequenceID) = phrase.trigger else {
                    return true
                }
                return triggerSequenceID != sequenceID
            },
            theme: settings.speechSettings.theme,
            placement: settings.speechSettings.placement
        )
        return replacing(
            settings,
            sequences: sequences,
            manualSequenceID: manualSequenceID,
            automaticRules: automaticRules,
            movement: movement,
            pettingMotionUpdate: settings.pettingBehaviorID == sequenceID
                ? .replacing(nil)
                : .preserving,
            speech: speech
        )
    }

    static func addingStep(
        to sequenceID: String,
        motionID: String = PetMotionReference.currentPetDefault,
        in settings: AppSettings
    ) throws -> AppSettings {
        let sequence = try requiredSequence(id: sequenceID, in: settings)
        guard sequence.steps.count < AppSettingsLimits.maximumStepsPerSequence else {
            throw BehaviorSettingsEditError.stepLimitReached
        }
        guard normalizedIdentifier(motionID) == motionID else {
            throw BehaviorSettingsEditError.invalidStep
        }
        return try replacingSequence(
            BehaviorSequence(
                id: sequence.id,
                displayName: sequence.displayName,
                steps: sequence.steps + [
                    BehaviorStep(motionID: motionID, repeatCount: 1)
                ],
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
            BehaviorSequence(
                id: sequence.id,
                displayName: sequence.displayName,
                steps: steps,
                repeats: sequence.repeats
            ),
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
            BehaviorSequence(
                id: sequence.id,
                displayName: sequence.displayName,
                steps: steps,
                repeats: sequence.repeats
            ),
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
            BehaviorSequence(
                id: sequence.id,
                displayName: sequence.displayName,
                steps: steps,
                repeats: sequence.repeats
            ),
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
                displayName: sequence.displayName,
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
        let normalizedBundleIdentifier = normalizedIdentifier(bundleIdentifier)
        guard
            let normalizedBundleIdentifier,
            !settings.automaticRules.contains(where: {
                guard case let .application(existing) = $0.condition else {
                    return false
                }
                return existing.caseInsensitiveCompare(
                    normalizedBundleIdentifier
                ) == .orderedSame
            })
        else {
            throw BehaviorSettingsEditError.invalidRule
        }
        let condition = RuleCondition.application(bundleIdentifier: bundleIdentifier)
        return try addingRule(
            id: id,
            condition: condition,
            sequenceID: sequenceID,
            to: settings
        )
    }

    static func addingIdleRule(
        seconds: Int,
        sequenceID: String,
        id: UUID = UUID(),
        to settings: AppSettings
    ) throws -> AppSettings {
        try settingIdleRule(
            seconds: seconds,
            sequenceID: sequenceID,
            isEnabled: true,
            id: id,
            in: settings
        )
    }

    static func settingIdleRule(
        seconds: Int,
        sequenceID: String,
        isEnabled: Bool,
        id: UUID = UUID(),
        in settings: AppSettings
    ) throws -> AppSettings {
        guard (1...86_400).contains(seconds) else {
            throw BehaviorSettingsEditError.invalidRule
        }
        if let existing = settings.automaticRules.first(where: {
            if case .idleAtLeast = $0.condition { return true }
            return false
        }) {
            return try replacingRule(
                AutomaticRule(
                    id: existing.id,
                    isEnabled: isEnabled,
                    priority: existing.priority,
                    condition: .idleAtLeast(
                        milliseconds: Int64(seconds) * 1_000
                    ),
                    sequenceID: sequenceID
                ),
                in: settings
            )
        }
        return try addingRule(
            id: id,
            condition: .idleAtLeast(milliseconds: Int64(seconds) * 1_000),
            sequenceID: sequenceID,
            isEnabled: isEnabled,
            to: settings
        )
    }

    static func settingAutomaticRulePriorityOrder(
        _ order: [AutomaticRuleCategory],
        in settings: AppSettings
    ) throws -> AppSettings {
        guard Set(order) == Set(AutomaticRuleCategory.allCases),
              order.count == AutomaticRuleCategory.allCases.count else {
            throw BehaviorSettingsEditError.invalidRule
        }
        return replacing(
            settings,
            sequences: settings.sequences,
            manualSequenceID: settings.manualSequenceID,
            automaticRules: settings.automaticRules,
            automaticRulePriorityOrder: order
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
        guard !settings.automaticRules.contains(where: {
            $0.id != rule.id && conflicts($0.condition, with: rule.condition)
        }) else {
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
        movementReplacementMotionID: String?,
        in settings: AppSettings
    ) throws -> AppSettings {
        guard
            let oldMotionID = normalizedIdentifier(oldMotionID),
            let newMotionID = normalizedIdentifier(newMotionID)
        else {
            throw BehaviorSettingsEditError.invalidStep
        }
        if let movementReplacementMotionID,
           normalizedIdentifier(movementReplacementMotionID)
            != movementReplacementMotionID {
            throw BehaviorSettingsEditError.invalidStep
        }
        let synchronizedSequenceID = settings.sequences.first(where: { sequence in
            sequence.displayName == oldMotionID
                && sequence.steps.count == 1
                && sequence.steps.first?.motionID == oldMotionID
                && !settings.sequences.contains(where: {
                    $0.id != sequence.id
                        && $0.displayName.compare(
                            newMotionID,
                            options: .caseInsensitive
                        ) == .orderedSame
                })
        })?.id
        let sequences = settings.sequences.map { sequence in
            BehaviorSequence(
                id: sequence.id,
                displayName: sequence.id == synchronizedSequenceID
                    ? newMotionID
                    : sequence.displayName,
                steps: sequence.steps.map { step in
                    guard step.motionID == oldMotionID else {
                        return step
                    }
                    return BehaviorStep(
                        motionID: newMotionID,
                        repeatCount: step.repeatCount
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

    static func synchronizingGeneratedSingleStepBehaviorNames(
        in settings: AppSettings
    ) throws -> AppSettings {
        let candidates = Set(
            settings.sequences.compactMap { sequence in
                isGeneratedDuplicateBehavior(sequence) ? sequence.id : nil
            }
        )
        var reservedNames = Set(
            settings.sequences.compactMap { sequence in
                candidates.contains(sequence.id)
                    ? nil
                    : sequence.displayName.lowercased()
            }
        )
        let sequences = settings.sequences.map { sequence in
            guard candidates.contains(sequence.id),
                  let motionID = sequence.steps.first?.motionID,
                  !reservedNames.contains(motionID.lowercased()) else {
                reservedNames.insert(sequence.displayName.lowercased())
                return sequence
            }
            reservedNames.insert(motionID.lowercased())
            return BehaviorSequence(
                id: sequence.id,
                displayName: motionID,
                steps: sequence.steps,
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

    private static func isGeneratedDuplicateBehavior(
        _ sequence: BehaviorSequence
    ) -> Bool {
        guard sequence.steps.count == 1,
              let motionID = sequence.steps.first?.motionID,
              motionID != PetMotionReference.currentPetDefault,
              sequence.displayName != motionID,
              let markerRange = sequence.displayName.range(
                  of: " 복사본",
                  options: .backwards
              ),
              !sequence.displayName[..<markerRange.lowerBound].isEmpty else {
            return false
        }
        let suffix = sequence.displayName[markerRange.upperBound...]
        guard !suffix.isEmpty else {
            return true
        }
        guard suffix.first == " ",
              let copyNumber = Int(suffix.dropFirst()),
              copyNumber >= 2 else {
            return false
        }
        return suffix == " \(copyNumber)"
    }

    private static let defaultStep = BehaviorStep(
        motionID: PetMotionReference.currentPetDefault,
        repeatCount: 1
    )

    private static func addingRule(
        id: UUID,
        condition: RuleCondition,
        sequenceID: String,
        isEnabled: Bool = true,
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
            isEnabled: isEnabled,
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
            && normalizedIdentifier(sequence.displayName)
                == sequence.displayName
            && !sequence.steps.isEmpty
            && sequence.steps.count <= AppSettingsLimits.maximumStepsPerSequence
            && sequence.steps.allSatisfy(isValid)
    }

    private static func isValid(_ step: BehaviorStep) -> Bool {
        guard
            normalizedIdentifier(step.motionID) == step.motionID,
            step.legacyTiming == nil,
            (1...AppSettingsLimits.maximumRepeatCount).contains(step.repeatCount)
        else {
            return false
        }
        return true
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
            return (1_000...AppSettingsLimits.maximumDurationMilliseconds)
                .contains(milliseconds)
        case let .unsupported(type):
            return !rule.isEnabled && normalizedIdentifier(type) == type
        }
    }

    private static func conflicts(
        _ lhs: RuleCondition,
        with rhs: RuleCondition
    ) -> Bool {
        switch (lhs, rhs) {
        case (.idleAtLeast, .idleAtLeast):
            true
        case let (
            .application(lhsIdentifier),
            .application(rhsIdentifier)
        ):
            lhsIdentifier.caseInsensitiveCompare(rhsIdentifier)
                == .orderedSame
        default:
            false
        }
    }

    private static func normalizedIdentifier(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func replacingMotionID(
        _ motionID: String?,
        oldMotionID: String,
        replacementMotionID: String?
    ) -> String? {
        motionID == oldMotionID ? replacementMotionID : motionID
    }

    private static func replacingMotionReferences(
        in animation: MovementAnimationSettings,
        oldMotionID: String,
        replacementMotionID: String?
    ) -> MovementAnimationSettings {
        var directions = animation.directionMotionIDs
        for direction in MovementDirection.allCases
            where directions[direction] == oldMotionID {
            directions = directions.replacing(
                direction,
                with: replacementMotionID
            )
        }
        return MovementAnimationSettings(
            fallbackMotionID: replacingMotionID(
                animation.fallbackMotionID,
                oldMotionID: oldMotionID,
                replacementMotionID: replacementMotionID
            ),
            usesDirectionalMotions: animation.usesDirectionalMotions,
            usesDiagonalMotions: animation.usesDiagonalMotions,
            directionMotionIDs: directions
        )
    }

    private static func replacing(
        _ settings: AppSettings,
        sequences: [BehaviorSequence],
        manualSequenceID: String?,
        automaticRules: [AutomaticRule],
        automaticRulePriorityOrder: [AutomaticRuleCategory]? = nil,
        movement: PetMovementSettings? = nil,
        pettingMotionUpdate: PettingMotionUpdate = .preserving,
        speech: PetSpeechSettings? = nil
    ) -> AppSettings {
        let pettingMotionID = switch pettingMotionUpdate {
        case .preserving:
            settings.pettingMotionID
        case let .replacing(motionID):
            motionID
        }
        return settings.replacingActiveBehaviorProfile(
            BehaviorProfile(
                petKey: settings.selectedPetKey,
                mode: settings.behaviorMode,
                manualSequenceID: manualSequenceID,
                randomSequenceIDs: settings.randomSequenceIDs.filter {
                    sequenceID in
                    sequences.contains(where: { $0.id == sequenceID })
                },
                sequences: sequences,
                automaticRules: automaticRules,
                automaticRulePriorityOrder: automaticRulePriorityOrder
                    ?? settings.automaticRulePriorityOrder,
                movement: movement ?? settings.movementSettings,
                pettingMotionID: pettingMotionID,
                speech: speech ?? settings.speechSettings
            )
        )
    }

    private enum PettingMotionUpdate {
        case preserving
        case replacing(String?)
    }
}
