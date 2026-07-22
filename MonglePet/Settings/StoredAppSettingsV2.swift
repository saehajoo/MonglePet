import Foundation

nonisolated struct StoredAppSettingsV2: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let selectedPetInstallationID: String?
    let lastUserPresentation: String
    let overlay: StoredOverlaySettings
    let behaviorProfiles: [StoredBehaviorProfileV2]
}

nonisolated struct StoredBehaviorProfileV2: Codable, Equatable, Sendable {
    let petKey: StoredPetBehaviorKeyV2
    let mode: String
    let manualSequenceID: String?
    let sequences: [StoredBehaviorSequenceV2]
    let automaticRules: [StoredAutomaticRule]
}

nonisolated enum StoredPetBehaviorKeyV2: Equatable, Sendable {
    case builtIn
    case installed(installationID: String)
}

nonisolated extension StoredPetBehaviorKeyV2: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case installationID
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "builtIn":
            self = .builtIn
        case "installed":
            self = .installed(
                installationID: try container.decode(String.self, forKey: .installationID)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "지원하지 않는 펫 행동 키입니다."
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .builtIn:
            try container.encode("builtIn", forKey: .type)
        case let .installed(installationID):
            try container.encode("installed", forKey: .type)
            try container.encode(installationID, forKey: .installationID)
        }
    }
}

nonisolated struct StoredBehaviorSequenceV2: Codable, Equatable, Sendable {
    let id: String
    let steps: [StoredBehaviorStepV2]
    let repeats: Bool
}

nonisolated struct StoredBehaviorStepV2: Codable, Equatable, Sendable {
    let motionID: String
    let repeatCount: Int
}

nonisolated struct AppSettingsV2MigrationResult: Equatable, Sendable {
    let settings: StoredAppSettingsV2
    let issues: [SettingsRecoveryIssue]
}

nonisolated enum AppSettingsV1ToV2MigrationError: Error, Equatable, Sendable {
    case unsupportedSourceSchema(Int)
}

nonisolated enum AppSettingsV1ToV2Migrator {
    static func migrate(
        _ stored: StoredAppSettings,
        selectedPetDefinition: PetDefinition
    ) throws -> AppSettingsV2MigrationResult {
        guard stored.schemaVersion == 1 else {
            throw AppSettingsV1ToV2MigrationError.unsupportedSourceSchema(
                stored.schemaVersion
            )
        }
        let mapped = AppSettingsMapper.domainSettings(from: stored)
        let normalized = try AppSettingsMapper.storedSettings(from: mapped.settings)
        var issues = mapped.issues

        let selectedInstallationID = mapped.settings.selectedPetInstallationID
        let petKey: StoredPetBehaviorKeyV2 = if let installationID = selectedInstallationID {
            .installed(installationID: installationID.uuidString)
        } else {
            .builtIn
        }

        let sequences = normalized.sequences.enumerated().map { sequenceIndex, sequence in
            let steps = sequence.steps.enumerated().map { stepIndex, step in
                migratedStep(
                    step,
                    definition: selectedPetDefinition,
                    fieldPath: "behaviorProfiles.0.sequences.\(sequenceIndex).steps.\(stepIndex)",
                    issues: &issues
                )
            }
            return StoredBehaviorSequenceV2(
                id: sequence.id,
                steps: steps,
                repeats: sequence.repeats
            )
        }

        return AppSettingsV2MigrationResult(
            settings: StoredAppSettingsV2(
                schemaVersion: 2,
                selectedPetInstallationID: normalized.selectedPetInstallationID,
                lastUserPresentation: normalized.lastUserPresentation,
                overlay: normalized.overlay,
                behaviorProfiles: [
                    StoredBehaviorProfileV2(
                        petKey: petKey,
                        mode: normalized.behaviorMode,
                        manualSequenceID: normalized.manualSequenceID,
                        sequences: sequences,
                        automaticRules: normalized.automaticRules
                    )
                ]
            ),
            issues: issues
        )
    }

    private static func migratedStep(
        _ step: StoredBehaviorStep,
        definition: PetDefinition,
        fieldPath: String,
        issues: inout [SettingsRecoveryIssue]
    ) -> StoredBehaviorStepV2 {
        guard let cycleMilliseconds = cycleMilliseconds(
            for: step.motionID,
            in: definition
        ) else {
            issues.append(.invalidField("\(fieldPath).motionID"))
            return StoredBehaviorStepV2(
                motionID: PetMotionReference.currentPetDefault,
                repeatCount: 1
            )
        }

        let nearestRepeatCount = Int(
            (Double(step.durationMilliseconds) / Double(cycleMilliseconds)).rounded()
        )
        return StoredBehaviorStepV2(
            motionID: step.motionID,
            repeatCount: max(1, nearestRepeatCount)
        )
    }

    private static func cycleMilliseconds(
        for motionID: String,
        in definition: PetDefinition
    ) -> Int64? {
        let motion = motionID == PetMotionReference.currentPetDefault
            ? definition.defaultMotion
            : definition.motion(id: motionID)
        guard let motion, !motion.frames.isEmpty else {
            return nil
        }

        var total: Int64 = 0
        for frame in motion.frames {
            guard let frameMilliseconds = durationMilliseconds(frame.duration) else {
                return nil
            }
            let sum = total.addingReportingOverflow(frameMilliseconds)
            guard !sum.overflow else {
                return nil
            }
            total = sum.partialValue
        }
        return total > 0 ? total : nil
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
