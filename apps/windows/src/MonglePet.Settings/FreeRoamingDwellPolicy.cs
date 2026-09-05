namespace MonglePet.Settings;

public static class FreeRoamingDwellPolicy
{
    public static long ResolveMinimum(
        long maximumMilliseconds,
        FreeRoamingDwellMode dwellMode,
        long storedMinimumMilliseconds,
        long? editedMinimumMilliseconds)
    {
        if (maximumMilliseconds is < AppSettingsLimits.MinimumFreeRoamingDwellMilliseconds or
            > AppSettingsLimits.MaximumFreeRoamingDwellMilliseconds)
        {
            throw new ArgumentOutOfRangeException(nameof(maximumMilliseconds));
        }

        long requestedMinimum = dwellMode == FreeRoamingDwellMode.Random
            ? editedMinimumMilliseconds ?? storedMinimumMilliseconds
            : storedMinimumMilliseconds;
        return Math.Clamp(
            requestedMinimum,
            AppSettingsLimits.MinimumFreeRoamingDwellMilliseconds,
            maximumMilliseconds);
    }
}
