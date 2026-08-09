namespace MonglePet.Activity;

public sealed record WindowsApplicationChoice(
    string Identifier,
    string DisplayName,
    string? ExecutablePath);

public sealed record WindowsApplicationCandidate(
    string? Identifier,
    string? DisplayName,
    string? ExecutablePath,
    bool IsUserFacing);

public static class WindowsApplicationCatalogNormalizer
{
    public static IReadOnlyList<WindowsApplicationChoice> Choices(
        IEnumerable<WindowsApplicationCandidate> candidates,
        IEnumerable<string>? excludedIdentifiers = null)
    {
        ArgumentNullException.ThrowIfNull(candidates);
        var excluded = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (string value in excludedIdentifiers ?? [])
        {
            if (NormalizeIdentifier(value) is { } identifier)
            {
                excluded.Add(identifier);
            }
        }

        var choices = new Dictionary<string, ChoiceCandidate>(
            StringComparer.OrdinalIgnoreCase);
        foreach (WindowsApplicationCandidate candidate in candidates)
        {
            if (!candidate.IsUserFacing ||
                NormalizeIdentifier(candidate.Identifier) is not { } identifier ||
                excluded.Contains(identifier))
            {
                continue;
            }

            string? executablePath = NormalizePath(candidate.ExecutablePath);
            string? explicitName = NormalizeName(candidate.DisplayName);
            string displayName = explicitName ??
                NameFromPath(executablePath) ??
                identifier[(identifier.IndexOf(':') + 1)..];
            var normalized = new ChoiceCandidate(
                new WindowsApplicationChoice(identifier, displayName, executablePath),
                (explicitName is null ? 0 : 2) + (executablePath is null ? 0 : 1));

            if (!choices.TryGetValue(identifier, out ChoiceCandidate? existing) ||
                normalized.Preference > existing.Preference)
            {
                choices[identifier] = normalized;
            }
        }

        return choices.Values
            .Select(value => value.Choice)
            .OrderBy(value => value.DisplayName, StringComparer.CurrentCultureIgnoreCase)
            .ThenBy(value => value.Identifier, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    public static string? NormalizeIdentifier(string? value)
    {
        string normalized = value?.Trim() ?? string.Empty;
        int separator = normalized.IndexOf(':');
        if (separator <= 0 || separator == normalized.Length - 1)
        {
            return null;
        }

        string prefix = normalized[..separator].ToLowerInvariant();
        string identifier = normalized[(separator + 1)..].Trim().ToLowerInvariant();
        if (prefix is not ("pfn" or "exe") ||
            identifier.Length == 0 ||
            identifier.Any(char.IsWhiteSpace) ||
            identifier.Contains('/') ||
            identifier.Contains('\\'))
        {
            return null;
        }

        return $"{prefix}:{identifier}";
    }

    private static string? NormalizeName(string? value)
    {
        string normalized = value?.Trim() ?? string.Empty;
        return normalized.Length == 0 ? null : normalized;
    }

    private static string? NormalizePath(string? value)
    {
        string normalized = value?.Trim() ?? string.Empty;
        return normalized.Length == 0 ? null : normalized;
    }

    private static string? NameFromPath(string? value)
    {
        if (value is null)
        {
            return null;
        }

        try
        {
            string name = Path.GetFileNameWithoutExtension(value);
            return string.IsNullOrWhiteSpace(name) ? null : name;
        }
        catch (ArgumentException)
        {
            return null;
        }
    }

    private sealed record ChoiceCandidate(
        WindowsApplicationChoice Choice,
        int Preference);
}
