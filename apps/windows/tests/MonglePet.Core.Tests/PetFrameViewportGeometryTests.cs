using MonglePet.Core.Presentation;

namespace MonglePet.Core.Tests;

public sealed class PetFrameViewportGeometryTests
{
    [Fact]
    public void NonSquareFrameIsCenteredAndLetterboxInsetsAreExplicit()
    {
        PetFrameViewport result = PetFrameViewportGeometry.AspectFit(
            343,
            406,
            302,
            254);

        Assert.Equal(343d / 302d, result.Scale, 10);
        Assert.Equal(0, result.Left, 10);
        Assert.Equal(343, result.Width, 10);
        Assert.Equal((406 - result.Height) / 2, result.Top, 10);
        Assert.Equal(0, result.RightInset, 10);
        Assert.Equal(result.Top, result.BottomInset, 10);
    }

    [Fact]
    public void AtlasFrameMapsExactlyInsideItsClippedViewport()
    {
        const int frameY = 254;
        const int frameHeight = 254;
        PetFrameViewport result = PetFrameViewportGeometry.AspectFit(
            343,
            406,
            302,
            frameHeight);
        double brushOffsetY = result.Top - (frameY * result.Scale);

        Assert.Equal(result.Top, (frameY * result.Scale) + brushOffsetY, 10);
        Assert.Equal(
            result.Top + result.Height,
            ((frameY + frameHeight) * result.Scale) + brushOffsetY,
            10);
        Assert.True(result.Top > 0);
        Assert.True(result.BottomInset > 0);
    }

    [Fact]
    public void MatchingAspectRatioNeedsNoClipInsets()
    {
        PetFrameViewport result = PetFrameViewportGeometry.AspectFit(
            604,
            508,
            302,
            254);

        Assert.Equal(2, result.Scale, 10);
        Assert.Equal(0, result.Left, 10);
        Assert.Equal(0, result.Top, 10);
        Assert.Equal(0, result.RightInset, 10);
        Assert.Equal(0, result.BottomInset, 10);
    }
}
