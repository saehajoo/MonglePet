using System.Globalization;
using System.Text.RegularExpressions;
using MonglePet.Packages;

namespace MonglePet.PetLibrary;

public enum RemotePetImportEnvironment
{
    Development,
    Production,
}

public enum RemotePetImportError
{
    UnsupportedWebUrl,
    InvalidDeepLink,
    InvalidServerResponse,
    ServerRejected,
    MetadataMismatch,
    PackageTooLarge,
    PackageSizeMismatch,
    ChecksumMismatch,
    NetworkUnavailable,
    Timeout,
    ConnectionFailed,
    TlsFailure,
}

public sealed record PetCompatibilityAdvisory(
    RemotePetSemanticVersion CurrentAppVersion,
    RemotePetSemanticVersion? CreatedWithAppVersion,
    RemotePetSemanticVersion? RequiredMinimumAppVersion)
{
    public const string DownloadPageUrl =
        "https://mapleroom.kr/monglepet/download";

    public bool RecommendsUpdate =>
        RequiredMinimumAppVersion is { } required && CurrentAppVersion < required;

    public bool WasCreatedWithNewerApp =>
        CreatedWithAppVersion is { } created && CurrentAppVersion < created;

    public bool HasWarning => RecommendsUpdate || WasCreatedWithNewerApp;

    public static PetCompatibilityAdvisory Create(
        PetPackageCompatibility? compatibility,
        RemotePetSemanticVersion currentAppVersion,
        RemotePetSemanticVersion? publishedMinimumAppVersion = null)
    {
        RemotePetSemanticVersion? created = ParseOptional(
            compatibility?.CreatedWithMonglePetVersion);
        RemotePetSemanticVersion? manifestMinimum = ParseOptional(
            compatibility?.MinimumMonglePetVersion);
        RemotePetSemanticVersion? required = manifestMinimum switch
        {
            { } manifest when publishedMinimumAppVersion is { } published =>
                manifest >= published ? manifest : published,
            { } manifest => manifest,
            _ => publishedMinimumAppVersion,
        };
        return new PetCompatibilityAdvisory(
            currentAppVersion,
            created,
            required);
    }

    private static RemotePetSemanticVersion? ParseOptional(string? value) =>
        RemotePetSemanticVersion.TryParse(value, out RemotePetSemanticVersion parsed)
            ? parsed
            : null;
}

public sealed class RemotePetImportException : Exception
{
    public RemotePetImportException(
        RemotePetImportError error,
        string message,
        Exception? innerException = null,
        RemotePetSemanticVersion? requiredVersion = null,
        RemotePetSemanticVersion? currentVersion = null,
        long? maximumBytes = null)
        : base(message, innerException)
    {
        Error = error;
        RequiredVersion = requiredVersion;
        CurrentVersion = currentVersion;
        MaximumBytes = maximumBytes;
    }

    public RemotePetImportError Error { get; }

    public RemotePetSemanticVersion? RequiredVersion { get; }

    public RemotePetSemanticVersion? CurrentVersion { get; }

    public long? MaximumBytes { get; }

    internal static RemotePetImportException UnsupportedWebUrl() =>
        new(
            RemotePetImportError.UnsupportedWebUrl,
            "지원하는 MonglePet 펫 상세 주소를 입력해 주세요.");

    internal static RemotePetImportException InvalidDeepLink() =>
        new(
            RemotePetImportError.InvalidDeepLink,
            "MonglePet에서 열기 링크가 올바르지 않습니다.");

    internal static RemotePetImportException InvalidServerResponse(Exception? inner = null) =>
        new(
            RemotePetImportError.InvalidServerResponse,
            "펫 서버의 응답을 확인할 수 없습니다. 잠시 뒤 다시 시도해 주세요.",
            inner);
}

