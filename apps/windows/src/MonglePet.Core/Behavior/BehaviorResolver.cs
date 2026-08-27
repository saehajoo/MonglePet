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

        if (configuration.Mode == BehaviorMode.Manual)
        {
            if (MovementDecision(configuration, runtimeState) is { } movement)
            {
                return movement;
            }
            if (configuration.ManualSequenceId is { } manualId &&
                configuration.FindSequence(manualId) is { } manual)
            {
                return new BehaviorDecision.Sequence(
                    manual,
                    new BehaviorSource.Manual());
            }

            return DefaultDecision(configuration);
        }

        if (configuration.Mode == BehaviorMode.Random)
        {
            if (MovementDecision(configuration, runtimeState) is { } movement)
            {
                return movement;
            }
            if (runtimeState.RandomSequenceId is { } randomId &&
                configuration.RandomSequences.Contains(randomId, StringComparer.Ordinal) &&
                configuration.FindSequence(randomId) is { } random)
            {
                return new BehaviorDecision.Sequence(
                    random with { Repeats = false },
                    new BehaviorSource.Random());
            }
            return DefaultDecision(configuration);
        }

        return ResolveAutomatic(configuration, snapshot, runtimeState);
    }

    private static BehaviorDecision ResolveAutomatic(
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
        return DefaultDecision(configuration);
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
}
