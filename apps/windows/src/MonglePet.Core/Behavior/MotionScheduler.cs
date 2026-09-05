namespace MonglePet.Core.Behavior;

public static class BehaviorMotionReferences
{
    public const string CurrentPetDefault = "__monglepet_current_pet_default__";
    public const string DefaultSequence = "__monglepet_default_behavior__";
}

public sealed record MotionDefinition(string Id, TimeSpan CycleDuration);

public enum MotionSequencePlayback
{
    Stored,
    Once,
    RepeatWhileRequested,
}

public sealed record ScheduledMotion(
    string SequenceId,
    int StepIndex,
    string RequestedMotionId,
    string ResolvedMotionId)
{
    public bool UsesFallback =>
        RequestedMotionId != BehaviorMotionReferences.CurrentPetDefault &&
        !string.Equals(RequestedMotionId, ResolvedMotionId, StringComparison.Ordinal);
}

public abstract record MotionSchedulerStatus
{
    private MotionSchedulerStatus() { }

    public sealed record Stopped : MotionSchedulerStatus;

    public sealed record Playing(ScheduledMotion Motion) : MotionSchedulerStatus;

    public sealed record Completed(string SequenceId) : MotionSchedulerStatus;

    public sealed record Unavailable : MotionSchedulerStatus;
}

public sealed class MotionScheduler
{
    private readonly IReadOnlyDictionary<string, TimeSpan> _cycleDurations;
    private readonly string _defaultMotionId;
    private Cursor? _cursor;
    private bool _unavailable;

    public MotionScheduler(
        string defaultMotionId,
        IReadOnlyDictionary<string, TimeSpan> cycleDurations)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(defaultMotionId);
        ArgumentNullException.ThrowIfNull(cycleDurations);
        if (!cycleDurations.TryGetValue(defaultMotionId, out TimeSpan duration) ||
            duration <= TimeSpan.Zero)
        {
            throw new ArgumentException(
                "The default motion must have a positive cycle duration.",
                nameof(cycleDurations));
        }
        if (cycleDurations.Any(item =>
                string.IsNullOrWhiteSpace(item.Key) || item.Value <= TimeSpan.Zero))
        {
            throw new ArgumentException(
                "Every motion must have an identifier and a positive cycle duration.",
                nameof(cycleDurations));
        }

