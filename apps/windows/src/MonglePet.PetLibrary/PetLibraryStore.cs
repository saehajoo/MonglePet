using MonglePet.Packages;

namespace MonglePet.PetLibrary;

public sealed class PetLibraryStore
{
    private readonly PetPackageLoader _loader;
    private readonly Func<Guid> _installationIdGenerator;
    private readonly Func<Guid> _operationIdGenerator;

    public PetLibraryStore(
        string libraryRootPath,
        PetPackageLoader? loader = null,
        Func<Guid>? installationIdGenerator = null,
        Func<Guid>? operationIdGenerator = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(libraryRootPath);
        try
        {
            LibraryRootPath = Path.GetFullPath(libraryRootPath);
        }
        catch (Exception exception) when (exception is ArgumentException or NotSupportedException)
        {
            throw Error(PetLibraryError.InvalidLibraryRoot, libraryRootPath, exception);
        }

        _loader = loader ?? new PetPackageLoader();
        _installationIdGenerator = installationIdGenerator ?? Guid.NewGuid;
        _operationIdGenerator = operationIdGenerator ?? Guid.NewGuid;
    }

    public string LibraryRootPath { get; }

    public IReadOnlyList<InstalledPetPackage> GetInstalledPackages()
    {
        if (!Directory.Exists(LibraryRootPath))
        {
            return [];
        }

        var installed = new List<InstalledPetPackage>();
        string[] children;
        try
        {
            children = Directory.EnumerateDirectories(
                LibraryRootPath,
                "*",
                SearchOption.TopDirectoryOnly).ToArray();
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            throw Error(PetLibraryError.FileOperationFailed, LibraryRootPath, exception);
        }

        foreach (string child in children)
        {
            string name = Path.GetFileName(child);
            if (name.StartsWith(".", StringComparison.Ordinal) ||
                !Guid.TryParseExact(name, "D", out Guid installationId))
            {
                continue;
            }

            try
            {
                LoadedPetPackage package = _loader.LoadDirectory(child);
                installed.Add(new InstalledPetPackage(installationId, child, package));
            }
            catch (Exception exception) when (
                exception is PetPackageLoadException or PetPackageManifestException)
            {
                // A damaged installation is isolated from the usable library list.
            }
        }

        return installed
            .OrderBy(value => value.InstallationId)
            .ToArray();
    }

    public InstalledPetPackage InstallFromDirectory(
        string sourcePackagePath,
        PetPackageInstallMode mode = PetPackageInstallMode.RejectDuplicate,
        Guid? replacementInstallationId = null) =>
        InstallFromDirectoryCore(
            sourcePackagePath,
            mode,
            replacementInstallationId,
            preserveEditorMarker: false);

    internal InstalledPetPackage InstallEditableFromDirectory(
        string sourcePackagePath,
        PetPackageInstallMode mode = PetPackageInstallMode.RejectDuplicate,
        Guid? replacementInstallationId = null) =>
        InstallFromDirectoryCore(
            sourcePackagePath,
            mode,
            replacementInstallationId,
            preserveEditorMarker: true);

