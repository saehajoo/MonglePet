using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using MonglePet.PetLibrary;

namespace MonglePet.PetLibrary.Tests;

public sealed class RemotePetImportSourceTests
{
    [Theory]
    [InlineData(
        " https://dev.mapleroom.kr/monglepet/pets/monglepet-abc123?shared=1#preview ",
        RemotePetImportEnvironment.Development,
        "https://dev.mapleroom.kr/monglepet/pets/monglepet-abc123",
        "https://dev-api.mapleroom.kr/api/v1/monglepet/pets/monglepet-abc123")]
    [InlineData(
        "https://mapleroom.kr/monglepet/pets/monglepet-def456",
        RemotePetImportEnvironment.Production,
        "https://mapleroom.kr/monglepet/pets/monglepet-def456",
        "https://api.mapleroom.kr/api/v1/monglepet/pets/monglepet-def456")]
    public void ParseAcceptsSupportedDetailUrls(
        string value,
        RemotePetImportEnvironment environment,
        string canonical,
        string detailApi)
    {
        RemotePetImportSource source = RemotePetImportSource.Parse(value);

        Assert.Equal(environment, source.Environment);
        Assert.Equal(canonical, source.CanonicalWebUri.AbsoluteUri);
        Assert.Equal(detailApi, source.DetailApiUri.AbsoluteUri);
    }

    [Theory]
    [InlineData("http://dev.mapleroom.kr/monglepet/pets/monglepet-abc123")]
    [InlineData("https://evil.example/monglepet/pets/monglepet-abc123")]
    [InlineData("https://dev.mapleroom.kr.evil.example/monglepet/pets/monglepet-abc123")]
    [InlineData("https://user@dev.mapleroom.kr/monglepet/pets/monglepet-abc123")]
    [InlineData("https://dev.mapleroom.kr:443/monglepet/pets/monglepet-abc123")]
    [InlineData("https://dev.mapleroom.kr/monglepet/pets/monglepet-abc123/extra")]
    [InlineData("https://dev.mapleroom.kr/monglepet/pets/MonglePet-ABC")]
    [InlineData("https://dev.mapleroom.kr/monglepet//pets/monglepet-abc123")]
    [InlineData("https://dev.mapleroom.kr/monglepet/other/monglepet-abc123")]
    public void ParseRejectsUntrustedOrMalformedUrls(string value)
    {
        RemotePetImportException exception = Assert.Throws<RemotePetImportException>(
            () => RemotePetImportSource.Parse(value));

        Assert.Equal(RemotePetImportError.UnsupportedWebUrl, exception.Error);
    }

    [Fact]
    public void DeepLinkAcceptsExactlyOneEncodedDetailUrl()
    {
        const string detail = "https://dev.mapleroom.kr/monglepet/pets/monglepet-abc123";
        string value = $"monglepet://install?url={Uri.EscapeDataString(detail)}";

        RemotePetImportDeepLink link = RemotePetImportDeepLink.Parse(value);

        Assert.Equal(detail, link.Source.CanonicalWebUri.AbsoluteUri);
    }

    [Theory]
    [InlineData("monglepet://download?url=https%3A%2F%2Fdev.mapleroom.kr%2Fmonglepet%2Fpets%2Fpet")]
    [InlineData("monglepet://install")]
    [InlineData("monglepet://install/?url=https%3A%2F%2Fdev.mapleroom.kr%2Fmonglepet%2Fpets%2Fpet")]
    [InlineData("monglepet://install?url=https%3A%2F%2Fevil.example%2Fpet")]
    [InlineData("monglepet://install?url=a&url=b")]
    [InlineData("monglepet://install?url=a&token=secret")]
    [InlineData("monglepet://install?url=%ZZ")]
    [InlineData("monglepet://install:443?url=a")]
    public void DeepLinkRejectsAnyOtherShape(string value)
    {
        RemotePetImportException exception = Assert.Throws<RemotePetImportException>(
            () => RemotePetImportDeepLink.Parse(value));

        Assert.Equal(RemotePetImportError.InvalidDeepLink, exception.Error);
    }

