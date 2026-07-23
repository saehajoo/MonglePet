import Foundation

nonisolated enum AppSettingsV2Mapper {
    static func domainSettings(
        from stored: StoredAppSettingsV2
    ) -> (settings: AppSettings, issues: [SettingsRecoveryIssue]) {
        var issues: [SettingsRecoveryIssue] = []
        let selectedPetInstallationID = normalizedInstallationID(
            stored.selectedPetInstallationID,
            field: "selectedPetInstallationID",
            issues: &issues
        )
        let presentation = normalizedPresentation(
            stored.lastUserPresentation,
            issues: &issues
        )
        let overlay = normalizedOverlay(from: stored.overlay, issues: &issues)

        if stored.behaviorProfiles.count > AppSettingsLimits.maximumBehaviorProfiles {
            issues.append(.truncatedCollection("behaviorProfiles"))
        }

        var seenKeys: Set<PetBehaviorKey> = []
        var profiles: [BehaviorProfile] = []
        for (index, storedProfile) in stored.behaviorProfiles
            .prefix(AppSettingsLimits.maximumBehaviorProfiles)
            .enumerated() {
            let fieldPath = "behaviorProfiles.\(index)"
            guard let key = normalizedPetKey(storedProfile.petKey) else {
                issues.append(.invalidField("\(fieldPath).petKey"))
                continue
            }
            guard seenKeys.insert(key).inserted else {
                issues.append(.invalidField("\(fieldPath).petKey"))
                continue
            }

            let mode: BehaviorMode
            switch storedProfile.mode {
            case "automatic":
                mode = .automatic
            case "manual":
                mode = .manual
            default:
                mode = .automatic
                issues.append(.invalidField("\(fieldPath).mode"))
            }

            let sequences = normalizedSequences(
                from: storedProfile.sequences,
                fieldPath: "\(fieldPath).sequences",
                issues: &issues
            )
            let sequenceIDs = Set(sequences.map(\.id))
            let manualSequenceID = normalizedManualSequenceID(
                storedProfile.manualSequenceID,
                validSequenceIDs: sequenceIDs,
                fieldPath: "\(fieldPath).manualSequenceID",
                issues: &issues
            )
            let automaticRules = normalizedRules(
                from: storedProfile.automaticRules,
                validSequenceIDs: sequenceIDs,
                fieldPath: "\(fieldPath).automaticRules",
                issues: &issues
            )
            profiles.append(
                BehaviorProfile(
                    petKey: key,
                    mode: mode,
                    manualSequenceID: manualSequenceID,
                    sequences: sequences,
                    automaticRules: automaticRules
                )
            )
        }

        return (
            AppSettings(
                selectedPetInstallationID: selectedPetInstallationID,
                lastUserPresentation: presentation,
                overlay: overlay,
                behaviorProfiles: profiles
            ),
            issues
        )
    }

    static func storedSettings(from settings: AppSettings) throws -> StoredAppSettingsV2 {
        guard settings.lastUserPresentation == .awake
            || settings.lastUserPresentation == .tuckedAway
        else {
            throw AppSettingsMappingError.invalidSettings("lastUserPresentation")
        }
        try validateOverlay(settings.overlay)
        guard settings.behaviorProfiles.count <= AppSettingsLimits.maximumBehaviorProfiles else {
            throw AppSettingsMappingError.invalidSettings("behaviorProfiles")
        }

        var profileKeys: Set<PetBehaviorKey> = []
        let storedProfiles = try settings.behaviorProfiles.enumerated().map { index, profile in
            guard profileKeys.insert(profile.petKey).inserted else {
                throw AppSettingsMappingError.invalidSettings(
                    "behaviorProfiles.\(index).petKey"
                )
            }
            let fieldPath = "behaviorProfiles.\(index)"
            let storedSequences = try storedSequences(
                from: profile.sequences,
                fieldPath: "\(fieldPath).sequences"
            )
            let sequenceIDs = Set(profile.sequences.map(\.id))
            if let manualSequenceID = profile.manualSequenceID,
               !sequenceIDs.contains(manualSequenceID) {
                throw AppSettingsMappingError.invalidSettings(
                    "\(fieldPath).manualSequenceID"
                )
            }
            let storedRules = try storedRules(
                from: profile.automaticRules,
                validSequenceIDs: sequenceIDs,
                fieldPath: "\(fieldPath).automaticRules"
            )
            return StoredBehaviorProfileV2(
                petKey: storedPetKey(from: profile.petKey),
                mode: profile.mode == .automatic ? "automatic" : "manual",
                manualSequenceID: profile.manualSequenceID,
                sequences: storedSequences,
                automaticRules: storedRules
            )
        }

        return StoredAppSettingsV2(
            schemaVersion: 2,
            selectedPetInstallationID: settings.selectedPetInstallationID?.uuidString,
            lastUserPresentation: settings.lastUserPresentation == .awake
                ? "awake"
                : "tuckedAway",
            overlay: StoredOverlaySettings(
                screenIdentifier: settings.overlay.screenIdentifier,
                originX: settings.overlay.originX,
                originY: settings.overlay.originY,
                width: settings.overlay.width,
                clickThrough: settings.overlay.clickThrough
            ),
            behaviorProfiles: storedProfiles
        )
    }

    private static func normalizedInstallationID(
        _ storedID: String?,
        field: String,
        issues: inout [SettingsRecoveryIssue]
    ) -> UUID? {
        guard let storedID else {
            return nil
        }
        guard let installationID = UUID(uuidString: storedID) else {
            issues.append(.invalidField(field))
            return nil
        }
        return installationID
    }

    private static func normalizedPetKey(
        _ stored: StoredPetBehaviorKeyV2
    ) -> PetBehaviorKey? {
        switch stored {
        case .builtIn:
            return .builtIn
        case let .installed(installationID):
            guard let id = UUID(uuidString: installationID) else { return nil }
            return .installed(id)
        }
    }

    private static func storedPetKey(
        from key: PetBehaviorKey
    ) -> StoredPetBehaviorKeyV2 {
        switch key {
        case .builtIn:
            return .builtIn
        case let .installed(installationID):
            return .installed(installationID: installationID.uuidString)
        }
    }

    private static func normalizedPresentation(
        _ stored: String,
        issues: inout [SettingsRecoveryIssue]
    ) -> PetPresentation {
        switch stored {
        case "awake":
            return .awake
        case "tuckedAway":
            return .tuckedAway
        default:
            issues.append(.invalidField("lastUserPresentation"))
            return .awake
        }
    }

    private static func normalizedOverlay(
        from stored: StoredOverlaySettings,
        issues: inout [SettingsRecoveryIssue]
    ) -> OverlaySettings {
        let screenIdentifier = normalizedIdentifier(stored.screenIdentifier)
        if stored.screenIdentifier != nil, screenIdentifier == nil {
            issues.append(.invalidField("overlay.screenIdentifier"))
        }
        let originX = normalizedFinite(
            stored.originX,
            fallback: OverlaySettings.default.originX,
            field: "overlay.originX",
            issues: &issues
        )
        let originY = normalizedFinite(
            stored.originY,
            fallback: OverlaySettings.default.originY,
            field: "overlay.originY",
            issues: &issues
        )

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

    private static func normalizedFinite(
        _ value: Double,
        fallback: Double,
        field: String,
        issues: inout [SettingsRecoveryIssue]
    ) -> Double {
        guard value.isFinite else {
            issues.append(.invalidField(field))
            return fallback
        }
        return value
    }

    private static func normalizedSequences(
        from storedSequences: [StoredBehaviorSequenceV2],
        fieldPath: String,
        issues: inout [SettingsRecoveryIssue]
    ) -> [BehaviorSequence] {
        if storedSequences.count > AppSettingsLimits.maximumSequences {
            issues.append(.truncatedCollection(fieldPath))
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
            let stepPath = "\(fieldPath).\(id).steps"
            if stored.steps.count > AppSettingsLimits.maximumStepsPerSequence {
                issues.append(.truncatedCollection(stepPath))
            }
            let steps = stored.steps
                .prefix(AppSettingsLimits.maximumStepsPerSequence)
                .compactMap { storedStep -> BehaviorStep? in
                    guard
                        let motionID = normalizedIdentifier(storedStep.motionID),
                        (1...AppSettingsLimits.maximumRepeatCount)
                            .contains(storedStep.repeatCount)
                    else {
                        issues.append(.invalidField(stepPath))
                        return nil
                    }
                    return BehaviorStep(
                        motionID: motionID,
                        repeatCount: storedStep.repeatCount
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

    private static func normalizedManualSequenceID(
        _ storedID: String?,
        validSequenceIDs: Set<String>,
        fieldPath: String,
        issues: inout [SettingsRecoveryIssue]
    ) -> String? {
        guard let storedID else {
            return nil
        }
        guard
            let candidate = normalizedIdentifier(storedID),
            validSequenceIDs.contains(candidate)
        else {
            issues.append(.invalidField(fieldPath))
            return nil
        }
        return candidate
    }

    private static func normalizedRules(
        from storedRules: [StoredAutomaticRule],
        validSequenceIDs: Set<String>,
        fieldPath: String,
        issues: inout [SettingsRecoveryIssue]
    ) -> [AutomaticRule] {
        if storedRules.count > AppSettingsLimits.maximumAutomaticRules {
            issues.append(.truncatedCollection(fieldPath))
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
                if let normalized = normalizedIdentifier(bundleIdentifier) {
                    condition = .application(bundleIdentifier: normalized)
                    if normalized != bundleIdentifier {
                        issues.append(.invalidField("\(fieldPath).\(stored.id).condition"))
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

    private static func storedSequences(
        from sequences: [BehaviorSequence],
        fieldPath: String
    ) throws -> [StoredBehaviorSequenceV2] {
        guard sequences.count <= AppSettingsLimits.maximumSequences else {
            throw AppSettingsMappingError.invalidSettings(fieldPath)
        }
        var sequenceIDs: Set<String> = []
        return try sequences.map { sequence in
            guard
                normalizedIdentifier(sequence.id) == sequence.id,
                sequenceIDs.insert(sequence.id).inserted,
                !sequence.steps.isEmpty,
                sequence.steps.count <= AppSettingsLimits.maximumStepsPerSequence
            else {
                throw AppSettingsMappingError.invalidSettings("\(fieldPath).\(sequence.id)")
            }
            let steps = try sequence.steps.map { step in
                guard
                    normalizedIdentifier(step.motionID) == step.motionID,
                    step.legacyTiming == nil,
                    (1...AppSettingsLimits.maximumRepeatCount).contains(step.repeatCount)
                else {
                    throw AppSettingsMappingError.invalidSettings(
                        "\(fieldPath).\(sequence.id).steps"
                    )
                }
                return StoredBehaviorStepV2(
                    motionID: step.motionID,
                    repeatCount: step.repeatCount
                )
            }
            return StoredBehaviorSequenceV2(
                id: sequence.id,
                steps: steps,
                repeats: sequence.repeats
            )
        }
    }

    private static func storedRules(
        from rules: [AutomaticRule],
        validSequenceIDs: Set<String>,
        fieldPath: String
    ) throws -> [StoredAutomaticRule] {
        guard rules.count <= AppSettingsLimits.maximumAutomaticRules else {
            throw AppSettingsMappingError.invalidSettings(fieldPath)
        }
        var ruleIDs: Set<UUID> = []
        return try rules.map { rule in
            guard
                ruleIDs.insert(rule.id).inserted,
                normalizedIdentifier(rule.sequenceID) == rule.sequenceID,
                !rule.isEnabled || validSequenceIDs.contains(rule.sequenceID)
            else {
                throw AppSettingsMappingError.invalidSettings(fieldPath)
            }

            let condition: StoredRuleCondition
            switch rule.condition {
            case let .application(bundleIdentifier):
                guard
                    !rule.isEnabled
                        || normalizedIdentifier(bundleIdentifier) == bundleIdentifier
                else {
                    throw AppSettingsMappingError.invalidSettings(
                        "\(fieldPath).\(rule.id.uuidString).condition"
                    )
                }
                condition = .application(bundleIdentifier: bundleIdentifier)
            case let .idleAtLeast(milliseconds):
                guard
                    !rule.isEnabled
                        || (1...AppSettingsLimits.maximumDurationMilliseconds)
                            .contains(milliseconds)
                else {
                    throw AppSettingsMappingError.invalidSettings(
                        "\(fieldPath).\(rule.id.uuidString).condition"
                    )
                }
                condition = .idleAtLeast(milliseconds: milliseconds)
            case let .unsupported(type):
                guard !rule.isEnabled, normalizedIdentifier(type) != nil else {
                    throw AppSettingsMappingError.invalidSettings(
                        "\(fieldPath).\(rule.id.uuidString).condition"
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
}
