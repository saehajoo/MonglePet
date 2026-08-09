using System.IO.Compression;

namespace MonglePet.Packages.Tests;

public sealed class PetPackageLoaderTests
{
    private readonly PetPackageLoader _loader = new();

    [Fact]
    public void LoadsSharedPackageAndResolvesAtlas()
    {
        string fixture = FixturePath();

        LoadedPetPackage package = _loader.LoadDirectory(fixture);

        Assert.Equal("kr.mapleroom.monglepet.sample.readonly", package.Manifest.Id);
        Assert.Equal("idle", package.DefaultMotion.Id);
        LoadedPetAtlas atlas = Assert.Single(package.Atlases).Value;
        Assert.Equal(PetPackageImageFormat.Png, atlas.Format);
        Assert.Equal(1_254, atlas.Definition.PixelWidth);
        Assert.True(File.Exists(atlas.FilePath));
    }

    [Fact]
    public void RejectsUnsupportedFilesAnywhereInDirectory()
    {
        using var workspace = new TemporaryDirectory();
        string packagePath = Path.Combine(workspace.Path, "pet.monglepet");
        CopyDirectory(FixturePath(), packagePath);
        File.WriteAllText(Path.Combine(packagePath, "run.ps1"), "Write-Output unsafe");

        PetPackageLoadException exception = Assert.Throws<PetPackageLoadException>(
            () => _loader.LoadDirectory(packagePath));

        Assert.Equal(PetPackageLoadError.UnsupportedFile, exception.Error);
    }

    [Fact]
    public void RejectsDeclaredAtlasDimensionsThatDoNotMatchImage()
    {
        using var workspace = new TemporaryDirectory();
        string packagePath = Path.Combine(workspace.Path, "pet.monglepet");
        CopyDirectory(FixturePath(), packagePath);
        string manifestPath = Path.Combine(packagePath, "pet.json");
        File.WriteAllText(
            manifestPath,
            File.ReadAllText(manifestPath).Replace(
                "\"pixelWidth\" : 1254",
                "\"pixelWidth\" : 1255",
                StringComparison.Ordinal));

        PetPackageLoadException exception = Assert.Throws<PetPackageLoadException>(
            () => _loader.LoadDirectory(packagePath));

        Assert.Equal(PetPackageLoadError.ImageDimensionsMismatch, exception.Error);
    }

    [Fact]
    public void RejectsImageContentThatDoesNotMatchExtension()
    {
        using var workspace = new TemporaryDirectory();
        string packagePath = Path.Combine(workspace.Path, "pet.monglepet");
        CopyDirectory(FixturePath(), packagePath);
        string assetsPath = Path.Combine(packagePath, "assets");
        File.Copy(
            Path.Combine(assetsPath, "spritesheet.png"),
            Path.Combine(assetsPath, "spritesheet.webp"));
        string manifestPath = Path.Combine(packagePath, "pet.json");
        File.WriteAllText(
            manifestPath,
            File.ReadAllText(manifestPath).Replace(
                "assets/spritesheet.png",
                "assets/spritesheet.webp",
                StringComparison.Ordinal));

        PetPackageLoadException exception = Assert.Throws<PetPackageLoadException>(
            () => _loader.LoadDirectory(packagePath));

        Assert.Equal(PetPackageLoadError.ImageFormatMismatch, exception.Error);
    }

    [Fact]
    public void RejectsMissingReferencedAtlas()
    {
        using var workspace = new TemporaryDirectory();
        string packagePath = Path.Combine(workspace.Path, "pet.monglepet");
        CopyDirectory(FixturePath(), packagePath);
        File.Delete(Path.Combine(packagePath, "assets", "spritesheet.png"));

        PetPackageLoadException exception = Assert.Throws<PetPackageLoadException>(
            () => _loader.LoadDirectory(packagePath));

        Assert.Equal(PetPackageLoadError.MissingReferencedFile, exception.Error);
    }

