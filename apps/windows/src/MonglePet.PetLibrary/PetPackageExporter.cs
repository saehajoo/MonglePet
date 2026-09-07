using System.IO.Compression;
using MonglePet.Packages;
using MonglePet.Settings;

namespace MonglePet.PetLibrary;

public sealed class PetPackageExporter
{
    public const string CurrentPackageFormatMinimumAppVersion = "0.1.0";
    public const string CurrentCreatorSettingsMinimumAppVersion = "1.7.0";

    private readonly PetPackageLoader _loader;
    private readonly PetPackageArchiveExtractor _archiveExtractor;
    private readonly IPngExportOptimizer _pngOptimizer;
    private readonly Func<Guid> _operationIdGenerator;
    private readonly string _appVersion;
    private readonly string _packageFormatMinimumAppVersion;
    private readonly string _creatorSettingsMinimumAppVersion;

    public PetPackageExporter(
        PetPackageLoader? loader = null,
        PetPackageArchiveExtractor? archiveExtractor = null,
        IPngExportOptimizer? pngOptimizer = null,
        Func<Guid>? operationIdGenerator = null,
        string appVersion = "1.7.0",
        string packageFormatMinimumAppVersion = CurrentPackageFormatMinimumAppVersion,
        string creatorSettingsMinimumAppVersion = CurrentCreatorSettingsMinimumAppVersion)
    {
        if (!RemotePetSemanticVersion.TryParse(appVersion, out _) ||
            !RemotePetSemanticVersion.TryParse(packageFormatMinimumAppVersion, out _) ||
            !RemotePetSemanticVersion.TryParse(creatorSettingsMinimumAppVersion, out _))
        {
            throw new ArgumentException("Package compatibility versions must use MAJOR.MINOR.PATCH.");
        }
        _loader = loader ?? new PetPackageLoader();
        _archiveExtractor = archiveExtractor ?? new PetPackageArchiveExtractor();
        _pngOptimizer = pngOptimizer ?? new PngExportOptimizer();
        _operationIdGenerator = operationIdGenerator ?? Guid.NewGuid;
        _appVersion = appVersion;
        _packageFormatMinimumAppVersion = packageFormatMinimumAppVersion;
        _creatorSettingsMinimumAppVersion = creatorSettingsMinimumAppVersion;
    }

    public string Export(
        InstalledPetPackage installedPackage,
        string destinationPath,
        BehaviorProfile? recommendedProfile = null,
        bool includesApplicationRules = false,
        OverlaySettings? recommendedDisplay = null)
    => ExportCore(
        installedPackage,
        destinationPath,
        recommendedProfile,
        includesApplicationRules,
        recommendedDisplay,
        progress: null,
        CancellationToken.None).DestinationPath;

    public Task<PetPackageExportResult> ExportAsync(
        InstalledPetPackage installedPackage,
        string destinationPath,
        BehaviorProfile? recommendedProfile = null,
        bool includesApplicationRules = false,
        OverlaySettings? recommendedDisplay = null,
        IProgress<PetPackageExportProgress>? progress = null,
        CancellationToken cancellationToken = default) => Task.Run(
            () => ExportCore(
                installedPackage,
                destinationPath,
                recommendedProfile,
                includesApplicationRules,
                recommendedDisplay,
                progress,
                cancellationToken),
            cancellationToken);

    public PetPackageAssetSizeReport AnalyzeAssets(InstalledPetPackage installedPackage)
    {
        ArgumentNullException.ThrowIfNull(installedPackage);
        LoadedPetPackage source = LoadSource(installedPackage);
        ReferencedAsset[] assets = ReferencedAssets(source);
        return new(
            assets.Sum(asset => asset.Bytes),
            assets
                .OrderByDescending(asset => asset.Bytes)
                .ThenBy(asset => asset.Label, StringComparer.CurrentCulture)
                .Select(asset => new PetPackageAssetSizeDetail(asset.Label, asset.Bytes))
                .ToArray());
    }

