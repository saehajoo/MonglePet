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

public enum PetPackageImportDisposition
{
    Compatible,
    LegacyWithoutCreatorSettings,
    UpdateRequiredForMinimumVersion,
    UpdateRequiredForCreatorSettings,
    InvalidCreatorSettings,
}

public sealed record PetPackageImportReview(
    string SourcePath,
    string SourceFingerprint,
    PetPackageManifest Manifest,
    bool ContainsRecommendedProfile,
    BehaviorProfile? RecommendedProfile,
    RecommendedPetProfileError? RecommendedProfileIssue,
    string? RecommendedProfileIssueDetail,
    RemotePetSemanticVersion? CurrentAppVersion = null,
    RemotePetSemanticVersion? PublishedMinimumAppVersion = null,
    PetCompatibilityAdvisory? CompatibilityAdvisory = null,
    PortablePetDisplaySettings? RecommendedDisplay = null,
    bool RecommendedProfileIncludesDisplay = false)
{
    public bool CanApplyRecommendedProfile => RecommendedProfile is not null;

    public PetPackageImportDisposition Disposition
    {
        get
        {
            if (CompatibilityAdvisory?.RecommendsUpdate == true)
            {
                return PetPackageImportDisposition.UpdateRequiredForMinimumVersion;
            }
            if (RecommendedProfileIssue == RecommendedPetProfileError.UnsupportedSchema)
            {
                return PetPackageImportDisposition.UpdateRequiredForCreatorSettings;
            }
            if (ContainsRecommendedProfile && RecommendedProfile is null)
            {
                return PetPackageImportDisposition.InvalidCreatorSettings;
            }
            return RecommendedProfile is null
                ? PetPackageImportDisposition.LegacyWithoutCreatorSettings
                : PetPackageImportDisposition.Compatible;
        }
    }

    public bool CanInstall => Disposition is
        PetPackageImportDisposition.Compatible or
        PetPackageImportDisposition.LegacyWithoutCreatorSettings;

    public bool RequiresUpdate => Disposition is
        PetPackageImportDisposition.UpdateRequiredForMinimumVersion or
        PetPackageImportDisposition.UpdateRequiredForCreatorSettings;
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
    ImportBlocked,
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
