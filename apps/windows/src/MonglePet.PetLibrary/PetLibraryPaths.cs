namespace MonglePet.PetLibrary;

public static class PetLibraryPaths
{
    public static string FromAppLocalDataRoot(string appLocalDataRoot)
    {
        if (string.IsNullOrWhiteSpace(appLocalDataRoot))
        {
            throw new PetLibraryException(
                PetLibraryError.InvalidLibraryRoot,
                "The application-local data root is unavailable.");
        }

        return Path.Combine(Path.GetFullPath(appLocalDataRoot), "MonglePet", "Library");
    }
}
