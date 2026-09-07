using System.Buffers.Binary;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using MonglePet.Packages;

namespace MonglePet.PetLibrary.Tests;

public sealed class PngExportOptimizerTests
{
    [Fact]
    public void OptimizesLosslesslyAndUsesValidatedCache()
    {
        using var workspace = new TemporaryDirectory();
        byte[] original = CreateUnoptimizedRgbaPng(64, 48);
        var optimizer = new PngExportOptimizer(workspace.Path);

        PngExportOptimizationResult first = optimizer.Optimize(original);
        PngExportOptimizationResult second = optimizer.Optimize(original);

        Assert.True(first.IsOptimized);
        Assert.False(first.IsCacheHit);
        Assert.True(first.Bytes.Length < original.Length);
        Assert.True(second.IsOptimized);
        Assert.True(second.IsCacheHit);
        Assert.Equal(first.Bytes, second.Bytes);
        LoadedPetPackage package = CreatePackageWithImage(workspace.Path, first.Bytes);
        Assert.Equal(64, package.Atlases["main"].Definition.PixelWidth);
        Assert.Equal(48, package.Atlases["main"].Definition.PixelHeight);
    }

    [Fact]
    public void SourceChangeAndOptimizerVersionInvalidateCache()
    {
        using var workspace = new TemporaryDirectory();
        byte[] original = CreateUnoptimizedRgbaPng(48, 32);
        var optimizer = new PngExportOptimizer(workspace.Path, implementationVersion: "v1");
        Assert.True(optimizer.Optimize(original).IsOptimized);

        byte[] changed = CreateUnoptimizedRgbaPng(48, 33);
        PngExportOptimizationResult changedResult = optimizer.Optimize(changed);
        PngExportOptimizationResult newVersionResult = new PngExportOptimizer(
            workspace.Path,
            implementationVersion: "v2").Optimize(original);

        Assert.False(changedResult.IsCacheHit);
        Assert.False(newVersionResult.IsCacheHit);
    }

    [Fact]
    public void CorruptCacheIsDiscardedAndRebuilt()
    {
        using var workspace = new TemporaryDirectory();
        byte[] original = CreateUnoptimizedRgbaPng(40, 40);
        var optimizer = new PngExportOptimizer(workspace.Path);
        PngExportOptimizationResult first = optimizer.Optimize(original);
        Assert.True(first.IsOptimized);
        string cacheFile = Assert.Single(Directory.GetFiles(workspace.Path, "*.png"));
        File.WriteAllBytes(cacheFile, [1, 2, 3, 4]);

        PngExportOptimizationResult recovered = optimizer.Optimize(original);

        Assert.True(recovered.IsOptimized);
        Assert.False(recovered.IsCacheHit);
        Assert.Equal(first.Bytes, recovered.Bytes);
    }

    [Fact]
    public void UnsupportedOrDamagedPngFallsBackToOriginalBytes()
    {
        using var workspace = new TemporaryDirectory();
        byte[] original = [137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3];

        PngExportOptimizationResult result = new PngExportOptimizer(workspace.Path)
            .Optimize(original);

        Assert.False(result.IsOptimized);
        Assert.False(result.IsCacheHit);
        Assert.Equal(original, result.Bytes);
    }

    [Fact]
    public void ResultThatCannotBecomeSmallerKeepsOriginalBytes()
    {
        using var firstWorkspace = new TemporaryDirectory();
        using var secondWorkspace = new TemporaryDirectory();
        byte[] original = CreateUnoptimizedRgbaPng(32, 24);
        byte[] compact = new PngExportOptimizer(firstWorkspace.Path).Optimize(original).Bytes;

        PngExportOptimizationResult result = new PngExportOptimizer(secondWorkspace.Path)
            .Optimize(compact);

        Assert.False(result.IsOptimized);
        Assert.Equal(compact, result.Bytes);
    }

