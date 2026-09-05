using System.IO.Compression;
using System.Text.Json.Nodes;
using MonglePet.Settings;

namespace MonglePet.PetLibrary.Tests;

public sealed class PetLibraryStoreTests
{
    [Fact]
    public void BuildsLibraryPathFromInjectedApplicationLocalDataRoot()
    {
        string appDataRoot = Path.Combine("C:\\", "PackageLocalState");

        string path = PetLibraryPaths.FromAppLocalDataRoot(appDataRoot);

        Assert.Equal(
            Path.Combine(appDataRoot, "MonglePet", "Library"),
            path);
    }

    [Fact]
    public void InstallsValidatedPackageIntoUuidDirectoryAndListsIt()
    {
        using var workspace = new TemporaryDirectory();
        Guid installationId = Guid.Parse("10000000-0000-0000-0000-000000000001");
        var store = CreateStore(workspace, [installationId]);

        InstalledPetPackage installed = store.InstallFromDirectory(FixturePath());
        InstalledPetPackage listed = Assert.Single(store.GetInstalledPackages());

        Assert.Equal(installationId, installed.InstallationId);
        Assert.Equal(installationId, listed.InstallationId);
        Assert.Equal(
            Path.Combine(workspace.LibraryPath, installationId.ToString("D")),
            installed.RootPath);
        Assert.Equal("kr.mapleroom.monglepet.sample.readonly", listed.Package.Manifest.Id);
        Assert.True(File.Exists(Path.Combine(installed.RootPath, "assets", "spritesheet.png")));
    }

    [Fact]
    public void RejectsDuplicateAndReturnsMatchingInstallationIds()
    {
        using var workspace = new TemporaryDirectory();
        Guid firstId = Guid.Parse("20000000-0000-0000-0000-000000000001");
        var store = CreateStore(workspace, [firstId, Guid.NewGuid()]);
        store.InstallFromDirectory(FixturePath());

        PetLibraryException exception = Assert.Throws<PetLibraryException>(
            () => store.InstallFromDirectory(FixturePath()));

        Assert.Equal(PetLibraryError.DuplicatePackage, exception.Error);
        Assert.Equal([firstId], exception.MatchingInstallationIds);
        Assert.Single(store.GetInstalledPackages());
    }

    [Fact]
    public void InstallsSamePackageSeparatelyWithIndependentUuid()
    {
        using var workspace = new TemporaryDirectory();
        Guid firstId = Guid.Parse("30000000-0000-0000-0000-000000000001");
        Guid secondId = Guid.Parse("30000000-0000-0000-0000-000000000002");
        var store = CreateStore(workspace, [firstId, secondId]);

        store.InstallFromDirectory(FixturePath());
        store.InstallFromDirectory(
            FixturePath(),
            PetPackageInstallMode.InstallSeparately);

        Assert.Equal(
            [firstId, secondId],
            store.GetInstalledPackages().Select(value => value.InstallationId).ToArray());
    }

    [Fact]
    public void ReplacesSamePackageWhilePreservingInstallationUuid()
    {
        using var workspace = new TemporaryDirectory();
        Guid installationId = Guid.Parse("40000000-0000-0000-0000-000000000001");
        var store = CreateStore(workspace, [installationId]);
        store.InstallFromDirectory(FixturePath());
        string updatedSource = workspace.CopyFixture("updated.monglepet");
        UpdateManifest(updatedSource, json => json
            .Replace("\"version\" : \"1.0.0\"", "\"version\" : \"2.0.0\"", StringComparison.Ordinal)
            .Replace("\"displayName\" : \"읽기 전용 샘플\"", "\"displayName\" : \"업데이트 샘플\"", StringComparison.Ordinal));

        InstalledPetPackage updated = store.InstallFromDirectory(
            updatedSource,
            PetPackageInstallMode.Replace,
            installationId);

        Assert.Equal(installationId, updated.InstallationId);
        Assert.Equal("2.0.0", updated.Package.Manifest.Version);
        Assert.Equal("업데이트 샘플", updated.Package.Manifest.DisplayName);
        Assert.DoesNotContain(
            Directory.EnumerateDirectories(workspace.LibraryPath),
            path => Path.GetFileName(path).StartsWith(".backup-", StringComparison.Ordinal));
    }

