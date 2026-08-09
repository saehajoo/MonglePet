namespace MonglePet.Activity;

public static class WindowsApplicationIdentifier
{
    public static string? FromPackageFamilyName(string? packageFamilyName) =>
        Normalize("pfn", packageFamilyName);

    public static string? FromExecutablePath(string? executablePath)
    {
        if (string.IsNullOrWhiteSpace(executablePath))
        {
            return null;
        }

        string fileName;
        try
        {
            fileName = Path.GetFileName(executablePath.Trim());
        }
        catch (ArgumentException)
        {
            return null;
        }

        return Normalize("exe", fileName);
    }

    private static string? Normalize(string prefix, string? value)
    {
        string? normalized = value?.Trim();
        return string.IsNullOrWhiteSpace(normalized)
            ? null
            : $"{prefix}:{normalized.ToLowerInvariant()}";
    }
}