    private PetPackageExportResult ExportCore(
        InstalledPetPackage installedPackage,
        string destinationPath,
        BehaviorProfile? recommendedProfile,
        bool includesApplicationRules,
        OverlaySettings? recommendedDisplay,
        IProgress<PetPackageExportProgress>? progress,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(installedPackage);
        ArgumentException.ThrowIfNullOrWhiteSpace(destinationPath);
        var progressReporter = new MonotonicProgressReporter(progress);
        progressReporter.Report(PetPackageExportStage.Preparing, 0);
        cancellationToken.ThrowIfCancellationRequested();
        string destination = Path.GetFullPath(destinationPath);
        if (!string.Equals(Path.GetExtension(destination), ".monglepet", StringComparison.OrdinalIgnoreCase))
        {
            throw Error(PetPackageExportError.InvalidDestination, destination);
        }

        string? destinationDirectory = Path.GetDirectoryName(destination);
        if (string.IsNullOrWhiteSpace(destinationDirectory) || !Directory.Exists(destinationDirectory))
        {
            throw Error(PetPackageExportError.InvalidDestination, destination);
        }

        Guid operationId = _operationIdGenerator();
        string workspace = Path.Combine(Path.GetTempPath(), $"MonglePetExport-{operationId:N}");
        string payload = Path.Combine(workspace, "payload.monglepet");
        string verification = Path.Combine(workspace, "verification");
        string temporaryArchive = Path.Combine(
            destinationDirectory,
            $".{Path.GetFileNameWithoutExtension(destination)}-{operationId:N}.tmp.monglepet");
        try
        {
            Directory.CreateDirectory(payload);
            LoadedPetPackage source = LoadSource(installedPackage);
            ReferencedAsset[] assets = ReferencedAssets(source);
            string minimumAppVersion = recommendedProfile is null
                ? _packageFormatMinimumAppVersion
                : _creatorSettingsMinimumAppVersion;
            PetPackageManifest exportedManifest = source.Manifest with
            {
                Compatibility = new PetPackageCompatibility(_appVersion, minimumAppVersion),
            };
            File.WriteAllBytes(
                Path.Combine(payload, "pet.json"),
                PetPackageManifestWriter.Write(exportedManifest));
            progressReporter.Report(PetPackageExportStage.Preparing, 0.05);
            long totalImageBytes = Math.Max(1, assets.Sum(asset => asset.Bytes));
            long completedImageBytes = 0;
            for (int assetIndex = 0; assetIndex < assets.Length; assetIndex++)
            {
                cancellationToken.ThrowIfCancellationRequested();
                ReferencedAsset asset = assets[assetIndex];
                CopyReferencedFile(asset.SourcePath, asset.RelativePath, payload, cancellationToken);
                completedImageBytes += asset.Bytes;
                double fraction = 0.05 + (0.65 * completedImageBytes / totalImageBytes);
                progressReporter.Report(
                    PetPackageExportStage.OptimizingImages,
                    fraction,
                    assetIndex + 1,
                    assets.Length);
            }

            byte[]? expectedRecommendedProfile = null;
            if (recommendedProfile is not null)
            {
                expectedRecommendedProfile = RecommendedPetProfileCodec.Encode(
                    recommendedProfile,
                    exportedManifest.Motions.Select(motion => motion.Id).ToArray(),
                    includesApplicationRules,
                    recommendedDisplay);
                File.WriteAllBytes(
                    Path.Combine(payload, "recommended-profile.json"),
                    expectedRecommendedProfile);
            }

            LoadedPetPackage sanitized = _loader.LoadDirectory(payload);
            EnsureEquivalent(exportedManifest, sanitized.Manifest);
            cancellationToken.ThrowIfCancellationRequested();
            progressReporter.Report(
                PetPackageExportStage.CreatingArchive,
                0.70,
                assets.Length,
                assets.Length);
            CreateArchive(payload, temporaryArchive);
            progressReporter.Report(
                PetPackageExportStage.CreatingArchive,
                0.85,
                assets.Length,
                assets.Length);
            if (new FileInfo(temporaryArchive).Length > _archiveExtractor.Limits.MaximumArchiveBytes)
            {
                throw Error(PetPackageExportError.ArchiveTooLarge, temporaryArchive);
            }
            ValidateArchiveRoundTrip(
                temporaryArchive,
                verification,
                exportedManifest,
                expectedRecommendedProfile);
            progressReporter.Report(
                PetPackageExportStage.ValidatingArchive,
                0.97,
                assets.Length,
                assets.Length);
            cancellationToken.ThrowIfCancellationRequested();
            progressReporter.Report(
                PetPackageExportStage.Saving,
                0.98,
                assets.Length,
                assets.Length);
            ReplaceAtomically(temporaryArchive, destination);
            long archiveBytes = new FileInfo(destination).Length;
            progressReporter.Report(
                PetPackageExportStage.Completed,
                1,
                assets.Length,
                assets.Length);
            return new(destination, archiveBytes);
        }
        catch (PetPackageExportException)
        {
            throw;
        }
        catch (RecommendedPetProfileException exception)
        {
            throw Error(PetPackageExportError.PackageValidationFailed, exception.Message, exception);
        }
        catch (Exception exception) when (
            exception is PetPackageLoadException or PetPackageManifestException)
        {
            throw Error(PetPackageExportError.PackageValidationFailed, exception.Message, exception);
        }
        catch (PetPackageArchiveException exception)
        {
            throw Error(PetPackageExportError.ArchiveValidationFailed, exception.Message, exception);
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException or InvalidDataException)
        {
            throw Error(PetPackageExportError.FileOperationFailed, destination, exception);
        }
        finally
        {
            TryDeleteFile(temporaryArchive);
            TryDeleteDirectory(workspace);
        }
    }

