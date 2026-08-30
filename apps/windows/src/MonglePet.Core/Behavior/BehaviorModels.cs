namespace MonglePet.Core.Behavior;

public enum PetPresentation
{
    Awake,
    TuckedAway,
    Suspended,
}

public enum StationaryBehaviorMode
{
    Fixed,
    Random,
}

public enum AutomaticRuleKind
{
    Movement,
    Idle,
    Application,
}

public sealed record BehaviorStep(string MotionId, int RepeatCount);

public sealed record BehaviorSequence(
    string Id,
    IReadOnlyList<BehaviorStep> Steps,
    bool Repeats)
{
    public string DisplayName { get; init; } = Id;
}

public abstract record RuleCondition
{
    private RuleCondition() { }

    public sealed record Application(string ApplicationId) : RuleCondition;

    public sealed record IdleAtLeast(long Milliseconds) : RuleCondition;

    public sealed record Unsupported(string Type) : RuleCondition;
}

public sealed record AutomaticRule(
    Guid Id,
    bool IsEnabled,
    int Priority,
    RuleCondition Condition,
    string SequenceId);

public sealed record ActivitySnapshot(
    TimeSpan CapturedAt,
    TimeSpan IdleDuration,
    string? FrontmostApplicationId,
    bool IsScreenLocked,
    bool IsSystemSleeping);

public sealed record BehaviorConfiguration(
    StationaryBehaviorMode StationaryBehaviorMode,
    string DefaultSequenceId,
    IReadOnlyList<BehaviorSequence> Sequences,
    string? StationarySequenceId = null,
    IReadOnlyList<AutomaticRule>? AutomaticRules = null,
    IReadOnlyList<string>? RandomSequenceIds = null,
    IReadOnlyList<AutomaticRuleKind>? AutomaticRulePriorityOrder = null)
{
    public IReadOnlyList<AutomaticRule> Rules =>
        AutomaticRules ?? Array.Empty<AutomaticRule>();

    public IReadOnlyList<string> RandomSequences =>
        RandomSequenceIds ?? Array.Empty<string>();

    public IReadOnlyList<AutomaticRuleKind> RulePriorityOrder =>
        AutomaticRulePriorityOrder ??
        [AutomaticRuleKind.Movement, AutomaticRuleKind.Idle, AutomaticRuleKind.Application];

    public BehaviorSequence? FindSequence(string id) =>
        Sequences.FirstOrDefault(sequence => sequence.Id == id);

    public BehaviorSequence? DefaultSequence =>
        FindSequence(DefaultSequenceId) ?? Sequences.FirstOrDefault();
}

public sealed record BehaviorRuntimeState(
    PetPresentation Presentation,
    string? InteractionSequenceId = null,
    string? MovementSequenceId = null,
    string? RandomSequenceId = null);

public abstract record BehaviorSource
{
    private BehaviorSource() { }

    public sealed record Interaction : BehaviorSource;

    public sealed record Fixed : BehaviorSource;

    public sealed record Random : BehaviorSource;

    public sealed record Movement : BehaviorSource;

    public sealed record AutomaticRule(Guid RuleId) : BehaviorSource;

    public sealed record DefaultBehavior : BehaviorSource;
}

public abstract record BehaviorDecision
{
    private BehaviorDecision() { }

    public sealed record TuckedAway : BehaviorDecision;

    public sealed record Suspended : BehaviorDecision;

    public sealed record Sequence(
        BehaviorSequence Value,
        BehaviorSource Source) : BehaviorDecision;

    public sealed record Unavailable : BehaviorDecision;
}