        _defaultMotionId = defaultMotionId;
        _cycleDurations = cycleDurations;
    }

    public MotionSchedulerStatus Status
    {
        get
        {
            if (_cursor is null)
            {
                return _unavailable
                    ? new MotionSchedulerStatus.Unavailable()
                    : new MotionSchedulerStatus.Stopped();
            }
            if (_cursor.IsComplete)
            {
                return new MotionSchedulerStatus.Completed(_cursor.Sequence.Id);
            }

            return new MotionSchedulerStatus.Playing(Scheduled(_cursor, _cursor.StepIndex));
        }
    }

    public bool IsPaused { get; private set; }

    public string? ActiveSequenceId => _cursor?.Sequence.Id;

    public ulong CompletedSequencePassCount { get; private set; }

    public bool IsSequenceComplete => _cursor?.IsComplete ?? false;

    public ScheduledMotion? CompletedMotion => _cursor is { IsComplete: true } cursor
        ? Scheduled(cursor, cursor.Steps.Count - 1)
        : null;

    public TimeSpan? ActiveCycleRemainingDuration =>
        _cursor is { IsComplete: false } cursor
            ? cursor.RemainingCycleDuration
            : null;

    public TimeSpan? ActiveCycleElapsedDuration =>
        _cursor is { IsComplete: false } cursor
            ? cursor.Steps[cursor.StepIndex].CycleDuration - cursor.RemainingCycleDuration
            : null;

    public bool Request(
        BehaviorSequence sequence,
        MotionSequencePlayback playback = MotionSequencePlayback.Stored)
    {
        ArgumentNullException.ThrowIfNull(sequence);
        sequence = ApplyPlayback(sequence, playback);
        Cursor? requested = MakeCursor(sequence);
        if (requested is null)
        {
            if (_cursor is null)
            {
                _unavailable = true;
            }
            return false;
        }

        if (_cursor is not null && SequencesEqual(_cursor.Sequence, sequence))
        {
            _unavailable = false;
            return false;
        }

        _cursor = requested;
        _unavailable = false;
        return true;
    }

    public bool Restart(
        BehaviorSequence sequence,
        MotionSequencePlayback playback = MotionSequencePlayback.Stored)
    {
        ArgumentNullException.ThrowIfNull(sequence);
        sequence = ApplyPlayback(sequence, playback);
        Cursor? requested = MakeCursor(sequence);
        if (requested is null)
        {
            if (_cursor is null)
            {
                _unavailable = true;
            }
            return false;
        }

        _cursor = requested;
        _unavailable = false;
        return true;
    }

    public void Advance(TimeSpan elapsed)
    {
        if (IsPaused || elapsed <= TimeSpan.Zero || _cursor is null || _cursor.IsComplete)
        {
            return;
        }

        TimeSpan remainingElapsed = elapsed;
        while (remainingElapsed > TimeSpan.Zero && !_cursor.IsComplete)
        {
            if (remainingElapsed < _cursor.RemainingCycleDuration)
            {
                _cursor.RemainingCycleDuration -= remainingElapsed;
                return;
            }

            remainingElapsed -= _cursor.RemainingCycleDuration;
            bool completesSequencePass = CycleCompletesSequencePass(_cursor);
            AdvanceAfterCycle(_cursor);
            if (completesSequencePass)
            {
                unchecked
                {
                    CompletedSequencePassCount++;
                }
            }
        }
    }

    public void Pause() => IsPaused = true;

    public void Resume() => IsPaused = false;

    public void Stop()
    {
        _cursor = null;
        _unavailable = false;
        IsPaused = false;
        CompletedSequencePassCount = 0;
    }

    private static bool CycleCompletesSequencePass(Cursor cursor)
    {
        ResolvedStep step = cursor.Steps[cursor.StepIndex];
        return cursor.StepIndex == cursor.Steps.Count - 1 &&
            cursor.CompletedCycles + 1 >= step.Source.RepeatCount;
    }

    private Cursor? MakeCursor(BehaviorSequence sequence)
    {
        if (string.IsNullOrWhiteSpace(sequence.Id) || sequence.Steps.Count == 0)
        {
            return null;
        }

        var steps = new List<ResolvedStep>(sequence.Steps.Count);
        foreach (BehaviorStep step in sequence.Steps)
        {
            if (string.IsNullOrWhiteSpace(step.MotionId) || step.RepeatCount < 1)
            {
                return null;
            }

            string resolvedMotionId = ResolveMotionId(step.MotionId);
            steps.Add(new ResolvedStep(
                step,
                resolvedMotionId,
                _cycleDurations[resolvedMotionId]));
        }

        return new Cursor(sequence, steps);
    }

    private string ResolveMotionId(string requestedMotionId)
    {
        if (string.Equals(
                requestedMotionId,
                BehaviorMotionReferences.CurrentPetDefault,
                StringComparison.Ordinal))
        {
            return _defaultMotionId;
        }

        return _cycleDurations.ContainsKey(requestedMotionId)
            ? requestedMotionId
            : _defaultMotionId;
    }

    private static void AdvanceAfterCycle(Cursor cursor)
    {
        ResolvedStep step = cursor.Steps[cursor.StepIndex];
        cursor.CompletedCycles++;
        if (cursor.CompletedCycles < step.Source.RepeatCount)
        {
            cursor.RemainingCycleDuration = step.CycleDuration;
            return;
        }

        int nextStepIndex = cursor.StepIndex + 1;
        if (nextStepIndex < cursor.Steps.Count)
        {
            cursor.StepIndex = nextStepIndex;
            cursor.CompletedCycles = 0;
            cursor.RemainingCycleDuration = cursor.Steps[nextStepIndex].CycleDuration;
            return;
        }

        if (!cursor.Sequence.Repeats)
        {
            cursor.RemainingCycleDuration = TimeSpan.Zero;
            cursor.IsComplete = true;
            return;
        }

        cursor.StepIndex = 0;
        cursor.CompletedCycles = 0;
        cursor.RemainingCycleDuration = cursor.Steps[0].CycleDuration;
    }

    private static BehaviorSequence ApplyPlayback(
        BehaviorSequence sequence,
        MotionSequencePlayback playback) => playback switch
    {
        MotionSequencePlayback.Once => sequence with { Repeats = false },
        MotionSequencePlayback.RepeatWhileRequested => sequence with { Repeats = true },
        _ => sequence,
    };

    private static ScheduledMotion Scheduled(Cursor cursor, int stepIndex)
    {
        ResolvedStep step = cursor.Steps[stepIndex];
        return new ScheduledMotion(
            cursor.Sequence.Id,
            stepIndex,
            step.Source.MotionId,
            step.ResolvedMotionId);
    }

    private static bool SequencesEqual(BehaviorSequence left, BehaviorSequence right)
    {
        if (!string.Equals(left.Id, right.Id, StringComparison.Ordinal) ||
            left.Repeats != right.Repeats ||
            left.Steps.Count != right.Steps.Count)
        {
            return false;
        }

        for (int index = 0; index < left.Steps.Count; index++)
        {
            if (left.Steps[index] != right.Steps[index])
            {
                return false;
            }
        }
        return true;
    }

    private sealed record ResolvedStep(
        BehaviorStep Source,
        string ResolvedMotionId,
        TimeSpan CycleDuration);

    private sealed class Cursor
    {
        public Cursor(BehaviorSequence sequence, IReadOnlyList<ResolvedStep> steps)
        {
            Sequence = sequence;
            Steps = steps;
            RemainingCycleDuration = steps[0].CycleDuration;
        }

        public BehaviorSequence Sequence { get; }

        public IReadOnlyList<ResolvedStep> Steps { get; }

        public int StepIndex { get; set; }

        public int CompletedCycles { get; set; }

        public TimeSpan RemainingCycleDuration { get; set; }

        public bool IsComplete { get; set; }
    }
}