    [Fact]
    public void SemanticVersionRequiresCanonicalThreePartVersion()
    {
        Assert.True(RemotePetSemanticVersion.TryParse("1.1.0", out var version));
        Assert.Equal(new RemotePetSemanticVersion(1, 1, 0), version);
        Assert.False(RemotePetSemanticVersion.TryParse("1.1", out _));
        Assert.False(RemotePetSemanticVersion.TryParse("01.1.0", out _));
        Assert.True(version < new RemotePetSemanticVersion(1, 2, 0));
    }

    [Fact]
    public void InteractionStatePreventsDuplicateWorkAndClearsErrorOnEdit()
    {
        RemotePetImportInteractionState state = RemotePetImportInteractionState.Initial
            .WithInput("first");

        Assert.True(state.TryBegin(out state));
        Assert.False(state.TryBegin(out RemotePetImportInteractionState duplicate));
        Assert.Same(state, duplicate);

        state = state.Fail("failed");
        Assert.Equal("다시 시도", state.ActionText);
        state = state.WithInput("second");
        Assert.Null(state.ErrorMessage);
        Assert.False(state.IsRetry);
        Assert.Equal("주소에서 가져오기", state.ActionText);
    }
}

public sealed class RemotePetImportServiceTests
{
    private static readonly RemotePetSemanticVersion CurrentVersion = new(1, 1, 0);

    [Fact]
    public async Task PrepareDownloadsAndVerifiesPublishedPackageWithoutChangingLibrary()
    {
        using var root = new TemporaryDirectory();
        byte[] package = Encoding.UTF8.GetBytes("valid monglepet package");
        string checksum = Sha256(package);
        var handler = CreateSuccessfulHandler(package, checksum);
        using var client = new HttpClient(handler);
        using var service = new RemotePetImportService(CurrentVersion, client, root.Path);
        var library = new PetLibraryStore(System.IO.Path.Combine(root.Path, "library"));

        using RemotePetPreparedPackage prepared = await service.PreparePackageAsync(DevelopmentUrl);

        Assert.Equal(package, await File.ReadAllBytesAsync(prepared.PackagePath));
        Assert.Equal("monglepet-abc123-1.0.0.monglepet", prepared.SuggestedFileName);
        Assert.Empty(library.GetInstalledPackages());
        Assert.Equal(
            [DetailApiUrl, DownloadMetadataUrl, DownloadUrl],
            handler.RequestedUris.Select(uri => uri.AbsoluteUri));
    }

    [Fact]
    public async Task PreparedPackageDeletesItsOwnedDirectoryAfterReviewLifetime()
    {
        using var root = new TemporaryDirectory();
        byte[] package = Encoding.UTF8.GetBytes("valid package");
        string checksum = Sha256(package);
        using var client = new HttpClient(CreateSuccessfulHandler(package, checksum));
        using var service = new RemotePetImportService(CurrentVersion, client, root.Path);

        RemotePetPreparedPackage prepared = await service.PreparePackageAsync(DevelopmentUrl);
        string workspace = prepared.TemporaryDirectoryPath;
        Assert.True(Directory.Exists(workspace));

        prepared.Dispose();

        Assert.False(Directory.Exists(workspace));
    }

    [Fact]
    public async Task Http200ErrorEnvelopeIsRejectedBeforeDownload()
    {
        var handler = new StubHttpMessageHandler(request =>
            JsonResponse(
                request,
                """{"status":"error","message":"공개된 펫이 아닙니다.","code":"not_public","data":{}}"""));
        using var client = new HttpClient(handler);
        using var service = new RemotePetImportService(CurrentVersion, client);

        RemotePetImportException exception = await Assert.ThrowsAsync<RemotePetImportException>(
            () => service.PreparePackageAsync(DevelopmentUrl));

        Assert.Equal(RemotePetImportError.ServerRejected, exception.Error);
        Assert.Equal("공개된 펫이 아닙니다.", exception.Message);
        Assert.Single(handler.RequestedUris);
    }

