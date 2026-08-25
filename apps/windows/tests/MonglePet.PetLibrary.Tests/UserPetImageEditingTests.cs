using MonglePet.Packages;

namespace MonglePet.PetLibrary.Tests;

public sealed class UserPetImageEditingTests
{
    [Theory]
    [InlineData(false, false, new byte[] { 2, 3, 5, 6 })]
    [InlineData(true, false, new byte[] { 3, 2, 6, 5 })]
    [InlineData(false, true, new byte[] { 5, 6, 2, 3 })]
    [InlineData(true, true, new byte[] { 6, 5, 3, 2 })]
    public void CropAndFlipProduceDeterministicAsymmetricPixels(
        bool horizontal,
        bool vertical,
        byte[] expected)
    {
        byte[] source = Pixels(1, 2, 3, 4, 5, 6);
        var crop = new PetPackageFrame(1, 0, 2, 2, 450);

        UserPetProcessedFrame result = UserPetPixelProcessor.Process(
            source,
            3,
            2,
            crop,
            horizontal,
            vertical);

        Assert.Equal(2, result.Width);
        Assert.Equal(2, result.Height);
        Assert.Equal(expected, PixelIds(result.BgraPixels));
    }

    [Fact]
    public void CanvasPlacementPreservesTransparentMarginAndActualCropPixels()
    {
        byte[] source = Pixels(1, 2, 3, 4, 5, 6);
        var crop = new PetPackageFrame(1, 0, 2, 2, 450);
        var placement = new UserPetCanvasPlacement(4, 4, 1, 1, 2, 2);

        UserPetProcessedFrame result = UserPetPixelProcessor.Process(
            source,
            3,
            2,
            crop,
            placement: placement);

        Assert.Equal(
            new byte[]
            {
                0, 0, 0, 0,
                0, 2, 3, 0,
                0, 5, 6, 0,
                0, 0, 0, 0,
            },
            PixelIds(result.BgraPixels));
    }

    [Fact]
    public void DifferentPngSizesUseOneScaleAndAlignVisiblePixelCenters()
    {
        IReadOnlyList<UserPetCanvasPlacement> result =
            UserPetImageEditingGeometry.CreateCommonCanvasPlacements(
            [
                new UserPetVisibleFrameGeometry(
                    8,
                    6,
                    new UserPetPixelRect(1, 1, 3, 2)),
                new UserPetVisibleFrameGeometry(
                    5,
                    8,
                    new UserPetPixelRect(2, 3, 1, 2)),
            ]);

        Assert.Equal(new UserPetCanvasPlacement(9, 8, 1, 2, 8, 6), result[0]);
        Assert.Equal(new UserPetCanvasPlacement(9, 8, 1, 0, 5, 8), result[1]);
        double firstVisibleCenterX = result[0].X + 1 + (3 / 2d);
        double secondVisibleCenterX = result[1].X + 2 + (1 / 2d);
        double firstVisibleCenterY = result[0].Y + 1 + (2 / 2d);
        double secondVisibleCenterY = result[1].Y + 3 + (2 / 2d);
        Assert.Equal(firstVisibleCenterX, secondVisibleCenterX);
        Assert.Equal(firstVisibleCenterY, secondVisibleCenterY);
    }

    [Fact]
    public void CommonCanvasFallsBackToSafeSourceBoundsWhenAlphaAlignmentWouldExceedLimit()
    {
        IReadOnlyList<UserPetCanvasPlacement> result =
            UserPetImageEditingGeometry.CreateCommonCanvasPlacements(
            [
                new UserPetVisibleFrameGeometry(
                    8192,
                    2,
                    new UserPetPixelRect(8191, 0, 1, 1)),
                new UserPetVisibleFrameGeometry(
                    8192,
                    2,
                    new UserPetPixelRect(0, 1, 1, 1)),
            ]);

        Assert.All(result, placement =>
        {
            Assert.Equal(8192, placement.CanvasWidth);
            Assert.Equal(2, placement.CanvasHeight);
            Assert.Equal(0, placement.X);
            Assert.Equal(0, placement.Y);
        });
    }

    [Fact]
    public void CropDragClampsMoveAndEightDirectionResizeToImage()
    {
        var original = new UserPetPixelRect(2, 2, 4, 4);

        Assert.Equal(
            new UserPetPixelRect(6, 6, 4, 4),
            UserPetImageEditingGeometry.DragCrop(
                original,
                UserPetCropHandle.Move,
                20,
                20,
                10,
                10));
        Assert.Equal(
            new UserPetPixelRect(0, 0, 6, 6),
            UserPetImageEditingGeometry.DragCrop(
                original,
                UserPetCropHandle.TopLeft,
                -20,
                -20,
                10,
                10));
        Assert.Equal(
            new UserPetPixelRect(2, 2, 8, 8),
            UserPetImageEditingGeometry.DragCrop(
                original,
                UserPetCropHandle.BottomRight,
                20,
                20,
                10,
                10));
    }

