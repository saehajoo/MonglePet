namespace MonglePet.Settings;

public enum AppSettingsLoadSource
{
    Defaults,
    File,
    Recovered,
    Migrated,
    UnsupportedLegacySchema,
    NewerSchema,
}

public enum AppSettingsError
{
    InvalidSettingsPath,
    InvalidSettings,
    WritingDisabled,
    FileOperationFailed,
}

public sealed record AppSettingsLoadResult(
    Guid? SelectedPetInstallationId,
    AppSettingsLoadSource Source,
    IReadOnlyList<string> Issues,
    bool IsWritingEnabled,
    int? PreservedSchemaVersion = null,
    int? MigratedFromSchemaVersion = null,
    AppSettings? Settings = null,
    IReadOnlyList<SettingsRecoveryIssue>? RecoveryIssues = null);

public sealed class AppSettingsException : Exception
{
    public AppSettingsException(
        AppSettingsError error,
        string detail,
        Exception? innerException = null)
        : base(detail, innerException)
    {
        Error = error;
    }

    public AppSettingsError Error { get; }
}
