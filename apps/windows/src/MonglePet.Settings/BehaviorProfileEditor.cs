using MonglePet.Core.Behavior;

namespace MonglePet.Settings;

public enum BehaviorProfileEditError
{
    InvalidSequenceName,
    DuplicateSequenceName,
    SequenceLimitReached,
    SequenceNotFound,
    ProtectedSequence,
    StepLimitReached,
    CannotRemoveLastStep,
    InvalidStep,
    InvalidStepIndex,
    RuleLimitReached,
    RuleNotFound,
    InvalidRule,
}

public sealed class BehaviorProfileEditException(
    BehaviorProfileEditError error,
    string message) : Exception(message)
{
    public BehaviorProfileEditError Error { get; } = error;
}

public static class BehaviorProfileEditor
{
    private static readonly BehaviorStep DefaultStep = new(
        BehaviorMotionReferences.CurrentPetDefault,
        1);

    public static BehaviorProfile AddSequence(
        BehaviorProfile profile,
        string name,
        Guid? id = null)
    {
        ArgumentNullException.ThrowIfNull(profile);
        if (profile.Sequences.Count >= AppSettingsLimits.MaximumSequences)
        {
            throw Error(BehaviorProfileEditError.SequenceLimitReached, "행동 루틴은 최대 100개까지 만들 수 있습니다.");
        }

        string displayName = RequiredIdentifier(
            name,
            BehaviorProfileEditError.InvalidSequenceName,
            "행동 루틴 이름을 입력해 주세요.");
        if (profile.Sequences.Any(sequence =>
            string.Equals(sequence.DisplayName, displayName, StringComparison.OrdinalIgnoreCase)))
        {
            throw Error(BehaviorProfileEditError.DuplicateSequenceName, "같은 이름의 행동 루틴이 이미 있습니다.");
        }

        string sequenceId = (id ?? Guid.NewGuid()).ToString("D");
        if (profile.Sequences.Any(sequence => sequence.Id == sequenceId))
        {
            throw Error(BehaviorProfileEditError.DuplicateSequenceName, "같은 ID의 행동이 이미 있습니다.");
        }
        var sequence = new BehaviorSequence(sequenceId, [DefaultStep], true)
        {
            DisplayName = displayName,
        };
        return profile with
        {
            Sequences = [.. profile.Sequences, sequence],
        };
    }

    public static BehaviorProfile RenameSequence(
        BehaviorProfile profile,
        string sequenceId,
        string displayName)
    {
        BehaviorSequence sequence = RequiredSequence(profile, sequenceId);
        string normalized = RequiredIdentifier(
            displayName,
            BehaviorProfileEditError.InvalidSequenceName,
            "행동 이름을 입력해 주세요.");
        if (profile.Sequences.Any(value => value.Id != sequenceId &&
            string.Equals(value.DisplayName, normalized, StringComparison.OrdinalIgnoreCase)))
        {
            throw Error(BehaviorProfileEditError.DuplicateSequenceName, "같은 이름의 행동이 이미 있습니다.");
        }
        return ReplaceSequence(profile, sequence with { DisplayName = normalized });
    }

    public static BehaviorProfile AddSequenceForMotion(
        BehaviorProfile profile,
        string displayName,
        string motionId,
        Guid? id = null)
    {
        BehaviorProfile added = AddSequence(profile, displayName, id);
        string sequenceId = added.Sequences[^1].Id;
        return ReplaceStep(
            added,
            sequenceId,
            0,
            new BehaviorStep(
                RequiredIdentifier(
                    motionId,
                    BehaviorProfileEditError.InvalidStep,
                    "연결할 애니메이션을 찾을 수 없습니다."),
                1));
    }