    [Fact]
    public void RejectsReplacingInstallationWithDifferentPackageIdentifier()
    {
        using var workspace = new TemporaryDirectory();
        Guid installationId = Guid.Parse("50000000-0000-0000-0000-000000000001");
        var store = CreateStore(workspace, [installationId]);
        store.InstallFromDirectory(FixturePath());
        string otherSource = workspace.CopyFixture("other.monglepet");
        UpdateManifest(otherSource, json => json.Replace(
            "kr.mapleroom.monglepet.sample.readonly",
            "com.example.other",
            StringComparison.Ordinal));

        PetLibraryException exception = Assert.Throws<PetLibraryException>(
            () => store.InstallFromDirectory(
                otherSource,
                PetPackageInstallMode.Replace,
                installationId));

        Assert.Equal(PetLibraryError.PackageIdentifierMismatch, exception.Error);
        InstalledPetPackage preserved = store.GetInstallation(installationId);
        Assert.Equal("kr.mapleroom.monglepet.sample.readonly", preserved.Package.Manifest.Id);
    }

    [Fact]
    public void RemovesOnlyRequestedInstallation()
    {
        using var workspace = new TemporaryDirectory();
        Guid firstId = Guid.Parse("60000000-0000-0000-0000-000000000001");
        Guid secondId = Guid.Parse("60000000-0000-0000-0000-000000000002");
        var store = CreateStore(workspace, [firstId, secondId]);
        store.InstallFromDirectory(FixturePath());
        store.InstallFromDirectory(FixturePath(), PetPackageInstallMode.InstallSeparately);

        store.RemoveInstallation(firstId);

        InstalledPetPackage remaining = Assert.Single(store.GetInstalledPackages());
        Assert.Equal(secondId, remaining.InstallationId);
        Assert.False(Directory.Exists(Path.Combine(workspace.LibraryPath, firstId.ToString("D"))));
    }

    [Fact]
    public void ImportsZipThroughValidatedTemporaryWorkspace()
    {
        using var workspace = new TemporaryDirectory();
        Guid installationId = Guid.Parse("70000000-0000-0000-0000-000000000001");
        var store = CreateStore(workspace, [installationId]);
        string archivePath = Path.Combine(workspace.Path, "sample.monglepet");
        ZipFile.CreateFromDirectory(
            FixturePath(),
            archivePath,
            CompressionLevel.Optimal,
            includeBaseDirectory: false);
        var importer = new PetPackageImporter(
            store,
            operationIdGenerator: () => Guid.Parse("70000000-0000-0000-0000-000000000099"));

        InstalledPetPackage installed = importer.Import(archivePath);

        Assert.Equal(installationId, installed.InstallationId);
        Assert.Single(store.GetInstalledPackages());
        Assert.DoesNotContain(
            Directory.EnumerateDirectories(workspace.LibraryPath),
            path => Path.GetFileName(path).StartsWith(".import-", StringComparison.Ordinal));
    }

    [Fact]
    public void IgnoresHiddenWorkspacesAndDamagedUuidDirectories()
    {
        using var workspace = new TemporaryDirectory();
        Guid installationId = Guid.Parse("80000000-0000-0000-0000-000000000001");
        var store = CreateStore(workspace, [installationId]);
        store.InstallFromDirectory(FixturePath());
        Directory.CreateDirectory(Path.Combine(workspace.LibraryPath, ".staging-orphan"));
        string damagedPath = Path.Combine(
            workspace.LibraryPath,
            "80000000-0000-0000-0000-000000000099");
        Directory.CreateDirectory(damagedPath);
        File.WriteAllText(Path.Combine(damagedPath, "pet.json"), "{}");

        InstalledPetPackage installed = Assert.Single(store.GetInstalledPackages());

        Assert.Equal(installationId, installed.InstallationId);
    }

