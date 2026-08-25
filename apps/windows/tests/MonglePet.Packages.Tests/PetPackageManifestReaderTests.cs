using System.Text;

namespace MonglePet.Packages.Tests;

public sealed class PetPackageManifestReaderTests
{
    private readonly PetPackageManifestReader _reader = new();

    [Fact]
    public void ReadsSharedMacOSFixtureAndIgnoresLegacyLicenseField()
    {
        var path = Path.Combine(
            AppContext.BaseDirectory,
            "Fixtures",
            "ReadOnlySample.monglepet",
            "pet.json");
        using var stream = File.OpenRead(path);

        var manifest = _reader.Read(stream);

        Assert.Equal(1, manifest.FormatVersion);
        Assert.Equal("kr.mapleroom.monglepet.sample.readonly", manifest.Id);
        Assert.Equal("idle", manifest.DefaultMotion);
        Assert.Single(manifest.Atlases);
        Assert.Single(manifest.Motions);
    }

    [Fact]
    public void MissingDefaultMotionUsesIdle()
    {
        using var stream = JsonStream(ValidManifest(defaultMotionProperty: string.Empty));

        var manifest = _reader.Read(stream);

        Assert.Null(manifest.DefaultMotion);
    }

    [Theory]
    [InlineData("봄 에디션")]
    [InlineData("release-A")]
    public void ContentVersionIsPreservedAsAFreeString(string contentVersion)
    {
        using var stream = JsonStream(ValidManifest(version: contentVersion));

        PetPackageManifest manifest = _reader.Read(stream);

        Assert.Equal(contentVersion, manifest.Version);
    }

    [Fact]
    public void RejectsPathTraversal()
    {
        using var stream = JsonStream(
            ValidManifest(atlasPath: "../outside.png"));

        var exception = Assert.Throws<PetPackageManifestException>(
            () => _reader.Read(stream));

        Assert.Equal(PetPackageManifestError.InvalidRelativePath, exception.Error);
    }

    [Fact]
    public void RejectsFrameOutsideDeclaredAtlasBounds()
    {
        using var stream = JsonStream(
            ValidManifest(frameX: 48, frameWidth: 32));

        var exception = Assert.Throws<PetPackageManifestException>(
            () => _reader.Read(stream));

        Assert.Equal(PetPackageManifestError.InvalidFrame, exception.Error);
    }

    [Fact]
    public void RejectsDuplicateMotionIdentifiers()
    {
        var duplicateMotion =
            """
            ,
                {
                  "id": "idle",
                  "atlas": "main",
                  "loop": false,
                  "frames": [
                    { "x": 0, "y": 0, "width": 32, "height": 32, "durationMs": 100 }
                  ]
                }
            """;
        using var stream = JsonStream(ValidManifest(extraMotion: duplicateMotion));

        var exception = Assert.Throws<PetPackageManifestException>(
            () => _reader.Read(stream));

        Assert.Equal(PetPackageManifestError.DuplicateIdentifier, exception.Error);
    }

    [Fact]
    public void RejectsInvalidCompatibilityVersion()
    {
        const string compatibility =
            """
            ,
              "compatibility": {
                "createdWithMonglePetVersion": "preview",
                "minimumMonglePetVersion": "1.0.0"
              }
            """;
        using var stream = JsonStream(
            ValidManifest(compatibilityProperty: compatibility));

        var exception = Assert.Throws<PetPackageManifestException>(
            () => _reader.Read(stream));

        Assert.Equal(
            PetPackageManifestError.InvalidCompatibilityVersion,
            exception.Error);
    }

    [Fact]
    public void RejectsManifestLargerThanOneMiB()
    {
        using var stream = new MemoryStream(
            new byte[PetPackageManifestReader.MaximumManifestBytes + 1]);

        var exception = Assert.Throws<PetPackageManifestException>(
            () => _reader.Read(stream));

        Assert.Equal(PetPackageManifestError.ManifestTooLarge, exception.Error);
    }

    private static MemoryStream JsonStream(string json) =>
        new(Encoding.UTF8.GetBytes(json));

    private static string ValidManifest(
        string atlasPath = "assets/atlas.png",
        int frameX = 0,
        int frameWidth = 32,
        string defaultMotionProperty = "\"defaultMotion\": \"idle\",",
        string extraMotion = "",
        string compatibilityProperty = "",
        string version = "1.0.0") =>
        $$"""
        {
          "formatVersion": 1,
          "id": "com.example.pet",
          "displayName": "Example",
          "version": "{{version}}",
          "author": "Example",
          "previewPath": "preview.png",
          {{defaultMotionProperty}}
          "atlases": [
            {
              "id": "main",
              "path": "{{atlasPath}}",
              "pixelWidth": 64,
              "pixelHeight": 64
            }
          ],
          "motions": [
            {
              "id": "idle",
              "atlas": "main",
              "loop": true,
              "frames": [
                {
                  "x": {{frameX}},
                  "y": 0,
                  "width": {{frameWidth}},
                  "height": 32,
                  "durationMs": 100
                }
              ]
            }
            {{extraMotion}}
          ]
          {{compatibilityProperty}}
        }
        """;
}
