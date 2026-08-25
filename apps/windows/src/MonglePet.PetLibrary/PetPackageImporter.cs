using System.Security.Cryptography;
using System.Text;
using MonglePet.Packages;
using MonglePet.Settings;

namespace MonglePet.PetLibrary;

public sealed class PetPackageImporter
{
    private readonly PetLibraryStore _libraryStore;
    private readonly PetPackageArchiveExtractor _archiveExtractor;
    private readonly PetPackageLoader _loader;
    private readonly Func<Guid> _operationIdGenerator;

    public PetPackageImporter(
        PetLibraryStore libraryStore,
        PetPackageArchiveExtractor? archiveExtractor = null,
        PetPackageLoader? loader = null,
        Func<Guid>? operationIdGenerator = null)
    {
        _libraryStore = libraryStore ?? throw new ArgumentNullException(nameof(libraryStore));
        _archiveExtractor = archiveExtractor ?? new PetPackageArchiveExtractor();
        _loader = loader ?? new PetPackageLoader();
        _operationIdGenerator = operationIdGenerator ?? Guid.NewGuid;
    }

    public PetPackageImportReview Review(
        string sourcePath,
        RemotePetSemanticVersion? currentAppVersion = null,
        RemotePetSemanticVersion? publishedMinimumAppVersion = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(sourcePath);
        string fullPath = Path.GetFullPath(sourcePath);
        string fingerprint = Fingerprint(fullPath);
        return WithPreparedPackage(fullPath, packageRoot =>
        {
            LoadedPetPackage package = _loader.LoadDirectory(packageRoot);
            PetCompatibilityAdvisory? advisory = currentAppVersion is { } current
                ? PetCompatibilityAdvisory.Create(
                    package.Manifest.Compatibility,
                    current,
                    publishedMinimumAppVersion)
                : null;
            string recommendedPath = Path.Combine(packageRoot, "recommended-profile.json");
            if (!File.Exists(recommendedPath))
            {
                return new PetPackageImportReview(
                    fullPath,
                    fingerprint,
                    package.Manifest,
                    false,
                    null,
                    null,
                    null,
                    currentAppVersion,
                    publishedMinimumAppVersion,
                    advisory);
            }

            var info = new FileInfo(recommendedPath);
            if (info.Length > RecommendedPetProfileCodec.MaximumFileSize)
            {
                throw new PetLibraryException(
                    PetLibraryError.PackageValidationFailed,
                    "recommended-profile.json exceeds the 1 MiB security limit.");
            }

            try
            {
                BehaviorProfile profile = RecommendedPetProfileCodec.Decode(
                    File.ReadAllBytes(recommendedPath),
                    PetBehaviorKey.BuiltInKey,
                    package.Manifest.Motions.Select(motion => motion.Id).ToArray());
                return new PetPackageImportReview(
                    fullPath,
                    fingerprint,
                    package.Manifest,
                    true,
                    profile,
                    null,
                    null,
                    currentAppVersion,
                    publishedMinimumAppVersion,
                    advisory);
            }
            catch (RecommendedPetProfileException exception)
                when (exception.Error != RecommendedPetProfileError.TooLarge)
            {
                return new PetPackageImportReview(
                    fullPath,
                    fingerprint,
                    package.Manifest,
                    true,
                    null,
                    exception.Error,
                    exception.Message,
                    currentAppVersion,
                    publishedMinimumAppVersion,
                    advisory);
            }
        });
    }

    public InstalledPetPackage ImportReviewed(
        PetPackageImportReview review,
        PetPackageInstallMode mode = PetPackageInstallMode.RejectDuplicate,
        Guid? replacementInstallationId = null)
    {
        ArgumentNullException.ThrowIfNull(review);
        PetPackageImportReview current = Review(
            review.SourcePath,
            review.CurrentAppVersion,
            review.PublishedMinimumAppVersion);
        if (!string.Equals(
                current.SourceFingerprint,
                review.SourceFingerprint,
                StringComparison.Ordinal))
        {
            throw new PetLibraryException(
                PetLibraryError.ReviewedContentChanged,
                "The package changed after review. Review it again before importing.");
        }

        return Import(review.SourcePath, mode, replacementInstallationId);
    }