    private LoadedPetPackage LoadSource(InstalledPetPackage installed)
    {
        LoadedPetPackage current = _loader.LoadDirectory(installed.RootPath);
        byte[] expected = PetPackageManifestWriter.Write(installed.Package.Manifest);
        byte[] actual = PetPackageManifestWriter.Write(current.Manifest);
        if (!expected.AsSpan().SequenceEqual(actual))
        {
            throw Error(PetPackageExportError.SourcePackageChanged, installed.RootPath);
        }
        return current;
    }

    private void ValidateArchiveRoundTrip(
        string archivePath,
        string verificationWorkspace,
        PetPackageManifest expectedManifest,
        byte[]? expectedRecommendedProfile)
    {
        Directory.CreateDirectory(verificationWorkspace);
        string extracted = _archiveExtractor.Extract(archivePath, verificationWorkspace);
        LoadedPetPackage roundTripped = _loader.LoadDirectory(extracted);
        EnsureEquivalent(expectedManifest, roundTripped.Manifest);
        string recommendedPath = Path.Combine(extracted, "recommended-profile.json");
        if (expectedRecommendedProfile is null)
        {
            if (File.Exists(recommendedPath))
            {
                throw Error(PetPackageExportError.SourcePackageChanged, recommendedPath);
            }
        }
        else if (!File.Exists(recommendedPath) ||
                 !File.ReadAllBytes(recommendedPath).AsSpan().SequenceEqual(expectedRecommendedProfile))
        {
            throw Error(PetPackageExportError.SourcePackageChanged, recommendedPath);
        }
    }

    private static void EnsureEquivalent(PetPackageManifest expected, PetPackageManifest actual)
    {
        if (!PetPackageManifestWriter.Write(expected).AsSpan()
                .SequenceEqual(PetPackageManifestWriter.Write(actual)))
        {
            throw Error(PetPackageExportError.SourcePackageChanged, "Manifest changed during export.");
        }
    }

