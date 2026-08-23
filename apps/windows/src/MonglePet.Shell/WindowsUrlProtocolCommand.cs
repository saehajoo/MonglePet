namespace MonglePet.Shell;

public static class WindowsUrlProtocolCommand
{
    public const string Scheme = "monglepet";
    private const string WindowsInstallPrefix = "monglepet://install/?";
    private const string ContractInstallPrefix = "monglepet://install?";

    public static string Create(string executablePath)
    {
        if (string.IsNullOrWhiteSpace(executablePath))
        {
            throw new ArgumentException(
                "The executable path is unavailable.",
                nameof(executablePath));
        }

        string fullPath = Path.GetFullPath(executablePath);
        if (fullPath.Contains('"', StringComparison.Ordinal))
        {
            throw new ArgumentException(
                "The executable path contains a quote.",
                nameof(executablePath));
        }

        return $"\"{fullPath}\" \"%1\"";
    }

    public static bool Matches(string? storedCommand, string executablePath) =>
        !string.IsNullOrWhiteSpace(storedCommand) &&
        string.Equals(
            storedCommand.Trim(),
            Create(executablePath),
            StringComparison.OrdinalIgnoreCase);

    public static bool TryGetProtocolUri(
        string? argument,
        out Uri? protocolUri)
    {
        protocolUri = null;
        string value = argument?.Trim() ?? string.Empty;
        if (value.Length >= 2 && value[0] == '"' && value[^1] == '"')
        {
            value = value[1..^1];
        }

        if (!Uri.TryCreate(value, UriKind.Absolute, out Uri? candidate) ||
            !candidate.Scheme.Equals(Scheme, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        protocolUri = candidate;
        return true;
    }

    public static string NormalizeForApplication(Uri protocolUri)
    {
        ArgumentNullException.ThrowIfNull(protocolUri);
        string value = protocolUri.OriginalString;
        return value.StartsWith(WindowsInstallPrefix, StringComparison.OrdinalIgnoreCase)
            ? ContractInstallPrefix + value[WindowsInstallPrefix.Length..]
            : value;
    }

    public static bool TryGetProtocolUri(
        IEnumerable<string> arguments,
        out Uri? protocolUri)
    {
        ArgumentNullException.ThrowIfNull(arguments);
        protocolUri = null;
        string[] values = arguments.ToArray();
        if (values.Length != 1 ||
            !TryGetProtocolUri(values[0], out Uri? candidate))
        {
            return false;
        }

        protocolUri = candidate;
        return true;
    }
}
