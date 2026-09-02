namespace MonglePet.Settings;

public static class FreeRoamingDwellPolicy
{
    public static long ResolveMinimum(
        long maximumMilliseconds,
        bool randomizesDwell,
        long storedMinimumMilliseconds,
        long? editedMinimumMilliseconds)
    {
        if (maximumMilliseconds is < AppSettingsLimits.MinimumFreeRoamingDwellMilliseconds or
            > AppSettingsLimits.MaximumFreeRoamingDwellMilliseconds)
        {
            throw new ArgumentOutOfRangeException(nameof(maximumMilliseconds));
        }

        long requestedMinimum = randomizesDwell
            ? editedMinimumMilliseconds ?? storedMinimumMilliseconds
            : storedMinimumMilliseconds;
        return Math.Clamp(
            requestedMinimum,
            AppSettingsLimits.MinimumFreeRoamingDwellMilliseconds,
            maximumMilliseconds);
    }
}