    private void CopyReferencedFile(
        string source,
        string relativePath,
        string payload,
        CancellationToken cancellationToken)
    {
        string destination = Path.Combine(
            payload,
            relativePath.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
        if (Path.GetExtension(source).Equals(".png", StringComparison.OrdinalIgnoreCase))
        {
            byte[] original = File.ReadAllBytes(source);
            PngExportOptimizationResult optimized = _pngOptimizer.Optimize(
                original,
                cancellationToken);
            File.WriteAllBytes(destination, optimized.Bytes);
        }
        else
        {
            File.Copy(source, destination, overwrite: false);
        }
    }

    private static ReferencedAsset[] ReferencedAssets(LoadedPetPackage source)
    {
        var assets = new List<ReferencedAsset>
        {
            new(
                source.PreviewFilePath,
                source.Manifest.PreviewPath,
                "대표 이미지",
                new FileInfo(source.PreviewFilePath).Length),
        };
        foreach (PetPackageAtlas atlas in source.Manifest.Atlases)
        {
            if (!source.Atlases.TryGetValue(atlas.Id, out LoadedPetAtlas? loaded))
            {
                throw Error(PetPackageExportError.SourcePackageChanged, atlas.Id);
            }
            string[] motionNames = source.Manifest.Motions
                .Where(motion => string.Equals(motion.Atlas, atlas.Id, StringComparison.Ordinal))
                .Select(motion => motion.Id)
                .Distinct(StringComparer.Ordinal)
                .ToArray();
            string label = motionNames.Length == 0
                ? "애니메이션 이미지"
                : string.Join(", ", motionNames);
            assets.Add(new(
                loaded.FilePath,
                atlas.Path,
                label,
                new FileInfo(loaded.FilePath).Length));
        }
        return assets
            .GroupBy(asset => asset.RelativePath, StringComparer.OrdinalIgnoreCase)
            .Select(group => group.First())
            .ToArray();
    }

    private static void CreateArchive(string payload, string archivePath)
    {
        using FileStream stream = new(archivePath, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        using var archive = new ZipArchive(stream, ZipArchiveMode.Create, leaveOpen: false);
        foreach (string file in Directory.GetFiles(payload, "*", SearchOption.AllDirectories)
                     .OrderBy(path => Path.GetRelativePath(payload, path), StringComparer.Ordinal))
        {
            string entryName = Path.GetRelativePath(payload, file).Replace('\\', '/');
            ZipArchiveEntry entry = archive.CreateEntry(entryName, CompressionLevel.Optimal);
            using Stream entryStream = entry.Open();
            using FileStream source = File.OpenRead(file);
            source.CopyTo(entryStream);
        }
    }

    private static void ReplaceAtomically(string temporaryArchive, string destination)
    {
        if (File.Exists(destination))
        {
            File.Replace(temporaryArchive, destination, null, ignoreMetadataErrors: true);
        }
        else
        {
            File.Move(temporaryArchive, destination);
        }
    }

    private static void TryDeleteFile(string path)
    {
        try
        {
            if (File.Exists(path)) File.Delete(path);
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    private static void TryDeleteDirectory(string path)
    {
        try
        {
            if (Directory.Exists(path)) Directory.Delete(path, recursive: true);
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    private static PetPackageExportException Error(
        PetPackageExportError error,
        string detail,
        Exception? innerException = null)
    {
        string message = error switch
        {
            PetPackageExportError.InvalidDestination =>
                "선택한 위치에 MonglePet 패키지를 저장할 수 없습니다.",
            PetPackageExportError.SourcePackageChanged =>
                "내보내기를 준비하는 동안 펫 이미지나 정보가 변경되었습니다. 다시 시도해 주세요.",
            PetPackageExportError.PackageValidationFailed =>
                "펫 정보와 이미지 검증에 실패해 공유 파일을 만들지 않았습니다.",
            PetPackageExportError.ArchiveValidationFailed =>
                "완성된 공유 파일을 다시 검증하지 못해 저장하지 않았습니다.",
            PetPackageExportError.ArchiveTooLarge =>
                "이미지를 무손실 최적화한 뒤에도 공유 파일이 30 MiB 제한을 초과합니다. 설치된 펫과 기존 파일은 변경되지 않았습니다.",
            PetPackageExportError.FileOperationFailed =>
                "공유 파일을 준비하거나 저장하지 못했습니다. 저장 위치와 사용 가능한 공간을 확인해 주세요.",
            _ => detail,
        };
        return new(error, message, innerException);
    }

    private sealed record ReferencedAsset(
        string SourcePath,
        string RelativePath,
        string Label,
        long Bytes);

    private sealed class MonotonicProgressReporter(IProgress<PetPackageExportProgress>? progress)
    {
        private double _lastFraction;

        public void Report(
            PetPackageExportStage stage,
            double fraction,
            int currentImage = 0,
            int totalImages = 0)
        {
            double clamped = Math.Clamp(fraction, _lastFraction, 1);
            _lastFraction = clamped;
            progress?.Report(new(stage, clamped, currentImage, totalImages));
        }
    }
}
