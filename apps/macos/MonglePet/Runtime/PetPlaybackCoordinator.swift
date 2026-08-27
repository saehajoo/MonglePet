import Foundation

nonisolated struct MovementPriorityResolution: Equatable, Sendable {
    let movementTakesPriority: Bool
    let blocksMovement: Bool
}

nonisolated struct MovementPlaybackPriorityResolver: Sendable {
    func resolve(
        mode: BehaviorMode,
        decision: BehaviorDecision?,
        rules: [AutomaticRule],
        order: [AutomaticRuleCategory]
    ) -> MovementPriorityResolution {
        guard
            mode == .automatic,
            case let .sequence(_, source) = decision,
            case let .automaticRule(ruleID) = source,
            let rule = rules.first(where: { $0.id == ruleID }),
            let category = rule.category
        else {
            return MovementPriorityResolution(
                movementTakesPriority: true,
                blocksMovement: false
            )
        }

        let movementIndex = order.firstIndex(of: .movement) ?? 0
        let ruleIndex = order.firstIndex(of: category) ?? order.count
        let movementTakesPriority = movementIndex < ruleIndex
        return MovementPriorityResolution(
            movementTakesPriority: movementTakesPriority,
            blocksMovement: !movementTakesPriority
        )
    }
}

@MainActor
final class PetPlaybackCoordinator {
    private var behaviorPlayback: ScheduledMotion?
    private var movementPlayback: ScheduledMotion?
    private var movementTakesPriority = true
    private let onPlaybackChange: (ScheduledMotion?) -> Void
    private var hasEmittedPlayback = false
    private(set) var currentPlayback: ScheduledMotion?

    init(
        petDefinition: PetDefinition,
        onPlaybackChange: @escaping (ScheduledMotion?) -> Void
    ) {
        self.onPlaybackChange = onPlaybackChange
    }

    func replacePetDefinition(_ petDefinition: PetDefinition) {
        behaviorPlayback = nil
        movementPlayback = nil
        currentPlayback = nil
        hasEmittedPlayback = false
    }

    func setBehaviorPlayback(_ playback: ScheduledMotion?) {
        behaviorPlayback = playback
        refresh()
    }

    func setMovementPlayback(_ playback: ScheduledMotion?) {
        movementPlayback = playback
        refresh()
    }

    func setMovementTakesPriority(_ takesPriority: Bool) {
        guard movementTakesPriority != takesPriority else {
            return
        }
        movementTakesPriority = takesPriority
        refresh()
    }

    private func refresh() {
        emit(effectivePlayback)
    }

    private var effectivePlayback: ScheduledMotion? {
        if behaviorPlayback?.isInteraction == true {
            return behaviorPlayback
        }
        return movementTakesPriority
            ? movementPlayback ?? behaviorPlayback
            : behaviorPlayback ?? movementPlayback
    }

    private func emit(_ playback: ScheduledMotion?) {
        guard !hasEmittedPlayback || playback != currentPlayback else {
            return
        }
        hasEmittedPlayback = true
        currentPlayback = playback
        onPlaybackChange(playback)
    }
}
