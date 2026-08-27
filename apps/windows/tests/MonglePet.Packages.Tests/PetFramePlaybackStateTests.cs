namespace MonglePet.Packages.Tests;

public sealed class PetFramePlaybackStateTests
{
    [Fact]
    public void LoopingMotionWrapsToFirstFrame()
    {
        var state = new PetFramePlaybackState(Motion(loop: true));

        Assert.True(state.Advance());
        Assert.Equal(1, state.CurrentFrameIndex);
        Assert.True(state.Advance());
        Assert.Equal(0, state.CurrentFrameIndex);
        Assert.True(state.IsPlaying);
    }

    [Fact]
    public void NonLoopingMotionStopsOnLastFrame()
    {
        var state = new PetFramePlaybackState(Motion(loop: false));

        Assert.True(state.Advance());
        Assert.False(state.Advance());
        Assert.Equal(1, state.CurrentFrameIndex);
        Assert.False(state.IsPlaying);
    }

    [Fact]
    public void BehaviorLoopOverrideWrapsNonLoopingManifestMotion()
    {
        var state = new PetFramePlaybackState(Motion(loop: false), loops: true);

        Assert.True(state.Advance());
        Assert.True(state.Advance());
        Assert.Equal(0, state.CurrentFrameIndex);
        Assert.True(state.IsPlaying);
    }

    [Theory]
    [InlineData(0, 0, 100)]
    [InlineData(75, 0, 25)]
    [InlineData(100, 1, 200)]
    [InlineData(250, 1, 50)]
    [InlineData(300, 0, 100)]
    [InlineData(725, 1, 175)]
    public void SeekUsesMonotonicElapsedTimeAcrossFrameBoundaries(
        int elapsedMilliseconds,
        int expectedFrameIndex,
        int expectedRemainingMilliseconds)
    {
        var state = new PetFramePlaybackState(Motion(loop: true));

        TimeSpan remaining = state.Seek(TimeSpan.FromMilliseconds(elapsedMilliseconds));

        Assert.Equal(expectedFrameIndex, state.CurrentFrameIndex);
        Assert.Equal(TimeSpan.FromMilliseconds(expectedRemainingMilliseconds), remaining);
    }

    private static PetPackageMotion Motion(bool loop) => new(
        "idle",
        "main",
        loop,
        [
            new PetPackageFrame(0, 0, 32, 32, 100),
            new PetPackageFrame(32, 0, 32, 32, 200),
        ]);
}
