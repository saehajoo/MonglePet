import Foundation

nonisolated enum AppSettingsV8Mapper {
    static func domainSettings(
        from stored: StoredAppSettingsV8
    ) -> (settings: AppSettings, issues: [SettingsRecoveryIssue]) {
        let storedV7 = StoredAppSettingsV7(
            schemaVersion: 7,
            selectedPetInstallationID: stored.selectedPetInstallationID,
            lastUserPresentation: stored.lastUserPresentation,
            overlay: stored.overlay,
            behaviorProfiles: stored.behaviorProfiles.map { profile in
                StoredPetProfileV7(
                    petKey: profile.petKey,
                    mode: profile.mode,
                    manualSequenceID: profile.manualSequenceID,
                    sequences: profile.sequences,
                    automaticRules: profile.automaticRules,
                    movement: profile.movement,
                    pettingMotionID: profile.pettingMotionID,
                    speech: StoredPetSpeechSettingsV7(
                        isEnabled: profile.speech.isEnabled,
                        periodicIntervalMilliseconds:
                            profile.speech.periodicIntervalMilliseconds,
                        phrases: profile.speech.phrases
                    )
                )
            }
        )
        let mappedV7 = AppSettingsV7Mapper.domainSettings(from: storedV7)
        var issues = mappedV7.issues
        var themesByKey:
            [PetBehaviorKey: (Int, StoredPetSpeechBubbleThemeV8)] = [:]
        for (index, profile) in stored.behaviorProfiles.enumerated() {
            guard
                let key = domainPetKey(from: profile.petKey),
                themesByKey[key] == nil
            else {
                continue
            }
            themesByKey[key] = (index, profile.speech.theme)
        }

        let profiles = mappedV7.settings.behaviorProfiles.map { profile in
            guard let (index, storedTheme) = themesByKey[profile.petKey] else {
                return profile
            }
            let theme = normalizedTheme(
                storedTheme,
                field: "behaviorProfiles.\(index).speech.theme",
                issues: &issues
            )
            return BehaviorProfile(
                petKey: profile.petKey,
                mode: profile.mode,
                manualSequenceID: profile.manualSequenceID,
                sequences: profile.sequences,
                automaticRules: profile.automaticRules,
                movement: profile.movement,
                pettingMotionID: profile.pettingMotionID,
                speech: PetSpeechSettings(
                    isEnabled: profile.speech.isEnabled,
                    periodicIntervalMilliseconds:
                        profile.speech.periodicIntervalMilliseconds,
                    phrases: profile.speech.phrases,
                    theme: theme
                )
            )
        }
        return (
            AppSettings(
                selectedPetInstallationID:
                    mappedV7.settings.selectedPetInstallationID,
                lastUserPresentation:
                    mappedV7.settings.lastUserPresentation,
                overlay: mappedV7.settings.overlay,
                behaviorProfiles: profiles
            ),
            issues
        )
    }

    static func storedSettings(
        from settings: AppSettings
    ) throws -> StoredAppSettingsV8 {
        let storedV7 = try AppSettingsV7Mapper.storedSettings(from: settings)
        let profiles = try zip(
            storedV7.behaviorProfiles,
            settings.behaviorProfiles
        )
        .enumerated()
        .map { index, pair in
            let (storedProfile, profile) = pair
            guard profile.speech.theme.isValid else {
                throw AppSettingsMappingError.invalidSettings(
                    "behaviorProfiles.\(index).speech.theme"
                )
            }
            return StoredPetProfileV8(
                petKey: storedProfile.petKey,
                mode: storedProfile.mode,
                manualSequenceID: storedProfile.manualSequenceID,
                sequences: storedProfile.sequences,
                automaticRules: storedProfile.automaticRules,
                movement: storedProfile.movement,
                pettingMotionID: storedProfile.pettingMotionID,
                speech: StoredPetSpeechSettingsV8(
                    isEnabled: storedProfile.speech.isEnabled,
                    periodicIntervalMilliseconds:
                        storedProfile.speech
                            .periodicIntervalMilliseconds,
                    phrases: storedProfile.speech.phrases,
                    theme: storedTheme(profile.speech.theme)
                )
            )
        }
        return StoredAppSettingsV8(
            schemaVersion: 8,
            selectedPetInstallationID:
                storedV7.selectedPetInstallationID,
            lastUserPresentation: storedV7.lastUserPresentation,
            overlay: storedV7.overlay,
            behaviorProfiles: profiles
        )
    }

    private static func normalizedTheme(
        _ stored: StoredPetSpeechBubbleThemeV8,
        field: String,
        issues: inout [SettingsRecoveryIssue]
    ) -> PetSpeechBubbleTheme {
        let defaults = PetSpeechBubbleTheme.default
        let colorStyle: PetSpeechBubbleColorStyle
        switch stored.colorStyle {
        case "system": colorStyle = .system
        case "cream": colorStyle = .cream
        case "midnight": colorStyle = .midnight
        case "mint": colorStyle = .mint
        case "peach": colorStyle = .peach
        case "custom": colorStyle = .custom
        default:
            colorStyle = .system
            issues.append(.invalidField("\(field).colorStyle"))
        }

        let background = normalizedColor(
            stored.customBackgroundColor,
            fallback: defaults.customBackgroundColor,
            field: "\(field).customBackgroundColor",
            issues: &issues
        )
        var text = normalizedColor(
            stored.customTextColor,
            fallback: defaults.customTextColor,
            field: "\(field).customTextColor",
            issues: &issues
        )
        if colorStyle == .custom,
           background.contrastRatio(with: text)
            < AppSettingsLimits.minimumSpeechBubbleTextContrastRatio {
            text = PetSpeechColor.preferredTextColor(for: background)
            issues.append(.invalidField("\(field).customTextColor"))
        }

        let opacity = normalized(
            stored.backgroundOpacity,
            range: AppSettingsLimits.minimumSpeechBubbleBackgroundOpacity
                ... AppSettingsLimits.maximumSpeechBubbleBackgroundOpacity,
            fallback: defaults.backgroundOpacity,
            field: "\(field).backgroundOpacity",
            issues: &issues
        )
        let fontSize = normalized(
            stored.fontSize,
            range: AppSettingsLimits.minimumSpeechBubbleFontSize
                ... AppSettingsLimits.maximumSpeechBubbleFontSize,
            fallback: defaults.fontSize,
            field: "\(field).fontSize",
            issues: &issues
        )
        let contentPadding = normalized(
            stored.contentPadding,
            range: AppSettingsLimits.minimumSpeechBubbleContentPadding
                ... AppSettingsLimits.maximumSpeechBubbleContentPadding,
            fallback: defaults.contentPadding,
            field: "\(field).contentPadding",
            issues: &issues
        )
        let cornerRadius = normalized(
            stored.cornerRadius,
            range: AppSettingsLimits.minimumSpeechBubbleCornerRadius
                ... AppSettingsLimits.maximumSpeechBubbleCornerRadius,
            fallback: defaults.cornerRadius,
            field: "\(field).cornerRadius",
            issues: &issues
        )
        let tailAlignment: PetSpeechBubbleTailAlignment
        switch stored.tailAlignment {
        case "leading": tailAlignment = .leading
        case "center": tailAlignment = .center
        case "trailing": tailAlignment = .trailing
        default:
            tailAlignment = .center
            issues.append(.invalidField("\(field).tailAlignment"))
        }

        return PetSpeechBubbleTheme(
            colorStyle: colorStyle,
            customBackgroundColor: background,
            customTextColor: text,
            backgroundOpacity: opacity,
            fontSize: fontSize,
            contentPadding: contentPadding,
            cornerRadius: cornerRadius,
            showsTail: stored.showsTail,
            tailAlignment: tailAlignment
        )
    }

    private static func normalizedColor(
        _ stored: StoredPetSpeechColorV8,
        fallback: PetSpeechColor,
        field: String,
        issues: inout [SettingsRecoveryIssue]
    ) -> PetSpeechColor {
        let color = PetSpeechColor(
            red: stored.red,
            green: stored.green,
            blue: stored.blue
        )
        guard color.isValid else {
            issues.append(.invalidField(field))
            return fallback
        }
        return color
    }

    private static func normalized(
        _ value: Double,
        range: ClosedRange<Double>,
        fallback: Double,
        field: String,
        issues: inout [SettingsRecoveryIssue]
    ) -> Double {
        guard value.isFinite, range.contains(value) else {
            issues.append(.invalidField(field))
            return fallback
        }
        return value
    }

    private static func storedTheme(
        _ theme: PetSpeechBubbleTheme
    ) -> StoredPetSpeechBubbleThemeV8 {
        let colorStyle: String = switch theme.colorStyle {
        case .system: "system"
        case .cream: "cream"
        case .midnight: "midnight"
        case .mint: "mint"
        case .peach: "peach"
        case .custom: "custom"
        }
        let tailAlignment: String = switch theme.tailAlignment {
        case .leading: "leading"
        case .center: "center"
        case .trailing: "trailing"
        }
        return StoredPetSpeechBubbleThemeV8(
            colorStyle: colorStyle,
            customBackgroundColor: storedColor(
                theme.customBackgroundColor
            ),
            customTextColor: storedColor(theme.customTextColor),
            backgroundOpacity: theme.backgroundOpacity,
            fontSize: theme.fontSize,
            contentPadding: theme.contentPadding,
            cornerRadius: theme.cornerRadius,
            showsTail: theme.showsTail,
            tailAlignment: tailAlignment
        )
    }

    private static func storedColor(
        _ color: PetSpeechColor
    ) -> StoredPetSpeechColorV8 {
        StoredPetSpeechColorV8(
            red: color.red,
            green: color.green,
            blue: color.blue
        )
    }

    private static func domainPetKey(
        from stored: StoredPetBehaviorKeyV2
    ) -> PetBehaviorKey? {
        switch stored {
        case .builtIn:
            .builtIn
        case let .installed(installationID):
            UUID(uuidString: installationID).map(PetBehaviorKey.installed)
        }
    }
}