    [Fact]
    public void ExtractsAndLoadsZipContainer()
    {
        using var workspace = new TemporaryDirectory();
        string archivePath = Path.Combine(workspace.Path, "sample.monglepet");
        ZipFile.CreateFromDirectory(
            FixturePath(),
            archivePath,
            CompressionLevel.Optimal,
            includeBaseDirectory: false);
        string extractionWorkspace = Path.Combine(workspace.Path, "extract");
        Directory.CreateDirectory(extractionWorkspace);

        string packagePath = new PetPackageArchiveExtractor().Extract(
            archivePath,
            extractionWorkspace);
        LoadedPetPackage package = _loader.LoadDirectory(packagePath);

        Assert.Equal("kr.mapleroom.monglepet.sample.readonly", package.Manifest.Id);
        Assert.True(File.Exists(package.Atlases["main"].FilePath));
    }

    [Fact]
    public void RejectsZipPathTraversalBeforeExtraction()
    {
        using var workspace = new TemporaryDirectory();
        string archivePath = Path.Combine(workspace.Path, "unsafe.monglepet");
        using (FileStream stream = File.Create(archivePath))
        using (var archive = new ZipArchive(stream, ZipArchiveMode.Create))
        {
            using StreamWriter writer = new(archive.CreateEntry("../outside.json").Open());
            writer.Write("{}");
        }
        string extractionWorkspace = Path.Combine(workspace.Path, "extract");
        Directory.CreateDirectory(extractionWorkspace);

        PetPackageArchiveException exception = Assert.Throws<PetPackageArchiveException>(
            () => new PetPackageArchiveExtractor().Extract(archivePath, extractionWorkspace));

        Assert.Equal(PetPackageArchiveError.InvalidEntryPath, exception.Error);
        Assert.False(File.Exists(Path.Combine(workspace.Path, "outside.json")));
    }

    [Fact]
    public void RejectsSuspiciousPerEntryCompressionRatio()
    {
        using var workspace = new TemporaryDirectory();
        string archivePath = Path.Combine(workspace.Path, "bomb.monglepet");
        using (FileStream stream = File.Create(archivePath))
        using (var archive = new ZipArchive(stream, ZipArchiveMode.Create))
        {
            using Stream entry = archive.CreateEntry(
                "pet.json",
                CompressionLevel.SmallestSize).Open();
            entry.Write(new byte[1024 * 1024]);
        }
        string extractionWorkspace = Path.Combine(workspace.Path, "extract");
        Directory.CreateDirectory(extractionWorkspace);

        PetPackageArchiveException exception = Assert.Throws<PetPackageArchiveException>(
            () => new PetPackageArchiveExtractor().Extract(archivePath, extractionWorkspace));

        Assert.Equal(PetPackageArchiveError.SuspiciousCompressionRatio, exception.Error);
    }

    private static string FixturePath() => Path.Combine(
        AppContext.BaseDirectory,
        "Fixtures",
        "ReadOnlySample.monglepet");

    private static void CopyDirectory(string source, string destination)
    {
        Directory.CreateDirectory(destination);
        foreach (string directory in Directory.GetDirectories(source, "*", SearchOption.AllDirectories))
        {
            Directory.CreateDirectory(Path.Combine(
                destination,
                Path.GetRelativePath(source, directory)));
        }

        foreach (string file in Directory.GetFiles(source, "*", SearchOption.AllDirectories))
        {
            File.Copy(file, Path.Combine(destination, Path.GetRelativePath(source, file)));
        }
    }

    private sealed class TemporaryDirectory : IDisposable
    {
        public TemporaryDirectory()
        {
            Path = System.IO.Path.Combine(
                System.IO.Path.GetTempPath(),
                "MonglePet.Tests",
                Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(Path);
        }

        public string Path { get; }

        public void Dispose()
        {
            if (Directory.Exists(Path))
            {
                Directory.Delete(Path, recursive: true);
            }
        }
    }
}
