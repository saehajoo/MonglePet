namespace MonglePet.Shell;

public static class WindowsRunAtLoginCommand
{
    public static string Create(string executablePath)
    {
        string normalized = NormalizeExecutablePath(executablePath);
        return $"\"{normalized}\" --startup";
    }

    public static bool Matches(string? storedCommand, string executablePath)
    {
        if (string.IsNullOrWhiteSpace(storedCommand))
        {
            return false;
        }

        return string.Equals(
            storedCommand.Trim(),
            Create(executablePath),
            StringComparison.OrdinalIgnoreCase);
    }

    public static bool IsStartupLaunch(IEnumerable<string> arguments)
    {
        ArgumentNullException.ThrowIfNull(arguments);
        return arguments.Any(argument => string.Equals(
            argument,
            "--startup",
            StringComparison.OrdinalIgnoreCase));
    }

    private static string NormalizeExecutablePath(string executablePath)
    {
        if (string.IsNullOrWhiteSpace(executablePath))
        {
            throw new ArgumentException("The executable path is unavailable.", nameof(executablePath));
        }

        string fullPath = Path.GetFullPath(executablePath);
        if (fullPath.Contains('"', StringComparison.Ordinal))
        {
            throw new ArgumentException("The executable path contains a quote.", nameof(executablePath));
        }

        return fullPath;
    }
}
