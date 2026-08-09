namespace MonglePet.Packages;

public sealed record PetPackageManifest(
    int FormatVersion,
    string Id,
    string DisplayName,
    string Version,
    string Author,
    string? Description,
    string PreviewPath,
    string? DefaultMotion,
    IReadOnlyList<PetPackageAtlas> Atlases,
    IReadOnlyList<PetPackageMotion> Motions,
    PetPackageCompatibility? Compatibility = null);

public sealed record PetPackageCompatibility(
    string? CreatedWithMonglePetVersion,
    string? MinimumMonglePetVersion);

public sealed record PetPackageAtlas(
    string Id,
    string Path,
    int PixelWidth,
    int PixelHeight);

public sealed record PetPackageMotion(
    string Id,
    string Atlas,
    bool Loop,
    IReadOnlyList<PetPackageFrame> Frames);

public sealed record PetPackageFrame(
    int X,
    int Y,
    int Width,
    int Height,
    int DurationMs);

public enum PetPackageManifestError
{
    ManifestTooLarge,
    InvalidJson,
    UnsupportedFormatVersion,
    EmptyRequiredField,
    InvalidRelativePath,
    UnsupportedImageExtension,
    LimitExceeded,
    DuplicateIdentifier,
    DuplicateResourcePath,
    MissingAtlas,
    MissingDefaultMotion,
    InvalidFrame,
    InvalidCompatibilityVersion,
}

public sealed class PetPackageManifestException : Exception
{
    public PetPackageManifestException(
        PetPackageManifestError error,
        string detail,
        Exception? innerException = null)
        : base(detail, innerException)
    {
        Error = error;
    }

    public PetPackageManifestError Error { get; }
}

public sealed record LoadedPetPackage(
    string PackageRootPath,
    PetPackageManifest Manifest,
    string PreviewFilePath,
    IReadOnlyDictionary<string, LoadedPetAtlas> Atlases)
{
    public string DefaultMotionId => Manifest.DefaultMotion ?? "idle";

    public PetPackageMotion DefaultMotion => Manifest.Motions.Single(
        motion => string.Equals(motion.Id, DefaultMotionId, StringComparison.Ordinal));
}

public sealed record LoadedPetAtlas(
    PetPackageAtlas Definition,
    string FilePath,
    PetPackageImageFormat Format);

public enum PetPackageImageFormat
{
    Png,
    WebP,
}

public enum PetPackageLoadError
{
    InvalidPackageRoot,
    MissingManifest,
    UnsupportedFile,
    SymbolicLink,
    PackageTooLarge,
    MissingReferencedFile,
    InvalidImage,
    ImageFormatMismatch,
    AnimatedImage,
    ImageDimensionsMismatch,
    ImageMissingAlpha,
    DecodedPixelLimitExceeded,
}

public sealed class PetPackageLoadException : Exception
{
    public PetPackageLoadException(
        PetPackageLoadError error,
        string detail,
        Exception? innerException = null)
        : base(detail, innerException)
    {
        Error = error;
    }

    public PetPackageLoadError Error { get; }
}
