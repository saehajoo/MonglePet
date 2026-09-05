using MonglePet.Core.Behavior;

namespace MonglePet.Core.Tests;

public sealed class MotionSchedulerTests
{
    [Fact]
    public void AdvancesCyclesRepeatCountsStepsAndRepeatingSequence()
    {
        var scheduler = Scheduler();
        var sequence = new BehaviorSequence(
            "routine",
            [new("idle", 2), new("focus", 1)],
            true);

        Assert.True(scheduler.Request(sequence));
        scheduler.Advance(TimeSpan.FromMilliseconds(100));
        AssertPlaying(scheduler, "routine", 0, "idle");
        Assert.Equal(TimeSpan.FromMilliseconds(100), scheduler.ActiveCycleRemainingDuration);

        scheduler.Advance(TimeSpan.FromMilliseconds(100));
        AssertPlaying(scheduler, "routine", 1, "focus");
        Assert.Equal(TimeSpan.FromMilliseconds(250), scheduler.ActiveCycleRemainingDuration);

        scheduler.Advance(TimeSpan.FromMilliseconds(250));
        AssertPlaying(scheduler, "routine", 0, "idle");
    }

    [Fact]
    public void EquivalentRequestPreservesProgressAndEditedRequestRestarts()
    {
        var scheduler = Scheduler();
        var original = new BehaviorSequence("routine", [new("idle", 2)], true);
        scheduler.Request(original);
        scheduler.Advance(TimeSpan.FromMilliseconds(75));

        Assert.False(scheduler.Request(
            new BehaviorSequence("routine", [new("idle", 2)], true)));
        Assert.Equal(TimeSpan.FromMilliseconds(25), scheduler.ActiveCycleRemainingDuration);

        Assert.True(scheduler.Request(
            new BehaviorSequence("routine", [new("focus", 1)], true)));
        AssertPlaying(scheduler, "routine", 0, "focus");
        Assert.Equal(TimeSpan.FromMilliseconds(250), scheduler.ActiveCycleRemainingDuration);
    }

    [Fact]
    public void CurrentDefaultAndMissingMotionResolveToPackageDefault()
    {
        var scheduler = Scheduler();
        scheduler.Request(new BehaviorSequence(
            "routine",
            [
                new(BehaviorMotionReferences.CurrentPetDefault, 1),
                new("missing", 1),
            ],
            false));

        ScheduledMotion current = AssertPlaying(scheduler, "routine", 0, "idle");
        Assert.False(current.UsesFallback);
        scheduler.Advance(TimeSpan.FromMilliseconds(100));
        ScheduledMotion missing = AssertPlaying(scheduler, "routine", 1, "idle");
        Assert.True(missing.UsesFallback);
    }

    [Fact]
    public void PausePreservesRemainingTimeUntilResume()
    {
        var scheduler = Scheduler();
        scheduler.Request(new BehaviorSequence("routine", [new("idle", 1)], true));
        scheduler.Advance(TimeSpan.FromMilliseconds(40));

        scheduler.Pause();
        scheduler.Advance(TimeSpan.FromSeconds(10));
        Assert.Equal(TimeSpan.FromMilliseconds(60), scheduler.ActiveCycleRemainingDuration);

        scheduler.Resume();
        scheduler.Advance(TimeSpan.FromMilliseconds(60));
        Assert.Equal(TimeSpan.FromMilliseconds(100), scheduler.ActiveCycleRemainingDuration);
    }

    [Fact]
    public void NonRepeatingSequenceCompletesAndInvalidInitialRequestIsUnavailable()
    {
        var scheduler = Scheduler();
        Assert.False(scheduler.Request(new BehaviorSequence("invalid", [], false)));
        Assert.IsType<MotionSchedulerStatus.Unavailable>(scheduler.Status);

        Assert.True(scheduler.Request(
            new BehaviorSequence("once", [new("focus", 1)], false)));
        scheduler.Advance(TimeSpan.FromMilliseconds(250));

        Assert.Equal(
            new MotionSchedulerStatus.Completed("once"),
            scheduler.Status);
        Assert.Null(scheduler.ActiveCycleRemainingDuration);
    }

    [Fact]
    public void EquivalentRequestDoesNotRestartAfterSequenceCompletes()
    {
        var scheduler = Scheduler();
        var sequence = new BehaviorSequence("once", [new("idle", 1)], false);

        Assert.True(scheduler.Request(sequence));
        scheduler.Advance(TimeSpan.FromMilliseconds(100));
        Assert.IsType<MotionSchedulerStatus.Completed>(scheduler.Status);

        Assert.False(scheduler.Request(sequence));
        Assert.Equal(new MotionSchedulerStatus.Completed("once"), scheduler.Status);
        Assert.Null(scheduler.ActiveCycleRemainingDuration);
    }

