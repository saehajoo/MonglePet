using MonglePet.Core.Behavior;

namespace MonglePet.Core.Tests;

public sealed class BehaviorResolverTests
{
    private readonly BehaviorResolver _resolver = new();

    [Fact]
    public void TuckedAwayAndScreenLockTakePriorityOverInteraction()
    {
        var configuration = MakeConfiguration(BehaviorMode.Manual, "manual");
        var locked = Snapshot(
            idle: TimeSpan.FromMinutes(15),
            applicationId: "com.example.Editor",
            isScreenLocked: true);

        Assert.IsType<BehaviorDecision.TuckedAway>(
            _resolver.Resolve(
                configuration,
                locked,
                new(PetPresentation.TuckedAway, "petting")));
        Assert.IsType<BehaviorDecision.Suspended>(
            _resolver.Resolve(
                configuration,
                locked,
                new(PetPresentation.Awake, "petting")));
    }

    [Fact]
    public void InteractionTakesPriorityOverManualMode()
    {
        var decision = Assert.IsType<BehaviorDecision.Sequence>(
            _resolver.Resolve(
                MakeConfiguration(BehaviorMode.Manual, "manual"),
                Snapshot(),
                new(PetPresentation.Awake, "petting")));

        Assert.Equal("petting", decision.Value.Id);
        Assert.IsType<BehaviorSource.Interaction>(decision.Source);
    }

    [Fact]
    public void ManualModeIgnoresAutomaticRules()
    {
        var decision = Assert.IsType<BehaviorDecision.Sequence>(
            _resolver.Resolve(
                MakeConfiguration(BehaviorMode.Manual, "manual"),
                Snapshot(
                    idle: TimeSpan.FromMinutes(15),
                    applicationId: "com.example.Editor"),
                new(PetPresentation.Awake)));

        Assert.Equal("manual", decision.Value.Id);
        Assert.IsType<BehaviorSource.Manual>(decision.Source);
    }

    [Fact]
    public void AutomaticRulesUseConfiguredConditionTypeOrderBeforeLegacyPriority()
    {
        var applicationRule = new AutomaticRule(
            Guid.NewGuid(),
            true,
            30,
            new RuleCondition.Application("com.example.Editor"),
            "focus");
        var idleRule = new AutomaticRule(
            Guid.NewGuid(),
            true,
            10,
            new RuleCondition.IdleAtLeast(600_000),
            "sleep");
        var basis = MakeConfiguration(BehaviorMode.Automatic);
        var configuration = basis with
        {
            AutomaticRules = [idleRule, applicationRule],
            AutomaticRulePriorityOrder =
                [AutomaticRuleKind.Application, AutomaticRuleKind.Idle, AutomaticRuleKind.Movement],
        };

        var decision = Assert.IsType<BehaviorDecision.Sequence>(
            _resolver.Resolve(
                configuration,
                Snapshot(
                    idle: TimeSpan.FromMinutes(10),
                    applicationId: "com.example.Editor"),
                new(PetPresentation.Awake)));

        Assert.Equal("focus", decision.Value.Id);
        Assert.Equal(
            new BehaviorSource.AutomaticRule(applicationRule.Id),
            decision.Source);
    }

    [Fact]
    public void MovementParticipatesInAutomaticPriorityAndOverridesDirectModes()
    {
        AutomaticRule idleRule = new(
            Guid.NewGuid(), true, 1, new RuleCondition.IdleAtLeast(1_000), "sleep");
        BehaviorConfiguration automatic = MakeConfiguration(BehaviorMode.Automatic) with
        {
            AutomaticRules = [idleRule],
            AutomaticRulePriorityOrder =
                [AutomaticRuleKind.Idle, AutomaticRuleKind.Movement, AutomaticRuleKind.Application],
        };
        var idleDecision = Assert.IsType<BehaviorDecision.Sequence>(_resolver.Resolve(
            automatic,
            Snapshot(idle: TimeSpan.FromSeconds(2)),
            new(PetPresentation.Awake, MovementSequenceId: "focus")));
        var manualDecision = Assert.IsType<BehaviorDecision.Sequence>(_resolver.Resolve(
            MakeConfiguration(BehaviorMode.Manual, "manual"),
            Snapshot(),
            new(PetPresentation.Awake, MovementSequenceId: "focus")));

        Assert.Equal("sleep", idleDecision.Value.Id);
        Assert.Equal("focus", manualDecision.Value.Id);
        Assert.IsType<BehaviorSource.Movement>(manualDecision.Source);
    }

    [Fact]
    public void RandomModeUsesSelectedBagEntryOnceAndFallsBackWhenMissing()
    {
        BehaviorConfiguration configuration = MakeConfiguration(BehaviorMode.Random) with
        {
            RandomSequenceIds = ["focus", "rest"],
        };
        var selected = Assert.IsType<BehaviorDecision.Sequence>(_resolver.Resolve(
            configuration,
            Snapshot(),
            new(PetPresentation.Awake, RandomSequenceId: "focus")));
        var missing = Assert.IsType<BehaviorDecision.Sequence>(_resolver.Resolve(
            configuration,
            Snapshot(),
            new(PetPresentation.Awake, RandomSequenceId: "missing")));

        Assert.Equal("focus", selected.Value.Id);
        Assert.False(selected.Value.Repeats);
        Assert.IsType<BehaviorSource.Random>(selected.Source);
        Assert.Equal("idle", missing.Value.Id);
    }

