import Foundation

nonisolated enum AppSettingsLimits {
    static let schemaVersion = 1
    static let maximumFileSize = 5 * 1_024 * 1_024
    static let defaultOverlayWidth = 192.0
    static let minimumOverlayWidth = 96.0
    static let maximumOverlayWidth = 384.0
    static let minimumPlaybackSpeed = 0.25
    static let maximumPlaybackSpeed = 4.0
    static let maximumSequences = 100
    static let maximumStepsPerSequence = 100
    static let maximumAutomaticRules = 100
    static let maximumDurationMilliseconds: Int64 = 86_400_000
}

nonisolated struct OverlaySettings: Equatable, Sendable {
    let screenIdentifier: String?
    let originX: Double
    let originY: Double
    let width: Double
    let clickThrough: Bool

    static let `default` = OverlaySettings(
        screenIdentifier: nil,
        originX: 0,
        originY: 0,
        width: AppSettingsLimits.defaultOverlayWidth,
        clickThrough: false
    )
}

nonisolated struct AppSettings: Equatable, Sendable {
    let selectedPetInstallationID: UUID?
    let lastUserPresentation: PetPresentation
    let behaviorMode: BehaviorMode
    let overlay: OverlaySettings
    let manualSequenceID: String?
    let sequences: [BehaviorSequence]
    let automaticRules: [AutomaticRule]

    static let `default` = AppSettings(
        selectedPetInstallationID: nil,
        lastUserPresentation: .awake,
        behaviorMode: .automatic,
        overlay: .default,
        manualSequenceID: nil,
        sequences: [],
        automaticRules: []
    )
}

nonisolated enum SettingsRecoveryIssue: Equatable, Sendable {
    case invalidField(String)
    case droppedSequence(String)
    case droppedRule(String)
    case disabledRule(String)
    case truncatedCollection(String)
    case corruptFileQuarantined(String)
    case newerSchemaVersion(Int)
}

nonisolated enum AppSettingsLoadSource: Equatable, Sendable {
    case defaults
    case file
    case recovered
    case newerSchema(Int)
}

nonisolated struct AppSettingsLoadResult: Equatable, Sendable {
    let settings: AppSettings
    let issues: [SettingsRecoveryIssue]
    let source: AppSettingsLoadSource
    let isWritingEnabled: Bool
}
