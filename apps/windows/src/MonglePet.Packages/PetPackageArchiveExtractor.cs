using System.IO.Compression;

namespace MonglePet.Packages;

public sealed record PetPackageArchiveLimits(
    long MaximumArchiveBytes,
    long MaximumExpandedBytes,
    int MaximumEntryCount,
    int MaximumCompressionRatio)
{
    public static PetPackageArchiveLimits Standard { get; } = new(
        20L * 1024 * 1024,
        100L * 1024 * 1024,
        2_000,
        100);
}

public enum PetPackageArchiveError
{
    InvalidSource,
    ArchiveTooLarge,
    InvalidArchive,
    InvalidEntryPath,
    UnsupportedEntry,
    DuplicateEntry,
    EntryCountExceeded,
    ExpandedSizeExceeded,
    SuspiciousCompressionRatio,
    ExtractionFailed,
    MissingPackageRoot,
    MultiplePackageRoots,
}

public sealed class PetPackageArchiveException : Exception
{
    public PetPackageArchiveException(
        PetPackageArchiveError error,
        string detail,
        Exception? innerException = null)
        : base(detail, innerException)
    {
        Error = error;
    }

    public PetPackageArchiveError Error { get; }
}

public sealed class PetPackageArchiveExtractor
{
    private static readonly HashSet<string> SupportedExtensions =
        new(StringComparer.OrdinalIgnoreCase) { ".json", ".png", ".webp" };

    public PetPackageArchiveExtractor(PetPackageArchiveLimits? limits = null)
    {
        Limits = limits ?? PetPackageArchiveLimits.Standard;
    }

    public PetPackageArchiveLimits Limits { get; }

    public string Extract(string archivePath, string workspacePath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(archivePath);
        ArgumentException.ThrowIfNullOrWhiteSpace(workspacePath);

        var source = new FileInfo(Path.GetFullPath(archivePath));
        if (!source.Exists ||
            !source.Extension.Equals(".monglepet", StringComparison.OrdinalIgnoreCase) ||
            (source.Attributes & FileAttributes.ReparsePoint) != 0)
        {
            throw Error(PetPackageArchiveError.InvalidSource, archivePath);
        }

        if (source.Length > Limits.MaximumArchiveBytes)
        {
            throw Error(PetPackageArchiveError.ArchiveTooLarge, archivePath);
        }

        string extractionRoot = Path.Combine(Path.GetFullPath(workspacePath), "payload.monglepet");
        if (Directory.Exists(extractionRoot) || File.Exists(extractionRoot))
        {
            throw Error(PetPackageArchiveError.ExtractionFailed, extractionRoot);
        }

        try
        {
            using FileStream stream = source.OpenRead();
            using var archive = new ZipArchive(stream, ZipArchiveMode.Read, leaveOpen: false);
            List<ValidatedEntry> entries = ValidateEntries(archive, source.Length);
            Directory.CreateDirectory(extractionRoot);
            ExtractEntries(entries, extractionRoot);
        }
        catch (PetPackageArchiveException)
        {
            throw;
        }
        catch (InvalidDataException exception)
        {
            throw Error(PetPackageArchiveError.InvalidArchive, archivePath, exception);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            throw Error(PetPackageArchiveError.ExtractionFailed, archivePath, exception);
        }

        return LocatePackageRoot(extractionRoot);
    }

    private List<ValidatedEntry> ValidateEntries(ZipArchive archive, long archiveBytes)
    {
        if (archive.Entries.Count == 0)
        {
            throw Error(PetPackageArchiveError.InvalidArchive, "Archive contains no entries.");
        }

        if (archive.Entries.Count > Limits.MaximumEntryCount)
        {
            throw Error(PetPackageArchiveError.EntryCountExceeded, archive.Entries.Count.ToString());
        }

        long totalCompressed = 0;
        long totalExpanded = 0;
        var paths = new Dictionary<string, ValidatedEntry>(StringComparer.OrdinalIgnoreCase);
        foreach (ZipArchiveEntry entry in archive.Entries)
        {
            bool isDirectory = entry.Name.Length == 0 && entry.FullName.EndsWith('/');
            string relativePath = NormalizeEntryPath(entry.FullName, isDirectory);
            if (IsLinkOrUnsupportedEntry(entry, isDirectory))
            {
                throw Error(PetPackageArchiveError.UnsupportedEntry, relativePath);
            }

            if (!isDirectory && !SupportedExtensions.Contains(Path.GetExtension(relativePath)))
            {
                throw Error(PetPackageArchiveError.UnsupportedEntry, relativePath);
            }

            if (!paths.TryAdd(relativePath, new ValidatedEntry(entry, relativePath, isDirectory)))
            {
                throw Error(PetPackageArchiveError.DuplicateEntry, relativePath);
            }

            if (entry.CompressedLength < 0 || entry.Length < 0 ||
                entry.CompressedLength > archiveBytes - totalCompressed ||
                entry.Length > Limits.MaximumExpandedBytes - totalExpanded)
            {
                throw Error(PetPackageArchiveError.ExpandedSizeExceeded, relativePath);
            }


            totalCompressed += entry.CompressedLength;
            totalExpanded += entry.Length;

            ValidateCompressionRatio(entry.CompressedLength, entry.Length, relativePath);
        }

        ValidateCompressionRatio(totalCompressed, totalExpanded, "entire package");

        foreach (ValidatedEntry entry in paths.Values.Where(value => !value.IsDirectory))
        {
            string prefix = entry.RelativePath + "/";
            if (paths.Keys.Any(path => path.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)))
            {
                throw Error(PetPackageArchiveError.InvalidEntryPath, entry.RelativePath);
            }
        }

