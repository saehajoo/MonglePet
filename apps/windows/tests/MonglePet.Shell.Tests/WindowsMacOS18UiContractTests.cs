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

    private static string Fixture(string name) => File.ReadAllText(Path.Combine(
        AppContext.BaseDirectory,
        "Fixtures",
        name));
}
