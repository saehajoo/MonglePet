namespace MonglePet.Shell.Tests;

public sealed class WindowsPetImportUiContractTests
{
    [Fact]
    public void ProtocolImportOpensTheRemoteReviewSurface()
    {
        string fixtures = Path.Combine(AppContext.BaseDirectory, "Fixtures");
        string app = File.ReadAllText(Path.Combine(fixtures, "App.xaml.cs"));

        Assert.Contains(
            "mainWindow.OpenRemotePetImport(",
            app,
            StringComparison.Ordinal);
    }

    [Fact]
    public void ImportUsesOneCreatorSettingsActionAndBehaviorEditorFollowsAnimations()
    {
        string fixtures = Path.Combine(AppContext.BaseDirectory, "Fixtures");
        string app = File.ReadAllText(Path.Combine(fixtures, "App.xaml.cs"));
        string page = File.ReadAllText(Path.Combine(fixtures, "MainPage.xaml"));
        string pageCode = File.ReadAllText(Path.Combine(fixtures, "MainPage.xaml.cs"));

        Assert.DoesNotContain("PetRecommendedProfileApplyOptions", app, StringComparison.Ordinal);
        Assert.Contains(
            "return ImportReviewedPackage(review).InstalledPackage;",
            app,
            StringComparison.Ordinal);
        Assert.DoesNotContain(
            "PrimaryButtonText = \"기본 설정으로 추가\"",
            pageCode,
            StringComparison.Ordinal);
        Assert.DoesNotContain(
            "SecondaryButtonText = \"권장 설정으로 추가\"",
            pageCode,
            StringComparison.Ordinal);
        Assert.Contains("Title = \"펫 추가\"", pageCode, StringComparison.Ordinal);
        Assert.Contains("PrimaryButtonText = review.CanInstall", pageCode, StringComparison.Ordinal);
        Assert.Contains("? \"펫 추가\"", pageCode, StringComparison.Ordinal);
        Assert.Contains("MonglePet 업데이트", pageCode, StringComparison.Ordinal);
        Assert.Contains("자세히 보기", pageCode, StringComparison.Ordinal);
        Assert.Contains("review.CanInstall", pageCode, StringComparison.Ordinal);
        Assert.DoesNotContain(
            "일부 기능이 적용되지 않거나 다르게 보일 수 있지만 설치는 계속할 수 있습니다.",
            pageCode,
            StringComparison.Ordinal);
        Assert.Equal(
            2,
            pageCode.Split(
                "await ReviewAndImportPackageAsync(",
                StringSplitOptions.None).Length - 1);

        int petContent = page.IndexOf(
            "Content=\"펫 정보·애니메이션\"",
            StringComparison.Ordinal);
        int behaviorEditor = page.IndexOf(
            "Content=\"행동 편집\"",
            StringComparison.Ordinal);
        int display = page.IndexOf(
            "Content=\"화면 표시\"",
            StringComparison.Ordinal);
        Assert.True(petContent >= 0);
        Assert.True(behaviorEditor > petContent);
        Assert.True(display > behaviorEditor);
    }
}
