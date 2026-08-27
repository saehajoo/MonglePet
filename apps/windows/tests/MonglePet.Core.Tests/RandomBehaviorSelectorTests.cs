using MonglePet.Core.Behavior;

namespace MonglePet.Core.Tests;

public sealed class RandomBehaviorSelectorTests
{
    [Fact]
    public void CompletedSingleEntryIsSelectedAgain()
    {
        var selector = new RandomBehaviorSelector(new Random(1));

        Assert.Equal("only", selector.Update(["only"], sequenceCompleted: false));
        Assert.Equal("only", selector.Update(["only"], sequenceCompleted: true));
    }

    [Fact]
    public void CompletionAdvancesShuffleBagWithoutImmediateRepeat()
    {
        var selector = new RandomBehaviorSelector(new Random(42));
        string[] available = ["one", "two", "three"];

        string first = selector.Update(available, sequenceCompleted: false)!;
        string second = selector.Update(available, sequenceCompleted: true)!;

        Assert.NotEqual(first, second);
    }

    [Fact]
    public void MissingCurrentEntryIsRecoveredAndEmptySelectionResets()
    {
        var selector = new RandomBehaviorSelector(new Random(1));
        selector.Update(["old"], sequenceCompleted: false);

        Assert.Equal("new", selector.Update(["new"], sequenceCompleted: false));
        Assert.Null(selector.Update([], sequenceCompleted: false));
        Assert.Null(selector.CurrentSequenceId);
    }
}