    public static BehaviorProfile AppendMotionStep(
        BehaviorProfile profile,
        string sequenceId,
        string motionId)
    {
        BehaviorSequence sequence = RequiredSequence(profile, sequenceId);
        if (sequence.Steps.Count >= AppSettingsLimits.MaximumStepsPerSequence)
        {
            throw Error(BehaviorProfileEditError.StepLimitReached, "행동 단계는 루틴마다 최대 100개까지 추가할 수 있습니다.");
        }
        string normalizedMotionId = RequiredIdentifier(
            motionId,
            BehaviorProfileEditError.InvalidStep,
            "연결할 애니메이션을 찾을 수 없습니다.");
        return ReplaceSequence(profile, sequence with
        {
            Steps = [.. sequence.Steps, new BehaviorStep(normalizedMotionId, 1)],
        });
    }

    public static BehaviorProfile RemoveSequence(BehaviorProfile profile, string sequenceId)
    {
        ArgumentNullException.ThrowIfNull(profile);
        _ = RequiredSequence(profile, sequenceId);
        if (string.Equals(
            sequenceId,
            BehaviorMotionReferences.DefaultSequence,
            StringComparison.Ordinal))
        {
            throw Error(BehaviorProfileEditError.ProtectedSequence, "기본 행동 루틴은 삭제할 수 없습니다.");
        }

        IReadOnlyList<BehaviorSequence> sequences = profile.Sequences
            .Where(sequence => !string.Equals(sequence.Id, sequenceId, StringComparison.Ordinal))
            .ToList();
        PetSpeechSettings speech = profile.Speech with
        {
            Phrases = profile.Speech.Phrases.Where(phrase =>
                phrase.Trigger is not PetSpeechTrigger.Sequence trigger ||
                !string.Equals(trigger.SequenceId, sequenceId, StringComparison.Ordinal)).ToList(),
        };
        PetMovementSettings movement = RemoveMovementReference(
            profile.Movement,
            sequenceId);
        return profile with
        {
            Sequences = sequences,
            StationarySequenceId = string.Equals(
                profile.StationarySequenceId,
                sequenceId,
                StringComparison.Ordinal)
                ? null
                : profile.StationarySequenceId,
            AutomaticRules = profile.AutomaticRules.Where(rule =>
                !string.Equals(rule.SequenceId, sequenceId, StringComparison.Ordinal)).ToList(),
            RandomSequenceIds = profile.RandomSequences.Where(id =>
                !string.Equals(id, sequenceId, StringComparison.Ordinal)).ToArray(),
            Movement = movement,
            PettingBehaviorId = string.Equals(
                profile.PettingBehaviorId,
                sequenceId,
                StringComparison.Ordinal)
                ? null
                : profile.PettingBehaviorId,
            Speech = speech,
        };
    }

    private static PetMovementSettings RemoveMovementReference(
        PetMovementSettings movement,
        string sequenceId)
    {
        MovementBehaviorSettings Clean(MovementBehaviorSettings value)
        {
            string? Keep(string? id) => string.Equals(
                id,
                sequenceId,
                StringComparison.Ordinal) ? null : id;
            DirectionalBehaviorIds directions = value.DirectionBehaviorIds;
            return value with
            {
                FallbackBehaviorId = Keep(value.FallbackBehaviorId),
                DirectionBehaviorIds = directions with
                {
                    Left = Keep(directions.Left),
                    Right = Keep(directions.Right),
                    Up = Keep(directions.Up),
                    Down = Keep(directions.Down),
                    UpLeft = Keep(directions.UpLeft),
                    UpRight = Keep(directions.UpRight),
                    DownLeft = Keep(directions.DownLeft),
                    DownRight = Keep(directions.DownRight),
                },
            };
        }
        CursorFollowingMovementSettings following = movement.CursorFollowing with
        {
            Behavior = Clean(movement.CursorFollowing.Behavior),
        };
        FreeRoamingMovementSettings roaming = movement.FreeRoaming with
        {
            Behavior = Clean(movement.FreeRoaming.Behavior),
        };
        CursorAvoidingMovementSettings avoiding = movement.CursorAvoiding with
        {
            Behavior = Clean(movement.CursorAvoiding.Behavior),
            IdleFreeRoaming = movement.CursorAvoiding.IdleFreeRoaming with
            {
                Behavior = Clean(movement.CursorAvoiding.IdleFreeRoaming.Behavior),
            },
        };
        return movement with
        {
            CursorFollowingSettings = following,
            FreeRoamingSettings = roaming,
            CursorAvoidingSettings = avoiding,
        };
    }

