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
            if (configuration.ManualSequenceId is { } manualId &&
                configuration.FindSequence(manualId) is { } manual)
            {
                return new BehaviorDecision.Sequence(
                    manual,
                    new BehaviorSource.Manual());
            }

            return DefaultDecision(configuration);
        }

        return ResolveAutomatic(configuration, snapshot);
    }

    private static BehaviorDecision ResolveAutomatic(
        BehaviorConfiguration configuration,
        ActivitySnapshot snapshot)
    {
        var matchingRule = configuration.Rules
            .Select((rule, index) => (Rule: rule, Index: index))
            .Where(item => item.Rule.IsEnabled)
            .OrderByDescending(item => item.Rule.Priority)
            .ThenBy(item => item.Index)
            .Select(item => item.Rule)
            .FirstOrDefault(rule => Matches(rule.Condition, snapshot));

        if (matchingRule is null)
        {
            return DefaultDecision(configuration);
        }

        if (configuration.FindSequence(matchingRule.SequenceId) is not { } sequence)
        {
            return DefaultDecision(configuration);
        }

        return new BehaviorDecision.Sequence(
            sequence,
            new BehaviorSource.AutomaticRule(matchingRule.Id));
    }

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