    [Theory]
    [InlineData("{}")]
    [InlineData("{\"status\":\"success\",\"code\":\"ok\",\"data\":null}")]
    public async Task MalformedOrMissingSuccessEnvelopeIsRejected(string responseJson)
    {
        var handler = new StubHttpMessageHandler(request =>
            JsonResponse(request, responseJson));
        using var client = new HttpClient(handler);
        using var service = new RemotePetImportService(CurrentVersion, client);

        RemotePetImportException exception = await Assert.ThrowsAsync<RemotePetImportException>(
            () => service.PreparePackageAsync(DevelopmentUrl));

        Assert.Equal(RemotePetImportError.InvalidServerResponse, exception.Error);
        Assert.Single(handler.RequestedUris);
    }

    [Fact]
    public async Task DetailAndDownloadMetadataMustMatchBeforeFileRequest()
    {
        string first = new('a', 64);
        string second = new('b', 64);
        var handler = CreateHandler(
            package: [1, 2, 3, 4],
            detailSize: 4,
            detailChecksum: first,
            downloadSize: 4,
            downloadChecksum: second);
        using var client = new HttpClient(handler);
        using var service = new RemotePetImportService(CurrentVersion, client);

        RemotePetImportException exception = await Assert.ThrowsAsync<RemotePetImportException>(
            () => service.PreparePackageAsync(DevelopmentUrl));

        Assert.Equal(RemotePetImportError.MetadataMismatch, exception.Error);
        Assert.DoesNotContain(handler.RequestedUris, uri => uri.AbsoluteUri == DownloadUrl);
    }

    [Fact]
    public async Task MinimumAppVersionIsCheckedBeforeDownloadMetadataRequest()
    {
        string checksum = new('a', 64);
        var handler = CreateHandler(
            package: [1, 2, 3, 4],
            detailSize: 4,
            detailChecksum: checksum,
            minimumVersion: "9.0.0");
        using var client = new HttpClient(handler);
        using var service = new RemotePetImportService(CurrentVersion, client);

        RemotePetImportException exception = await Assert.ThrowsAsync<RemotePetImportException>(
            () => service.PreparePackageAsync(DevelopmentUrl));

        Assert.Equal(RemotePetImportError.MinimumAppVersionRequired, exception.Error);
        Assert.Equal(new RemotePetSemanticVersion(9, 0, 0), exception.RequiredVersion);
        Assert.Equal(CurrentVersion, exception.CurrentVersion);
        Assert.Single(handler.RequestedUris);
    }

    [Fact]
    public async Task PublishedPackageLargerThanLimitIsRejectedBeforeDownload()
    {
        string checksum = new('a', 64);
        var handler = CreateHandler(
            package: [1],
            detailSize: RemotePetImportService.MaximumPackageBytes + 1,
            detailChecksum: checksum);
        using var client = new HttpClient(handler);
        using var service = new RemotePetImportService(CurrentVersion, client);

        RemotePetImportException exception = await Assert.ThrowsAsync<RemotePetImportException>(
            () => service.PreparePackageAsync(DevelopmentUrl));

        Assert.Equal(RemotePetImportError.PackageTooLarge, exception.Error);
        Assert.Single(handler.RequestedUris);
    }