    [Fact]
    public void InvalidReplacementSourceLeavesExistingInstallationUntouched()
    {
        using var workspace = new TemporaryDirectory();
        Guid installationId = Guid.Parse("90000000-0000-0000-0000-000000000001");
        var store = CreateStore(workspace, [installationId]);
        store.InstallFromDirectory(FixturePath());
        string invalidSource = workspace.CopyFixture("invalid.monglepet");
        File.Delete(Path.Combine(invalidSource, "assets", "spritesheet.png"));

        PetLibraryException exception = Assert.Throws<PetLibraryException>(
            () => store.InstallFromDirectory(
                invalidSource,
                PetPackageInstallMode.Replace,
                installationId));

        Assert.Equal(PetLibraryError.PackageValidationFailed, exception.Error);
        InstalledPetPackage preserved = store.GetInstallation(installationId);
        Assert.Equal("1.0.0", preserved.Package.Manifest.Version);
    }

    [Fact]
    public void ReviewsRecommendedProfileAndRejectsChangedSource()
    {
        using var workspace = new TemporaryDirectory();
        var store = CreateStore(workspace, [Guid.NewGuid()]);
        string source = workspace.CopyFixture("review.monglepet");
        WriteRecommendedProfile(Path.Combine(source, "recommended-profile.json"));
        var importer = new PetPackageImporter(store);

        PetPackageImportReview review = importer.Review(source);

        Assert.True(review.ContainsRecommendedProfile);
        Assert.True(review.CanApplyRecommendedProfile);
        Assert.Equal("kr.mapleroom.monglepet.sample.readonly", review.Manifest.Id);
        File.AppendAllText(Path.Combine(source, "pet.json"), " ");
        PetLibraryException changed = Assert.Throws<PetLibraryException>(
            () => importer.ImportReviewed(review));
        Assert.Equal(PetLibraryError.ReviewedContentChanged, changed.Error);
    }

    [Fact]
    public void ReviewBlocksHigherLocalMinimumBeforeInstallation()
    {
        using var workspace = new TemporaryDirectory();
        var store = CreateStore(workspace, [Guid.NewGuid()]);
        string source = workspace.CopyFixture("future-compatible.monglepet");
        UpdateManifest(source, json =>
        {
            JsonObject document = JsonNode.Parse(json)!.AsObject();
            document["version"] = "봄 에디션";
            document["compatibility"] = new JsonObject
            {
                ["createdWithMonglePetVersion"] = "8.0.0",
                ["minimumMonglePetVersion"] = "9.0.0",
            };
            return document.ToJsonString();
        });
        var importer = new PetPackageImporter(store);

        PetPackageImportReview review = importer.Review(
            source,
            new RemotePetSemanticVersion(1, 3, 0));

        Assert.Equal("봄 에디션", review.Manifest.Version);
        Assert.True(review.CompatibilityAdvisory?.RecommendsUpdate);
        Assert.Equal(
            PetPackageImportDisposition.UpdateRequiredForMinimumVersion,
            review.Disposition);
        Assert.False(review.CanInstall);
        PetLibraryException exception = Assert.Throws<PetLibraryException>(
            () => importer.ImportReviewed(review));
        Assert.Equal(PetLibraryError.ImportBlocked, exception.Error);
        Assert.Empty(store.GetInstalledPackages());
    }

    [Fact]
    public void InvalidCreatorSettingsBlockInstallationAndOversizedProfileDoesToo()
    {
        using var workspace = new TemporaryDirectory();
        var store = CreateStore(workspace, [Guid.NewGuid()]);
        string source = workspace.CopyFixture("invalid-profile.monglepet");
        var importer = new PetPackageImporter(store);
        File.WriteAllText(Path.Combine(source, "recommended-profile.json"), "{");

        PetPackageImportReview review = importer.Review(source);

        Assert.True(review.ContainsRecommendedProfile);
        Assert.False(review.CanApplyRecommendedProfile);
        Assert.NotNull(review.RecommendedProfileIssue);
        Assert.Equal(PetPackageImportDisposition.InvalidCreatorSettings, review.Disposition);
        PetLibraryException blocked = Assert.Throws<PetLibraryException>(
            () => importer.ImportReviewed(review, PetPackageInstallMode.InstallSeparately));
        Assert.Equal(PetLibraryError.ImportBlocked, blocked.Error);

        string creatorSettingsPath = Path.Combine(source, "recommended-profile.json");
        WriteRecommendedProfile(creatorSettingsPath);
        JsonObject invalidSchema = JsonNode.Parse(
            File.ReadAllText(creatorSettingsPath))!.AsObject();
        invalidSchema["schemaVersion"] = 0;
        File.WriteAllText(creatorSettingsPath, invalidSchema.ToJsonString());
        PetPackageImportReview invalidSchemaReview = importer.Review(source);
        Assert.Equal(
            RecommendedPetProfileError.InvalidContent,
            invalidSchemaReview.RecommendedProfileIssue);
        Assert.Equal(
            PetPackageImportDisposition.InvalidCreatorSettings,
            invalidSchemaReview.Disposition);

        using FileStream stream = new(
            creatorSettingsPath,
            FileMode.Create,
            FileAccess.Write);
        stream.SetLength((1L * 1024 * 1024) + 1L);
        stream.Dispose();
        PetLibraryException tooLarge = Assert.Throws<PetLibraryException>(() => importer.Review(source));
        Assert.Equal(PetLibraryError.PackageValidationFailed, tooLarge.Error);
    }

