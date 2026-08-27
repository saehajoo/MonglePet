using MonglePet.Core.Behavior;

namespace MonglePet.Core.Tests;

public sealed class BehaviorShuffleBagTests
{
    [Fact]
    public void VisitsEveryEntryOnceAndAvoidsRepeatingAcrossBagBoundaries()
    {
        var bag = new BehaviorShuffleBag(new Random(42));
        string[] ids = ["one", "two", "three"];

        string[] first = Enumerable.Range(0, ids.Length)
            .Select(_ => bag.Next(ids)!)
            .ToArray();
        string[] second = Enumerable.Range(0, ids.Length)
            .Select(_ => bag.Next(ids)!)
            .ToArray();

        Assert.Equal(ids.Order(), first.Order());
        Assert.Equal(ids.Order(), second.Order());
        Assert.NotEqual(first[^1], second[0]);
    }

    [Fact]
    public void EmptyAndChangedSourcesResetSafely()
    {
        var bag = new BehaviorShuffleBag(new Random(1));

        Assert.Null(bag.Next([]));
        Assert.Equal("only", bag.Next(["only", "only"]));
        Assert.Equal("new", bag.Next(["new"]));
    }
}
