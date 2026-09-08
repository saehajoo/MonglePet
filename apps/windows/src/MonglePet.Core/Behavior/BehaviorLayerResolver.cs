namespace MonglePet.Core.Behavior;

public sealed record BehaviorLayerDecisions(
    BehaviorDecision Stationary,
    BehaviorDecision RuleWithoutMovement,
    BehaviorDecision Display);

/// <summary>
/// Resolves the independently scheduled base and rule layers as well as the
/// currently visible result. This lets a lower-priority rule remain paused
/// while movement is visible instead of losing its playback cursor.
/// </summary>
public sealed class BehaviorLayerResolver
{
    private readonly BehaviorResolver _resolver = new();

    public BehaviorLayerDecisions Resolve(
        BehaviorConfiguration configuration,
        ActivitySnapshot snapshot,
        BehaviorRuntimeState runtimeState)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        ArgumentNullException.ThrowIfNull(snapshot);
        ArgumentNullException.ThrowIfNull(runtimeState);

        BehaviorRuntimeState stationaryState = runtimeState with
        {
            InteractionSequenceId = null,
            MovementSequenceId = null,
        };
        BehaviorDecision stationary = _resolver.Resolve(
            configuration with { AutomaticRules = [] },
            snapshot,
            stationaryState);
        BehaviorDecision ruleWithoutMovement = _resolver.Resolve(
            configuration,
            snapshot,
            stationaryState);
        BehaviorDecision display = _resolver.Resolve(configuration, snapshot, runtimeState);
        return new BehaviorLayerDecisions(stationary, ruleWithoutMovement, display);
    }
}
