using MonglePet.Core.Behavior;

namespace MonglePet.Core.Tests;

public sealed class BehaviorPlaybackPolicyTests
{
    [Theory]
    [InlineData(StationaryBehaviorMode.Fixed, MotionSequencePlayback.RepeatWhileRequested)]
    [InlineData(StationaryBehaviorMode.Random, MotionSequencePlayback.Once)]
    public void StationaryModeChoosesContinuousFixedAndOneShotRandomPlayback(
        StationaryBehaviorMode mode,
        MotionSequencePlayback expected)
    {
        Assert.Equal(expected, BehaviorPlaybackPolicy.ForStationary(mode));
    }
}
