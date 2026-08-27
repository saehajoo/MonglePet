import Foundation

nonisolated struct BehaviorResolver: Sendable {
    init() {}

    mutating func resolve(
        configuration: BehaviorConfiguration,
        snapshot: ActivitySnapshot,
        runtimeState: BehaviorRuntimeState
    ) -> BehaviorDecision {
        switch runtimeState.presentation {
        case .tuckedAway:
            return .tuckedAway
        case .suspended:
            return .suspended
        case .awake:
            break
        }

        if snapshot.isScreenLocked || snapshot.isSystemSleeping {
            return .suspended
        }

        if
            let interactionSequenceID = runtimeState.interactionSequenceID,
            let interactionSequence = configuration.sequence(id: interactionSequenceID)
        {
            return .sequence(interactionSequence, source: .interaction)
        }

        switch configuration.mode {
        case .manual:
            if
                let manualSequenceID = configuration.manualSequenceID,
                let manualSequence = configuration.sequence(id: manualSequenceID)
            {
                return .sequence(manualSequence, source: .manual)
            }

            return defaultDecision(configuration: configuration)
        case .random:
            if
                let randomSequenceID = runtimeState.randomSequenceID,
                configuration.randomSequenceIDs.contains(randomSequenceID),
                let randomSequence = configuration.sequence(
                    id: randomSequenceID
                )
            {
                return .sequence(randomSequence, source: .random)
            }

            return defaultDecision(configuration: configuration)
        case .automatic:
            return resolveAutomatic(configuration: configuration, snapshot: snapshot)
        }
    }

    private func resolveAutomatic(
        configuration: BehaviorConfiguration,
        snapshot: ActivitySnapshot
    ) -> BehaviorDecision {
        let orderedRules = configuration.automaticRules
            .enumerated()
            .filter { $0.element.isEnabled }
            .sorted { lhs, rhs in
                let lhsCategoryPriority = categoryPriority(
                    for: lhs.element,
                    order: configuration.automaticRulePriorityOrder
                )
                let rhsCategoryPriority = categoryPriority(
                    for: rhs.element,
                    order: configuration.automaticRulePriorityOrder
                )
                if lhsCategoryPriority != rhsCategoryPriority {
                    return lhsCategoryPriority < rhsCategoryPriority
                }
                if lhs.element.priority != rhs.element.priority {
                    return lhs.element.priority > rhs.element.priority
                }

                return lhs.offset < rhs.offset
            }
            .map(\.element)

        guard
            let matchingRule = firstMatchingRule(
                in: orderedRules,
                snapshot: snapshot
            )
        else {
            return defaultDecision(configuration: configuration)
        }

        return decision(for: matchingRule, configuration: configuration)
    }

    private func categoryPriority(
        for rule: AutomaticRule,
        order: [AutomaticRuleCategory]
    ) -> Int {
        guard let category = rule.category else {
            return Int.max
        }
        return order.firstIndex(of: category) ?? Int.max - 1
    }

    private func firstMatchingRule(
        in orderedRules: [AutomaticRule],
        snapshot: ActivitySnapshot
    ) -> AutomaticRule? {
        orderedRules.first { rule in
            switch rule.condition {
            case let .application(bundleIdentifier):
                return !bundleIdentifier.isEmpty
                    && bundleIdentifier == snapshot.frontmostApplicationID
            case let .idleAtLeast(milliseconds):
                return milliseconds > 0
                    && snapshot.idleDuration >= Duration.milliseconds(milliseconds)
            case .unsupported:
                return false
            }
        }
    }

    private func decision(
        for rule: AutomaticRule,
        configuration: BehaviorConfiguration
    ) -> BehaviorDecision {
        guard let sequence = configuration.sequence(id: rule.sequenceID) else {
            return defaultDecision(configuration: configuration)
        }

        return .sequence(sequence, source: .automaticRule(rule.id))
    }

    private func defaultDecision(configuration: BehaviorConfiguration) -> BehaviorDecision {
        guard let sequence = configuration.defaultSequence else {
            return .unavailable
        }

        return .sequence(sequence, source: .defaultBehavior)
    }
}