    [Fact]
    public void VisibleBoundsIncludesEveryNonTransparentPixelOnceAnalyzed()
    {
        byte[] pixels = Pixels(0, 0, 0, 0, 1, 0, 0, 2, 0, 0, 0, 0);

        UserPetPixelRect? bounds = UserPetImageEditingGeometry.FindVisibleBounds(
            pixels,
            4,
            3);

        Assert.Equal(new UserPetPixelRect(0, 1, 4, 1), bounds);
    }

    [Theory]
    [InlineData(1, false)]
    [InlineData(1.0001, true)]
    [InlineData(8, true)]
    [InlineData(20, true)]
    public void InnerViewportOwnsPanOnlyAboveOneTimes(double zoom, bool expected)
    {
        Assert.Equal(expected, UserPetImageEditingGeometry.CanPan(zoom));
    }

    [Fact]
    public void FrameCopyPreservesPixelsCropFlipDurationAndPlacementWithIndependentId()
    {
        Guid originalId = Guid.Parse("10000000-0000-0000-0000-000000000001");
        Guid copiedId = Guid.Parse("10000000-0000-0000-0000-000000000002");
        var original = new UserPetFrameSourceRequest(
            "frame.png",
            450,
            new PetPackageFrame(3, 4, 20, 30, 450),
            true,
            false,
            new UserPetCanvasPlacement(64, 64, 10, 12, 20, 30),
            originalId,
            new UserPetBackgroundRemoval(240, 241, 242, 12));

        UserPetFrameSourceRequest copy = UserPetFrameEditing.Duplicate(
            original,
            () => copiedId);

        Assert.Equal(original with { FrameId = copiedId }, copy);
        Assert.NotEqual(original.FrameId, copy.FrameId);
    }

    [Fact]
    public void BackgroundRemovalIsAppliedToFinalPixelsAfterCropAndFlip()
    {
        byte[] source =
        [
            255, 255, 255, 255,
            0, 0, 255, 255,
        ];

        UserPetProcessedFrame result = UserPetPixelProcessor.Process(
            source,
            2,
            1,
            flipsHorizontally: true,
            backgroundRemoval: new UserPetBackgroundRemoval(255, 255, 255, 0));

        Assert.Equal(
            new byte[]
            {
                0, 0, 255, 255,
                0, 0, 0, 0,
            },
            result.BgraPixels);
    }

    [Fact]
    public void TransparentSpriteBoundarySuggestionFindsRowsAndColumnsOnce()
    {
        var pixels = new byte[7 * 5 * 4];
        SetOpaque(pixels, 7, 1, 1, 10);
        SetOpaque(pixels, 7, 5, 1, 20);
        SetOpaque(pixels, 7, 1, 3, 30);
        SetOpaque(pixels, 7, 5, 3, 40);

        UserPetSpriteBoundarySuggestion result = UserPetSpriteBoundaryAnalyzer.Analyze(
            pixels,
            7,
            5);

        Assert.Null(result.InferredBackground);
        Assert.Equal(
            new[]
            {
                new UserPetPixelRect(1, 1, 1, 1),
                new UserPetPixelRect(5, 1, 1, 1),
                new UserPetPixelRect(1, 3, 1, 1),
                new UserPetPixelRect(5, 3, 1, 1),
            },
            result.Frames);
    }

    [Fact]
    public void OpaqueSpriteBoundarySuggestionInfersCornerColorWithoutChangingSource()
    {
        var pixels = Enumerable.Repeat((byte)255, 7 * 3 * 4).ToArray();
        SetOpaque(pixels, 7, 1, 1, 7);
        SetOpaque(pixels, 7, 5, 1, 9);
        byte[] original = [.. pixels];

        UserPetSpriteBoundarySuggestion result = UserPetSpriteBoundaryAnalyzer.Analyze(
            pixels,
            7,
            3,
            opaqueBackgroundTolerance: 0);

        Assert.Equal(new UserPetBackgroundRemoval(255, 255, 255, 0), result.InferredBackground);
        Assert.Equal(
            new[]
            {
                new UserPetPixelRect(1, 1, 1, 1),
                new UserPetPixelRect(5, 1, 1, 1),
            },
            result.Frames);
        Assert.Equal(original, pixels);
    }

    private static byte[] Pixels(params byte[] ids)
    {
        var result = new byte[ids.Length * 4];
        for (int index = 0; index < ids.Length; index++)
        {
            byte value = ids[index];
            result[(index * 4) + 0] = value;
            result[(index * 4) + 1] = value;
            result[(index * 4) + 2] = value;
            result[(index * 4) + 3] = value == 0 ? (byte)0 : (byte)255;
        }
        return result;
    }

    private static byte[] PixelIds(byte[] pixels) => pixels
        .Where((_, index) => index % 4 == 0)
        .ToArray();

    private static void SetOpaque(byte[] pixels, int width, int x, int y, byte value)
    {
        int offset = ((y * width) + x) * 4;
        pixels[offset + 0] = value;
        pixels[offset + 1] = value;
        pixels[offset + 2] = value;
        pixels[offset + 3] = 255;
    }
}
