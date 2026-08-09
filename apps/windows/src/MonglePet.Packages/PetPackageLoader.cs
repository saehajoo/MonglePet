using System.Buffers.Binary;
using System.Text;

namespace MonglePet.Packages;

public sealed class PetPackageLoader
{
    public const long MaximumExpandedBytes = 100L * 1024 * 1024;
    public const long MaximumDecodedPixels = 64L * 1024 * 1024;

    private static readonly HashSet<string> SupportedExtensions =
        new(StringComparer.OrdinalIgnoreCase) { ".json", ".png", ".webp" };

    private readonly PetPackageManifestReader _manifestReader;

    public PetPackageLoader(PetPackageManifestReader? manifestReader = null)
    {
        _manifestReader = manifestReader ?? new PetPackageManifestReader();
    }

    public LoadedPetPackage LoadDirectory(string packageRootPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(packageRootPath);

        string rootPath;
        try
        {
            rootPath = Path.GetFullPath(packageRootPath);
        }
        catch (Exception exception) when (exception is ArgumentException or NotSupportedException)
        {
            throw LoadError(PetPackageLoadError.InvalidPackageRoot, packageRootPath, exception);
        }

        var root = new DirectoryInfo(rootPath);
        if (!root.Exists || IsReparsePoint(root))
        {
            throw LoadError(PetPackageLoadError.InvalidPackageRoot, rootPath);
        }

        ValidateContents(root);

        var manifestPath = Path.Combine(root.FullName, "pet.json");
        if (!File.Exists(manifestPath))
        {
            throw LoadError(PetPackageLoadError.MissingManifest, manifestPath);
        }

        PetPackageManifest manifest;
        using (var manifestStream = File.OpenRead(manifestPath))
        {
            manifest = _manifestReader.Read(manifestStream);
        }

        string previewPath = ResolveReferencedFile(root, manifest.PreviewPath);
        InspectedImage preview = PetPackageImageInspector.Inspect(
            previewPath,
            PetPackageImageFormat.Png,
            requiresAlpha: false);
        long decodedPixels = preview.PixelCount;

        var atlases = new Dictionary<string, LoadedPetAtlas>(StringComparer.Ordinal);
        foreach (PetPackageAtlas atlas in manifest.Atlases)
        {
            PetPackageImageFormat format = GetFormat(atlas.Path);
            string filePath = ResolveReferencedFile(root, atlas.Path);
            InspectedImage image = PetPackageImageInspector.Inspect(
                filePath,
                format,
                requiresAlpha: true);

            if (image.Width != atlas.PixelWidth || image.Height != atlas.PixelHeight)
            {
                throw LoadError(
                    PetPackageLoadError.ImageDimensionsMismatch,
                    $"{atlas.Path}: expected {atlas.PixelWidth}x{atlas.PixelHeight}, " +
                    $"decoded {image.Width}x{image.Height}.");
            }

            decodedPixels = checked(decodedPixels + image.PixelCount);
            if (decodedPixels > MaximumDecodedPixels)
            {
                throw LoadError(
                    PetPackageLoadError.DecodedPixelLimitExceeded,
                    $"Decoded image budget exceeds {MaximumDecodedPixels} pixels.");
            }

            atlases.Add(atlas.Id, new LoadedPetAtlas(atlas, filePath, format));
        }

        return new LoadedPetPackage(
            root.FullName,
            manifest,
            previewPath,
            atlases);
    }