    public static BehaviorProfile AddStep(BehaviorProfile profile, string sequenceId)
    {
        BehaviorSequence sequence = RequiredSequence(profile, sequenceId);
        if (sequence.Steps.Count >= AppSettingsLimits.MaximumStepsPerSequence)
        {
            throw Error(BehaviorProfileEditError.StepLimitReached, "행동 단계는 루틴마다 최대 100개까지 추가할 수 있습니다.");
        }

        return ReplaceSequence(
            profile,
            sequence with { Steps = [.. sequence.Steps, DefaultStep] });
    }

    public static BehaviorProfile ReplaceStep(
        BehaviorProfile profile,
        string sequenceId,
        int index,
        BehaviorStep step)
    {
        BehaviorSequence sequence = RequiredSequence(profile, sequenceId);
        ValidateStep(step);
        if (index < 0 || index >= sequence.Steps.Count)
        {
            throw Error(BehaviorProfileEditError.InvalidStepIndex, "편집할 행동 단계를 찾을 수 없습니다.");
        }

        var steps = sequence.Steps.ToList();
        steps[index] = step;
        return ReplaceSequence(profile, sequence with { Steps = steps });
    }

    public static BehaviorProfile RemoveStep(
        BehaviorProfile profile,
        string sequenceId,
        int index)
    {
        BehaviorSequence sequence = RequiredSequence(profile, sequenceId);
        if (index < 0 || index >= sequence.Steps.Count)
        {
            throw Error(BehaviorProfileEditError.InvalidStepIndex, "삭제할 행동 단계를 찾을 수 없습니다.");
        }
        if (sequence.Steps.Count == 1)
        {
            throw Error(BehaviorProfileEditError.CannotRemoveLastStep, "행동 루틴에는 단계가 하나 이상 필요합니다.");
        }

        var steps = sequence.Steps.ToList();
        steps.RemoveAt(index);
        return ReplaceSequence(profile, sequence with { Steps = steps });
    }

    public static BehaviorProfile MoveStep(
        BehaviorProfile profile,
        string sequenceId,
        int sourceIndex,
        int destinationIndex)
    {
        BehaviorSequence sequence = RequiredSequence(profile, sequenceId);
        if (sourceIndex < 0 || sourceIndex >= sequence.Steps.Count ||
            destinationIndex < 0 || destinationIndex >= sequence.Steps.Count)
        {
            throw Error(BehaviorProfileEditError.InvalidStepIndex, "이동할 행동 단계를 찾을 수 없습니다.");
        }
        if (sourceIndex == destinationIndex)
        {
            return profile;
        }

        var steps = sequence.Steps.ToList();
        BehaviorStep step = steps[sourceIndex];
        steps.RemoveAt(sourceIndex);
        steps.Insert(destinationIndex, step);
        return ReplaceSequence(profile, sequence with { Steps = steps });
    }

    public static BehaviorProfile SetSequenceRepeats(
        BehaviorProfile profile,
        string sequenceId,
        bool repeats)
    {
        BehaviorSequence sequence = RequiredSequence(profile, sequenceId);
        return ReplaceSequence(profile, sequence with { Repeats = repeats });
    }

    public static BehaviorProfile AddApplicationRule(
        BehaviorProfile profile,
        string applicationId,
        string sequenceId,
        Guid? id = null) =>
        AddRule(
            profile,
            new RuleCondition.Application(RequiredIdentifier(
                applicationId,
                BehaviorProfileEditError.InvalidRule,
                "앱 식별자가 올바르지 않습니다.")),
            sequenceId,
            id);

