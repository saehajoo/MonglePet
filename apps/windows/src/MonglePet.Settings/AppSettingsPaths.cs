namespace MonglePet.Settings;

public static class AppSettingsPaths
{
    public static string FromAppLocalDataRoot(string appLocalDataRoot)
    {
        if (string.IsNullOrWhiteSpace(appLocalDataRoot))
        {
            throw new AppSettingsException(
                AppSettingsError.InvalidSettingsPath,
                "The application-local data root is unavailable.");
        }

        try
        {
            return Path.Combine(
                Path.GetFullPath(appLocalDataRoot),
                "MonglePet",
                "settings.json");
        }
        catch (Exception exception) when (exception is ArgumentException or NotSupportedException)
        {
            throw new AppSettingsException(
                AppSettingsError.InvalidSettingsPath,
                appLocalDataRoot,
                exception);
        }
    }
}
