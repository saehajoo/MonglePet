using MonglePet.Core.Movement;

namespace MonglePet.Core.Tests;

public sealed class PetFrameAlphaMaskTests
{
    [Fact]
    public void UsesVisiblePixelsAndIncludesNormalizedEdges()
    {
        var mask = new PetFrameAlphaMask(2, 2, [
            0, 255,
            255, 0,
        ]);

        Assert.False(mask.ContainsVisiblePixel(0.25, 0.25));
        Assert.True(mask.ContainsVisiblePixel(0.75, 0.25));
        Assert.True(mask.ContainsVisiblePixel(0.25, 0.75));
        Assert.False(mask.ContainsVisiblePixel(1, 1));
        Assert.False(mask.ContainsVisiblePixel(-0.01, 0.5));
        Assert.False(mask.ContainsVisiblePixel(double.NaN, 0.5));
    }

    [Fact]
    public void NormalizesOnlyInsideAspectFitContent()
    {
        Assert.Null(PetFrameAlphaMask.NormalizedContentPoint(
            20, 20, 200, 200, 200, 100));

        MovementPoint point = Assert.IsType<MovementPoint>(
            PetFrameAlphaMask.NormalizedContentPoint(
                150, 75, 200, 200, 200, 100));
        Assert.Equal(0.75, point.X, 3);
        Assert.Equal(0.25, point.Y, 3);
    }

    [Fact]
    public void ExtractsStraightAlphaFromRgbaPixels()
    {
        PetFrameAlphaMask mask = PetFrameAlphaMask.FromRgba8(
            2,
            1,
            [10, 20, 30, 0, 40, 50, 60, 1]);

        Assert.False(mask.ContainsVisiblePixel(0.25, 0.5));
        Assert.True(mask.ContainsVisiblePixel(0.75, 0.5));
    }

    [Fact]
    public void RejectsInvalidDimensionsAndPixelCounts()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            new PetFrameAlphaMask(0, 1, [0]));
        Assert.Throws<ArgumentException>(() =>
            new PetFrameAlphaMask(2, 1, [0]));
        Assert.Throws<ArgumentException>(() =>
            PetFrameAlphaMask.FromRgba8(1, 1, [0, 0, 0]));
    }

    [Fact]
    public void BuildsTopOriginCropAndDownscalesLargeFrame()
    {
        PetFrameAlphaDecodeRegion unchanged = PetFrameAlphaMask.DecodeRegion(
            100, 100, 10, 20, 40, 20);
        Assert.Equal(
            new PetFrameAlphaDecodeRegion(100, 100, 10, 20, 40, 20),
            unchanged);

        PetFrameAlphaDecodeRegion scaled = PetFrameAlphaMask.DecodeRegion(
            512, 256, 128, 64, 128, 64);
        Assert.Equal(
            new PetFrameAlphaDecodeRegion(256, 128, 64, 32, 64, 32),
            scaled);
    }

    [Fact]
    public void RejectsFrameOutsideAtlas()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            PetFrameAlphaMask.DecodeRegion(100, 100, 80, 0, 21, 20));
    }
}