    public static BehaviorProfile AddIdleRule(
        BehaviorProfile profile,
        int seconds,
        string sequenceId,
        Guid? id = null)
    {
        if (seconds is < 1 or > 86_400)
        {
            throw Error(BehaviorProfileEditError.InvalidRule, "입력 없음 시간은 1초에서 86,400초 사이여야 합니다.");
        }
        return AddRule(
            profile,
            new RuleCondition.IdleAtLeast(checked((long)seconds * 1_000)),
            sequenceId,
            id);
    }

    public static BehaviorProfile ReplaceRule(
        BehaviorProfile profile,
        AutomaticRule rule)
    {
        ArgumentNullException.ThrowIfNull(profile);
        ArgumentNullException.ThrowIfNull(rule);
        int index = profile.AutomaticRules.ToList().FindIndex(value => value.Id == rule.Id);
        if (index < 0)
        {
            throw Error(BehaviorProfileEditError.RuleNotFound, "조건 규칙을 찾을 수 없습니다.");
        }
        ValidateRule(rule, profile.Sequences);
        var rules = profile.AutomaticRules.ToList();
        EnsureUniqueCondition(rule, rules.Where(value => value.Id != rule.Id));
        rules[index] = rule;
        return profile with { AutomaticRules = rules };
    }

    public static BehaviorProfile RemoveRule(BehaviorProfile profile, Guid ruleId)
    {
        ArgumentNullException.ThrowIfNull(profile);
        if (!profile.AutomaticRules.Any(rule => rule.Id == ruleId))
        {
            throw Error(BehaviorProfileEditError.RuleNotFound, "조건 규칙을 찾을 수 없습니다.");
        }
        return profile with
        {
            AutomaticRules = profile.AutomaticRules.Where(rule => rule.Id != ruleId).ToList(),
        };
    }

    private static BehaviorProfile AddRule(
        BehaviorProfile profile,
        RuleCondition condition,
        string sequenceId,
        Guid? id)
    {
        ArgumentNullException.ThrowIfNull(profile);
        if (profile.AutomaticRules.Count >= AppSettingsLimits.MaximumAutomaticRules)
        {
            throw Error(BehaviorProfileEditError.RuleLimitReached, "조건 규칙은 최대 100개까지 만들 수 있습니다.");
        }
        Guid ruleId = id ?? Guid.NewGuid();
        if (profile.AutomaticRules.Any(rule => rule.Id == ruleId))
        {
            throw Error(BehaviorProfileEditError.InvalidRule, "같은 ID의 조건 규칙이 이미 있습니다.");
        }
        int maximumPriority = profile.AutomaticRules.Count == 0
            ? -1
            : profile.AutomaticRules.Max(rule => rule.Priority);
        int priority = maximumPriority == int.MaxValue ? int.MaxValue : maximumPriority + 1;
        var rule = new AutomaticRule(ruleId, true, priority, condition, sequenceId);
        ValidateRule(rule, profile.Sequences);
        EnsureUniqueCondition(rule, profile.AutomaticRules);
        return profile with { AutomaticRules = [.. profile.AutomaticRules, rule] };
    }

    private static void EnsureUniqueCondition(
        AutomaticRule candidate,
        IEnumerable<AutomaticRule> existing)
    {
        bool duplicate = candidate.Condition switch
        {
            RuleCondition.IdleAtLeast => existing.Any(rule =>
                rule.Condition is RuleCondition.IdleAtLeast),
            RuleCondition.Application application => existing.Any(rule =>
                rule.Condition is RuleCondition.Application other &&
                string.Equals(
                    other.ApplicationId,
                    application.ApplicationId,
                    StringComparison.Ordinal)),
            _ => false,
        };
        if (duplicate)
        {
            throw Error(
                BehaviorProfileEditError.InvalidRule,
                "같은 종류와 대상의 조건 규칙이 이미 있습니다.");
        }
    }

