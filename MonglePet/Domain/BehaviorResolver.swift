import Foundation

nonisolated struct BehaviorResolver: Sendable {
    private var activeIdleRuleID: UUID?
    private var idleRecoveryStartedAt: ContinuousClock.Instant?

    init() {}

    mutating func resolve(
        configuration: BehaviorConfiguration,
        snapshot: ActivitySnapshot,
        runtimeState: BehaviorRuntimeState
    ) -> BehaviorDecision {
        switch runtimeState.presentation {
        case .tuckedAway:
            resetIdleState()
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
            resetIdleState()
            if
                let manualSequenceID = configuration.manualSequenceID,
                let manualSequence = configuration.sequence(id: manualSequenceID)
            {
                return .sequence(manualSequence, source: .manual)
            }

            return defaultDecision(configuration: configuration)
        case .automatic:
            return resolveAutomatic(configuration: configuration, snapshot: snapshot)
        }
    }

    private mutating func resolveAutomatic(
        configuration: BehaviorConfiguration,
        snapshot: ActivitySnapshot
    ) -> BehaviorDecision {
        let orderedRules = configuration.automaticRules
            .enumerated()
            .filter { $0.element.isEnabled }
            .sorted { lhs, rhs in
                if lhs.element.priority != rhs.element.priority {
                    return lhs.element.priority > rhs.element.priority
                }

                return lhs.offset < rhs.offset
            }
            .map(\.element)

        let rawRule = firstMatchingRule(in: orderedRules, snapshot: snapshot)

        if let activeIdleRuleID,
           let activeRule = orderedRules.first(where: { $0.id == activeIdleRuleID }),
           case let .idleAtLeast(milliseconds) = activeRule.condition,
           milliseconds > 0 {
            let activeThreshold = Duration.milliseconds(milliseconds)
            if snapshot.idleDuration < activeThreshold {
                if shouldKeepIdleRule(
                    at: snapshot.capturedAt,
                    exitDelay: configuration.idleExitDelay
                ) {
                    return decision(for: activeRule, configuration: configuration)
                }

                resetIdleState()
            } else {
                idleRecoveryStartedAt = nil
            }
        } else {
            resetIdleState()
        }

        guard let rawRule else {
            return defaultDecision(configuration: configuration)
        }

        if case .idleAtLeast = rawRule.condition {
            activeIdleRuleID = rawRule.id
            idleRecoveryStartedAt = nil
        } else {
            resetIdleState()
        }

        return decision(for: rawRule, configuration: configuration)
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

    private mutating func shouldKeepIdleRule(
        at capturedAt: ContinuousClock.Instant,
        exitDelay: Duration
    ) -> Bool {
        guard exitDelay > .zero else {
            return false
        }

        guard let idleRecoveryStartedAt else {
            self.idleRecoveryStartedAt = capturedAt
            return true
        }

        let recoveryDuration = idleRecoveryStartedAt.duration(to: capturedAt)
        if recoveryDuration < .zero {
            self.idleRecoveryStartedAt = capturedAt
            return true
        }

        return recoveryDuration < exitDelay
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

    private mutating func resetIdleState() {
        activeIdleRuleID = nil
        idleRecoveryStartedAt = nil
    }
}
