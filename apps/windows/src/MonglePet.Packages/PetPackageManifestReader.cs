using System.Diagnostics.CodeAnalysis;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace MonglePet.Packages;

public sealed partial class PetPackageManifestReader
{
    public const int MaximumManifestBytes = 1 * 1024 * 1024;
    public const int MaximumImageDimension = 8_192;
    public const int MaximumMotionCount = 100;
    public const int MaximumFrameCount = 1_000;
    public const int MinimumFrameDurationMilliseconds = 16;
    public const int MaximumFrameDurationMilliseconds = 60_000;

    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        PropertyNameCaseInsensitive = false,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    public PetPackageManifest Read(Stream stream)
    {
        ArgumentNullException.ThrowIfNull(stream);

        using var buffer = ReadWithLimit(stream, MaximumManifestBytes);
        PetPackageManifest manifest;
        try
        {
            manifest = JsonSerializer.Deserialize<PetPackageManifest>(
                buffer.ToArray(),
                SerializerOptions) ?? throw InvalidJson();
        }
        catch (JsonException exception)
        {
            throw InvalidJson(exception);
        }

        Validate(manifest);
        return manifest;
    }

    private static MemoryStream ReadWithLimit(Stream source, int maximumBytes)
    {
        var result = new MemoryStream();
        var chunk = new byte[16 * 1024];
        var total = 0;

        while (true)
        {
            var remaining = maximumBytes + 1 - total;
            var count = source.Read(chunk, 0, Math.Min(chunk.Length, remaining));
            if (count == 0)
            {
                result.Position = 0;
                return result;
            }

            total += count;
            if (total > maximumBytes)
            {
                result.Dispose();
                throw new PetPackageManifestException(
                    PetPackageManifestError.ManifestTooLarge,
                    $"pet.json exceeds {maximumBytes} bytes.");
            }

            result.Write(chunk, 0, count);
        }
    }

    private static void Validate(PetPackageManifest manifest)
    {
        if (manifest.FormatVersion != 1)
        {
            throw new PetPackageManifestException(
                PetPackageManifestError.UnsupportedFormatVersion,
                $"Unsupported formatVersion: {manifest.FormatVersion}.");
        }

        RequireText(manifest.Id, "id");
        RequireText(manifest.DisplayName, "displayName");
        RequireText(manifest.Version, "version");
        RequireText(manifest.Author, "author");
        RequireText(manifest.PreviewPath, "previewPath");
        ValidateRelativeImagePath(manifest.PreviewPath, [".png"]);
        ValidateCompatibility(manifest.Compatibility);

        if (manifest.Atlases is null || manifest.Atlases.Count == 0)
        {
            ThrowLimit("At least one atlas is required.");
        }

        if (manifest.Motions is null || manifest.Motions.Count == 0)
        {
            ThrowLimit("At least one motion is required.");
        }

        if (manifest.Motions.Count > MaximumMotionCount)
        {
            ThrowLimit($"Motion count exceeds {MaximumMotionCount}.");
        }

        var atlasIds = new HashSet<string>(StringComparer.Ordinal);
        var resourcePaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            NormalizeRelativePath(manifest.PreviewPath),
        };
        var atlasSizes = new Dictionary<string, (int Width, int Height)>(
            StringComparer.Ordinal);

        foreach (var atlas in manifest.Atlases)
        {
            RequireText(atlas.Id, "atlases.id");
            RequireText(atlas.Path, "atlases.path");
            if (!atlasIds.Add(atlas.Id))
            {
                ThrowDuplicateIdentifier("atlas", atlas.Id);
            }

            var normalizedPath = ValidateRelativeImagePath(
                atlas.Path,
                [".png", ".webp"]);
            if (!resourcePaths.Add(normalizedPath))
            {
                throw new PetPackageManifestException(
                    PetPackageManifestError.DuplicateResourcePath,
                    $"Duplicate resource path: {atlas.Path}.");
            }

            if (atlas.PixelWidth <= 0 ||
                atlas.PixelHeight <= 0 ||
                atlas.PixelWidth > MaximumImageDimension ||
                atlas.PixelHeight > MaximumImageDimension)
            {
                ThrowLimit($"Invalid atlas dimensions for {atlas.Id}.");
            }

            atlasSizes.Add(atlas.Id, (atlas.PixelWidth, atlas.PixelHeight));
        }