    private InstalledPetPackage InstallFromDirectoryCore(
        string sourcePackagePath,
        PetPackageInstallMode mode,
        Guid? replacementInstallationId,
        bool preserveEditorMarker)
    {
        LoadedPetPackage sourcePackage = LoadForInstallation(sourcePackagePath);
        EnsureLibraryRoot();

        InstalledPetPackage[] matching = GetInstalledPackages()
            .Where(value => string.Equals(
                value.Package.Manifest.Id,
                sourcePackage.Manifest.Id,
                StringComparison.Ordinal))
            .ToArray();

        Guid installationId = ResolveInstallationId(
            sourcePackage,
            matching,
            mode,
            replacementInstallationId);
        Guid operationId = _operationIdGenerator();
        string stagingPath = Path.Combine(LibraryRootPath, $".staging-{operationId:N}");
        string destinationPath = Path.Combine(LibraryRootPath, installationId.ToString("D"));

        try
        {
            CopyPackageDirectory(sourcePackagePath, stagingPath, preserveEditorMarker);
            LoadedPetPackage stagedPackage = LoadForInstallation(stagingPath);
            if (!string.Equals(
                    stagedPackage.Manifest.Id,
                    sourcePackage.Manifest.Id,
                    StringComparison.Ordinal))
            {
                throw Error(
                    PetLibraryError.PackageIdentifierMismatch,
                    $"Package changed during staging: {sourcePackage.Manifest.Id} -> " +
                    stagedPackage.Manifest.Id);
            }

            return mode == PetPackageInstallMode.Replace
                ? ReplaceInstallation(stagingPath, destinationPath, installationId, operationId)
                : CommitNewInstallation(stagingPath, destinationPath, installationId);
        }
        finally
        {
            TryDeleteDirectory(stagingPath);
        }
    }

    public void RemoveInstallation(Guid installationId)
    {
        InstalledPetPackage installed = GetInstallation(installationId);
        try
        {
            Directory.Delete(installed.RootPath, recursive: true);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            throw Error(PetLibraryError.FileOperationFailed, installed.RootPath, exception);
        }
    }

    public InstalledPetPackage GetInstallation(Guid installationId)
    {
        InstalledPetPackage? installed = GetInstalledPackages().FirstOrDefault(
            value => value.InstallationId == installationId);
        return installed ?? throw Error(
            PetLibraryError.MissingInstallation,
            installationId.ToString("D"));
    }

    private Guid ResolveInstallationId(
        LoadedPetPackage sourcePackage,
        IReadOnlyList<InstalledPetPackage> matching,
        PetPackageInstallMode mode,
        Guid? replacementInstallationId)
    {
        if (mode == PetPackageInstallMode.RejectDuplicate && matching.Count > 0)
        {
            throw new PetLibraryException(
                PetLibraryError.DuplicatePackage,
                $"Package is already installed: {sourcePackage.Manifest.Id}.")
            {
                MatchingInstallationIds = matching
                    .Select(value => value.InstallationId)
                    .ToArray(),
            };
        }

        if (mode != PetPackageInstallMode.Replace)
        {
            return _installationIdGenerator();
        }

        if (replacementInstallationId is not Guid requestedId)
        {
            throw Error(
                PetLibraryError.ReplacementInstallationRequired,
                "A replacement installation ID is required.");
        }

        InstalledPetPackage existing = GetInstallation(requestedId);
        if (!string.Equals(
                existing.Package.Manifest.Id,
                sourcePackage.Manifest.Id,
                StringComparison.Ordinal))
        {
            throw Error(
                PetLibraryError.PackageIdentifierMismatch,
                $"Cannot replace {existing.Package.Manifest.Id} with " +
                sourcePackage.Manifest.Id);
        }

        return requestedId;
    }

    private InstalledPetPackage CommitNewInstallation(
        string stagingPath,
        string destinationPath,
        Guid installationId)
    {
        if (Directory.Exists(destinationPath) || File.Exists(destinationPath))
        {
            throw Error(PetLibraryError.FileOperationFailed, destinationPath);
        }

        try
        {
            Directory.Move(stagingPath, destinationPath);
            LoadedPetPackage installed = LoadForInstallation(destinationPath);
            return new InstalledPetPackage(installationId, destinationPath, installed);
        }
        catch (PetLibraryException)
        {
            TryDeleteDirectory(destinationPath);
            throw;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            TryDeleteDirectory(destinationPath);
            throw Error(PetLibraryError.FileOperationFailed, destinationPath, exception);
        }
        catch
        {
            TryDeleteDirectory(destinationPath);
            throw;
        }
    }

