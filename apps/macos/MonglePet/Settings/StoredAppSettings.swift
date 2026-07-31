import Foundation

nonisolated struct StoredAppSettings: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let selectedPetInstallationID: String?
    let lastUserPresentation: String
    let behaviorMode: String
    let overlay: StoredOverlaySettings
    let manualSequenceID: String?
    let sequences: [StoredBehaviorSequence]
    let automaticRules: [StoredAutomaticRule]
}

nonisolated struct StoredOverlaySettings: Codable, Equatable, Sendable {
    let screenIdentifier: String?
    let originX: Double
    let originY: Double
    let width: Double
    let clickThrough: Bool
}

nonisolated struct StoredBehaviorStep: Codable, Equatable, Sendable {
    let motionID: String
    let durationMilliseconds: Int64
    let playbackSpeed: Double
}

nonisolated struct StoredBehaviorSequence: Codable, Equatable, Sendable {
    let id: String
    let steps: [StoredBehaviorStep]
    let repeats: Bool
}

nonisolated struct StoredAutomaticRule: Codable, Equatable, Sendable {
    let id: String
    let isEnabled: Bool
    let priority: Int
    let condition: StoredRuleCondition
    let sequenceID: String
}

nonisolated enum StoredRuleCondition: Equatable, Sendable {
    case application(bundleIdentifier: String)
    case idleAtLeast(milliseconds: Int64)
    case unsupported(type: String)
}

extension StoredRuleCondition: Codable {
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
                bundleIdentifier: try container.decodeIfPresent(
                    String.self,
                    forKey: .bundleIdentifier
                ) ?? ""
            )
        case "idleAtLeast":
            self = .idleAtLeast(
                milliseconds: try container.decodeIfPresent(
                    Int64.self,
                    forKey: .milliseconds
                ) ?? 0
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

nonisolated struct StoredSchemaEnvelope: Decodable, Sendable {
    let schemaVersion: Int
}
