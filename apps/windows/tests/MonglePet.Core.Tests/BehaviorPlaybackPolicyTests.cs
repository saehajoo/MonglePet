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

    [Fact]
    public void RandomMissingSelectionFallbackAndAutomaticRulesRepeatByContext()
    {
        Assert.Equal(
            MotionSequencePlayback.RepeatWhileRequested,
            BehaviorPlaybackPolicy.ForStationary(
                StationaryBehaviorMode.Random,
                new BehaviorSource.DefaultBehavior()));
        Assert.Equal(
            MotionSequencePlayback.Once,
            BehaviorPlaybackPolicy.ForStationary(
                StationaryBehaviorMode.Random,
                new BehaviorSource.Random()));
        Assert.Equal(
            MotionSequencePlayback.RepeatWhileRequested,
            BehaviorPlaybackPolicy.ForAutomaticRule());
    }
}