    [Fact]
    public async Task ActualPackageSizeMustMatchPublishedMetadataAndFailureCleansWorkspace()
    {
        using var root = new TemporaryDirectory();
        byte[] package = [1, 2, 3, 4, 5];
        string checksum = Sha256(package);
        var handler = CreateHandler(
            package,
            detailSize: package.Length - 1,
            detailChecksum: checksum);
        using var client = new HttpClient(handler);
        using var service = new RemotePetImportService(CurrentVersion, client, root.Path);

        RemotePetImportException exception = await Assert.ThrowsAsync<RemotePetImportException>(
            () => service.PreparePackageAsync(DevelopmentUrl));

        Assert.Equal(RemotePetImportError.PackageSizeMismatch, exception.Error);
        Assert.Empty(Directory.EnumerateDirectories(root.Path, "MonglePetRemoteImport-*"));
    }

    [Fact]
    public async Task ActualUnknownLengthStreamCannotExceedPackageLimit()
    {
        using var root = new TemporaryDirectory();
        byte[] package = new byte[RemotePetImportService.MaximumPackageBytes + 1];
        string checksum = Sha256(package);
        var handler = CreateHandler(
            package,
            RemotePetImportService.MaximumPackageBytes,
            checksum,
            downloadResponse: request => new HttpResponseMessage(HttpStatusCode.OK)
            {
                RequestMessage = request,
                Content = new UnknownLengthByteArrayContent(package),
            });
        using var client = new HttpClient(handler);
        using var service = new RemotePetImportService(CurrentVersion, client, root.Path);

        RemotePetImportException exception = await Assert.ThrowsAsync<RemotePetImportException>(
            () => service.PreparePackageAsync(DevelopmentUrl));

        Assert.Equal(RemotePetImportError.PackageTooLarge, exception.Error);
        Assert.Empty(Directory.EnumerateDirectories(root.Path, "MonglePetRemoteImport-*"));
    }

    [Fact]
    public async Task ActualPackageChecksumMustMatchPublishedMetadata()
    {
        byte[] package = Encoding.UTF8.GetBytes("changed");
        string published = Sha256(Encoding.UTF8.GetBytes("expected"));
        var handler = CreateHandler(package, package.Length, published);
        using var client = new HttpClient(handler);
        using var service = new RemotePetImportService(CurrentVersion, client);

        RemotePetImportException exception = await Assert.ThrowsAsync<RemotePetImportException>(
            () => service.PreparePackageAsync(DevelopmentUrl));

        Assert.Equal(RemotePetImportError.ChecksumMismatch, exception.Error);
    }

    [Theory]
    [InlineData("https://evil.example/media/monglepet/downloads/token")]
    [InlineData("http://dev-api.mapleroom.kr/media/monglepet/downloads/token")]
    [InlineData("https://dev-api.mapleroom.kr:443/media/monglepet/downloads/token")]
    public async Task UnsafeRedirectsAreRejected(string location)
    {
        byte[] package = [1, 2, 3, 4];
        string checksum = Sha256(package);
        var handler = CreateHandler(
            package,
            package.Length,
            checksum,
            downloadResponse: request =>
            {
                var response = new HttpResponseMessage(HttpStatusCode.Redirect)
                {
                    RequestMessage = request,
                };
                response.Headers.Location = new Uri(location);
                return response;
            });
        using var client = new HttpClient(handler);
        using var service = new RemotePetImportService(CurrentVersion, client);

        RemotePetImportException exception = await Assert.ThrowsAsync<RemotePetImportException>(
            () => service.PreparePackageAsync(DevelopmentUrl));

        Assert.Equal(RemotePetImportError.InvalidServerResponse, exception.Error);
    }

    [Theory]
    [InlineData("https://dev-api.mapleroom.kr/media/monglepet/downloads/token")]
    [InlineData("/media/monglepet/downloads/token/extra")]
    [InlineData("/media/monglepet/downloads/token?secret=value")]
    [InlineData("/media/other/token")]
    public async Task DownloadMetadataOnlyAcceptsOpaqueRelativePath(string unsafeDownloadUrl)
    {
        byte[] package = [1, 2, 3, 4];
        string checksum = Sha256(package);
        var handler = CreateHandler(
            package,
            package.Length,
            checksum,
            downloadUrl: unsafeDownloadUrl);
        using var client = new HttpClient(handler);
        using var service = new RemotePetImportService(CurrentVersion, client);

        RemotePetImportException exception = await Assert.ThrowsAsync<RemotePetImportException>(
            () => service.PreparePackageAsync(DevelopmentUrl));

        Assert.Equal(RemotePetImportError.InvalidServerResponse, exception.Error);
    }

