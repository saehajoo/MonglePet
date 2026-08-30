import Foundation

nonisolated struct MovementPriorityResolution: Equatable, Sendable {
    let movementTakesPriority: Bool
    let blocksMovement: Bool
}

nonisolated struct MovementPlaybackPriorityResolver: Sendable {
    func resolve(
        mode _: BehaviorMode,
        decision: BehaviorDecision?,
        rules: [AutomaticRule],
        order: [AutomaticRuleCategory]
    ) -> MovementPriorityResolution {
        guard
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

nonisolated enum PetPlaybackLayer: Equatable, Sendable {
    case behavior
    case movement
}

@MainActor
final class PetPlaybackCoordinator {
    private var behaviorPlayback: ScheduledMotion?
    private var movementPlayback: ScheduledMotion?
    private var movementTakesPriority = true
    private let onPlaybackChange: (ScheduledMotion?) -> Void
    private var onMovementPresentationChange: (Bool) -> Void = { _ in }
    private var isMovementPresentationActive = false
    private var hasEmittedPlayback = false
    private(set) var currentPlayback: ScheduledMotion?
    private(set) var currentPlaybackLayer: PetPlaybackLayer?

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
        currentPlaybackLayer = nil
        isMovementPresentationActive = false
        hasEmittedPlayback = false
    }

    func setMovementPresentationChangeHandler(
        _ handler: @escaping (Bool) -> Void
    ) {
        onMovementPresentationChange = handler
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
        let movementPresentationActive = movementTakesPriority
            && movementPlayback != nil
        if movementPresentationActive != isMovementPresentationActive {
            isMovementPresentationActive = movementPresentationActive
            onMovementPresentationChange(movementPresentationActive)
        }
        let selection = effectivePlaybackSelection
        emit(selection.playback, layer: selection.layer)
    }

    private var effectivePlaybackSelection: (
        playback: ScheduledMotion?,
        layer: PetPlaybackLayer?
    ) {
        if behaviorPlayback?.isInteraction == true {
            return (behaviorPlayback, .behavior)
        }
        if movementTakesPriority, let movementPlayback {
            return (movementPlayback, .movement)
        }
        if let behaviorPlayback {
            return (behaviorPlayback, .behavior)
        }
        if let movementPlayback {
            return (movementPlayback, .movement)
        }
        return (nil, nil)
    }

    private func emit(
        _ playback: ScheduledMotion?,
        layer: PetPlaybackLayer?
    ) {
        guard !hasEmittedPlayback
                || playback != currentPlayback
                || layer != currentPlaybackLayer else {
            return
        }
        hasEmittedPlayback = true
        currentPlayback = playback
        currentPlaybackLayer = layer
        onPlaybackChange(playback)
    }
}
