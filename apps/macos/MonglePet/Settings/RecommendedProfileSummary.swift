import Foundation

nonisolated struct RecommendedProfileSummary: Equatable, Sendable {
    let stationaryBehaviorMode: StationaryBehaviorMode
    let stationarySequenceID: String?
    let randomSequenceIDs: [String]
    let sequences: [BehaviorSequence]
    let automaticRules: [AutomaticRule]
    let automaticRulePriorityOrder: [AutomaticRuleCategory]
    let movement: PetMovementSettings
    let pettingMotionID: String?
    let speech: PetSpeechSettings
    let display: PortablePetDisplaySettings
    let includesDisplaySettings: Bool

    init(profile: RecommendedPetProfile) {
        stationaryBehaviorMode = profile.stationaryBehaviorMode
        stationarySequenceID = profile.stationarySequenceID
        randomSequenceIDs = profile.randomSequenceIDs
        sequences = profile.sequences
        automaticRules = profile.automaticRules
        automaticRulePriorityOrder = profile.automaticRulePriorityOrder
        movement = profile.movement
        pettingMotionID = profile.pettingMotionID
        speech = profile.speech
        display = profile.display
        includesDisplaySettings = profile.includesDisplaySettings
    }

    var mode: BehaviorMode {
        switch stationaryBehaviorMode {
        case .fixed:
            stationarySequenceID == nil ? .automatic : .manual
        case .random:
            .random
        }
    }

    var manualSequenceID: String? { stationarySequenceID }

    func behaviorDisplayName(for behaviorID: String) -> String {
        sequences.first(where: { $0.id == behaviorID })?.displayName
            ?? (behaviorID == BuiltInBehaviorPresets.defaultSequenceID
                ? "기본"
                : "찾을 수 없는 행동")
    }

    var automaticRulePriorityDescription: String {
        automaticRulePriorityOrder
            .map(Self.automaticRuleCategoryName)
            .joined(separator: " → ")
    }

    var conditionRuleDescription: String {
        guard !automaticRules.isEmpty else {
            return "없음"
        }
        let enabledCount = automaticRules.count(where: \.isEnabled)
        return "\(automaticRules.count)개 · 사용 \(enabledCount)개"
    }

    private static func automaticRuleCategoryName(
        _ category: AutomaticRuleCategory
    ) -> String {
        switch category {
        case .movement:
            "이동"
        case .idle:
            "입력 없음"
        case .application:
            "앱 사용"
        }
    }
}
