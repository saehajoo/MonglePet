namespace MonglePet.Shell.Tests;

public sealed class WindowsMacOS19UiContractTests
{
    [Fact]
    public void SettingsShellExposesAppLifetimeSaveFailureRetry()
    {
        string page = Fixture("MainPage.xaml");
        string code = Fixture("MainPage.xaml.cs");
        string app = Fixture("App.xaml.cs");

        Assert.Contains("SettingsSaveFailureInfoBar", page, StringComparison.Ordinal);
        Assert.Contains("Content=\"다시 저장\"", page, StringComparison.Ordinal);
        Assert.Contains("RetryCurrentSettingsSave", code, StringComparison.Ordinal);
        Assert.Contains("LatestSettingsPersistence", app, StringComparison.Ordinal);
    }

    [Fact]
    public void OwnedEditorsProtectMeaningfulDraftOnCancelEscapeAndTitleClose()
    {
        string host = Fixture("EditorWindowHost.cs");
        string animation = Fixture("PetAnimationEditorControl.xaml.cs");
        string png = Fixture("PngFrameImportControl.xaml.cs");
        string sprite = Fixture("SpriteSheetImportControl.xaml.cs");
        string currentFrames = Fixture("CurrentPetFramePickerControl.xaml.cs");

        Assert.Contains("AppWindow.Closing += AppWindow_Closing", host, StringComparison.Ordinal);
        Assert.Contains("계속 편집", host, StringComparison.Ordinal);
        Assert.Contains("변경사항 버리기", host, StringComparison.Ordinal);
        Assert.Contains("아직 저장하지 않은 변경사항은 사라집니다", host, StringComparison.Ordinal);
        Assert.Contains("acceptAction", host, StringComparison.Ordinal);
        Assert.Contains("DraftFingerprint", animation, StringComparison.Ordinal);
        Assert.Contains("DraftFingerprint", png, StringComparison.Ordinal);
        Assert.Contains("DraftFingerprint", sprite, StringComparison.Ordinal);
        Assert.Contains("DraftFingerprint", currentFrames, StringComparison.Ordinal);
    }

    [Fact]
    public void RuleRuntimeRepeatsMatchingRuleAndKeepsIndependentHiddenDecision()
    {
        string runtime = Fixture("PetBehaviorRuntime.cs");
        string page = Fixture("MainPage.xaml");

        Assert.Contains("RuleWithoutMovement", runtime, StringComparison.Ordinal);
        Assert.Contains("ForAutomaticRule()", runtime, StringComparison.Ordinal);
        Assert.Contains(
            "조건이 유지되는 동안 선택한 행동 전체를 반복합니다.",
            page,
            StringComparison.Ordinal);
    }

    private static string Fixture(string name) => File.ReadAllText(Path.Combine(
        AppContext.BaseDirectory,
        "Fixtures",
        name));
}
