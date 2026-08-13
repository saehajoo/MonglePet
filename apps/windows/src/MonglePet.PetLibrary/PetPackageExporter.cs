using System.IO.Compression;
using MonglePet.Packages;
using MonglePet.Settings;

namespace MonglePet.PetLibrary;

public sealed class PetPackageExporter
{
    private readonly PetPackageLoader _loader;
    private readonly PetPackageArchiveExtractor _archiveExtractor;
    private readonly Func<Guid> _operationIdGenerator;
    private readonly string _appVersion;

    public PetPackageExporter(
        PetPackageLoader? loader = null,
        PetPackageArchiveExtractor? archiveExtractor = null,
        Func<Guid>? operationIdGenerator = null,
        string appVersion = "1.1.0")
    {
        _loader = loader ?? new PetPackageLoader();
        _archiveExtractor = archiveExtractor ?? new PetPackageArchiveExtractor();
        _operationIdGenerator = operationIdGenerator ?? Guid.NewGuid;
        _appVersion = appVersion;
    }

    public string Export(
        InstalledPetPackage installedPackage,
        string destinationPath,
        BehaviorProfile? recommendedProfile = null,
        bool includesApplicationRules = false)
    {
        ArgumentNullException.ThrowIfNull(installedPackage);
        ArgumentException.ThrowIfNullOrWhiteSpace(destinationPath);
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
            PetPackageManifest exportedManifest = source.Manifest with
            {
                Compatibility = new PetPackageCompatibility(_appVersion, _appVersion),
            };
            File.WriteAllBytes(
                Path.Combine(payload, "pet.json"),
                PetPackageManifestWriter.Write(exportedManifest));
            CopyReferencedFile(source.PreviewFilePath, exportedManifest.PreviewPath, payload);
            foreach (PetPackageAtlas atlas in exportedManifest.Atlases)
            {
                if (!source.Atlases.TryGetValue(atlas.Id, out LoadedPetAtlas? loaded))
                {
                    throw Error(PetPackageExportError.SourcePackageChanged, atlas.Id);
                }
                CopyReferencedFile(loaded.FilePath, atlas.Path, payload);
            }

            byte[]? expectedRecommendedProfile = null;
            if (recommendedProfile is not null)
            {
                expectedRecommendedProfile = RecommendedPetProfileCodec.Encode(
                    recommendedProfile,
                    exportedManifest.Motions.Select(motion => motion.Id).ToArray(),
                    includesApplicationRules);
                File.WriteAllBytes(
                    Path.Combine(payload, "recommended-profile.json"),
                    expectedRecommendedProfile);
            }

            LoadedPetPackage sanitized = _loader.LoadDirectory(payload);
            EnsureEquivalent(exportedManifest, sanitized.Manifest);
            CreateArchive(payload, temporaryArchive);
            if (new FileInfo(temporaryArchive).Length > PetPackageArchiveLimits.Standard.MaximumArchiveBytes)
            {
                throw Error(PetPackageExportError.ArchiveTooLarge, temporaryArchive);
            }
            ValidateArchiveRoundTrip(
                temporaryArchive,
                verification,
                exportedManifest,
                expectedRecommendedProfile);
            ReplaceAtomically(temporaryArchive, destination);
            return destination;
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

    private static void CopyReferencedFile(string source, string relativePath, string payload)
    {
        string destination = Path.Combine(
            payload,
            relativePath.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
        File.Copy(source, destination, overwrite: false);
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
        Exception? innerException = null) => new(error, detail, innerException);
}
