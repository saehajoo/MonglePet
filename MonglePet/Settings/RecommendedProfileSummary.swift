import Foundation

nonisolated struct RecommendedProfileSummary: Equatable, Sendable {
    let mode: BehaviorMode
    let manualSequenceID: String?
    let sequences: [BehaviorSequence]
    let automaticRules: [AutomaticRule]
    let movement: PetMovementSettings
    let pettingMotionID: String?

    init(profile: RecommendedPetProfile) {
        mode = profile.mode
        manualSequenceID = profile.manualSequenceID
        sequences = profile.sequences
        automaticRules = profile.automaticRules
        movement = profile.movement
        pettingMotionID = profile.pettingMotionID
    }
}