        var motionIds = new HashSet<string>(StringComparer.Ordinal);
        var frameCount = 0;
        foreach (var motion in manifest.Motions)
        {
            RequireText(motion.Id, "motions.id");
            RequireText(motion.Atlas, "motions.atlas");
            if (!motionIds.Add(motion.Id))
            {
                ThrowDuplicateIdentifier("motion", motion.Id);
            }

            if (!atlasSizes.TryGetValue(motion.Atlas, out var atlasSize))
            {
                throw new PetPackageManifestException(
                    PetPackageManifestError.MissingAtlas,
                    $"Motion {motion.Id} references missing atlas {motion.Atlas}.");
            }

            if (motion.Frames is null || motion.Frames.Count == 0)
            {
                ThrowInvalidFrame(motion.Id, 0);
            }

            frameCount += motion.Frames.Count;
            if (frameCount > MaximumFrameCount)
            {
                ThrowLimit($"Frame count exceeds {MaximumFrameCount}.");
            }

            for (var index = 0; index < motion.Frames.Count; index++)
            {
                var frame = motion.Frames[index];
                var isContained = frame.X >= 0 &&
                    frame.Y >= 0 &&
                    frame.Width > 0 &&
                    frame.Height > 0 &&
                    frame.Width <= atlasSize.Width &&
                    frame.Height <= atlasSize.Height &&
                    frame.X <= atlasSize.Width - frame.Width &&
                    frame.Y <= atlasSize.Height - frame.Height;
                var hasValidDuration = frame.DurationMs is >=
                    MinimumFrameDurationMilliseconds and <=
                    MaximumFrameDurationMilliseconds;

                if (!isContained || !hasValidDuration)
                {
                    ThrowInvalidFrame(motion.Id, index);
                }
            }
        }

        var defaultMotion = manifest.DefaultMotion ?? "idle";
        RequireText(defaultMotion, "defaultMotion");
        if (!motionIds.Contains(defaultMotion))
        {
            throw new PetPackageManifestException(
                PetPackageManifestError.MissingDefaultMotion,
                $"Default motion does not exist: {defaultMotion}.");
        }
    }

    private static void ValidateCompatibility(PetPackageCompatibility? compatibility)
    {
        if (compatibility is null)
        {
            return;
        }

        ValidateSemanticVersion(
            compatibility.CreatedWithMonglePetVersion,
            "createdWithMonglePetVersion");
        ValidateSemanticVersion(
            compatibility.MinimumMonglePetVersion,
            "minimumMonglePetVersion");
    }

    private static void ValidateSemanticVersion(string? value, string field)
    {
        if (value is null)
        {
            return;
        }

        if (!SemanticVersionPattern().IsMatch(value))
        {
            throw new PetPackageManifestException(
                PetPackageManifestError.InvalidCompatibilityVersion,
                $"Invalid {field}: {value}.");
        }
    }

    private static string ValidateRelativeImagePath(
        string value,
        string[] allowedExtensions)
    {
        var normalized = NormalizeRelativePath(value);
        var extension = Path.GetExtension(normalized);
        if (!allowedExtensions.Contains(extension, StringComparer.OrdinalIgnoreCase))
        {
            throw new PetPackageManifestException(
                PetPackageManifestError.UnsupportedImageExtension,
                $"Unsupported image extension: {value}.");
        }

        return normalized;
    }

    private static string NormalizeRelativePath(string value)
    {
        if (string.IsNullOrWhiteSpace(value) ||
            value != value.Trim() ||
            value.Contains('\\') ||
            value.Contains(':') ||
            value.StartsWith('/') ||
            Path.IsPathRooted(value))
        {
            ThrowInvalidPath(value);
        }

        var segments = value.Split('/');
        if (segments.Any(segment =>
                segment.Length == 0 || segment is "." or ".." ||
                segment.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0))
        {
            ThrowInvalidPath(value);
        }

        return string.Join('/', segments);
    }

    private static void RequireText(string? value, string field)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new PetPackageManifestException(
                PetPackageManifestError.EmptyRequiredField,
                $"Required field is empty: {field}.");
        }
    }

    [DoesNotReturn]
    private static void ThrowInvalidPath(string value) =>
        throw new PetPackageManifestException(
            PetPackageManifestError.InvalidRelativePath,
            $"Unsafe package-relative path: {value}.");

    [DoesNotReturn]
    private static void ThrowLimit(string detail) =>
        throw new PetPackageManifestException(
            PetPackageManifestError.LimitExceeded,
            detail);

    [DoesNotReturn]
    private static void ThrowDuplicateIdentifier(string kind, string id) =>
        throw new PetPackageManifestException(
            PetPackageManifestError.DuplicateIdentifier,
            $"Duplicate {kind} identifier: {id}.");

    [DoesNotReturn]
    private static void ThrowInvalidFrame(string motionId, int index) =>
        throw new PetPackageManifestException(
            PetPackageManifestError.InvalidFrame,
            $"Invalid frame {index} in motion {motionId}.");

    private static PetPackageManifestException InvalidJson(
        Exception? innerException = null) =>
        new(
            PetPackageManifestError.InvalidJson,
            "pet.json is not a valid MonglePet manifest.",
            innerException);

    [GeneratedRegex("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$", RegexOptions.CultureInvariant)]
    private static partial Regex SemanticVersionPattern();
}
