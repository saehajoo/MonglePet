import Foundation

nonisolated enum AppSettingsMappingError: Error, Equatable, Sendable {
    case invalidSettings(String)
}

extension AppSettingsMappingError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .invalidSettings(field):
            "저장할 설정 값이 올바르지 않습니다: \(field)"
        }
    }
}

nonisolated enum AppSettingsMapper {
    static func domainSettings(
        from stored: StoredAppSettings
    ) -> (settings: AppSettings, issues: [SettingsRecoveryIssue]) {
        var issues: [SettingsRecoveryIssue] = []

        let selectedPetInstallationID: UUID?
        if let storedID = stored.selectedPetInstallationID {
            selectedPetInstallationID = UUID(uuidString: storedID)
            if selectedPetInstallationID == nil {
                issues.append(.invalidField("selectedPetInstallationID"))
            }
        } else {
            selectedPetInstallationID = nil
        }

        let presentation: PetPresentation
        switch stored.lastUserPresentation {
        case "awake":
            presentation = .awake
        case "tuckedAway":
            presentation = .tuckedAway
        default:
            presentation = .awake
            issues.append(.invalidField("lastUserPresentation"))
        }

        let behaviorMode: BehaviorMode
        switch stored.behaviorMode {
        case "automatic":
            behaviorMode = .automatic
        case "manual":
            behaviorMode = .manual
        default:
            behaviorMode = .automatic
            issues.append(.invalidField("behaviorMode"))
        }

        let overlay = normalizedOverlay(from: stored.overlay, issues: &issues)
        let sequences = normalizedSequences(from: stored.sequences, issues: &issues)
        let sequenceIDs = Set(sequences.map(\.id))

        let manualSequenceID: String?
        if let candidate = normalizedIdentifier(stored.manualSequenceID) {
            if sequenceIDs.contains(candidate) {
                manualSequenceID = candidate
            } else {
                manualSequenceID = nil
                issues.append(.invalidField("manualSequenceID"))
            }
        } else {
            manualSequenceID = nil
            if stored.manualSequenceID != nil {
                issues.append(.invalidField("manualSequenceID"))
            }
        }

        let automaticRules = normalizedRules(
            from: stored.automaticRules,
            validSequenceIDs: sequenceIDs,
            issues: &issues
        )

        return (
            AppSettings(
                selectedPetInstallationID: selectedPetInstallationID,
                lastUserPresentation: presentation,
                behaviorMode: behaviorMode,
                overlay: overlay,
                manualSequenceID: manualSequenceID,
                sequences: sequences,
                automaticRules: automaticRules
            ),
            issues
        )
    }

    static func storedSettings(from settings: AppSettings) throws -> StoredAppSettings {
        guard settings.lastUserPresentation == .awake
            || settings.lastUserPresentation == .tuckedAway
        else {
            throw AppSettingsMappingError.invalidSettings("lastUserPresentation")
        }
        try validateOverlay(settings.overlay)
        guard settings.sequences.count <= AppSettingsLimits.maximumSequences else {
            throw AppSettingsMappingError.invalidSettings("sequences")
        }
        guard settings.automaticRules.count <= AppSettingsLimits.maximumAutomaticRules else {
            throw AppSettingsMappingError.invalidSettings("automaticRules")
        }

        var sequenceIDs: Set<String> = []
        let storedSequences = try settings.sequences.map { sequence in
            guard
                normalizedIdentifier(sequence.id) == sequence.id,
                sequenceIDs.insert(sequence.id).inserted,
                !sequence.steps.isEmpty,
                sequence.steps.count <= AppSettingsLimits.maximumStepsPerSequence
            else {
                throw AppSettingsMappingError.invalidSettings("sequences.\(sequence.id)")
            }

            let steps = try sequence.steps.map { step in
                guard
                    normalizedIdentifier(step.motionID) == step.motionID,
                    let milliseconds = durationMilliseconds(step.duration),
                    (1...AppSettingsLimits.maximumDurationMilliseconds).contains(milliseconds),
                    step.playbackSpeed.isFinite,
                    step.playbackSpeed >= AppSettingsLimits.minimumPlaybackSpeed,
                    step.playbackSpeed <= AppSettingsLimits.maximumPlaybackSpeed
                else {
                    throw AppSettingsMappingError.invalidSettings(
                        "sequences.\(sequence.id).steps"
                    )
                }

                return StoredBehaviorStep(
                    motionID: step.motionID,
                    durationMilliseconds: milliseconds,
                    playbackSpeed: step.playbackSpeed
                )
            }

            return StoredBehaviorSequence(
                id: sequence.id,
                steps: steps,
                repeats: sequence.repeats
            )
        }

        if let manualSequenceID = settings.manualSequenceID,
           !sequenceIDs.contains(manualSequenceID) {
            throw AppSettingsMappingError.invalidSettings("manualSequenceID")
        }

        var ruleIDs: Set<UUID> = []
        let storedRules = try settings.automaticRules.map { rule in
            guard
                ruleIDs.insert(rule.id).inserted,
                normalizedIdentifier(rule.sequenceID) == rule.sequenceID
            else {
                throw AppSettingsMappingError.invalidSettings("automaticRules")
            }
            if rule.isEnabled, !sequenceIDs.contains(rule.sequenceID) {
                throw AppSettingsMappingError.invalidSettings(
                    "automaticRules.\(rule.id.uuidString).sequenceID"
                )
            }

            let condition: StoredRuleCondition
            switch rule.condition {
            case let .application(bundleIdentifier):
                guard !rule.isEnabled || normalizedIdentifier(bundleIdentifier) == bundleIdentifier else {
                    throw AppSettingsMappingError.invalidSettings(
                        "automaticRules.\(rule.id.uuidString).condition"
                    )
                }
                condition = .application(bundleIdentifier: bundleIdentifier)
            case let .idleAtLeast(milliseconds):
                guard !rule.isEnabled || (1...AppSettingsLimits.maximumDurationMilliseconds)
                    .contains(milliseconds)
                else {
                    throw AppSettingsMappingError.invalidSettings(
                        "automaticRules.\(rule.id.uuidString).condition"
                    )
                }
                condition = .idleAtLeast(milliseconds: milliseconds)
            case let .unsupported(type):
                guard !rule.isEnabled, normalizedIdentifier(type) != nil else {
                    throw AppSettingsMappingError.invalidSettings(
                        "automaticRules.\(rule.id.uuidString).condition"
                    )
                }
                condition = .unsupported(type: type)
            }

            return StoredAutomaticRule(
                id: rule.id.uuidString,
                isEnabled: rule.isEnabled,
                priority: rule.priority,
                condition: condition,
                sequenceID: rule.sequenceID
            )
        }

        return StoredAppSettings(
            schemaVersion: AppSettingsLimits.schemaVersion,
            selectedPetInstallationID: settings.selectedPetInstallationID?.uuidString,
            lastUserPresentation: settings.lastUserPresentation == .awake
                ? "awake"
                : "tuckedAway",
            behaviorMode: settings.behaviorMode == .automatic ? "automatic" : "manual",
            overlay: StoredOverlaySettings(
                screenIdentifier: settings.overlay.screenIdentifier,
                originX: settings.overlay.originX,
                originY: settings.overlay.originY,
                width: settings.overlay.width,
                clickThrough: settings.overlay.clickThrough
            ),
            manualSequenceID: settings.manualSequenceID,
            sequences: storedSequences,
            automaticRules: storedRules
        )
    }

    private static func normalizedOverlay(
        from stored: StoredOverlaySettings,
        issues: inout [SettingsRecoveryIssue]
    ) -> OverlaySettings {
        let screenIdentifier = normalizedIdentifier(stored.screenIdentifier)
        if stored.screenIdentifier != nil, screenIdentifier == nil {
            issues.append(.invalidField("overlay.screenIdentifier"))
        }

        let originX: Double
        if stored.originX.isFinite {
            originX = stored.originX
        } else {
            originX = OverlaySettings.default.originX
            issues.append(.invalidField("overlay.originX"))
        }

        let originY: Double
        if stored.originY.isFinite {
            originY = stored.originY
        } else {
            originY = OverlaySettings.default.originY
            issues.append(.invalidField("overlay.originY"))
        }

        let width: Double
        if stored.width.isFinite {
            width = min(
                max(stored.width, AppSettingsLimits.minimumOverlayWidth),
                AppSettingsLimits.maximumOverlayWidth
            )
            if width != stored.width {
                issues.append(.invalidField("overlay.width"))
            }
        } else {
            width = AppSettingsLimits.defaultOverlayWidth
            issues.append(.invalidField("overlay.width"))
        }

        return OverlaySettings(
            screenIdentifier: screenIdentifier,
            originX: originX,
            originY: originY,
            width: width,
            clickThrough: stored.clickThrough
        )
    }

    private static func normalizedSequences(
        from storedSequences: [StoredBehaviorSequence],
        issues: inout [SettingsRecoveryIssue]
    ) -> [BehaviorSequence] {
        if storedSequences.count > AppSettingsLimits.maximumSequences {
            issues.append(.truncatedCollection("sequences"))
        }

        var seenIDs: Set<String> = []
        var sequences: [BehaviorSequence] = []
        for stored in storedSequences.prefix(AppSettingsLimits.maximumSequences) {
            guard
                let id = normalizedIdentifier(stored.id),
                seenIDs.insert(id).inserted
            else {
                issues.append(.droppedSequence(stored.id))
                continue
            }
            if stored.steps.count > AppSettingsLimits.maximumStepsPerSequence {
                issues.append(.truncatedCollection("sequences.\(id).steps"))
            }

            let steps = stored.steps
                .prefix(AppSettingsLimits.maximumStepsPerSequence)
                .compactMap { storedStep -> BehaviorStep? in
                    guard
                        let motionID = normalizedIdentifier(storedStep.motionID),
                        (1...AppSettingsLimits.maximumDurationMilliseconds)
                            .contains(storedStep.durationMilliseconds),
                        storedStep.playbackSpeed.isFinite,
                        storedStep.playbackSpeed >= AppSettingsLimits.minimumPlaybackSpeed,
                        storedStep.playbackSpeed <= AppSettingsLimits.maximumPlaybackSpeed
                    else {
                        issues.append(.invalidField("sequences.\(id).steps"))
                        return nil
                    }

                    return BehaviorStep(
                        motionID: motionID,
                        duration: .milliseconds(storedStep.durationMilliseconds),
                        playbackSpeed: storedStep.playbackSpeed
                    )
                }

            guard !steps.isEmpty else {
                issues.append(.droppedSequence(id))
                continue
            }
            sequences.append(
                BehaviorSequence(id: id, steps: steps, repeats: stored.repeats)
            )
        }
        return sequences
    }

    private static func normalizedRules(
        from storedRules: [StoredAutomaticRule],
        validSequenceIDs: Set<String>,
        issues: inout [SettingsRecoveryIssue]
    ) -> [AutomaticRule] {
        if storedRules.count > AppSettingsLimits.maximumAutomaticRules {
            issues.append(.truncatedCollection("automaticRules"))
        }

        var seenIDs: Set<UUID> = []
        var rules: [AutomaticRule] = []
        for stored in storedRules.prefix(AppSettingsLimits.maximumAutomaticRules) {
            guard
                let id = UUID(uuidString: stored.id),
                seenIDs.insert(id).inserted,
                let sequenceID = normalizedIdentifier(stored.sequenceID)
            else {
                issues.append(.droppedRule(stored.id))
                continue
            }

            var isEnabled = stored.isEnabled
            let condition: RuleCondition
            switch stored.condition {
            case let .application(bundleIdentifier):
                if let normalizedBundleIdentifier = normalizedIdentifier(bundleIdentifier) {
                    condition = .application(bundleIdentifier: normalizedBundleIdentifier)
                    if normalizedBundleIdentifier != bundleIdentifier {
                        issues.append(
                            .invalidField("automaticRules.\(stored.id).condition")
                        )
                    }
                } else {
                    condition = .application(bundleIdentifier: "")
                    isEnabled = false
                }
            case let .idleAtLeast(milliseconds):
                condition = .idleAtLeast(milliseconds: milliseconds)
                if !(1...AppSettingsLimits.maximumDurationMilliseconds).contains(milliseconds) {
                    isEnabled = false
                }
            case let .unsupported(type):
                condition = .unsupported(type: type)
                isEnabled = false
            }

            if !validSequenceIDs.contains(sequenceID) {
                isEnabled = false
            }
            if stored.isEnabled, !isEnabled {
                issues.append(.disabledRule(stored.id))
            }

            rules.append(
                AutomaticRule(
                    id: id,
                    isEnabled: isEnabled,
                    priority: stored.priority,
                    condition: condition,
                    sequenceID: sequenceID
                )
            )
        }
        return rules
    }

    private static func validateOverlay(_ overlay: OverlaySettings) throws {
        guard
            overlay.originX.isFinite,
            overlay.originY.isFinite,
            overlay.width.isFinite,
            (AppSettingsLimits.minimumOverlayWidth...AppSettingsLimits.maximumOverlayWidth)
                .contains(overlay.width),
            overlay.screenIdentifier == nil
                || normalizedIdentifier(overlay.screenIdentifier) != nil
        else {
            throw AppSettingsMappingError.invalidSettings("overlay")
        }
    }

    private static func normalizedIdentifier(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func durationMilliseconds(_ duration: Duration) -> Int64? {
        guard duration > .zero else {
            return nil
        }
        let components = duration.components
        let seconds = components.seconds.multipliedReportingOverflow(by: 1_000)
        guard !seconds.overflow else {
            return nil
        }
        let fractionalMilliseconds = components.attoseconds / 1_000_000_000_000_000
        let total = seconds.partialValue.addingReportingOverflow(fractionalMilliseconds)
        guard !total.overflow else {
            return nil
        }
        return total.partialValue
    }
}