    [Fact]
    public void FutureCreatorSettingsRequireUpdateAndBlockInstallation()
    {
        using var workspace = new TemporaryDirectory();
        Guid installationId = Guid.NewGuid();
        var store = CreateStore(workspace, [installationId]);
        string source = workspace.CopyFixture("future-profile.monglepet");
        string creatorSettingsPath = Path.Combine(source, "recommended-profile.json");
        WriteRecommendedProfile(creatorSettingsPath);
        JsonObject creatorSettings = JsonNode.Parse(
            File.ReadAllText(creatorSettingsPath))!.AsObject();
        creatorSettings["schemaVersion"] = RecommendedPetProfileCodec.CurrentSchemaVersion + 1;
        File.WriteAllText(creatorSettingsPath, creatorSettings.ToJsonString());
        var importer = new PetPackageImporter(store);

        PetPackageImportReview review = importer.Review(source);
        Assert.True(review.ContainsRecommendedProfile);
        Assert.Null(review.RecommendedProfile);
        Assert.Equal(
            RecommendedPetProfileError.UnsupportedSchema,
            review.RecommendedProfileIssue);
        Assert.Equal(
            PetPackageImportDisposition.UpdateRequiredForCreatorSettings,
            review.Disposition);
        PetLibraryException blocked = Assert.Throws<PetLibraryException>(
            () => importer.ImportReviewed(review, PetPackageInstallMode.InstallSeparately));
        Assert.Equal(PetLibraryError.ImportBlocked, blocked.Error);
        Assert.Empty(store.GetInstalledPackages());
    }

    [Fact]
    public void ExporterWritesOnlyCanonicalFilesAndRoundTrips()
    {
        using var workspace = new TemporaryDirectory();
        Guid installationId = Guid.Parse("99999999-0000-0000-0000-000000000001");
        var store = CreateStore(workspace, [installationId]);
        InstalledPetPackage installed = store.InstallFromDirectory(FixturePath());
        File.WriteAllText(Path.Combine(installed.RootPath, "monglepet-editor.json"), "{}");
        string destination = Path.Combine(workspace.Path, "shared.monglepet");
        var exporter = new PetPackageExporter(
            operationIdGenerator: () => Guid.Parse("99999999-0000-0000-0000-000000000099"));

        exporter.Export(installed, destination);

        using ZipArchive archive = ZipFile.OpenRead(destination);
        string[] entries = archive.Entries.Select(entry => entry.FullName).Order().ToArray();
        Assert.Equal(
            ["assets/spritesheet.png", "pet.json", "preview.png"],
            entries);
        PetPackageImportReview review = new PetPackageImporter(store).Review(destination);
        Assert.False(review.ContainsRecommendedProfile);
        Assert.Equal("1.7.0", review.Manifest.Compatibility?.CreatedWithMonglePetVersion);
        Assert.Equal("0.1.0", review.Manifest.Compatibility?.MinimumMonglePetVersion);
    }

