namespace MonglePet.Core.Behavior;

public sealed class BehaviorResolver
{
    public BehaviorDecision Resolve(
        BehaviorConfiguration configuration,
        ActivitySnapshot snapshot,
        BehaviorRuntimeState runtimeState)
    {
        if (runtimeState.Presentation == PetPresentation.TuckedAway)
        {
            return new BehaviorDecision.TuckedAway();
        }

        if (runtimeState.Presentation == PetPresentation.Suspended ||
            snapshot.IsScreenLocked ||
            snapshot.IsSystemSleeping)
        {
            return new BehaviorDecision.Suspended();
        }

        if (runtimeState.InteractionSequenceId is { } interactionId &&
            configuration.FindSequence(interactionId) is { } interaction)
        {
            return new BehaviorDecision.Sequence(
                interaction,
                new BehaviorSource.Interaction());
        }

        return ResolveRulesAndMovement(configuration, snapshot, runtimeState);
    }

    private static BehaviorDecision ResolveRulesAndMovement(
        BehaviorConfiguration configuration,
        ActivitySnapshot snapshot,
        BehaviorRuntimeState runtimeState)
    {
        AutomaticRule? BestRule(AutomaticRuleKind kind) => configuration.Rules
            .Select((rule, index) => (Rule: rule, Index: index))
            .Where(item => item.Rule.IsEnabled && Kind(item.Rule.Condition) == kind)
            .OrderByDescending(item => item.Rule.Priority)
            .ThenBy(item => item.Index)
            .Select(item => item.Rule)
            .FirstOrDefault(rule => Matches(rule.Condition, snapshot));
        foreach (AutomaticRuleKind kind in configuration.RulePriorityOrder)
        {
            if (kind == AutomaticRuleKind.Movement)
            {
                if (MovementDecision(configuration, runtimeState) is { } movement)
                {
                    return movement;
                }
                continue;
            }
            AutomaticRule? matchingRule = BestRule(kind);
            if (matchingRule is not null &&
                configuration.FindSequence(matchingRule.SequenceId) is { } sequence)
            {
                return new BehaviorDecision.Sequence(
                    sequence,
                    new BehaviorSource.AutomaticRule(matchingRule.Id));
            }
        }
        return StationaryDecision(configuration, runtimeState);
    }

    private static BehaviorDecision.Sequence? MovementDecision(
        BehaviorConfiguration configuration,
        BehaviorRuntimeState runtimeState) =>
        runtimeState.MovementSequenceId is { } movementId &&
        configuration.FindSequence(movementId) is { } movement
            ? new BehaviorDecision.Sequence(movement, new BehaviorSource.Movement())
            : null;

    private static AutomaticRuleKind? Kind(RuleCondition condition) => condition switch
    {
        RuleCondition.IdleAtLeast => AutomaticRuleKind.Idle,
        RuleCondition.Application => AutomaticRuleKind.Application,
        _ => null,
    };

    private static bool Matches(
        RuleCondition condition,
        ActivitySnapshot snapshot) => condition switch
        {
            RuleCondition.Application application =>
                !string.IsNullOrWhiteSpace(application.ApplicationId) &&
                string.Equals(
                    application.ApplicationId,
                    snapshot.FrontmostApplicationId,
                    StringComparison.Ordinal),
            RuleCondition.IdleAtLeast idle =>
                idle.Milliseconds > 0 &&
                snapshot.IdleDuration >= TimeSpan.FromMilliseconds(idle.Milliseconds),
            RuleCondition.Unsupported => false,
            _ => false,
        };

    private static BehaviorDecision DefaultDecision(
        BehaviorConfiguration configuration) =>
        configuration.DefaultSequence is { } sequence
            ? new BehaviorDecision.Sequence(
                sequence,
                new BehaviorSource.DefaultBehavior())
            : new BehaviorDecision.Unavailable();

    private static BehaviorDecision StationaryDecision(
        BehaviorConfiguration configuration,
        BehaviorRuntimeState runtimeState)
    {
        if (configuration.StationaryBehaviorMode == StationaryBehaviorMode.Random &&
            runtimeState.RandomSequenceId is { } randomId &&
            configuration.RandomSequences.Contains(randomId, StringComparer.Ordinal) &&
            configuration.FindSequence(randomId) is { } random)
        {
            return new BehaviorDecision.Sequence(
                random with { Repeats = false },
                new BehaviorSource.Random());
        }
        if (configuration.StationaryBehaviorMode == StationaryBehaviorMode.Fixed &&
            configuration.StationarySequenceId is { } fixedId &&
            configuration.FindSequence(fixedId) is { } fixedSequence)
        {
            return new BehaviorDecision.Sequence(
                fixedSequence,
                new BehaviorSource.Fixed());
        }
        return DefaultDecision(configuration);
    }
}
