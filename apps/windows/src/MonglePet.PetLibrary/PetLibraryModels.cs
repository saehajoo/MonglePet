using MonglePet.Packages;
using MonglePet.Settings;

namespace MonglePet.PetLibrary;

public enum PetPackageInstallMode
{
    RejectDuplicate,
    InstallSeparately,
    Replace,
}

public sealed record InstalledPetPackage(
    Guid InstallationId,
    string RootPath,
    LoadedPetPackage Package);

public sealed record PetPackageImportReview(
    string SourcePath,
    string SourceFingerprint,
    PetPackageManifest Manifest,
    bool ContainsRecommendedProfile,
    BehaviorProfile? RecommendedProfile,
    RecommendedPetProfileError? RecommendedProfileIssue,
    string? RecommendedProfileIssueDetail)
{
    public bool CanApplyRecommendedProfile => RecommendedProfile is not null;
}

public enum PetLibraryError
{
    InvalidLibraryRoot,
    DuplicatePackage,
    MissingInstallation,
    ReplacementInstallationRequired,
    PackageIdentifierMismatch,
    PackageValidationFailed,
    ReviewedContentChanged,
    FileOperationFailed,
}

public sealed class PetLibraryException : Exception
{
    public PetLibraryException(
        PetLibraryError error,
        string detail,
        Exception? innerException = null)
        : base(detail, innerException)
    {
        Error = error;
    }

    public PetLibraryError Error { get; }

    public IReadOnlyList<Guid> MatchingInstallationIds { get; init; } = [];
}

public enum PetPackageExportError
{
    InvalidDestination,
    SourcePackageChanged,
    PackageValidationFailed,
    ArchiveValidationFailed,
    ArchiveTooLarge,
    FileOperationFailed,
}

public sealed class PetPackageExportException(
    PetPackageExportError error,
    string detail,
    Exception? innerException = null) : Exception(detail, innerException)
{
    public PetPackageExportError Error { get; } = error;
}
