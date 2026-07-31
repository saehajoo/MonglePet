import XCTest
@testable import MonglePet

final class AppSettingsV8MigrationTests: XCTestCase {
    func testV7MigrationPreservesSpeechAndAddsLegacyCompatibleTheme() throws {
        let settings = makeSettings(theme: .default)
        let storedV7 = try AppSettingsV7Mapper.storedSettings(from: settings)

        let migrated = try AppSettingsV7ToV8Migrator.migrate(storedV7)
        let theme = try XCTUnwrap(
            migrated.settings.behaviorProfiles.first?.speech.theme
        )

        XCTAssertEqual(migrated.settings.schemaVersion, 8)
        XCTAssertEqual(theme.colorStyle, "system")
        XCTAssertFalse(theme.showsTail)
        XCTAssertEqual(theme.tailAlignment, "center")
        XCTAssertTrue(migrated.issues.isEmpty)
        XCTAssertEqual(
            AppSettingsV8Mapper.domainSettings(from: migrated.settings)
                .settings,
            settings
        )
    }

    func testV8MapperRoundTripsCustomAccessibleTheme() throws {
        let theme = PetSpeechBubbleTheme(
            colorStyle: .custom,
            customBackgroundColor: PetSpeechColor(
                red: 0.08,
                green: 0.12,
                blue: 0.2
            ),
            customTextColor: .white,
            backgroundOpacity: 0.85,
            fontSize: 18,
            contentPadding: 16,
            cornerRadius: 20,
            showsTail: true,
            tailAlignment: .leading
        )
        let settings = makeSettings(theme: theme)

        let stored = try AppSettingsV8Mapper.storedSettings(from: settings)
        let mapped = AppSettingsV8Mapper.domainSettings(from: stored)

        XCTAssertEqual(stored.schemaVersion, 8)
        XCTAssertEqual(mapped.settings, settings)
        XCTAssertTrue(mapped.issues.isEmpty)
    }

    func testV8MapperRecoversUnreadableCustomTextColorIndependently() throws {
        let valid = try AppSettingsV8Mapper.storedSettings(
            from: makeSettings(theme: .default)
        )
        let profile = try XCTUnwrap(valid.behaviorProfiles.first)
        let white = StoredPetSpeechColorV8(red: 1, green: 1, blue: 1)
        let invalidTheme = StoredPetSpeechBubbleThemeV8(
            colorStyle: "custom",
            customBackgroundColor: white,
            customTextColor: white,
            backgroundOpacity: 0.9,
            fontSize: 15,
            contentPadding: 13,
            cornerRadius: 12,
            showsTail: true,
            tailAlignment: "trailing"
        )
        let stored = StoredAppSettingsV8(
            schemaVersion: 8,
            selectedPetInstallationID: valid.selectedPetInstallationID,
            lastUserPresentation: valid.lastUserPresentation,
            overlay: valid.overlay,
            behaviorProfiles: [
                StoredPetProfileV8(
                    petKey: profile.petKey,
                    mode: profile.mode,
                    manualSequenceID: profile.manualSequenceID,
                    sequences: profile.sequences,
                    automaticRules: profile.automaticRules,
                    movement: profile.movement,
                    pettingMotionID: profile.pettingMotionID,
                    speech: StoredPetSpeechSettingsV8(
                        isEnabled: profile.speech.isEnabled,
                        periodicIntervalMilliseconds:
                            profile.speech.periodicIntervalMilliseconds,
                        phrases: profile.speech.phrases,
                        theme: invalidTheme
                    )
                )
            ]
        )

        let mapped = AppSettingsV8Mapper.domainSettings(from: stored)

        XCTAssertEqual(
            mapped.settings.speechSettings.theme.customTextColor,
            .black
        )
        XCTAssertEqual(
            mapped.issues,
            [
                .invalidField(
                    "behaviorProfiles.0.speech.theme.customTextColor"
                )
            ]
        )
        XCTAssertTrue(mapped.settings.speechSettings.theme.isValid)
    }

    func testCustomThemeRequiresReadableTextContrast() {
        let theme = PetSpeechBubbleTheme(
            colorStyle: .custom,
            customBackgroundColor: .white,
            customTextColor: PetSpeechColor(
                red: 0.8,
                green: 0.8,
                blue: 0.8
            )
        )

        XCTAssertFalse(theme.isValid)
        XCTAssertGreaterThanOrEqual(
            PetSpeechColor.white.contrastRatio(with: .black),
            AppSettingsLimits.minimumSpeechBubbleTextContrastRatio
        )
    }

    private func makeSettings(theme: PetSpeechBubbleTheme) -> AppSettings {
        let sequence = BehaviorSequence(
            id: "default",
            steps: [BehaviorStep(motionID: "idle", repeatCount: 1)],
            repeats: true
        )
        return AppSettings(
            selectedPetInstallationID: nil,
            lastUserPresentation: .awake,
            behaviorMode: .manual,
            overlay: .default,
            speech: PetSpeechSettings(
                isEnabled: true,
                periodicIntervalMilliseconds: 20_000,
                phrases: [
                    PetSpeechPhrase(text: "안녕하세요!", trigger: .periodic)
                ],
                theme: theme
            ),
            manualSequenceID: sequence.id,
            sequences: [sequence],
            automaticRules: []
        )
    }
}
