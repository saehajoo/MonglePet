namespace MonglePet.Shell.Tests;

public sealed class WindowsMacOS18UiContractTests
{
    [Fact]
    public void QuickGuidePrecedesTroubleshootingAndUsesFixedExternalUrl()
    {
        string fixtures = Path.Combine(AppContext.BaseDirectory, "Fixtures");
        string page = File.ReadAllText(Path.Combine(fixtures, "MainPage.xaml"));
        string guide = File.ReadAllText(Path.Combine(fixtures, "QuickGuideControl.xaml"));
        string guideCode = File.ReadAllText(Path.Combine(fixtures, "QuickGuideControl.xaml.cs"));

        int guideNavigation = page.IndexOf(
            "Content=\"이용 가이드\" Tag=\"guide\"",
            StringComparison.Ordinal);
        int troubleshooting = page.IndexOf(
            "Content=\"문제 해결\" Tag=\"troubleshooting\"",
            StringComparison.Ordinal);
        Assert.True(guideNavigation >= 0);
        Assert.True(troubleshooting > guideNavigation);
        Assert.Contains("1. 펫 준비하기", guide, StringComparison.Ordinal);
        Assert.Contains("5. 완성한 펫 보관하고 공유하기", guide, StringComparison.Ordinal);
        Assert.Contains("https://mapleroom.kr/monglepet/guide", guideCode, StringComparison.Ordinal);
        Assert.Contains("WebGuideErrorInfoBar.IsOpen = !opened", guideCode, StringComparison.Ordinal);
    }

    [Fact]
    public void GuideNavigationDoesNotRefreshSelectedPetState()
    {
        string code = File.ReadAllText(Path.Combine(
            AppContext.BaseDirectory,
            "Fixtures",
            "MainPage.xaml.cs"));

        Assert.Contains("!isGuide && _selectedPetDetailsAreStale", code, StringComparison.Ordinal);
        Assert.Contains("SelectSettingsSection(\"guide\")", code, StringComparison.Ordinal);
    }

    [Fact]
    public void PngImportSeparatesInclusionFromEditSelection()
    {
        string code = Fixture("PngFrameImportControl.xaml.cs");

        Assert.Contains("Where(item => item.IsIncluded)", code, StringComparison.Ordinal);
        Assert.Contains("PngIncludedCheckBox_Changed", code, StringComparison.Ordinal);
        Assert.Contains("RemovePngButton_Click", code, StringComparison.Ordinal);
        Assert.Contains("commonWidth", code, StringComparison.Ordinal);
    }

    [Fact]
    public void SpriteOrderSwitchPreservesIncludedFramesAndUsesCommonCanvas()
    {
        string code = Fixture("SpriteSheetImportControl.xaml.cs");
        int handlerStart = code.IndexOf(
            "private async void OrderingRadio_Checked",
            StringComparison.Ordinal);
        int handlerEnd = code.IndexOf(
            "private async void ApplyReadingOrderButton_Click",
            handlerStart,
            StringComparison.Ordinal);
        Assert.True(handlerStart >= 0);
        Assert.True(handlerEnd > handlerStart);
        string orderHandler = code[handlerStart..handlerEnd];

        Assert.DoesNotContain(
            "foreach (SpriteFrameDraft frame in _frames) frame.IsIncluded = false",
            orderHandler,
            StringComparison.Ordinal);
        Assert.Contains("includedIds", orderHandler, StringComparison.Ordinal);
        Assert.Contains("commonWidth", code, StringComparison.Ordinal);
        Assert.Contains("Task.Run", code, StringComparison.Ordinal);
    }

    [Fact]
    public void CropPreviewsSeparateCommonCanvasFromCurrentCropWithoutOverflow()
    {
        string pngView = Fixture("PngFrameImportControl.xaml");
        string pngCode = Fixture("PngFrameImportControl.xaml.cs");
        string spriteView = Fixture("SpriteSheetImportControl.xaml");
        string spriteCode = Fixture("SpriteSheetImportControl.xaml.cs");

        Assert.Contains("ResultCropBorder", pngView, StringComparison.Ordinal);
        Assert.Contains("maximumPreviewWidth = 260", pngCode, StringComparison.Ordinal);
        Assert.Contains("maximumPreviewHeight = 130", pngCode, StringComparison.Ordinal);
        Assert.Contains("PreviewCropBorder", spriteView, StringComparison.Ordinal);
        Assert.Contains("maximumPreviewWidth = 260", spriteCode, StringComparison.Ordinal);
        Assert.Contains("maximumPreviewHeight = 130", spriteCode, StringComparison.Ordinal);
        Assert.Contains("MongleControlAccentBrush", spriteView, StringComparison.Ordinal);
    }

    [Fact]
    public void AnimationEditorOffersWholePlaybackAndPreservesLoopHintSilently()
    {
        string view = Fixture("PetAnimationEditorControl.xaml");
        string code = Fixture("PetAnimationEditorControl.xaml.cs");

        Assert.Contains("Content=\"전체 재생\"", view, StringComparison.Ordinal);
        Assert.Contains("Content=\"선택 프레임\"", view, StringComparison.Ordinal);
        Assert.Contains("AnimationPreviewTimer_Tick", code, StringComparison.Ordinal);
        Assert.Contains("frame.DurationMilliseconds", code, StringComparison.Ordinal);
        Assert.Contains("CreateBakedFramePlacements", code, StringComparison.Ordinal);
        Assert.Contains("FrameCanvasBoundaryBorder", view, StringComparison.Ordinal);
        Assert.Contains("MongleControlAccentBrush", view, StringComparison.Ordinal);
        Assert.Contains("ComposedPreviewSourceAsync(frame)", code, StringComparison.Ordinal);
        Assert.Contains("FramePlacementCanvas.Clip", code, StringComparison.Ordinal);
        Assert.Contains("PlacementFillsCanvas", code, StringComparison.Ordinal);
        Assert.DoesNotContain("LoopsToggle", view, StringComparison.Ordinal);
        Assert.DoesNotContain("LoopsToggle", code, StringComparison.Ordinal);
        Assert.Contains("_preservedLoop = motion.Loop", code, StringComparison.Ordinal);
    }

    [Fact]
    public void RuntimeClipsTheAtlasToTheCurrentFrameViewport()
    {
        string code = Fixture("PetFrameCompositionPlayer.cs");

        Assert.Contains("_visual.Clip = _frameClip", code, StringComparison.Ordinal);
        Assert.Contains("PetFrameViewportGeometry.AspectFit", code, StringComparison.Ordinal);
        Assert.Contains("_frameClip.TopInset = top", code, StringComparison.Ordinal);
        Assert.Contains("_frameClip.BottomInset", code, StringComparison.Ordinal);
    }

    private static string Fixture(string name) => File.ReadAllText(Path.Combine(
        AppContext.BaseDirectory,
        "Fixtures",
        name));
}