    public InstalledPetPackage Import(
        string sourcePath,
        PetPackageInstallMode mode = PetPackageInstallMode.RejectDuplicate,
        Guid? replacementInstallationId = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(sourcePath);
        string fullPath = Path.GetFullPath(sourcePath);
        if (Directory.Exists(fullPath))
        {
            return _libraryStore.InstallFromDirectory(
                fullPath,
                mode,
                replacementInstallationId);
        }

        string workspace = Path.Combine(
            _libraryStore.LibraryRootPath,
            $".import-{_operationIdGenerator():N}");
        try
        {
            _libraryStore.EnsureLibraryRoot();
            Directory.CreateDirectory(workspace);
            string extractedRoot = _archiveExtractor.Extract(fullPath, workspace);
            return _libraryStore.InstallFromDirectory(
                extractedRoot,
                mode,
                replacementInstallationId);
        }
        catch (PetLibraryException)
        {
            throw;
        }
        catch (Exception exception) when (
            exception is PetPackageArchiveException or IOException or UnauthorizedAccessException)
        {
            throw new PetLibraryException(
                PetLibraryError.PackageValidationFailed,
                sourcePath,
                exception);
        }
        finally
        {
            if (Directory.Exists(workspace))
            {
                try
                {
                    Directory.Delete(workspace, recursive: true);
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

    private T WithPreparedPackage<T>(string fullPath, Func<string, T> operation)
    {
        if (Directory.Exists(fullPath))
        {
            try
            {
                return operation(fullPath);
            }
            catch (PetLibraryException)
            {
                throw;
            }
            catch (Exception exception) when (
                exception is PetPackageLoadException or PetPackageManifestException or
                IOException or UnauthorizedAccessException)
            {
                throw new PetLibraryException(
                    PetLibraryError.PackageValidationFailed,
                    fullPath,
                    exception);
            }
        }

        string workspace = Path.Combine(
            _libraryStore.LibraryRootPath,
            $".review-{_operationIdGenerator():N}");
        try
        {
            _libraryStore.EnsureLibraryRoot();
            Directory.CreateDirectory(workspace);
            string extractedRoot = _archiveExtractor.Extract(fullPath, workspace);
            return operation(extractedRoot);
        }
        catch (PetLibraryException)
        {
            throw;
        }
        catch (Exception exception) when (
            exception is PetPackageArchiveException or PetPackageLoadException or
            PetPackageManifestException or IOException or UnauthorizedAccessException)
        {
            throw new PetLibraryException(
                PetLibraryError.PackageValidationFailed,
                fullPath,
                exception);
        }
        finally
        {
            TryDeleteDirectory(workspace);
        }
    }

    private static string Fingerprint(string fullPath)
    {
        try
        {
            if (File.Exists(fullPath))
            {
                using FileStream stream = File.OpenRead(fullPath);
                return Convert.ToHexString(SHA256.HashData(stream));
            }
            if (!Directory.Exists(fullPath))
            {
                throw new FileNotFoundException("Package source was not found.", fullPath);
            }

            using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
            string[] files = Directory.GetFiles(fullPath, "*", SearchOption.AllDirectories)
                .OrderBy(path => Path.GetRelativePath(fullPath, path), StringComparer.Ordinal)
                .ToArray();
            foreach (string file in files)
            {
                string relativePath = Path.GetRelativePath(fullPath, file).Replace('\\', '/');
                hash.AppendData(Encoding.UTF8.GetBytes(relativePath));
                hash.AppendData([0]);
                using FileStream stream = File.OpenRead(file);
                var buffer = new byte[64 * 1024];
                int read;
                while ((read = stream.Read(buffer, 0, buffer.Length)) > 0)
                {
                    hash.AppendData(buffer.AsSpan(0, read));
                }
            }
            return Convert.ToHexString(hash.GetHashAndReset());
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException)
        {
            throw new PetLibraryException(PetLibraryError.FileOperationFailed, fullPath, exception);
        }
    }

    private static void TryDeleteDirectory(string path)
    {
        if (!Directory.Exists(path))
        {
            return;
        }
        try
        {
            Directory.Delete(path, recursive: true);
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }
}
