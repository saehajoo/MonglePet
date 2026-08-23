using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace MonglePet.PetLibrary;

public sealed class RemotePetPreparedPackage : IDisposable
{
    private bool _isDisposed;

    internal RemotePetPreparedPackage(
        string packagePath,
        string temporaryDirectoryPath,
        RemotePetImportSource source,
        string suggestedFileName)
    {
        PackagePath = packagePath;
        TemporaryDirectoryPath = temporaryDirectoryPath;
        Source = source;
        SuggestedFileName = suggestedFileName;
    }

    public string PackagePath { get; }

    public string TemporaryDirectoryPath { get; }

    public RemotePetImportSource Source { get; }

    public string SuggestedFileName { get; }

    public void Dispose()
    {
        if (_isDisposed)
        {
            return;
        }

        _isDisposed = true;
        try
        {
            if (Directory.Exists(TemporaryDirectoryPath))
            {
                Directory.Delete(TemporaryDirectoryPath, recursive: true);
            }
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }
}

public sealed class RemotePetImportService : IDisposable
{
    public const long MaximumPackageBytes = 20L * 1_024 * 1_024;
    private const int MaximumJsonBytes = 1 * 1_024 * 1_024;
    private const int MaximumRedirects = 5;
    private static readonly Regex Sha256Pattern = new(
        "^[0-9a-fA-F]{64}$",
        RegexOptions.CultureInvariant);
    private static readonly Regex DownloadTokenPattern = new(
        "^[A-Za-z0-9_-]{1,512}$",
        RegexOptions.CultureInvariant);
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = false,
    };

    private readonly HttpClient _httpClient;
    private readonly bool _ownsHttpClient;
    private readonly string _temporaryRootPath;
    private readonly RemotePetSemanticVersion _currentAppVersion;

    public RemotePetImportService(
        RemotePetSemanticVersion currentAppVersion,
        HttpClient? httpClient = null,
        string? temporaryRootPath = null)
    {
        _currentAppVersion = currentAppVersion;
        _temporaryRootPath = temporaryRootPath ?? Path.GetTempPath();
        _httpClient = httpClient ?? CreateHttpClient();
        _ownsHttpClient = httpClient is null;
    }

    public async Task<RemotePetPreparedPackage> PreparePackageAsync(
        string userInput,
        CancellationToken cancellationToken = default)
    {
        try
        {
            RemotePetImportSource source = RemotePetImportSource.Parse(userInput);
            PetDetailData detail = await FetchJsonAsync<PetDetailData>(
                source.DetailApiUri,
                source,
                cancellationToken);
            PetData? pet = detail.Pet;
            PetVersionData? version = pet?.RepresentativeVersion;
            if (pet is null ||
                version is null ||
                !string.Equals(pet.Slug, source.PetSlug, StringComparison.Ordinal))
            {
                throw MetadataMismatch();
            }

            ValidateMetadata(version.SizeBytes, version.Sha256);
            if (!RemotePetSemanticVersion.TryParse(
                    version.MinimumAppVersion,
                    out RemotePetSemanticVersion minimumVersion))
            {
                throw RemotePetImportException.InvalidServerResponse();
            }

            if (_currentAppVersion < minimumVersion)
            {
                throw new RemotePetImportException(
                    RemotePetImportError.MinimumAppVersionRequired,
                    $"이 펫은 MonglePet {minimumVersion} 이상이 필요합니다. " +
                    $"현재 버전은 {_currentAppVersion}입니다.",
                    requiredVersion: minimumVersion,
                    currentVersion: _currentAppVersion);
            }

            if (!Guid.TryParse(version.PetVersionUuid, out _))
            {
                throw RemotePetImportException.InvalidServerResponse();
            }

            Uri downloadMetadataUri = new(
                source.ApiBaseUri,
                $"monglepet/pet-versions/{version.PetVersionUuid}/download");
            PetDownloadData download = await FetchJsonAsync<PetDownloadData>(
                downloadMetadataUri,
                source,
                cancellationToken);
            if (download.SizeBytes != version.SizeBytes ||
                !string.Equals(
                    download.Sha256,
                    version.Sha256,
                    StringComparison.OrdinalIgnoreCase))
            {
                throw MetadataMismatch();
            }

            ValidateMetadata(download.SizeBytes, download.Sha256);
            if (string.IsNullOrWhiteSpace(download.Filename))
            {
                throw RemotePetImportException.InvalidServerResponse();
            }
            Uri downloadUri = ValidateDownloadUri(download.DownloadUrl, source);
            return await DownloadAsync(
                downloadUri,
                download,
                source,
                cancellationToken);
        }
        catch (RemotePetImportException)
        {
            throw;
        }
        catch (OperationCanceledException exception) when (!cancellationToken.IsCancellationRequested)
        {
            throw new RemotePetImportException(
                RemotePetImportError.Timeout,
                "서버 응답이 늦거나 연결이 끊겼습니다. 잠시 뒤 다시 시도해 주세요.",
                exception);
        }
        catch (HttpRequestException exception)
        {
            throw MapHttpError(exception);
        }
        catch (JsonException exception)
        {
            throw RemotePetImportException.InvalidServerResponse(exception);
        }
    }