    [Fact]
    public void OncePlaybackIgnoresStoredRepeatsAndEditedSequenceRestarts()
    {
        var scheduler = Scheduler();
        var legacy = new BehaviorSequence("routine", [new("idle", 1)], true);

        Assert.True(scheduler.Request(legacy, MotionSequencePlayback.Once));
        scheduler.Advance(TimeSpan.FromMilliseconds(100));
        Assert.Equal(new MotionSchedulerStatus.Completed("routine"), scheduler.Status);
        Assert.Equal("idle", scheduler.CompletedMotion?.ResolvedMotionId);
        Assert.False(scheduler.Request(legacy, MotionSequencePlayback.Once));

        var edited = legacy with { Steps = [new("focus", 1)] };
        Assert.True(scheduler.Request(edited, MotionSequencePlayback.Once));
        AssertPlaying(scheduler, "routine", 0, "focus");
    }

    [Fact]
    public void MovementPlaybackRepeatsOnlyWhileRequested()
    {
        var scheduler = Scheduler();
        var storedOnce = new BehaviorSequence("move", [new("idle", 1)], false);

        Assert.True(scheduler.Request(storedOnce, MotionSequencePlayback.RepeatWhileRequested));
        scheduler.Advance(TimeSpan.FromMilliseconds(100));
        AssertPlaying(scheduler, "move", 0, "idle");
        Assert.False(scheduler.Request(storedOnce, MotionSequencePlayback.RepeatWhileRequested));

        scheduler.Stop();
        Assert.IsType<MotionSchedulerStatus.Stopped>(scheduler.Status);
    }

    [Fact]
    public void ReportsElapsedTimeInsideCurrentMotionCycle()
    {
        var scheduler = Scheduler();
        scheduler.Request(new BehaviorSequence("routine", [new("focus", 1)], true));

        scheduler.Advance(TimeSpan.FromMilliseconds(175));

        Assert.Equal(TimeSpan.FromMilliseconds(175), scheduler.ActiveCycleElapsedDuration);
        Assert.Equal(TimeSpan.FromMilliseconds(75), scheduler.ActiveCycleRemainingDuration);
    }

    [Fact]
    public void ExplicitRestartStartsEquivalentSequenceFromFirstCycle()
    {
        var scheduler = Scheduler();
        var sequence = new BehaviorSequence("random", [new("focus", 1)], false);
        scheduler.Request(sequence);
        scheduler.Advance(TimeSpan.FromMilliseconds(175));

        Assert.True(scheduler.Restart(sequence));

        AssertPlaying(scheduler, "random", 0, "focus");
        Assert.Equal(TimeSpan.Zero, scheduler.ActiveCycleElapsedDuration);
        Assert.Equal(TimeSpan.FromMilliseconds(250), scheduler.ActiveCycleRemainingDuration);
    }

    [Fact]
    public void CompletedPassCountAdvancesOnlyAtWholeSequenceBoundary()
    {
        var scheduler = Scheduler();
        scheduler.Request(new BehaviorSequence(
            "routine",
            [new("idle", 2), new("focus", 1)],
            true));

        scheduler.Advance(TimeSpan.FromMilliseconds(200));
        Assert.Equal(0UL, scheduler.CompletedSequencePassCount);

        scheduler.Advance(TimeSpan.FromMilliseconds(250));
        Assert.Equal(1UL, scheduler.CompletedSequencePassCount);
        Assert.False(scheduler.IsSequenceComplete);

        scheduler.Advance(TimeSpan.FromMilliseconds(450));
        Assert.Equal(2UL, scheduler.CompletedSequencePassCount);
    }

    private static MotionScheduler Scheduler() => new(
        "idle",
        new Dictionary<string, TimeSpan>(StringComparer.Ordinal)
        {
            ["idle"] = TimeSpan.FromMilliseconds(100),
            ["focus"] = TimeSpan.FromMilliseconds(250),
        });

    private static ScheduledMotion AssertPlaying(
        MotionScheduler scheduler,
        string sequenceId,
        int stepIndex,
        string motionId)
    {
        ScheduledMotion motion = Assert.IsType<MotionSchedulerStatus.Playing>(scheduler.Status).Motion;
        Assert.Equal(sequenceId, motion.SequenceId);
        Assert.Equal(stepIndex, motion.StepIndex);
        Assert.Equal(motionId, motion.ResolvedMotionId);
        return motion;
    }
}
