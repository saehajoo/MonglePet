using MonglePet.Core.Movement;

namespace MonglePet.Core.Tests;

public sealed class PointerHoverTrackerTests
{
    [Fact]
    public void TriggersOnceAfterPointerDrivenDwellAndRequiresPanelExit()
    {
        var tracker = new PointerHoverTracker();

        Assert.False(tracker.Update(0, false, false, false, true, false));
        Assert.False(tracker.Update(1, true, true, true, true, false));
        Assert.False(tracker.Update(300, true, true, false, true, false));
        Assert.True(tracker.Update(301, true, true, false, true, false));
        Assert.False(tracker.Update(800, true, true, true, true, false));
        Assert.False(tracker.Update(900, false, false, true, true, false));
        Assert.False(tracker.Update(1_000, true, true, true, true, false));
        Assert.True(tracker.Update(1_300, true, true, false, true, false));
    }

    [Fact]
    public void StationaryPointerCoveredByMovingPetDoesNotTrigger()
    {
        var tracker = new PointerHoverTracker();

        Assert.False(tracker.Update(0, false, false, false, true, false));
        Assert.False(tracker.Update(100, true, true, false, true, false));
        Assert.False(tracker.Update(1_000, true, true, false, true, false));
    }

    [Fact]
    public void DraggingOrDisabledStateResetsPendingHover()
    {
        var tracker = new PointerHoverTracker();

        Assert.False(tracker.Update(0, false, false, false, true, false));
        Assert.False(tracker.Update(10, true, true, true, true, false));
        Assert.False(tracker.Update(200, true, true, true, true, true));
        Assert.False(tracker.Update(600, true, true, false, true, false));
        Assert.False(tracker.Update(700, false, false, true, false, false));
    }

    [Fact]
    public void TransparentPixelCancelsDwellUntilPanelExit()
    {
        var tracker = new PointerHoverTracker();

        Assert.False(tracker.Update(0, false, false, false, true, false));
        Assert.False(tracker.Update(10, true, true, true, true, false));
        Assert.False(tracker.Update(110, true, false, true, true, false));
        Assert.False(tracker.Update(500, true, true, true, true, false));
        Assert.False(tracker.Update(600, false, false, true, true, false));
        Assert.False(tracker.Update(700, true, true, true, true, false));
        Assert.True(tracker.Update(1_000, true, true, false, true, false));
    }
}