    [Fact]
    public void EqualPriorityUsesStableConfigurationOrder()
    {
        var first = ApplicationRule(priority: 10, sequenceId: "focus");
        var second = ApplicationRule(priority: 10, sequenceId: "manual");
        var lower = ApplicationRule(priority: 1, sequenceId: "rest");
        var basis = MakeConfiguration(BehaviorMode.Automatic);
        var configuration = basis with
        {
            AutomaticRules = [first, second, lower],
        };

        var decision = Assert.IsType<BehaviorDecision.Sequence>(
            _resolver.Resolve(
                configuration,
                Snapshot(applicationId: "com.example.Editor"),
                new(PetPresentation.Awake)));

        Assert.Equal("focus", decision.Value.Id);
        Assert.Equal(new BehaviorSource.AutomaticRule(first.Id), decision.Source);
    }

    [Fact]
    public void IdleRuleExitsImmediatelyWhenInputResumes()
    {
        var configuration = MakeConfiguration(BehaviorMode.Automatic);

        var entered = Assert.IsType<BehaviorDecision.Sequence>(
            _resolver.Resolve(
                configuration,
                Snapshot(idle: TimeSpan.FromMinutes(2)),
                new(PetPresentation.Awake)));
        var resumed = Assert.IsType<BehaviorDecision.Sequence>(
            _resolver.Resolve(
                configuration,
                Snapshot(capturedAt: TimeSpan.FromSeconds(1)),
                new(PetPresentation.Awake)));

        Assert.Equal("rest", entered.Value.Id);
        Assert.Equal("idle", resumed.Value.Id);
        Assert.IsType<BehaviorSource.DefaultBehavior>(resumed.Source);
    }

    [Fact]
    public void MissingSequenceFallsBackAndEmptyConfigurationIsUnavailable()
    {
        var missingRule = ApplicationRule(priority: 1, sequenceId: "missing");
        var idle = Sequence("idle");
        var configuration = new BehaviorConfiguration(
            BehaviorMode.Automatic,
            idle.Id,
            [idle],
            AutomaticRules: [missingRule]);

        var fallback = Assert.IsType<BehaviorDecision.Sequence>(
            _resolver.Resolve(
                configuration,
                Snapshot(applicationId: "com.example.Editor"),
                new(PetPresentation.Awake)));
        var unavailable = _resolver.Resolve(
            new(BehaviorMode.Automatic, "missing", []),
            Snapshot(),
            new(PetPresentation.Awake));

        Assert.Equal("idle", fallback.Value.Id);
        Assert.IsType<BehaviorSource.DefaultBehavior>(fallback.Source);
        Assert.IsType<BehaviorDecision.Unavailable>(unavailable);
    }

    [Fact]
    public void UnsupportedConditionIsIgnored()
    {
        var idle = Sequence("idle");
        var configuration = new BehaviorConfiguration(
            BehaviorMode.Automatic,
            idle.Id,
            [idle],
            AutomaticRules:
            [
                new(
                    Guid.NewGuid(),
                    true,
                    100,
                    new RuleCondition.Unsupported("futureCondition"),
                    idle.Id),
            ]);

        var decision = Assert.IsType<BehaviorDecision.Sequence>(
            _resolver.Resolve(
                configuration,
                Snapshot(),
                new(PetPresentation.Awake)));

        Assert.Equal("idle", decision.Value.Id);
        Assert.IsType<BehaviorSource.DefaultBehavior>(decision.Source);
    }

    private static BehaviorConfiguration MakeConfiguration(
        BehaviorMode mode,
        string? manualSequenceId = null)
    {
        var rules = new AutomaticRule[]
        {
            new(
                Guid.Parse("10000000-0000-0000-0000-000000000001"),
                true,
                10,
                new RuleCondition.IdleAtLeast(600_000),
                "sleep"),
            new(
                Guid.Parse("10000000-0000-0000-0000-000000000002"),
                true,
                10,
                new RuleCondition.Application("com.example.Editor"),
                "focus"),
            new(
                Guid.Parse("10000000-0000-0000-0000-000000000003"),
                true,
                10,
                new RuleCondition.IdleAtLeast(120_000),
                "rest"),
        };

        return new(
            mode,
            "idle",
            [
                Sequence("idle"),
                Sequence("manual"),
                Sequence("focus"),
                Sequence("rest"),
                Sequence("sleep"),
                Sequence("petting", repeats: false),
            ],
            manualSequenceId,
            rules);
    }

    private static AutomaticRule ApplicationRule(int priority, string sequenceId) =>
        new(
            Guid.NewGuid(),
            true,
            priority,
            new RuleCondition.Application("com.example.Editor"),
            sequenceId);

    private static BehaviorSequence Sequence(string id, bool repeats = true) =>
        new(id, [new(id, 1)], repeats);

    private static ActivitySnapshot Snapshot(
        TimeSpan? capturedAt = null,
        TimeSpan? idle = null,
        string? applicationId = null,
        bool isScreenLocked = false,
        bool isSystemSleeping = false) =>
        new(
            capturedAt ?? TimeSpan.Zero,
            idle ?? TimeSpan.Zero,
            applicationId,
            isScreenLocked,
            isSystemSleeping);
}