        return paths.Values.ToList();
    }

    private void ExtractEntries(IEnumerable<ValidatedEntry> entries, string extractionRoot)
    {
        string rootPrefix = extractionRoot.TrimEnd(Path.DirectorySeparatorChar) +
            Path.DirectorySeparatorChar;

        foreach (ValidatedEntry validated in entries.OrderBy(value => value.IsDirectory ? 0 : 1))
        {
            string destination = Path.GetFullPath(Path.Combine(
                extractionRoot,
                validated.RelativePath.Replace('/', Path.DirectorySeparatorChar)));
            if (!destination.StartsWith(rootPrefix, StringComparison.OrdinalIgnoreCase))
            {
                throw Error(PetPackageArchiveError.InvalidEntryPath, validated.RelativePath);
            }

            if (validated.IsDirectory)
            {
                Directory.CreateDirectory(destination);
                continue;
            }

            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            try
            {
                using Stream source = validated.Entry.Open();
                using FileStream target = new(
                    destination,
                    FileMode.CreateNew,
                    FileAccess.Write,
                    FileShare.None);
                CopyExactly(source, target, validated.Entry.Length, validated.RelativePath);
            }
            catch (PetPackageArchiveException)
            {
                throw;
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
            {
                throw Error(PetPackageArchiveError.ExtractionFailed, validated.RelativePath, exception);
            }
        }
    }

    private static void CopyExactly(Stream source, Stream target, long expectedBytes, string path)
    {
        var buffer = new byte[64 * 1024];
        long written = 0;
        while (true)
        {
            int read = source.Read(buffer, 0, buffer.Length);
            if (read == 0)
            {
                break;
            }

            written = checked(written + read);
            if (written > expectedBytes)
            {
                throw Error(PetPackageArchiveError.ExtractionFailed, path);
            }

            target.Write(buffer, 0, read);
        }

        if (written != expectedBytes)
        {
            throw Error(PetPackageArchiveError.ExtractionFailed, path);
        }
    }

    private string LocatePackageRoot(string extractionRoot)
    {
        if (File.Exists(Path.Combine(extractionRoot, "pet.json")))
        {
            return extractionRoot;
        }

        string[] children = Directory.GetFileSystemEntries(extractionRoot);
        if (children.Length != 1)
        {
            throw Error(PetPackageArchiveError.MultiplePackageRoots, extractionRoot);
        }

        if (!Directory.Exists(children[0]) || !File.Exists(Path.Combine(children[0], "pet.json")))
        {
            throw Error(PetPackageArchiveError.MissingPackageRoot, extractionRoot);
        }

        return children[0];
    }

    private void ValidateCompressionRatio(long compressed, long expanded, string path)
    {
        if (expanded == 0)
        {
            return;
        }

        if (compressed <= 0 ||
            (compressed <= long.MaxValue / Limits.MaximumCompressionRatio &&
             expanded > compressed * Limits.MaximumCompressionRatio))
        {
            throw Error(PetPackageArchiveError.SuspiciousCompressionRatio, path);
        }
    }

    private static bool IsLinkOrUnsupportedEntry(ZipArchiveEntry entry, bool isDirectory)
    {
        int unixType = (entry.ExternalAttributes >> 16) & 0xF000;
        bool unixTypeIsSupported = unixType == 0 ||
            (isDirectory ? unixType == 0x4000 : unixType == 0x8000);
        bool hasReparsePoint =
            (entry.ExternalAttributes & (int)FileAttributes.ReparsePoint) != 0;
        return !unixTypeIsSupported || hasReparsePoint;
    }

    private static string NormalizeEntryPath(string original, bool isDirectory)
    {
        string path = isDirectory ? original.TrimEnd('/') : original;
        if (string.IsNullOrEmpty(path) ||
            path.Contains('\\') ||
            path.Contains(':') ||
            path.StartsWith('/') ||
            path.Any(char.IsControl))
        {
            throw Error(PetPackageArchiveError.InvalidEntryPath, original);
        }

        string[] components = path.Split('/');
        if (components.Any(component => component.Length == 0 || component is "." or ".."))
        {
            throw Error(PetPackageArchiveError.InvalidEntryPath, original);
        }

        return string.Join('/', components);
    }

    private static PetPackageArchiveException Error(
        PetPackageArchiveError error,
        string detail,
        Exception? innerException = null) =>
        new(error, detail, innerException);

    private sealed record ValidatedEntry(
        ZipArchiveEntry Entry,
        string RelativePath,
        bool IsDirectory);
}
