using MonglePet.Shell;

namespace MonglePet.Shell.Tests;

public sealed class WindowsDistributionTests : IDisposable
{
    private readonly string _temporaryRoot = Path.Combine(
        Path.GetTempPath(),
        "MonglePetShellTests",
        Guid.NewGuid().ToString("N"));

    [Fact]
    public void RunAtLoginCommandQuotesExecutableAndMatchesCaseInsensitively()
    {
        string executablePath = Path.Combine(_temporaryRoot, "MonglePet", "MonglePet.Windows.exe");

        string command = WindowsRunAtLoginCommand.Create(executablePath);

        Assert.Equal($"\"{Path.GetFullPath(executablePath)}\" --startup", command);
        Assert.True(WindowsRunAtLoginCommand.Matches(command.ToUpperInvariant(), executablePath));
        Assert.False(WindowsRunAtLoginCommand.Matches("other.exe", executablePath));
        Assert.True(WindowsRunAtLoginCommand.IsStartupLaunch(["--STARTUP"]));
        Assert.False(WindowsRunAtLoginCommand.IsStartupLaunch([]));
    }

    [Fact]
    public void MigrationCopiesKnownPackageDataWithoutRemovingSource()
    {
        const string packageFamilyName = "MonglePet_TestFamily";
        string source = Path.Combine(
            _temporaryRoot,
            "Packages",
            packageFamilyName,
            "LocalState",
            "MonglePet");
        Directory.CreateDirectory(Path.Combine(source, "Library", "pet-one"));
        File.WriteAllText(Path.Combine(source, "settings.json"), "{\"schemaVersion\":10}");
        File.WriteAllText(Path.Combine(source, "Library", "pet-one", "pet.json"), "{}");

        WindowsAppDataMigrationResult result =
            WindowsAppDataMigration.TryMigrateFromPackageLocalState(
                _temporaryRoot,
                [packageFamilyName]);

        Assert.Equal(WindowsAppDataMigrationStatus.Migrated, result.Status);
        Assert.True(File.Exists(Path.Combine(_temporaryRoot, "MonglePet", "settings.json")));
        Assert.True(File.Exists(Path.Combine(
            _temporaryRoot,
            "MonglePet",
            "Library",
            "pet-one",
            "pet.json")));
        Assert.True(File.Exists(Path.Combine(source, "settings.json")));
    }

    [Fact]
    public void MigrationDoesNotOverwriteExistingUnpackagedData()
    {
        string target = Path.Combine(_temporaryRoot, "MonglePet");
        Directory.CreateDirectory(target);
        File.WriteAllText(Path.Combine(target, "settings.json"), "current");

        string source = Path.Combine(
            _temporaryRoot,
            "Packages",
            "MonglePet_TestFamily",
            "LocalState",
            "MonglePet");
        Directory.CreateDirectory(source);
        File.WriteAllText(Path.Combine(source, "settings.json"), "legacy");

        WindowsAppDataMigrationResult result =
            WindowsAppDataMigration.TryMigrateFromPackageLocalState(
                _temporaryRoot,
                ["MonglePet_TestFamily"]);

        Assert.Equal(WindowsAppDataMigrationStatus.NotNeeded, result.Status);
        Assert.Equal("current", File.ReadAllText(Path.Combine(target, "settings.json")));
    }

    [Fact]
    public void MigrationReportsMissingSourceAndLeavesTargetAbsent()
    {
        WindowsAppDataMigrationResult result =
            WindowsAppDataMigration.TryMigrateFromPackageLocalState(
                _temporaryRoot,
                ["MonglePet_MissingFamily"]);

        Assert.Equal(WindowsAppDataMigrationStatus.SourceNotFound, result.Status);
        Assert.False(Directory.Exists(Path.Combine(_temporaryRoot, "MonglePet")));
    }

    public void Dispose()
    {
        if (Directory.Exists(_temporaryRoot))
        {
            Directory.Delete(_temporaryRoot, recursive: true);
        }
    }
}
