using MonglePet.Activity;

namespace MonglePet.Activity.Tests;

public sealed class WindowsApplicationCatalogTests
{
    [Fact]
    public void ChoicesFilterBackgroundInvalidAndExcludedCandidates()
    {
        IReadOnlyList<WindowsApplicationChoice> choices =
            WindowsApplicationCatalogNormalizer.Choices(
                [
                    new("exe:editor.exe", "Editor", @"C:\Apps\editor.exe", true),
                    new("exe:helper.exe", "Helper", @"C:\Apps\helper.exe", false),
                    new("invalid", "Invalid", null, true),
                    new(null, "Missing", null, true),
                    new("PFN:MONGLEPET_123", "MonglePet", null, true),
                ],
                ["pfn:monglepet_123"]);

        WindowsApplicationChoice choice = Assert.Single(choices);
        Assert.Equal("exe:editor.exe", choice.Identifier);
    }

    [Fact]
    public void ChoicesNormalizeDeduplicateAndPreferUsefulMetadata()
    {
        IReadOnlyList<WindowsApplicationChoice> choices =
            WindowsApplicationCatalogNormalizer.Choices(
            [
                new(" EXE:EDITOR.EXE ", null, null, true),
                new("exe:editor.exe", "Editor", @" C:\Apps\editor.exe ", true),
                new("exe:editor.exe", "", @"C:\Other\editor.exe", true),
            ]);

        WindowsApplicationChoice choice = Assert.Single(choices);
        Assert.Equal("exe:editor.exe", choice.Identifier);
        Assert.Equal("Editor", choice.DisplayName);
        Assert.Equal(@"C:\Apps\editor.exe", choice.ExecutablePath);
    }

    [Fact]
    public void ChoicesUsePathAndIdentifierFallbacksThenSortByName()
    {
        IReadOnlyList<WindowsApplicationChoice> choices =
            WindowsApplicationCatalogNormalizer.Choices(
            [
                new("pfn:zebra_123", null, null, true),
                new("exe:alpha.exe", null, @"C:\Tools\Alpha.exe", true),
            ]);

        Assert.Equal(["exe:alpha.exe", "pfn:zebra_123"],
            choices.Select(value => value.Identifier));
        Assert.Equal("Alpha", choices[0].DisplayName);
        Assert.Equal("zebra_123", choices[1].DisplayName);
    }

    [Theory]
    [InlineData(" PFN:Example_App ", "pfn:example_app")]
    [InlineData("exe:NOTEPAD.EXE", "exe:notepad.exe")]
    public void QualifiedIdentifierIsNormalized(string value, string expected) =>
        Assert.Equal(
            expected,
            WindowsApplicationCatalogNormalizer.NormalizeIdentifier(value));

    [Theory]
    [InlineData("bundle:example")]
    [InlineData("exe:C:\\Apps\\editor.exe")]
    [InlineData("exe:bad app.exe")]
    [InlineData("pfn:")]
    public void InvalidQualifiedIdentifierIsRejected(string value) =>
        Assert.Null(WindowsApplicationCatalogNormalizer.NormalizeIdentifier(value));

    [Fact]
    public void ExecutableInspectionUsesOnlyFileNameAsStoredIdentifier()
    {
        string source = Assert.IsType<string>(Environment.ProcessPath);
        string directory = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        string executable = Path.Combine(directory, "fixture-editor.exe");
        File.Copy(source, executable);
        try
        {
            var catalog = new WindowsApplicationCatalog();

            WindowsApplicationChoice choice = catalog.InspectExecutable(executable);

            Assert.Equal("exe:fixture-editor.exe", choice.Identifier);
            Assert.False(string.IsNullOrWhiteSpace(choice.DisplayName));
            Assert.Equal(executable, choice.ExecutablePath);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public void ExecutableInspectionRejectsMissingAndNonExecutableFiles()
    {
        var catalog = new WindowsApplicationCatalog();

        WindowsApplicationCatalogException nonExecutable = Assert.Throws<
            WindowsApplicationCatalogException>(() => catalog.InspectExecutable("readme.txt"));
        Assert.Equal(WindowsApplicationCatalogError.NotExecutable, nonExecutable.Error);

        WindowsApplicationCatalogException missing = Assert.Throws<
            WindowsApplicationCatalogException>(() => catalog.InspectExecutable(
                Path.Combine(Path.GetTempPath(), "missing-fixture.exe")));
        Assert.Equal(WindowsApplicationCatalogError.FileUnavailable, missing.Error);
    }

    [Fact]
    public void ExecutableInspectionRejectsCurrentMonglePetProcessImage()
    {
        string currentExecutable = Assert.IsType<string>(Environment.ProcessPath);
        var catalog = new WindowsApplicationCatalog();

        WindowsApplicationCatalogException exception = Assert.Throws<
            WindowsApplicationCatalogException>(() =>
                catalog.InspectExecutable(currentExecutable));

        Assert.Equal(
            WindowsApplicationCatalogError.MonglePetCannotBeSelected,
            exception.Error);
    }
}