    [Fact]
    public async Task SameOriginRedirectCanCompleteWithValidatedFinalPath()
    {
        byte[] package = [1, 2, 3, 4];
        string checksum = Sha256(package);
        int downloads = 0;
        var handler = CreateHandler(
            package,
            package.Length,
            checksum,
            downloadResponse: request =>
            {
                downloads++;
                if (downloads == 1)
                {
                    var redirect = new HttpResponseMessage(HttpStatusCode.TemporaryRedirect)
                    {
                        RequestMessage = request,
                    };
                    redirect.Headers.Location = new Uri(
                        "https://dev-api.mapleroom.kr/media/monglepet/downloads/fresh-token");
                    return redirect;
                }

                return BinaryResponse(request, package);
            });
        using var client = new HttpClient(handler);
        using var service = new RemotePetImportService(CurrentVersion, client);

        using RemotePetPreparedPackage prepared = await service.PreparePackageAsync(DevelopmentUrl);

        Assert.Equal(2, downloads);
        Assert.True(File.Exists(prepared.PackagePath));
    }

    [Theory]
    [InlineData(HttpRequestError.NameResolutionError, RemotePetImportError.NetworkUnavailable,
        "인터넷 연결을 확인한 뒤 다시 시도해 주세요.")]
    [InlineData(HttpRequestError.ConnectionError, RemotePetImportError.ConnectionFailed,
        "MonglePet 서버에 연결할 수 없습니다. 주소를 확인하거나 잠시 뒤 다시 시도해 주세요.")]
    [InlineData(HttpRequestError.SecureConnectionError, RemotePetImportError.TlsFailure,
        "MonglePet 서버와 안전하게 연결할 수 없어 가져오기를 중단했습니다.")]
    public async Task NetworkFailuresUseStableRecoveryMessages(
        HttpRequestError requestError,
        RemotePetImportError expectedError,
        string expectedMessage)
    {
        var handler = new StubHttpMessageHandler(_ =>
            throw new HttpRequestException(requestError, "transport failed"));
        using var client = new HttpClient(handler);
        using var service = new RemotePetImportService(CurrentVersion, client);

        RemotePetImportException exception = await Assert.ThrowsAsync<RemotePetImportException>(
            () => service.PreparePackageAsync(DevelopmentUrl));

        Assert.Equal(expectedError, exception.Error);
        Assert.Equal(expectedMessage, exception.Message);
    }

    [Fact]
    public async Task TimeoutUsesStableRecoveryMessage()
    {
        var handler = new StubHttpMessageHandler(_ => throw new TaskCanceledException());
        using var client = new HttpClient(handler);
        using var service = new RemotePetImportService(CurrentVersion, client);

        RemotePetImportException exception = await Assert.ThrowsAsync<RemotePetImportException>(
            () => service.PreparePackageAsync(DevelopmentUrl));

        Assert.Equal(RemotePetImportError.Timeout, exception.Error);
        Assert.Equal(
            "서버 응답이 늦거나 연결이 끊겼습니다. 잠시 뒤 다시 시도해 주세요.",
            exception.Message);
    }

    private static StubHttpMessageHandler CreateSuccessfulHandler(byte[] package, string checksum) =>
        CreateHandler(package, package.Length, checksum);