    public void Dispose()
    {
        if (_ownsHttpClient)
        {
            _httpClient.Dispose();
        }
    }

    public static HttpClient CreateHttpClient()
    {
        var handler = new HttpClientHandler
        {
            AllowAutoRedirect = false,
            UseCookies = false,
            CookieContainer = new CookieContainer(),
            UseDefaultCredentials = false,
            Credentials = null,
        };
        var client = new HttpClient(handler)
        {
            Timeout = TimeSpan.FromSeconds(60),
        };
        client.DefaultRequestHeaders.Accept.Add(
            new MediaTypeWithQualityHeaderValue("application/json"));
        return client;
    }

    private async Task<T> FetchJsonAsync<T>(
        Uri uri,
        RemotePetImportSource source,
        CancellationToken cancellationToken)
    {
        using HttpResponseMessage response = await SendWithSafeRedirectsAsync(
            uri,
            source.ApiBaseUri,
            cancellationToken);
        EnsureSuccess(response);
        byte[] body = await ReadLimitedAsync(
            response.Content,
            MaximumJsonBytes,
            cancellationToken);

        ApiStatusEnvelope status = JsonSerializer.Deserialize<ApiStatusEnvelope>(body, JsonOptions)
            ?? throw RemotePetImportException.InvalidServerResponse();
        if (string.IsNullOrWhiteSpace(status.Status) ||
            string.IsNullOrWhiteSpace(status.Code))
        {
            throw RemotePetImportException.InvalidServerResponse();
        }
        if (!string.Equals(status.Status, "success", StringComparison.Ordinal) ||
            !string.Equals(status.Code, "ok", StringComparison.Ordinal))
        {
            throw new RemotePetImportException(
                RemotePetImportError.ServerRejected,
                string.IsNullOrWhiteSpace(status.Message)
                    ? "이 펫을 다운로드할 수 없습니다."
                    : status.Message);
        }

        ApiEnvelope<T> envelope = JsonSerializer.Deserialize<ApiEnvelope<T>>(body, JsonOptions)
            ?? throw RemotePetImportException.InvalidServerResponse();
        return envelope.Data ?? throw RemotePetImportException.InvalidServerResponse();
    }

    private async Task<RemotePetPreparedPackage> DownloadAsync(
        Uri downloadUri,
        PetDownloadData metadata,
        RemotePetImportSource source,
        CancellationToken cancellationToken)
    {
        string workspacePath = Path.Combine(
            _temporaryRootPath,
            $"MonglePetRemoteImport-{Guid.NewGuid():N}");
        Directory.CreateDirectory(workspacePath);
        string packagePath = Path.Combine(workspacePath, "package.monglepet");

        try
        {
            using HttpResponseMessage response = await SendWithSafeRedirectsAsync(
                downloadUri,
                source.ApiBaseUri,
                cancellationToken);
            EnsureSuccess(response);
            Uri? finalUri = response.RequestMessage?.RequestUri;
            if (finalUri is null || !IsAllowedDownloadUri(finalUri, source))
            {
                throw RemotePetImportException.InvalidServerResponse();
            }

            long? contentLength = response.Content.Headers.ContentLength;
            if (contentLength > MaximumPackageBytes)
            {
                throw PackageTooLarge();
            }

            long actualSize = 0;
            using IncrementalHash hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
            await using Stream sourceStream = await response.Content.ReadAsStreamAsync(cancellationToken);
            await using var destination = new FileStream(
                packagePath,
                FileMode.CreateNew,
                FileAccess.Write,
                FileShare.None,
                64 * 1_024,
                FileOptions.Asynchronous | FileOptions.SequentialScan);
            byte[] buffer = new byte[64 * 1_024];
            while (true)
            {
                int read = await sourceStream.ReadAsync(buffer, cancellationToken);
                if (read == 0)
                {
                    break;
                }

                actualSize += read;
                if (actualSize > MaximumPackageBytes)
                {
                    throw PackageTooLarge();
                }

                hash.AppendData(buffer, 0, read);
                await destination.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
            }

            await destination.FlushAsync(cancellationToken);
            if (actualSize != metadata.SizeBytes)
            {
                throw new RemotePetImportException(
                    RemotePetImportError.PackageSizeMismatch,
                    "다운로드한 패키지 크기가 게시된 정보와 일치하지 않습니다.");
            }

            string actualSha256 = Convert.ToHexString(hash.GetHashAndReset()).ToLowerInvariant();
            if (!actualSha256.Equals(metadata.Sha256, StringComparison.OrdinalIgnoreCase))
            {
                throw new RemotePetImportException(
                    RemotePetImportError.ChecksumMismatch,
                    "다운로드한 패키지의 SHA-256이 게시된 정보와 일치하지 않습니다.");
            }

            return new RemotePetPreparedPackage(
                packagePath,
                workspacePath,
                source,
                metadata.Filename!);
        }
        catch
        {
            TryDeleteDirectory(workspacePath);
            throw;
        }
    }