public readonly record struct RemotePetSemanticVersion(
    int Major,
    int Minor,
    int Patch) : IComparable<RemotePetSemanticVersion>
{
    public static bool TryParse(string? value, out RemotePetSemanticVersion version)
    {
        version = default;
        if (string.IsNullOrEmpty(value))
        {
            return false;
        }

        string[] components = value.Split('.');
        if (components.Length != 3 || components.Any(component =>
                component.Length == 0 ||
                (component.Length > 1 && component[0] == '0') ||
                component.Any(character => character is < '0' or > '9')))
        {
            return false;
        }

        if (!int.TryParse(components[0], NumberStyles.None, CultureInfo.InvariantCulture, out int major) ||
            !int.TryParse(components[1], NumberStyles.None, CultureInfo.InvariantCulture, out int minor) ||
            !int.TryParse(components[2], NumberStyles.None, CultureInfo.InvariantCulture, out int patch))
        {
            return false;
        }

        version = new RemotePetSemanticVersion(major, minor, patch);
        return true;
    }

    public int CompareTo(RemotePetSemanticVersion other)
    {
        int comparison = Major.CompareTo(other.Major);
        if (comparison != 0)
        {
            return comparison;
        }

        comparison = Minor.CompareTo(other.Minor);
        return comparison != 0 ? comparison : Patch.CompareTo(other.Patch);
    }

    public static bool operator <(RemotePetSemanticVersion left, RemotePetSemanticVersion right) =>
        left.CompareTo(right) < 0;

    public static bool operator >(RemotePetSemanticVersion left, RemotePetSemanticVersion right) =>
        left.CompareTo(right) > 0;

    public static bool operator <=(RemotePetSemanticVersion left, RemotePetSemanticVersion right) =>
        left.CompareTo(right) <= 0;

    public static bool operator >=(RemotePetSemanticVersion left, RemotePetSemanticVersion right) =>
        left.CompareTo(right) >= 0;

    public override string ToString() => $"{Major}.{Minor}.{Patch}";
}

public sealed record RemotePetImportSource(
    RemotePetImportEnvironment Environment,
    string PetSlug)
{
    private static readonly Regex DetailPathPattern = new(
        "^/monglepet/pets/(?<slug>[a-z0-9-]{1,128})/?$",
        RegexOptions.CultureInvariant);

    public string WebHost => Environment switch
    {
        RemotePetImportEnvironment.Development => "dev.mapleroom.kr",
        RemotePetImportEnvironment.Production => "mapleroom.kr",
        _ => throw new InvalidOperationException("Unknown remote pet environment."),
    };

    public Uri ApiBaseUri => Environment switch
    {
        RemotePetImportEnvironment.Development => new("https://dev-api.mapleroom.kr/api/v1/"),
        RemotePetImportEnvironment.Production => new("https://api.mapleroom.kr/api/v1/"),
        _ => throw new InvalidOperationException("Unknown remote pet environment."),
    };

    public Uri CanonicalWebUri =>
        new($"https://{WebHost}/monglepet/pets/{PetSlug}");

    public Uri DetailApiUri =>
        new(ApiBaseUri, $"monglepet/pets/{PetSlug}");

    public static RemotePetImportSource Parse(string userInput)
    {
        string value = userInput?.Trim() ?? string.Empty;
        if (!TrySplitAbsoluteUri(value, out string scheme, out string authority, out string rawPath) ||
            !scheme.Equals("https", StringComparison.OrdinalIgnoreCase) ||
            !Uri.TryCreate(value, UriKind.Absolute, out Uri? uri) ||
            !string.IsNullOrEmpty(uri.UserInfo))
        {
            throw RemotePetImportException.UnsupportedWebUrl();
        }

        RemotePetImportEnvironment environment;
        if (authority.Equals("dev.mapleroom.kr", StringComparison.OrdinalIgnoreCase))
        {
            environment = RemotePetImportEnvironment.Development;
        }
        else if (authority.Equals("mapleroom.kr", StringComparison.OrdinalIgnoreCase))
        {
            environment = RemotePetImportEnvironment.Production;
        }
        else
        {
            throw RemotePetImportException.UnsupportedWebUrl();
        }

        Match pathMatch = DetailPathPattern.Match(rawPath);
        if (!pathMatch.Success ||
            !uri.Host.Equals(authority, StringComparison.OrdinalIgnoreCase) ||
            !uri.AbsolutePath.Equals(rawPath, StringComparison.Ordinal))
        {
            throw RemotePetImportException.UnsupportedWebUrl();
        }

        return new RemotePetImportSource(environment, pathMatch.Groups["slug"].Value);
    }

    internal static bool TrySplitAbsoluteUri(
        string value,
        out string scheme,
        out string authority,
        out string rawPath)
    {
        scheme = string.Empty;
        authority = string.Empty;
        rawPath = string.Empty;

        int separator = value.IndexOf("://", StringComparison.Ordinal);
        if (separator <= 0)
        {
            return false;
        }

        scheme = value[..separator];
        int authorityStart = separator + 3;
        int authorityEnd = value.IndexOfAny(['/', '?', '#'], authorityStart);
        if (authorityEnd < 0)
        {
            authorityEnd = value.Length;
        }

        if (authorityEnd == authorityStart)
        {
            return false;
        }

        authority = value[authorityStart..authorityEnd];
        int pathEnd = value.IndexOfAny(['?', '#'], authorityEnd);
        if (pathEnd < 0)
        {
            pathEnd = value.Length;
        }

        rawPath = authorityEnd < value.Length && value[authorityEnd] == '/'
            ? value[authorityEnd..pathEnd]
            : string.Empty;
        return true;
    }
}