    private static StubHttpMessageHandler CreateHandler(
        byte[] package,
        long detailSize,
        string detailChecksum,
        long? downloadSize = null,
        string? downloadChecksum = null,
        string minimumVersion = "1.1.0",
        string downloadUrl = "/media/monglepet/downloads/token",
        Func<HttpRequestMessage, HttpResponseMessage>? downloadResponse = null)
    {
        string detailJson = JsonSerializer.Serialize(new
        {
            status = "success",
            message = "ok",
            code = "ok",
            data = new
            {
                pet = new
                {
                    slug = "monglepet-abc123",
                    representative_version = new
                    {
                        pet_version_uuid = "30d59aa6-d722-4b4e-9181-e8e39425e708",
                        minimum_app_version = minimumVersion,
                        size_bytes = detailSize,
                        sha256 = detailChecksum,
                    },
                },
            },
        });
        string downloadJson = JsonSerializer.Serialize(new
        {
            status = "success",
            message = "ok",
            code = "ok",
            data = new
            {
                download_url = downloadUrl,
                filename = "monglepet-abc123-1.0.0.monglepet",
                size_bytes = downloadSize ?? detailSize,
                sha256 = downloadChecksum ?? detailChecksum,
            },
        });

        return new StubHttpMessageHandler(request => request.RequestUri!.AbsoluteUri switch
        {
            DetailApiUrl => JsonResponse(request, detailJson),
            DownloadMetadataUrl => JsonResponse(request, downloadJson),
            DownloadUrl or "https://dev-api.mapleroom.kr/media/monglepet/downloads/fresh-token" =>
                downloadResponse?.Invoke(request) ?? BinaryResponse(request, package),
            _ => throw new InvalidOperationException($"Unexpected request: {request.RequestUri}"),
        });
    }

    private static HttpResponseMessage JsonResponse(HttpRequestMessage request, string json) =>
        new(HttpStatusCode.OK)
        {
            RequestMessage = request,
            Content = new StringContent(json, Encoding.UTF8, "application/json"),
        };

    private static HttpResponseMessage BinaryResponse(HttpRequestMessage request, byte[] bytes) =>
        new(HttpStatusCode.OK)
        {
            RequestMessage = request,
            Content = new ByteArrayContent(bytes),
        };

    private static string Sha256(byte[] value) =>
        Convert.ToHexString(SHA256.HashData(value)).ToLowerInvariant();

    private const string DevelopmentUrl =
        "https://dev.mapleroom.kr/monglepet/pets/monglepet-abc123";
    private const string DetailApiUrl =
        "https://dev-api.mapleroom.kr/api/v1/monglepet/pets/monglepet-abc123";
    private const string DownloadMetadataUrl =
        "https://dev-api.mapleroom.kr/api/v1/monglepet/pet-versions/30d59aa6-d722-4b4e-9181-e8e39425e708/download";
    private const string DownloadUrl =
        "https://dev-api.mapleroom.kr/media/monglepet/downloads/token";

    private sealed class StubHttpMessageHandler(
        Func<HttpRequestMessage, HttpResponseMessage> responder) : HttpMessageHandler
    {
        public List<Uri> RequestedUris { get; } = [];

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            RequestedUris.Add(request.RequestUri!);
            return Task.FromResult(responder(request));
        }
    }

    private sealed class UnknownLengthByteArrayContent(byte[] bytes) : HttpContent
    {
        protected override Task SerializeToStreamAsync(
            Stream stream,
            TransportContext? context) =>
            stream.WriteAsync(bytes, 0, bytes.Length);

        protected override bool TryComputeLength(out long length)
        {
            length = 0;
            return false;
        }
    }

    private sealed class TemporaryDirectory : IDisposable
    {
        public TemporaryDirectory()
        {
            Path = System.IO.Path.Combine(
                System.IO.Path.GetTempPath(),
                $"MonglePetRemotePetTests-{Guid.NewGuid():N}");
            Directory.CreateDirectory(Path);
        }

        public string Path { get; }

        public void Dispose()
        {
            if (Directory.Exists(Path))
            {
                Directory.Delete(Path, recursive: true);
            }
        }
    }
}