    private async Task<HttpResponseMessage> SendWithSafeRedirectsAsync(
        Uri initialUri,
        Uri allowedOrigin,
        CancellationToken cancellationToken)
    {
        Uri currentUri = initialUri;
        for (int redirectCount = 0; redirectCount <= MaximumRedirects; redirectCount++)
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, currentUri);
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
            HttpResponseMessage response = await _httpClient.SendAsync(
                request,
                HttpCompletionOption.ResponseHeadersRead,
                cancellationToken);

            if (!IsRedirect(response.StatusCode))
            {
                return response;
            }

            Uri? location = response.Headers.Location;
            response.Dispose();
            if (location is null || redirectCount == MaximumRedirects)
            {
                throw RemotePetImportException.InvalidServerResponse();
            }

            Uri redirectedUri = location.IsAbsoluteUri
                ? location
                : new Uri(currentUri, location);
            if (!HasAllowedOrigin(redirectedUri, allowedOrigin))
            {
                throw RemotePetImportException.InvalidServerResponse();
            }

            currentUri = redirectedUri;
        }

        throw RemotePetImportException.InvalidServerResponse();
    }

    private static bool HasAllowedOrigin(Uri uri, Uri allowedOrigin) =>
        uri.Scheme.Equals("https", StringComparison.OrdinalIgnoreCase) &&
        uri.Host.Equals(allowedOrigin.Host, StringComparison.OrdinalIgnoreCase) &&
        uri.Port == 443 &&
        string.IsNullOrEmpty(uri.UserInfo) &&
        HasExactAuthority(uri.OriginalString, allowedOrigin.Host);

    private static bool HasExactAuthority(string value, string expectedHost)
    {
        if (!RemotePetImportSource.TrySplitAbsoluteUri(
                value,
                out _,
                out string authority,
                out _))
        {
            return false;
        }

        return authority.Equals(expectedHost, StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsAllowedDownloadUri(Uri uri, RemotePetImportSource source)
    {
        const string prefix = "/media/monglepet/downloads/";
        if (!HasAllowedOrigin(uri, source.ApiBaseUri) ||
            !uri.AbsolutePath.StartsWith(prefix, StringComparison.Ordinal) ||
            uri.Query.Length != 0 ||
            uri.Fragment.Length != 0)
        {
            return false;
        }

        string token = uri.AbsolutePath[prefix.Length..];
        return DownloadTokenPattern.IsMatch(token);
    }

    private static Uri ValidateDownloadUri(string? value, RemotePetImportSource source)
    {
        const string prefix = "/media/monglepet/downloads/";
        if (string.IsNullOrEmpty(value) ||
            !value.StartsWith(prefix, StringComparison.Ordinal) ||
            value.Contains('?') ||
            value.Contains('#'))
        {
            throw RemotePetImportException.InvalidServerResponse();
        }

        string token = value[prefix.Length..];
        if (!DownloadTokenPattern.IsMatch(token))
        {
            throw RemotePetImportException.InvalidServerResponse();
        }

        Uri result = new(source.ApiBaseUri.GetLeftPart(UriPartial.Authority) + value);
        return IsAllowedDownloadUri(result, source)
            ? result
            : throw RemotePetImportException.InvalidServerResponse();
    }

    private static void ValidateMetadata(long sizeBytes, string? sha256)
    {
        if (sizeBytes > MaximumPackageBytes)
        {
            throw PackageTooLarge();
        }

        if (sizeBytes < 0 || !Sha256Pattern.IsMatch(sha256 ?? string.Empty))
        {
            throw RemotePetImportException.InvalidServerResponse();
        }
    }

    private static RemotePetImportException MetadataMismatch() =>
        new(
            RemotePetImportError.MetadataMismatch,
            "펫 상세 정보와 다운로드 정보가 일치하지 않아 가져오기를 중단했습니다.");

    private static RemotePetImportException PackageTooLarge() =>
        new(
            RemotePetImportError.PackageTooLarge,
            $"패키지가 최대 허용 크기 {MaximumPackageBytes / 1_048_576} MiB를 초과합니다.",
            maximumBytes: MaximumPackageBytes);

    private static RemotePetImportException MapHttpError(HttpRequestException exception)
    {
        return exception.HttpRequestError switch
        {
            HttpRequestError.NameResolutionError => new RemotePetImportException(
                RemotePetImportError.NetworkUnavailable,
                "인터넷 연결을 확인한 뒤 다시 시도해 주세요.",
                exception),
            HttpRequestError.SecureConnectionError => new RemotePetImportException(
                RemotePetImportError.TlsFailure,
                "MonglePet 서버와 안전하게 연결할 수 없어 가져오기를 중단했습니다.",
                exception),
            _ => new RemotePetImportException(
                RemotePetImportError.ConnectionFailed,
                "MonglePet 서버에 연결할 수 없습니다. 주소를 확인하거나 잠시 뒤 다시 시도해 주세요.",
                exception),
        };
    }

    private static void EnsureSuccess(HttpResponseMessage response)
    {
        if (!response.IsSuccessStatusCode)
        {
            throw RemotePetImportException.InvalidServerResponse();
        }
    }

    private static bool IsRedirect(HttpStatusCode statusCode) =>
        statusCode is HttpStatusCode.MovedPermanently or
            HttpStatusCode.Found or
            HttpStatusCode.SeeOther or
            HttpStatusCode.TemporaryRedirect or
            HttpStatusCode.PermanentRedirect;

    private static async Task<byte[]> ReadLimitedAsync(
        HttpContent content,
        int maximumBytes,
        CancellationToken cancellationToken)
    {
        if (content.Headers.ContentLength > maximumBytes)
        {
            throw RemotePetImportException.InvalidServerResponse();
        }

        await using Stream stream = await content.ReadAsStreamAsync(cancellationToken);
        using var memory = new MemoryStream();
        byte[] buffer = new byte[16 * 1_024];
        while (true)
        {
            int read = await stream.ReadAsync(buffer, cancellationToken);
            if (read == 0)
            {
                return memory.ToArray();
            }

            if (memory.Length + read > maximumBytes)
            {
                throw RemotePetImportException.InvalidServerResponse();
            }

            memory.Write(buffer, 0, read);
        }
    }

    private static void TryDeleteDirectory(string path)
    {
        try
        {
            if (Directory.Exists(path))
            {
                Directory.Delete(path, recursive: true);
            }
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }

    private sealed record ApiStatusEnvelope(
        [property: JsonPropertyName("status")] string? Status,
        [property: JsonPropertyName("message")] string? Message,
        [property: JsonPropertyName("code")] string? Code);

    private sealed record ApiEnvelope<T>(
        [property: JsonPropertyName("status")] string? Status,
        [property: JsonPropertyName("message")] string? Message,
        [property: JsonPropertyName("code")] string? Code,
        [property: JsonPropertyName("data")] T? Data);

    private sealed record PetDetailData(
        [property: JsonPropertyName("pet")] PetData? Pet);

    private sealed record PetData(
        [property: JsonPropertyName("slug")] string? Slug,
        [property: JsonPropertyName("representative_version")] PetVersionData? RepresentativeVersion);

    private sealed record PetVersionData(
        [property: JsonPropertyName("pet_version_uuid")] string? PetVersionUuid,
        [property: JsonPropertyName("minimum_app_version")] string? MinimumAppVersion,
        [property: JsonPropertyName("size_bytes")] long SizeBytes,
        [property: JsonPropertyName("sha256")] string? Sha256);

    private sealed record PetDownloadData(
        [property: JsonPropertyName("download_url")] string? DownloadUrl,
        [property: JsonPropertyName("filename")] string? Filename,
        [property: JsonPropertyName("size_bytes")] long SizeBytes,
        [property: JsonPropertyName("sha256")] string? Sha256);
}