    private static BehaviorProfile ReplaceSequence(
        BehaviorProfile profile,
        BehaviorSequence sequence)
    {
        int index = profile.Sequences.ToList().FindIndex(value => string.Equals(
            value.Id,
            sequence.Id,
            StringComparison.Ordinal));
        if (index < 0)
        {
            throw Error(BehaviorProfileEditError.SequenceNotFound, "행동 루틴을 찾을 수 없습니다.");
        }
        ValidateSequence(sequence);
        var sequences = profile.Sequences.ToList();
        sequences[index] = sequence;
        return profile with { Sequences = sequences };
    }

    private static BehaviorSequence RequiredSequence(
        BehaviorProfile profile,
        string sequenceId)
    {
        ArgumentNullException.ThrowIfNull(profile);
        return profile.Sequences.FirstOrDefault(sequence => string.Equals(
                sequence.Id,
                sequenceId,
                StringComparison.Ordinal))
            ?? throw Error(BehaviorProfileEditError.SequenceNotFound, "행동 루틴을 찾을 수 없습니다.");
    }

    private static void ValidateSequence(BehaviorSequence sequence)
    {
        _ = RequiredIdentifier(
            sequence.Id,
            BehaviorProfileEditError.InvalidSequenceName,
            "행동 루틴 이름이 올바르지 않습니다.");
        if (sequence.Steps.Count is < 1 or > AppSettingsLimits.MaximumStepsPerSequence)
        {
            throw Error(BehaviorProfileEditError.InvalidStep, "행동 루틴의 단계 수가 올바르지 않습니다.");
        }
        foreach (BehaviorStep step in sequence.Steps)
        {
            ValidateStep(step);
        }
    }

    private static void ValidateStep(BehaviorStep step)
    {
        ArgumentNullException.ThrowIfNull(step);
        string motionId = RequiredIdentifier(
            step.MotionId,
            BehaviorProfileEditError.InvalidStep,
            "펫 모션을 선택해 주세요.");
        if (!string.Equals(motionId, step.MotionId, StringComparison.Ordinal) ||
            step.RepeatCount is < 1 or > AppSettingsLimits.MaximumRepeatCount)
        {
            throw Error(BehaviorProfileEditError.InvalidStep, "펫 모션 또는 반복 횟수가 올바르지 않습니다.");
        }
    }

    private static void ValidateRule(
        AutomaticRule rule,
        IReadOnlyList<BehaviorSequence> sequences)
    {
        if (!sequences.Any(sequence => string.Equals(
            sequence.Id,
            rule.SequenceId,
            StringComparison.Ordinal)))
        {
            throw Error(BehaviorProfileEditError.InvalidRule, "조건 규칙의 대상 행동을 찾을 수 없습니다.");
        }

        bool valid = rule.Condition switch
        {
            RuleCondition.Application application =>
                IsNormalizedIdentifier(application.ApplicationId) &&
                !application.ApplicationId.Any(char.IsWhiteSpace),
            RuleCondition.IdleAtLeast idle =>
                idle.Milliseconds is >= 1_000 and <= AppSettingsLimits.MaximumDurationMilliseconds,
            RuleCondition.Unsupported unsupported =>
                !rule.IsEnabled && IsNormalizedIdentifier(unsupported.Type),
            _ => false,
        };
        if (!valid)
        {
            throw Error(BehaviorProfileEditError.InvalidRule, "조건 규칙의 조건이 올바르지 않습니다.");
        }
    }

    private static bool IsNormalizedIdentifier(string value) =>
        !string.IsNullOrWhiteSpace(value) &&
        string.Equals(value, value.Trim(), StringComparison.Ordinal);

    private static string RequiredIdentifier(
        string? value,
        BehaviorProfileEditError error,
        string message)
    {
        string normalized = value?.Trim() ?? string.Empty;
        return normalized.Length == 0 ? throw Error(error, message) : normalized;
    }

    private static BehaviorProfileEditException Error(
        BehaviorProfileEditError error,
        string message) => new(error, message);
}
