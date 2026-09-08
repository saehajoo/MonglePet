using MonglePet.Core.Behavior;

namespace MonglePet.Core.Tests;

public sealed class BehaviorLayerResolverTests
{
    private static readonly BehaviorSequence Idle = new("idle", [new("idle", 1)], false);
    private static readonly BehaviorSequence Rule = new("rule", [new("rule", 1)], false);
    private static readonly BehaviorSequence Move = new("move", [new("move", 1)], false);

    [Fact]
    public void MovementPriorityKeepsMatchingRuleAsHiddenLayer()
    {
        var resolver = new BehaviorLayerResolver();
        BehaviorConfiguration configuration = Configuration(
            [AutomaticRuleKind.Movement, AutomaticRuleKind.Idle, AutomaticRuleKind.Application]);

        BehaviorLayerDecisions result = resolver.Resolve(
            configuration,
            Snapshot(idleSeconds: 2),
            new BehaviorRuntimeState(PetPresentation.Awake, MovementSequenceId: "move"));

        Assert.IsType<BehaviorSource.DefaultBehavior>(
            Assert.IsType<BehaviorDecision.Sequence>(result.Stationary).Source);
        Assert.IsType<BehaviorSource.AutomaticRule>(
            Assert.IsType<BehaviorDecision.Sequence>(result.RuleWithoutMovement).Source);
        Assert.IsType<BehaviorSource.Movement>(
            Assert.IsType<BehaviorDecision.Sequence>(result.Display).Source);
    }

    [Fact]
    public void RulePriorityDisplaysRuleAndConditionLossDropsHiddenRuleImmediately()
    {
        var resolver = new BehaviorLayerResolver();
        BehaviorConfiguration configuration = Configuration(
            [AutomaticRuleKind.Idle, AutomaticRuleKind.Movement, AutomaticRuleKind.Application]);
        var runtime = new BehaviorRuntimeState(
            PetPresentation.Awake,
            MovementSequenceId: "move");

        BehaviorLayerDecisions matching = resolver.Resolve(
            configuration,
            Snapshot(idleSeconds: 2),
            runtime);
        BehaviorLayerDecisions resumed = resolver.Resolve(
            configuration,
            Snapshot(idleSeconds: 0),
            runtime);

        Assert.IsType<BehaviorSource.AutomaticRule>(
            Assert.IsType<BehaviorDecision.Sequence>(matching.Display).Source);
        Assert.IsType<BehaviorSource.Movement>(
            Assert.IsType<BehaviorDecision.Sequence>(resumed.Display).Source);
        Assert.IsNotType<BehaviorSource.AutomaticRule>(
            Assert.IsType<BehaviorDecision.Sequence>(resumed.RuleWithoutMovement).Source);
    }

    private static BehaviorConfiguration Configuration(
        IReadOnlyList<AutomaticRuleKind> priority) => new(
        StationaryBehaviorMode.Random,
        "idle",
        [Idle, Rule, Move],
        AutomaticRules:
        [
            new(
                Guid.Parse("70000000-0000-0000-0000-000000000001"),
                true,
                0,
                new RuleCondition.IdleAtLeast(1_000),
                "rule"),
        ],
        RandomSequenceIds: [],
        AutomaticRulePriorityOrder: priority);

    private static ActivitySnapshot Snapshot(int idleSeconds) => new(
        TimeSpan.Zero,
        TimeSpan.FromSeconds(idleSeconds),
        null,
        false,
        false);
}
