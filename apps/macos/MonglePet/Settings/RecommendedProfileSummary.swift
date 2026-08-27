import Foundation

nonisolated struct RecommendedProfileSummary: Equatable, Sendable {
    let mode: BehaviorMode
    let manualSequenceID: String?
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
        mode = profile.mode
        manualSequenceID = profile.manualSequenceID
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

    private static func automaticRuleCategoryName(
        _ category: AutomaticRuleCategory
    ) -> String {
        switch category {
        case .movement:
            "표시 및 이동"
        case .idle:
            "입력 없음"
        case .application:
            "앱 사용"
        }
    }
}