public sealed record RemotePetImportDeepLink(RemotePetImportSource Source)
{
    public static RemotePetImportDeepLink Parse(string deepLink)
    {
        string value = deepLink?.Trim() ?? string.Empty;
        if (!RemotePetImportSource.TrySplitAbsoluteUri(
                value,
                out string scheme,
                out string authority,
                out string rawPath) ||
            !scheme.Equals("monglepet", StringComparison.OrdinalIgnoreCase) ||
            !authority.Equals("install", StringComparison.OrdinalIgnoreCase) ||
            rawPath.Length != 0 ||
            value.Contains('#'))
        {
            throw RemotePetImportException.InvalidDeepLink();
        }

        int queryStart = value.IndexOf('?');
        if (queryStart < 0)
        {
            throw RemotePetImportException.InvalidDeepLink();
        }

        string query = value[(queryStart + 1)..];
        string[] pairs = query.Split('&');
        if (pairs.Length != 1)
        {
            throw RemotePetImportException.InvalidDeepLink();
        }

        int equals = pairs[0].IndexOf('=');
        if (equals <= 0 ||
            !pairs[0][..equals].Equals("url", StringComparison.Ordinal) ||
            !TryUnescape(pairs[0][(equals + 1)..], out string detailUrl))
        {
            throw RemotePetImportException.InvalidDeepLink();
        }

        try
        {
            return new RemotePetImportDeepLink(RemotePetImportSource.Parse(detailUrl));
        }
        catch (RemotePetImportException exception)
            when (exception.Error == RemotePetImportError.UnsupportedWebUrl)
        {
            throw RemotePetImportException.InvalidDeepLink();
        }
    }

    private static bool TryUnescape(string value, out string unescaped)
    {
        unescaped = string.Empty;
        for (int index = 0; index < value.Length; index++)
        {
            if (value[index] != '%')
            {
                continue;
            }

            if (index + 2 >= value.Length ||
                !Uri.IsHexDigit(value[index + 1]) ||
                !Uri.IsHexDigit(value[index + 2]))
            {
                return false;
            }

            index += 2;
        }

        try
        {
            unescaped = Uri.UnescapeDataString(value.Replace("+", "%2B", StringComparison.Ordinal));
            return unescaped.Length > 0;
        }
        catch (UriFormatException)
        {
            return false;
        }
    }
}

public sealed record RemotePetImportInteractionState(
    string UserInput,
    bool IsBusy,
    string? ErrorMessage,
    bool IsRetry)
{
    public static RemotePetImportInteractionState Initial { get; } =
        new(string.Empty, false, null, false);

    public string ActionText => IsRetry ? "다시 시도" : "주소에서 가져오기";

    public RemotePetImportInteractionState WithInput(string value) =>
        value == UserInput
            ? this
            : this with
            {
                UserInput = value,
                ErrorMessage = null,
                IsRetry = false,
            };

    public bool TryBegin(out RemotePetImportInteractionState next)
    {
        if (IsBusy)
        {
            next = this;
            return false;
        }

        next = this with { IsBusy = true, ErrorMessage = null };
        return true;
    }

    public RemotePetImportInteractionState Complete() =>
        this with { IsBusy = false, ErrorMessage = null, IsRetry = false };

    public RemotePetImportInteractionState Fail(string message) =>
        this with { IsBusy = false, ErrorMessage = message, IsRetry = true };
}