    private InstalledPetPackage ReplaceInstallation(
        string stagingPath,
        string destinationPath,
        Guid installationId,
        Guid operationId)
    {
        if (!Directory.Exists(destinationPath))
        {
            throw Error(PetLibraryError.MissingInstallation, installationId.ToString("D"));
        }

        string backupPath = Path.Combine(LibraryRootPath, $".backup-{operationId:N}");
        try
        {
            Directory.Move(destinationPath, backupPath);
            try
            {
                Directory.Move(stagingPath, destinationPath);
                LoadedPetPackage installed = LoadForInstallation(destinationPath);
                TryDeleteDirectory(backupPath);
                return new InstalledPetPackage(installationId, destinationPath, installed);
            }
            catch
            {
                TryDeleteDirectory(destinationPath);
                if (Directory.Exists(backupPath))
                {
                    Directory.Move(backupPath, destinationPath);
                }

                throw;
            }
        }
        catch (PetLibraryException)
        {
            throw;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            throw Error(PetLibraryError.FileOperationFailed, destinationPath, exception);
        }
    }

    private LoadedPetPackage LoadForInstallation(string packagePath)
    {
        try
        {
            return _loader.LoadDirectory(packagePath);
        }
        catch (Exception exception) when (
            exception is PetPackageLoadException or PetPackageManifestException)
        {
            throw Error(PetLibraryError.PackageValidationFailed, packagePath, exception);
        }
    }

    internal void EnsureLibraryRoot()
    {
        try
        {
            Directory.CreateDirectory(LibraryRootPath);
            var root = new DirectoryInfo(LibraryRootPath);
            if ((root.Attributes & FileAttributes.ReparsePoint) != 0)
            {
                throw Error(PetLibraryError.InvalidLibraryRoot, LibraryRootPath);
            }
        }
        catch (PetLibraryException)
        {
            throw;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            throw Error(PetLibraryError.FileOperationFailed, LibraryRootPath, exception);
        }
    }

    private static void CopyPackageDirectory(
        string sourcePath,
        string destinationPath,
        bool preserveEditorMarker)
    {
        var source = new DirectoryInfo(Path.GetFullPath(sourcePath));
        if (!source.Exists || (source.Attributes & FileAttributes.ReparsePoint) != 0)
        {
            throw Error(PetLibraryError.PackageValidationFailed, sourcePath);
        }

        if (Directory.Exists(destinationPath) || File.Exists(destinationPath))
        {
            throw Error(PetLibraryError.FileOperationFailed, destinationPath);
        }

        try
        {
            Directory.CreateDirectory(destinationPath);
            var pending = new Stack<(DirectoryInfo Source, string Destination)>();
            pending.Push((source, destinationPath));

            while (pending.TryPop(out var current))
            {
                foreach (FileSystemInfo entry in current.Source.GetFileSystemInfos())
                {
                    if ((entry.Attributes & FileAttributes.ReparsePoint) != 0)
                    {
                        throw Error(PetLibraryError.PackageValidationFailed, entry.FullName);
                    }

                    string destination = Path.Combine(current.Destination, entry.Name);
                    if (!preserveEditorMarker && ReferenceEquals(current.Source, source) &&
                        string.Equals(
                            entry.Name,
                            "monglepet-editor.json",
                            StringComparison.OrdinalIgnoreCase))
                    {
                        continue;
                    }
                    if (entry is DirectoryInfo directory)
                    {
                        Directory.CreateDirectory(destination);
                        pending.Push((directory, destination));
                    }
                    else if (entry is FileInfo file)
                    {
                        file.CopyTo(destination, overwrite: false);
                    }
                    else
                    {
                        throw Error(PetLibraryError.PackageValidationFailed, entry.FullName);
                    }
                }
            }
        }
        catch (PetLibraryException)
        {
            throw;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            throw Error(PetLibraryError.FileOperationFailed, sourcePath, exception);
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

    private static PetLibraryException Error(
        PetLibraryError error,
        string detail,
        Exception? innerException = null) =>
        new(error, detail, innerException);
}