    private static void ValidateContents(DirectoryInfo root)
    {
        long expandedBytes = 0;
        var paths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var pending = new Stack<DirectoryInfo>();
        pending.Push(root);

        while (pending.TryPop(out DirectoryInfo? directory))
        {
            FileSystemInfo[] entries;
            try
            {
                entries = directory.GetFileSystemInfos();
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
            {
                throw LoadError(PetPackageLoadError.InvalidPackageRoot, directory.FullName, exception);
            }

            foreach (FileSystemInfo entry in entries)
            {
                string relativePath = Path.GetRelativePath(root.FullName, entry.FullName)
                    .Replace('\\', '/');
                if (!paths.Add(relativePath))
                {
                    throw LoadError(PetPackageLoadError.UnsupportedFile, relativePath);
                }

                if (IsReparsePoint(entry))
                {
                    throw LoadError(PetPackageLoadError.SymbolicLink, relativePath);
                }

                if (entry is DirectoryInfo childDirectory)
                {
                    pending.Push(childDirectory);
                    continue;
                }

                if (entry is not FileInfo file ||
                    !SupportedExtensions.Contains(file.Extension))
                {
                    throw LoadError(PetPackageLoadError.UnsupportedFile, relativePath);
                }

                if (file.Length < 0 || file.Length > MaximumExpandedBytes - expandedBytes)
                {
                    throw LoadError(
                        PetPackageLoadError.PackageTooLarge,
                        $"Expanded package exceeds {MaximumExpandedBytes} bytes.");
                }

                expandedBytes += file.Length;
            }
        }
    }

    private static string ResolveReferencedFile(DirectoryInfo root, string relativePath)
    {
        string normalized = relativePath.Replace('/', Path.DirectorySeparatorChar);
        string candidate = Path.GetFullPath(Path.Combine(root.FullName, normalized));
        string rootPrefix = root.FullName.TrimEnd(Path.DirectorySeparatorChar) +
            Path.DirectorySeparatorChar;
        if (!candidate.StartsWith(rootPrefix, StringComparison.OrdinalIgnoreCase))
        {
            throw LoadError(PetPackageLoadError.MissingReferencedFile, relativePath);
        }

        string current = root.FullName;
        foreach (string component in relativePath.Split('/'))
        {
            current = Path.Combine(current, component);
            FileSystemInfo info = Directory.Exists(current)
                ? new DirectoryInfo(current)
                : new FileInfo(current);
            if (!info.Exists)
            {
                throw LoadError(PetPackageLoadError.MissingReferencedFile, relativePath);
            }

            if (IsReparsePoint(info))
            {
                throw LoadError(PetPackageLoadError.SymbolicLink, relativePath);
            }
        }

        if (!File.Exists(candidate))
        {
            throw LoadError(PetPackageLoadError.MissingReferencedFile, relativePath);
        }

        return candidate;
    }

    private static PetPackageImageFormat GetFormat(string relativePath) =>
        Path.GetExtension(relativePath).ToLowerInvariant() switch
        {
            ".png" => PetPackageImageFormat.Png,
            ".webp" => PetPackageImageFormat.WebP,
            _ => throw LoadError(PetPackageLoadError.ImageFormatMismatch, relativePath),
        };

    private static bool IsReparsePoint(FileSystemInfo info) =>
        (info.Attributes & FileAttributes.ReparsePoint) != 0;

    private static PetPackageLoadException LoadError(
        PetPackageLoadError error,
        string detail,
        Exception? innerException = null) =>
        new(error, detail, innerException);

    private readonly record struct InspectedImage(int Width, int Height, bool HasAlpha)
    {
        public long PixelCount => (long)Width * Height;
    }

    private static class PetPackageImageInspector
    {
        private static readonly byte[] PngSignature =
            [137, 80, 78, 71, 13, 10, 26, 10];

        public static InspectedImage Inspect(
            string filePath,
            PetPackageImageFormat expectedFormat,
            bool requiresAlpha)
        {
            try
            {
                using FileStream stream = File.OpenRead(filePath);
                InspectedImage image = expectedFormat switch
                {
                    PetPackageImageFormat.Png => InspectPng(stream, filePath),
                    PetPackageImageFormat.WebP => InspectWebP(stream, filePath),
                    _ => throw LoadError(PetPackageLoadError.ImageFormatMismatch, filePath),
                };

                if (image.Width <= 0 || image.Height <= 0 ||
                    image.Width > PetPackageManifestReader.MaximumImageDimension ||
                    image.Height > PetPackageManifestReader.MaximumImageDimension)
                {
                    throw LoadError(PetPackageLoadError.InvalidImage, filePath);
                }

                if (requiresAlpha && !image.HasAlpha)
                {
                    throw LoadError(PetPackageLoadError.ImageMissingAlpha, filePath);
                }

                return image;
            }
            catch (PetPackageLoadException)
            {
                throw;
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
            {
                throw LoadError(PetPackageLoadError.InvalidImage, filePath, exception);
            }
        }

        private static InspectedImage InspectPng(Stream stream, string path)
        {
            Span<byte> signature = stackalloc byte[8];
            ReadExactly(stream, signature, path);
            if (!signature.SequenceEqual(PngSignature))
            {
                throw LoadError(PetPackageLoadError.ImageFormatMismatch, path);
            }

            int width = 0;
            int height = 0;
            bool? hasAlpha = null;
            bool sawHeader = false;
            bool sawEnd = false;
            Span<byte> chunkHeader = stackalloc byte[8];
            while (stream.Position < stream.Length)
            {
                ReadExactly(stream, chunkHeader, path);
                uint length = BinaryPrimitives.ReadUInt32BigEndian(chunkHeader[..4]);
                string type = Encoding.ASCII.GetString(chunkHeader[4..]);
                if (length > stream.Length - stream.Position - 4)
                {
                    throw LoadError(PetPackageLoadError.InvalidImage, path);
                }

                if (type == "IHDR")
                {
                    if (sawHeader || length != 13)
                    {
                        throw LoadError(PetPackageLoadError.InvalidImage, path);
                    }

                    Span<byte> header = new byte[13];
                    ReadExactly(stream, header, path);
                    uint rawWidth = BinaryPrimitives.ReadUInt32BigEndian(header[..4]);
                    uint rawHeight = BinaryPrimitives.ReadUInt32BigEndian(header.Slice(4, 4));
                    if (rawWidth > int.MaxValue || rawHeight > int.MaxValue)
                    {
                        throw LoadError(PetPackageLoadError.InvalidImage, path);
                    }

                    width = (int)rawWidth;
                    height = (int)rawHeight;
                    byte colorType = header[9];
                    hasAlpha = colorType is 4 or 6;
                    sawHeader = true;
                }
                else
                {
                    if (!sawHeader)
                    {
                        throw LoadError(PetPackageLoadError.InvalidImage, path);
                    }

                    if (type == "acTL")
                    {
                        throw LoadError(PetPackageLoadError.AnimatedImage, path);
                    }

                    if (type == "tRNS")
                    {
                        hasAlpha = true;
                    }

                    stream.Seek(length, SeekOrigin.Current);
                }

                stream.Seek(4, SeekOrigin.Current);
                if (type == "IEND")
                {
                    sawEnd = true;
                    break;
                }
            }

            if (!sawHeader || !sawEnd)
            {
                throw LoadError(PetPackageLoadError.InvalidImage, path);
            }

            return new InspectedImage(width, height, hasAlpha == true);
        }

        private static InspectedImage InspectWebP(Stream stream, string path)
        {
            Span<byte> riff = stackalloc byte[12];
            ReadExactly(stream, riff, path);
            if (!riff[..4].SequenceEqual("RIFF"u8) ||
                !riff[8..].SequenceEqual("WEBP"u8))
            {
                throw LoadError(PetPackageLoadError.ImageFormatMismatch, path);
            }

            int width = 0;
            int height = 0;
            bool hasAlpha = false;
            bool sawImage = false;
            Span<byte> chunkHeader = stackalloc byte[8];
            while (stream.Position < stream.Length)
            {
                ReadExactly(stream, chunkHeader, path);
                string type = Encoding.ASCII.GetString(chunkHeader[..4]);
                uint length = BinaryPrimitives.ReadUInt32LittleEndian(chunkHeader[4..]);
                long paddedLength = length + (length & 1u);
                if (paddedLength > stream.Length - stream.Position)
                {
                    throw LoadError(PetPackageLoadError.InvalidImage, path);
                }

                if (type is "ANIM" or "ANMF")
                {
                    throw LoadError(PetPackageLoadError.AnimatedImage, path);
                }

                if (type == "VP8X" && length >= 10)
                {
                    Span<byte> header = new byte[10];
                    ReadExactly(stream, header, path);
                    if ((header[0] & 0x02) != 0)
                    {
                        throw LoadError(PetPackageLoadError.AnimatedImage, path);
                    }

                    hasAlpha |= (header[0] & 0x10) != 0;
                    width = ReadUInt24LittleEndian(header.Slice(4, 3)) + 1;
                    height = ReadUInt24LittleEndian(header.Slice(7, 3)) + 1;
                    sawImage = true;
                    stream.Seek(paddedLength - 10, SeekOrigin.Current);
                    continue;
                }

                if (type == "ALPH")
                {
                    hasAlpha = true;
                }
                else if (type == "VP8 " && length >= 10 && !sawImage)
                {
                    Span<byte> header = new byte[10];
                    ReadExactly(stream, header, path);
                    if (header[3] != 0x9D || header[4] != 0x01 || header[5] != 0x2A)
                    {
                        throw LoadError(PetPackageLoadError.InvalidImage, path);
                    }

                    width = BinaryPrimitives.ReadUInt16LittleEndian(header.Slice(6, 2)) & 0x3FFF;
                    height = BinaryPrimitives.ReadUInt16LittleEndian(header.Slice(8, 2)) & 0x3FFF;
                    sawImage = true;
                    stream.Seek(paddedLength - 10, SeekOrigin.Current);
                    continue;
                }
                else if (type == "VP8L" && length >= 5 && !sawImage)
                {
                    Span<byte> header = new byte[5];
                    ReadExactly(stream, header, path);
                    if (header[0] != 0x2F)
                    {
                        throw LoadError(PetPackageLoadError.InvalidImage, path);
                    }

                    uint bits = BinaryPrimitives.ReadUInt32LittleEndian(header[1..]);
                    width = (int)(bits & 0x3FFF) + 1;
                    height = (int)((bits >> 14) & 0x3FFF) + 1;
                    hasAlpha = true;
                    sawImage = true;
                    stream.Seek(paddedLength - 5, SeekOrigin.Current);
                    continue;
                }

                stream.Seek(paddedLength, SeekOrigin.Current);
            }

            if (!sawImage)
            {
                throw LoadError(PetPackageLoadError.InvalidImage, path);
            }

            return new InspectedImage(width, height, hasAlpha);
        }

        private static int ReadUInt24LittleEndian(ReadOnlySpan<byte> value) =>
            value[0] | (value[1] << 8) | (value[2] << 16);

        private static void ReadExactly(Stream stream, Span<byte> buffer, string path)
        {
            try
            {
                stream.ReadExactly(buffer);
            }
            catch (EndOfStreamException exception)
            {
                throw LoadError(PetPackageLoadError.InvalidImage, path, exception);
            }
        }
    }
}
