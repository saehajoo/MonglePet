using MonglePet.Shell;
using System.Xml.Linq;

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
    public void UrlProtocolCommandQuotesExecutableAndOnlyAcceptsOneUri()
    {
        string executablePath = Path.Combine(
            _temporaryRoot,
            "MonglePet",
            "MonglePet.Windows.exe");
        string command = WindowsUrlProtocolCommand.Create(executablePath);

        Assert.Equal($"\"{Path.GetFullPath(executablePath)}\" \"%1\"", command);
        Assert.True(WindowsUrlProtocolCommand.Matches(
            command.ToUpperInvariant(),
            executablePath));
        Assert.False(WindowsUrlProtocolCommand.Matches("other.exe", executablePath));

        Assert.True(WindowsUrlProtocolCommand.TryGetProtocolUri(
            ["monglepet://install?url=https%3A%2F%2Fdev.mapleroom.kr%2Fmonglepet%2Fpets%2Fpet"],
            out Uri? protocolUri));
        Assert.Equal("monglepet", protocolUri!.Scheme);
        Assert.Equal(
            "monglepet://install?url=https%3A%2F%2Fdev.mapleroom.kr%2Fmonglepet%2Fpets%2Fpet",
            protocolUri.OriginalString);
        Assert.StartsWith("monglepet://install/?", protocolUri.AbsoluteUri);
        Assert.Equal(
            "monglepet://install?url=https%3A%2F%2Fdev.mapleroom.kr%2Fmonglepet%2Fpets%2Fpet",
            WindowsUrlProtocolCommand.NormalizeForApplication(
                new Uri(protocolUri.AbsoluteUri)));
        Assert.Equal(
            "monglepet://install//?url=value",
            WindowsUrlProtocolCommand.NormalizeForApplication(
                new Uri("monglepet://install//?url=value")));
        Assert.False(WindowsUrlProtocolCommand.TryGetProtocolUri(
            ["--startup"],
            out _));
        Assert.False(WindowsUrlProtocolCommand.TryGetProtocolUri(
            ["monglepet://install?url=a", "extra"],
            out _));
        Assert.True(WindowsUrlProtocolCommand.TryGetProtocolUri(
            "\"monglepet://install?url=https%3A%2F%2Fdev.mapleroom.kr%2Fmonglepet%2Fpets%2Fpet\"",
            out _));
    }

    [Fact]
    public void UrlProtocolActivationMessageRejectsInvalidInputs()
    {
        var valid = new Uri(
            "monglepet://install?url=https%3A%2F%2Fdev.mapleroom.kr%2Fmonglepet%2Fpets%2Fpet");

        Assert.Throws<ArgumentException>(() =>
            WindowsProtocolActivationMessage.TrySend(
                new Uri("https://dev.mapleroom.kr"),
                Environment.ProcessPath!,
                TimeSpan.FromMilliseconds(100)));
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            WindowsProtocolActivationMessage.TrySend(
                valid,
                Environment.ProcessPath!,
                TimeSpan.Zero));
    }

    [Fact]
    public void BrowserProtocolActivationTransfersForegroundPermissionToPrimaryProcess()
    {
        string fixtures = Path.Combine(AppContext.BaseDirectory, "Fixtures");
        string source = File.ReadAllText(Path.Combine(
            fixtures,
            "WindowsProtocolActivationMessage.cs"));

        int permission = source.IndexOf(
            "AllowSetForegroundWindow(processId)",
            StringComparison.Ordinal);
        int delivery = source.IndexOf(
            "SendMessageTimeout(",
            permission,
            StringComparison.Ordinal);

        Assert.True(permission >= 0);
        Assert.True(delivery > permission);
        Assert.Contains(
            "TryGetExpectedProcessId",
            source,
            StringComparison.Ordinal);
    }

    [Fact]
    public void PackagedAndUnpackagedDistributionsDeclareProtocolActivation()
    {
        string fixtures = Path.Combine(AppContext.BaseDirectory, "Fixtures");
        string manifest = File.ReadAllText(Path.Combine(fixtures, "Package.appxmanifest"));
        string installer = File.ReadAllText(Path.Combine(fixtures, "MonglePet.iss"));

        Assert.Contains("Category=\"windows.protocol\"", manifest, StringComparison.Ordinal);
        Assert.Contains("<uap:Protocol Name=\"monglepet\">", manifest, StringComparison.Ordinal);
        Assert.Contains("ChangesAssociations=yes", installer, StringComparison.Ordinal);
        Assert.Contains("Software\\Classes\\monglepet", installer, StringComparison.Ordinal);
        Assert.Contains("Software\\Classes\\{#ProtocolProgId}", installer, StringComparison.Ordinal);
        Assert.Contains("{#CapabilitiesPath}\\URLAssociations", installer, StringComparison.Ordinal);
        Assert.Contains("Software\\RegisteredApplications", installer, StringComparison.Ordinal);
        Assert.Contains("ValueName: \"monglepet\"; ValueData: \"{#ProtocolProgId}\"", installer, StringComparison.Ordinal);
        Assert.DoesNotContain("uninsdelete", installer, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("RegDeleteKeyIncludingSubkeys", installer, StringComparison.Ordinal);
        Assert.Contains("CloseApplications=no", installer, StringComparison.Ordinal);
        Assert.Contains("for Attempt := 1 to 300 do", installer, StringComparison.Ordinal);
    }

    [Fact]
    public void MarketingAssemblyFileAndPackageVersionsStayAligned()
    {
        string fixtures = Path.Combine(AppContext.BaseDirectory, "Fixtures");
        XDocument project = XDocument.Load(Path.Combine(fixtures, "MonglePet.Windows.csproj"));
        XDocument manifest = XDocument.Load(Path.Combine(fixtures, "Package.appxmanifest"));

        Assert.Equal("1.8.1", ProjectProperty(project, "Version"));
        Assert.Equal("1.8.1.20", ProjectProperty(project, "AssemblyVersion"));
        Assert.Equal("1.8.1.20", ProjectProperty(project, "FileVersion"));

        XNamespace packageNamespace =
            "http://schemas.microsoft.com/appx/manifest/foundation/windows10";
        Assert.Equal(
            "1.8.1.20",
            (string?)manifest.Root?.Element(packageNamespace + "Identity")?.Attribute("Version"));
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

    private static string? ProjectProperty(XDocument project, string name) =>
        project.Root?
            .Elements("PropertyGroup")
            .Elements(name)
            .Select(element => element.Value)
            .FirstOrDefault(value => !string.IsNullOrWhiteSpace(value));
}