    [Fact]
    public void ExporterRecordsCurrentAppAndCreatorSettingsMinimumSeparately()
    {
        using var workspace = new TemporaryDirectory();
        Guid installationId = Guid.NewGuid();
        var store = CreateStore(workspace, [installationId]);
        InstalledPetPackage installed = store.InstallFromDirectory(FixturePath());
        string destination = Path.Combine(workspace.Path, "shared-with-settings.monglepet");
        var exporter = new PetPackageExporter(appVersion: "1.8.0");
        BehaviorProfile profile = BehaviorProfileDefaults.Create(
            new PetBehaviorKey.Installed(installationId));

        exporter.Export(installed, destination, profile);

        PetPackageImportReview review = new PetPackageImporter(store).Review(destination);
        Assert.True(review.ContainsRecommendedProfile);
        Assert.Equal("1.8.0", review.Manifest.Compatibility?.CreatedWithMonglePetVersion);
        Assert.Equal("1.7.0", review.Manifest.Compatibility?.MinimumMonglePetVersion);
    }

    [Fact]
    public void InstallationRemovesEditorMarkerFromTheStagedCopy()
    {
        using var workspace = new TemporaryDirectory();
        var store = CreateStore(workspace, [Guid.NewGuid()]);
        string source = workspace.CopyFixture("editable.monglepet");
        File.WriteAllText(Path.Combine(source, "monglepet-editor.json"), "{}");

        InstalledPetPackage installed = store.InstallFromDirectory(source);

        Assert.False(File.Exists(Path.Combine(installed.RootPath, "monglepet-editor.json")));
        Assert.True(File.Exists(Path.Combine(source, "monglepet-editor.json")));
    }

    private static void WriteRecommendedProfile(string path)
    {
        File.WriteAllText(path, """
        {
          "schemaVersion": 7,
          "behavior": {
            "mode": "automatic",
            "manualSequenceID": "default",
            "sequences": [{
              "id": "default",
              "steps": [{"motionID": "idle", "repeatCount": 1}],
              "repeats": true
            }]
          },
          "movement": {"mode": "fixed"},
          "pettingMotionID": null,
          "automaticRules": [],
          "speech": {"isEnabled": false, "phrases": []}
        }
        """);
    }

    private static PetLibraryStore CreateStore(
        TemporaryDirectory workspace,
        IReadOnlyList<Guid> installationIds)
    {
        var ids = new Queue<Guid>(installationIds);
        int operation = 0;
        return new PetLibraryStore(
            workspace.LibraryPath,
            installationIdGenerator: () => ids.Dequeue(),
            operationIdGenerator: () => Guid.Parse(
                $"aaaaaaaa-0000-0000-0000-{++operation:000000000000}"));
    }

    private static string FixturePath() => Path.Combine(
        AppContext.BaseDirectory,
        "Fixtures",
        "ReadOnlySample.monglepet");

    private static void UpdateManifest(string packagePath, Func<string, string> update)
    {
        string manifestPath = Path.Combine(packagePath, "pet.json");
        File.WriteAllText(manifestPath, update(File.ReadAllText(manifestPath)));
    }

    private sealed class TemporaryDirectory : IDisposable
    {
        public TemporaryDirectory()
        {
            Path = System.IO.Path.Combine(
                System.IO.Path.GetTempPath(),
                "MonglePet.PetLibrary.Tests",
                Guid.NewGuid().ToString("N"));
            LibraryPath = System.IO.Path.Combine(Path, "Library");
            Directory.CreateDirectory(Path);
        }

        public string Path { get; }

        public string LibraryPath { get; }

        public string CopyFixture(string name)
        {
            string destination = System.IO.Path.Combine(Path, name);
            CopyDirectory(FixturePath(), destination);
            return destination;
        }

        public void Dispose()
        {
            if (Directory.Exists(Path))
            {
                Directory.Delete(Path, recursive: true);
            }
        }

        private static void CopyDirectory(string source, string destination)
        {
            Directory.CreateDirectory(destination);
            foreach (string directory in Directory.GetDirectories(
                         source,
                         "*",
                         SearchOption.AllDirectories))
            {
                Directory.CreateDirectory(System.IO.Path.Combine(
                    destination,
                    System.IO.Path.GetRelativePath(source, directory)));
            }

            foreach (string file in Directory.GetFiles(
                         source,
                         "*",
                         SearchOption.AllDirectories))
            {
                File.Copy(file, System.IO.Path.Combine(
                    destination,
                    System.IO.Path.GetRelativePath(source, file)));
            }
        }
    }
}
