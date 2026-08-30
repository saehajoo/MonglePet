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

        if let matchingRule = matchingRule(
            configuration: configuration,
            snapshot: snapshot
        ) {
            return decision(for: matchingRule, configuration: configuration)
        }

        switch configuration.stationaryBehaviorMode {
        case .fixed:
            if
                let stationarySequenceID = configuration.stationarySequenceID,
                let stationarySequence = configuration.sequence(
                    id: stationarySequenceID
                )
            {
                return .sequence(stationarySequence, source: .manual)
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
        }
    }

    private func matchingRule(
        configuration: BehaviorConfiguration,
        snapshot: ActivitySnapshot
    ) -> AutomaticRule? {
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

        return firstMatchingRule(in: orderedRules, snapshot: snapshot)
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
