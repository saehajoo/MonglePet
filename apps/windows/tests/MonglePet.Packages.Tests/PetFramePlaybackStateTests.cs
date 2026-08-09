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

    private static PetPackageMotion Motion(bool loop) => new(
        "idle",
        "main",
        loop,
        [
            new PetPackageFrame(0, 0, 32, 32, 100),
            new PetPackageFrame(32, 0, 32, 32, 200),
        ]);
}
