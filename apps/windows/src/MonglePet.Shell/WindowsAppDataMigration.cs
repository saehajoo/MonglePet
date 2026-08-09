namespace MonglePet.Shell;

public enum WindowsAppDataMigrationStatus
{
    NotNeeded,
    SourceNotFound,
    Migrated,
    Failed,
}

public sealed record WindowsAppDataMigrationResult(
    WindowsAppDataMigrationStatus Status,
    string TargetPath,
    string? SourcePath = null,
    string? ErrorMessage = null);

public static class WindowsAppDataMigration
{
    public const string AppDataDirectoryName = "MonglePet";

    public static WindowsAppDataMigrationResult TryMigrateFromPackageLocalState(
        string localAppDataRoot,
        IReadOnlyList<string> packageFamilyNames)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(localAppDataRoot);
        ArgumentNullException.ThrowIfNull(packageFamilyNames);

        string normalizedLocalRoot = Path.GetFullPath(localAppDataRoot);
        string targetPath = Path.Combine(normalizedLocalRoot, AppDataDirectoryName);

        try
        {
            if (Directory.Exists(targetPath) &&
                Directory.EnumerateFileSystemEntries(targetPath).Any())
            {
                return new WindowsAppDataMigrationResult(
                    WindowsAppDataMigrationStatus.NotNeeded,
                    targetPath);
            }

            string? sourcePath = packageFamilyNames
                .Where(packageFamilyName => !string.IsNullOrWhiteSpace(packageFamilyName))
                .Select(packageFamilyName => Path.Combine(
                    normalizedLocalRoot,
                    "Packages",
                    packageFamilyName,
                    "LocalState",
                    AppDataDirectoryName))
                .FirstOrDefault(Directory.Exists);

            if (sourcePath is null)
            {
                return new WindowsAppDataMigrationResult(
                    WindowsAppDataMigrationStatus.SourceNotFound,
                    targetPath);
            }

            string stagingPath = Path.Combine(
                normalizedLocalRoot,
                $".{AppDataDirectoryName}.migration.{Guid.NewGuid():N}");

            try
            {
                CopyDirectoryWithoutLinks(sourcePath, stagingPath);
                if (Directory.Exists(targetPath))
                {
                    Directory.Delete(targetPath, recursive: false);
                }
                Directory.Move(stagingPath, targetPath);
            }
            catch
            {
                if (Directory.Exists(stagingPath))
                {
                    Directory.Delete(stagingPath, recursive: true);
                }
                throw;
            }

            return new WindowsAppDataMigrationResult(
                WindowsAppDataMigrationStatus.Migrated,
                targetPath,
                sourcePath);
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException)
        {
            return new WindowsAppDataMigrationResult(
                WindowsAppDataMigrationStatus.Failed,
                targetPath,
                ErrorMessage: exception.Message);
        }
    }

    private static void CopyDirectoryWithoutLinks(string sourcePath, string destinationPath)
    {
        DirectoryInfo source = new(sourcePath);
        EnsureNotReparsePoint(source);
        Directory.CreateDirectory(destinationPath);

        foreach (DirectoryInfo directory in source.EnumerateDirectories(
                     "*",
                     SearchOption.AllDirectories))
        {
            EnsureNotReparsePoint(directory);
            string relativePath = Path.GetRelativePath(sourcePath, directory.FullName);
            Directory.CreateDirectory(Path.Combine(destinationPath, relativePath));
        }

        foreach (FileInfo file in source.EnumerateFiles("*", SearchOption.AllDirectories))
        {
            EnsureNotReparsePoint(file);
            string relativePath = Path.GetRelativePath(sourcePath, file.FullName);
            string destinationFile = Path.Combine(destinationPath, relativePath);
            Directory.CreateDirectory(Path.GetDirectoryName(destinationFile)!);
            file.CopyTo(destinationFile, overwrite: false);
        }
    }

    private static void EnsureNotReparsePoint(FileSystemInfo item)
    {
        if ((item.Attributes & FileAttributes.ReparsePoint) != 0)
        {
            throw new IOException($"App data migration does not follow links: {item.FullName}");
        }
    }
}