    [Fact]
    public void CacheCleanupFailureOrZeroBudgetDoesNotBlockOptimization()
    {
        using var workspace = new TemporaryDirectory();
        byte[] original = CreateUnoptimizedRgbaPng(32, 24);

        PngExportOptimizationResult result = new PngExportOptimizer(
            workspace.Path,
            maximumCacheBytes: 0).Optimize(original);

        Assert.True(result.IsOptimized);
        Assert.Empty(Directory.GetFiles(workspace.Path, "*.png"));
    }

    [Fact]
    public async Task ExportAsyncReportsMonotonicWorkAndPreservesSource()
    {
        using var workspace = new TemporaryDirectory();
        LoadedPetPackage loaded = new PetPackageLoader().LoadDirectory(FixturePath());
        var installed = new InstalledPetPackage(Guid.NewGuid(), loaded.PackageRootPath, loaded);
        string[] sourceFiles = [loaded.PreviewFilePath, .. loaded.Atlases.Values.Select(value => value.FilePath)];
        (string Hash, DateTime Timestamp)[] before = sourceFiles
            .Select(path => (
                Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path))),
                File.GetLastWriteTimeUtc(path)))
            .ToArray();
        var optimizer = new RecordingOptimizer();
        var exporter = new PetPackageExporter(
            pngOptimizer: optimizer,
            operationIdGenerator: () => Guid.Parse("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"));
        var progressValues = new List<PetPackageExportProgress>();
        string destination = Path.Combine(workspace.Path, "shared.monglepet");
        PetPackageExportResult result = await exporter.ExportAsync(
            installed,
            destination,
            progress: new InlineProgress<PetPackageExportProgress>(progressValues.Add));

        Assert.Equal(destination, result.DestinationPath);
        Assert.Equal(new FileInfo(destination).Length, result.ArchiveBytes);
        Assert.NotEmpty(progressValues);
        Assert.All(progressValues, value => Assert.InRange(value.Fraction, 0, 1));
        Assert.Equal(
            progressValues.Select(value => value.Fraction).Order().ToArray(),
            progressValues.Select(value => value.Fraction).ToArray());
        Assert.Equal(1, progressValues[^1].Fraction);
        Assert.Equal(PetPackageExportStage.Completed, progressValues[^1].Stage);
        Assert.Equal(2, optimizer.CallCount);
        for (int index = 0; index < sourceFiles.Length; index++)
        {
            Assert.Equal(before[index].Hash, Convert.ToHexString(
                SHA256.HashData(File.ReadAllBytes(sourceFiles[index]))));
            Assert.Equal(before[index].Timestamp, File.GetLastWriteTimeUtc(sourceFiles[index]));
        }
    }

    [Fact]
    public async Task ExportAsyncReturnsControlWhileImageWorkIsRunning()
    {
        using var workspace = new TemporaryDirectory();
        LoadedPetPackage loaded = new PetPackageLoader().LoadDirectory(FixturePath());
        var installed = new InstalledPetPackage(Guid.NewGuid(), loaded.PackageRootPath, loaded);
        var optimizer = new BlockingOptimizer();
        var exporter = new PetPackageExporter(pngOptimizer: optimizer);
        string destination = Path.Combine(workspace.Path, "async.monglepet");

        Task<PetPackageExportResult> export = exporter.ExportAsync(installed, destination);
        Assert.True(optimizer.Started.Wait(TimeSpan.FromSeconds(5)));
        Assert.False(export.IsCompleted);

        optimizer.Release.Set();
        PetPackageExportResult result = await export;
        Assert.True(File.Exists(result.DestinationPath));
    }

    [Fact]
    public async Task RepeatedExportUsesContentCacheWithoutChangingProgressOrder()
    {
        using var workspace = new TemporaryDirectory();
        byte[] png = CreateUnoptimizedRgbaPng(64, 48);
        LoadedPetPackage loaded = CreatePackageWithImage(workspace.Path, png);
        var installed = new InstalledPetPackage(Guid.NewGuid(), loaded.PackageRootPath, loaded);
        var optimizer = new CountingOptimizer(new PngExportOptimizer(
            Path.Combine(workspace.Path, "cache")));
        var exporter = new PetPackageExporter(pngOptimizer: optimizer);
        var firstProgress = new List<PetPackageExportProgress>();
        var secondProgress = new List<PetPackageExportProgress>();

        await exporter.ExportAsync(
            installed,
            Path.Combine(workspace.Path, "first.monglepet"),
            progress: new InlineProgress<PetPackageExportProgress>(firstProgress.Add));
        bool[] firstHits = optimizer.CacheHits.ToArray();
        optimizer.CacheHits.Clear();
        await exporter.ExportAsync(
            installed,
            Path.Combine(workspace.Path, "second.monglepet"),
            progress: new InlineProgress<PetPackageExportProgress>(secondProgress.Add));

        Assert.Contains(false, firstHits);
        Assert.All(optimizer.CacheHits, Assert.True);
        Assert.Equal(
            secondProgress.Select(value => value.Fraction).Order().ToArray(),
            secondProgress.Select(value => value.Fraction).ToArray());
        Assert.Equal(1, secondProgress[^1].Fraction);
    }

    [Fact]
    public void AssetReportCountsPreviewAndSharedAtlasOnce()
    {
        LoadedPetPackage loaded = new PetPackageLoader().LoadDirectory(FixturePath());
        var installed = new InstalledPetPackage(Guid.NewGuid(), loaded.PackageRootPath, loaded);
        var exporter = new PetPackageExporter(pngOptimizer: new RecordingOptimizer());

        PetPackageAssetSizeReport report = exporter.AnalyzeAssets(installed);

        long expected = new FileInfo(loaded.PreviewFilePath).Length +
            loaded.Atlases.Values.Sum(value => new FileInfo(value.FilePath).Length);
        Assert.Equal(expected, report.TotalImageBytes);
        Assert.Equal(2, report.Details.Count);
        Assert.Contains(report.Details, detail => detail.Label == "대표 이미지");
        Assert.DoesNotContain(report.Details, detail => detail.Label.Contains("main", StringComparison.Ordinal));
    }

    [Fact]
    public async Task ExportFailureDoesNotReplaceDestinationOrReportCompletion()
    {
        using var workspace = new TemporaryDirectory();
        LoadedPetPackage loaded = new PetPackageLoader().LoadDirectory(FixturePath());
        var installed = new InstalledPetPackage(Guid.NewGuid(), loaded.PackageRootPath, loaded);
        string destination = Path.Combine(workspace.Path, "existing.monglepet");
        byte[] existing = [9, 8, 7, 6];
        File.WriteAllBytes(destination, existing);
        var progressValues = new List<PetPackageExportProgress>();
        var exporter = new PetPackageExporter(pngOptimizer: new ThrowingOptimizer());

        PetPackageExportException exception = await Assert.ThrowsAsync<PetPackageExportException>(
            () => exporter.ExportAsync(
            installed,
            destination,
            progress: new InlineProgress<PetPackageExportProgress>(progressValues.Add)));

        Assert.Equal(PetPackageExportError.FileOperationFailed, exception.Error);
        Assert.IsType<InvalidDataException>(exception.InnerException);
        Assert.Equal(existing, File.ReadAllBytes(destination));
        Assert.DoesNotContain(progressValues, value => value.Fraction == 1);
        Assert.Empty(Directory.GetFiles(workspace.Path, ".*.tmp.monglepet"));
    }

    [Fact]
    public async Task ExportArchiveLimitIsInclusiveAndOneByteBelowPreservesDestination()
    {
        using var workspace = new TemporaryDirectory();
        LoadedPetPackage loaded = new PetPackageLoader().LoadDirectory(FixturePath());
        var installed = new InstalledPetPackage(Guid.NewGuid(), loaded.PackageRootPath, loaded);
        string baselinePath = Path.Combine(workspace.Path, "baseline.monglepet");
        PetPackageExportResult baseline = await new PetPackageExporter(
            pngOptimizer: new RecordingOptimizer()).ExportAsync(installed, baselinePath);
        var inclusiveLimits = new PetPackageArchiveLimits(
            baseline.ArchiveBytes,
            100L * 1024 * 1024,
            2_000,
            100);
        string boundaryPath = Path.Combine(workspace.Path, "boundary.monglepet");

        PetPackageExportResult boundary = await new PetPackageExporter(
            archiveExtractor: new PetPackageArchiveExtractor(inclusiveLimits),
            pngOptimizer: new RecordingOptimizer()).ExportAsync(installed, boundaryPath);

        Assert.Equal(baseline.ArchiveBytes, boundary.ArchiveBytes);
        byte[] existing = [4, 3, 2, 1];
        string rejectedPath = Path.Combine(workspace.Path, "rejected.monglepet");
        File.WriteAllBytes(rejectedPath, existing);
        var rejectedLimits = inclusiveLimits with
        {
            MaximumArchiveBytes = baseline.ArchiveBytes - 1,
        };
        PetPackageExportException exception = await Assert.ThrowsAsync<PetPackageExportException>(
            () => new PetPackageExporter(
                archiveExtractor: new PetPackageArchiveExtractor(rejectedLimits),
                pngOptimizer: new RecordingOptimizer()).ExportAsync(installed, rejectedPath));
        Assert.Equal(PetPackageExportError.ArchiveTooLarge, exception.Error);
        Assert.Equal(existing, File.ReadAllBytes(rejectedPath));
    }

    private static LoadedPetPackage CreatePackageWithImage(string workspace, byte[] png)
    {
        string root = Path.Combine(workspace, "fixture.monglepet");
        Directory.CreateDirectory(Path.Combine(root, "assets"));
        File.WriteAllBytes(Path.Combine(root, "preview.png"), png);
        File.WriteAllBytes(Path.Combine(root, "assets", "atlas.png"), png);
        File.WriteAllText(Path.Combine(root, "pet.json"), """
        {
          "formatVersion": 1,
          "id": "test.optimized",
          "displayName": "Optimized",
          "version": "1.0",
          "author": "Test",
          "previewPath": "preview.png",
          "defaultMotion": "idle",
          "atlases": [{"id":"main","path":"assets/atlas.png","pixelWidth":64,"pixelHeight":48}],
          "motions": [{"id":"idle","atlas":"main","loop":true,"frames":[{"x":0,"y":0,"width":64,"height":48,"durationMs":450}]}]
        }
        """);
        return new PetPackageLoader().LoadDirectory(root);
    }

    private static byte[] CreateUnoptimizedRgbaPng(int width, int height)
    {
        byte[] filtered = new byte[height * (1 + width * 4)];
        for (int y = 0; y < height; y++)
        {
            int row = y * (1 + width * 4);
            filtered[row] = 0;
            for (int x = 0; x < width; x++)
            {
                int pixel = row + 1 + x * 4;
                filtered[pixel] = (byte)(x * 3);
                filtered[pixel + 1] = (byte)(y * 5);
                filtered[pixel + 2] = (byte)(x + y);
                filtered[pixel + 3] = (byte)(64 + (x + y) % 192);
            }
        }
        byte[] compressed;
        using (var output = new MemoryStream())
        {
            using (var zlib = new ZLibStream(output, CompressionLevel.NoCompression, leaveOpen: true))
            {
                zlib.Write(filtered);
            }
            compressed = output.ToArray();
        }
        byte[] header = new byte[13];
        BinaryPrimitives.WriteUInt32BigEndian(header.AsSpan(0, 4), (uint)width);
        BinaryPrimitives.WriteUInt32BigEndian(header.AsSpan(4, 4), (uint)height);
        header[8] = 8;
        header[9] = 6;
        using var png = new MemoryStream();
        png.Write([137, 80, 78, 71, 13, 10, 26, 10]);
        WriteChunk(png, "IHDR", header);
        WriteChunk(png, "IDAT", compressed);
        WriteChunk(png, "IEND", []);
        return png.ToArray();
    }

    private static void WriteChunk(Stream stream, string type, byte[] data)
    {
        Span<byte> length = stackalloc byte[4];
        BinaryPrimitives.WriteUInt32BigEndian(length, (uint)data.Length);
        stream.Write(length);
        byte[] typeBytes = Encoding.ASCII.GetBytes(type);
        stream.Write(typeBytes);
        stream.Write(data);
        Span<byte> crc = stackalloc byte[4];
        BinaryPrimitives.WriteUInt32BigEndian(crc, Crc32(typeBytes, data));
        stream.Write(crc);
    }

    private static uint Crc32(byte[] type, byte[] data)
    {
        uint crc = uint.MaxValue;
        foreach (byte value in type.Concat(data))
        {
            crc ^= value;
            for (int index = 0; index < 8; index++)
            {
                crc = (crc & 1) != 0 ? 0xEDB88320u ^ (crc >> 1) : crc >> 1;
            }
        }
        return ~crc;
    }

    private static string FixturePath() => Path.GetFullPath(Path.Combine(
        AppContext.BaseDirectory,
        "Fixtures",
        "ReadOnlySample.monglepet"));

    private sealed class RecordingOptimizer : IPngExportOptimizer
    {
        public int CallCount { get; private set; }
        public int LastThreadId { get; private set; }

        public PngExportOptimizationResult Optimize(
            ReadOnlyMemory<byte> originalBytes,
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            CallCount++;
            LastThreadId = Environment.CurrentManagedThreadId;
            return new(originalBytes.ToArray(), false, false);
        }
    }

    private sealed class ThrowingOptimizer : IPngExportOptimizer
    {
        public PngExportOptimizationResult Optimize(
            ReadOnlyMemory<byte> originalBytes,
            CancellationToken cancellationToken = default) =>
            throw new InvalidDataException("optimizer failed");
    }

    private sealed class CountingOptimizer(IPngExportOptimizer inner) : IPngExportOptimizer
    {
        public List<bool> CacheHits { get; } = [];

        public PngExportOptimizationResult Optimize(
            ReadOnlyMemory<byte> originalBytes,
            CancellationToken cancellationToken = default)
        {
            PngExportOptimizationResult result = inner.Optimize(originalBytes, cancellationToken);
            CacheHits.Add(result.IsCacheHit);
            return result;
        }
    }

    private sealed class BlockingOptimizer : IPngExportOptimizer
    {
        public ManualResetEventSlim Started { get; } = new(false);
        public ManualResetEventSlim Release { get; } = new(false);

        public PngExportOptimizationResult Optimize(
            ReadOnlyMemory<byte> originalBytes,
            CancellationToken cancellationToken = default)
        {
            Started.Set();
            Release.Wait(cancellationToken);
            return new(originalBytes.ToArray(), false, false);
        }
    }

    private sealed class InlineProgress<T>(Action<T> handler) : IProgress<T>
    {
        public void Report(T value) => handler(value);
    }

    private sealed class TemporaryDirectory : IDisposable
    {
        public TemporaryDirectory()
        {
            Path = System.IO.Path.Combine(
                System.IO.Path.GetTempPath(),
                $"MonglePetPngExportTests-{Guid.NewGuid():N}");
            Directory.CreateDirectory(Path);
        }

        public string Path { get; }

        public void Dispose()
        {
            try
            {
                if (Directory.Exists(Path)) Directory.Delete(Path, recursive: true);
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
            }
        }
    }
}
