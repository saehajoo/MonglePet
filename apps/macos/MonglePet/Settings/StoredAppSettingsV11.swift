import Foundation

/// schema-v11 separates installed pet content from each visible desktop pet.
///
/// The profile collection intentionally keeps `petKey` even though instances
/// reference profiles by UUID. Unreferenced v10 profiles remain useful as the
/// starting template when the user activates that library pet again.
nonisolated struct StoredAppSettingsV11: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let selectedPetInstanceID: String
    let activePetInstances: [StoredPetInstanceV11]
    let behaviorProfiles: [StoredPetProfileV11]
}

nonisolated struct StoredPetInstanceV11: Codable, Equatable, Sendable {
    let instanceID: String
    let petKey: StoredPetBehaviorKeyV2
    let nickname: String?
    let presentation: String
    let overlay: StoredOverlaySettingsV4
    let behaviorProfileID: String
    let displayOrder: Int
}

nonisolated struct StoredPetProfileV11: Codable, Equatable, Sendable {
    let profileID: String
    let petKey: StoredPetBehaviorKeyV2
    let mode: String
    let manualSequenceID: String?
    let sequences: [StoredBehaviorSequenceV2]
    let automaticRules: [StoredAutomaticRule]
    let movement: StoredPetMovementSettingsV6
    let pettingMotionID: String?
    let speech: StoredPetSpeechSettingsV10

    init(
        profileID: String,
        petKey: StoredPetBehaviorKeyV2,
        mode: String,
        manualSequenceID: String?,
        sequences: [StoredBehaviorSequenceV2],
        automaticRules: [StoredAutomaticRule],
        movement: StoredPetMovementSettingsV6,
        pettingMotionID: String?,
        speech: StoredPetSpeechSettingsV10
    ) {
        self.profileID = profileID
        self.petKey = petKey
        self.mode = mode
        self.manualSequenceID = manualSequenceID
        self.sequences = sequences
        self.automaticRules = automaticRules
        self.movement = movement
        self.pettingMotionID = pettingMotionID
        self.speech = speech
    }

    init(profileID: UUID, profile: StoredPetProfileV10) {
        self.profileID = profileID.uuidString
        petKey = profile.petKey
        mode = profile.mode
        manualSequenceID = profile.manualSequenceID
        sequences = profile.sequences
        automaticRules = profile.automaticRules
        movement = profile.movement
        pettingMotionID = profile.pettingMotionID
        speech = profile.speech
    }
}

nonisolated struct AppSettingsV10ToV11MigrationResult:
    Equatable,
    Sendable
{
    let settings: StoredAppSettingsV11
    let issues: [SettingsRecoveryIssue]
}

nonisolated enum AppSettingsV10ToV11MigrationError:
    Error,
    Equatable,
    Sendable
{
    case unsupportedSourceSchema(Int)
    case unableToCreateDefaultProfile
}

nonisolated enum AppSettingsV10ToV11Migrator {
    static func migrate(
        _ stored: StoredAppSettingsV10,
        idGenerator: () -> UUID = UUID.init
    ) throws -> AppSettingsV10ToV11MigrationResult {
        guard stored.schemaVersion == 10 else {
            throw AppSettingsV10ToV11MigrationError
                .unsupportedSourceSchema(stored.schemaVersion)
        }

        let selectedPetKey: StoredPetBehaviorKeyV2 =
            stored.selectedPetInstallationID.map(
                StoredPetBehaviorKeyV2.installed
            ) ?? .builtIn
        let instanceID = idGenerator()

        var profiles = stored.behaviorProfiles.map { profile in
            StoredPetProfileV11(
                profileID: idGenerator(),
                profile: profile
            )
        }

        let selectedProfileID: UUID
        if let index = profiles.firstIndex(where: {
            $0.petKey == selectedPetKey
        }), let profileID = UUID(uuidString: profiles[index].profileID) {
            selectedProfileID = profileID
        } else {
            let profileID = idGenerator()
            let defaultProfile = try makeDefaultProfile(for: selectedPetKey)
            profiles.append(
                StoredPetProfileV11(
                    profileID: profileID,
                    profile: defaultProfile
                )
            )
            selectedProfileID = profileID
        }

        return AppSettingsV10ToV11MigrationResult(
            settings: StoredAppSettingsV11(
                schemaVersion: 11,
                selectedPetInstanceID: instanceID.uuidString,
                activePetInstances: [
                    StoredPetInstanceV11(
                        instanceID: instanceID.uuidString,
                        petKey: selectedPetKey,
                        nickname: nil,
                        presentation: stored.lastUserPresentation,
                        overlay: stored.overlay,
                        behaviorProfileID: selectedProfileID.uuidString,
                        displayOrder: 0
                    )
                ],
                behaviorProfiles: profiles
            ),
            issues: []
        )
    }

    private static func makeDefaultProfile(
        for petKey: StoredPetBehaviorKeyV2
    ) throws -> StoredPetProfileV10 {
        let settings: AppSettings
        switch petKey {
        case .builtIn:
            settings = .default
        case let .installed(installationID):
            guard let id = UUID(uuidString: installationID) else {
                throw AppSettingsV10ToV11MigrationError
                    .unableToCreateDefaultProfile
            }
            settings = AppSettings.default.addingPetInstance(
                for: .installed(id)
            )
        }
        guard
            let stored = try? AppSettingsV10Mapper.storedSettings(
                from: settings
            ),
            let template = stored.behaviorProfiles.first(where: {
                $0.petKey == petKey
            })
        else {
            throw AppSettingsV10ToV11MigrationError
                .unableToCreateDefaultProfile
        }
        return StoredPetProfileV10(
            petKey: petKey,
            mode: template.mode,
            manualSequenceID: template.manualSequenceID,
            sequences: template.sequences,
            automaticRules: template.automaticRules,
            movement: template.movement,
            pettingMotionID: template.pettingMotionID,
            speech: template.speech
        )
    }
}
