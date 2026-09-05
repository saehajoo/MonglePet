using MonglePet.Core.Movement;
using MonglePet.Core.Behavior;

namespace MonglePet.Core.Tests;

public sealed class FreeRoamingDwellStateTests
{
    [Fact]
    public void TimerAndFallbackExpireAtTheirBoundary()
    {
        var state = new FreeRoamingDwellState();

        state.WaitForTimer(100);
        Assert.True(state.IsWaiting(99));
        Assert.False(state.IsWaiting(100));

        state.WaitForBehaviorFallback(200);
        Assert.True(state.IsWaiting(199));
        Assert.False(state.IsWaiting(200));
    }

    [Fact]
    public void BehaviorCompletionIsAcceptedOnceOnlyWhileWaitingForIt()
    {
        var state = new FreeRoamingDwellState();
        state.WaitForBehaviorCompletion();

        Assert.True(state.IsWaiting(long.MaxValue));
        Assert.True(state.CompleteBehavior());
        Assert.False(state.CompleteBehavior());
        Assert.False(state.IsWaiting(0));
    }

    [Fact]
    public void CancelIgnoresLateBehaviorCompletion()
    {
        var state = new FreeRoamingDwellState();
        state.WaitForBehaviorCompletion();

        state.Cancel();

        Assert.False(state.CompleteBehavior());
        Assert.Equal(FreeRoamingDwellWaitKind.None, state.Kind);
    }

    [Fact]
    public void RepeatingStationaryBehaviorReleasesWaitAtWholePassBoundary()
    {
        var scheduler = new MotionScheduler(
            "idle",
            new Dictionary<string, TimeSpan> { ["idle"] = TimeSpan.FromMilliseconds(100) });
        scheduler.Request(new BehaviorSequence("fixed", [new("idle", 2)], true));
        ulong requestedPass = scheduler.CompletedSequencePassCount;
        var state = new FreeRoamingDwellState();
        state.WaitForBehaviorCompletion();

        scheduler.Advance(TimeSpan.FromMilliseconds(100));
        Assert.Equal(requestedPass, scheduler.CompletedSequencePassCount);
        Assert.True(state.IsWaiting(0));

        scheduler.Advance(TimeSpan.FromMilliseconds(100));
        Assert.NotEqual(requestedPass, scheduler.CompletedSequencePassCount);
        Assert.True(state.CompleteBehavior());
        Assert.False(state.IsWaiting(0));
    }
}
