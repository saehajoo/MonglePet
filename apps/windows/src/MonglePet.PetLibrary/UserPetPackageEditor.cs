using System.Text.Json;
using System.Text.Json.Serialization;
using MonglePet.Packages;

namespace MonglePet.PetLibrary;

public sealed record UserPetFrameSourceRequest(
    string ImagePath,
    int DurationMilliseconds,
    PetPackageFrame? SourceFrame = null,
    bool FlipsHorizontally = false,
    bool FlipsVertically = false,
    UserPetCanvasPlacement? CanvasPlacement = null,
    Guid? FrameId = null,
    UserPetBackgroundRemoval? BackgroundRemoval = null);

public static class UserPetFrameEditing
{
    public static UserPetFrameSourceRequest Duplicate(
        UserPetFrameSourceRequest source,
        Func<Guid>? idGenerator = null)
    {
        ArgumentNullException.ThrowIfNull(source);
        idGenerator ??= Guid.NewGuid;
        Guid id;
        do
        {
            id = idGenerator();
        }
        while (id == Guid.Empty || id == source.FrameId);
        return source with { FrameId = id };
    }
}

public sealed record UserPetCreationRequest(
    string DisplayName,
    string AnimationName,
    bool Loops,
    IReadOnlyList<UserPetFrameSourceRequest> Frames,
    string Version,
    string Author,
    string? Description);

public sealed record UserPetAnimationRequest(
    string AnimationName,
    bool Loops,
    IReadOnlyList<UserPetFrameSourceRequest> Frames);

public sealed record UserPetAnimationUpdateRequest(
    string AnimationId,
    string AnimationName,
    bool Loops,
    IReadOnlyList<UserPetFrameSourceRequest> Frames);

public sealed record UserPetDetailsRequest(
    string DisplayName,
    string Version,
    string Author,
    string? Description,
    string DefaultMotionId);

public sealed record UserPetBuiltAtlas(
    byte[] PngBytes,
    byte[] PreviewPngBytes,
    int PixelWidth,
    int PixelHeight,
    IReadOnlyList<PetPackageFrame> Frames);

public interface IUserPetAtlasBuilder
{
    Task<UserPetBuiltAtlas> BuildAsync(
        IReadOnlyList<UserPetFrameSourceRequest> frames,
        CancellationToken cancellationToken = default);
}

public enum UserPetEditingError
{
    InvalidPetName,
    InvalidVersion,
    InvalidAuthor,
    InvalidAnimationName,
    InvalidDefaultAnimation,
    AnimationNotFound,
    DuplicateAnimationName,
    EmptyAnimation,
    InvalidFrameDuration,
    CannotDeleteDefaultAnimation,
    CannotDeleteLastAnimation,
    ImportedPackageIsReadOnly,
    PetIsAlreadyEditable,
    FileOperationFailed,
}

public sealed class UserPetEditingException(
    UserPetEditingError error,
    string message,
    Exception? innerException = null) : Exception(message, innerException)
{
    public UserPetEditingError Error { get; } = error;
}

public sealed class UserPetPackageEditor
{
    public const string MarkerFileName = "monglepet-editor.json";
    private readonly PetLibraryStore _store;
    private readonly IUserPetAtlasBuilder _atlasBuilder;
    private readonly PetPackageLoader _loader;

    public UserPetPackageEditor(
        PetLibraryStore store,
        IUserPetAtlasBuilder atlasBuilder,
        PetPackageLoader? loader = null)
    {
        _store = store ?? throw new ArgumentNullException(nameof(store));
        _atlasBuilder = atlasBuilder ?? throw new ArgumentNullException(nameof(atlasBuilder));
        _loader = loader ?? new PetPackageLoader();
    }

    public bool IsEditable(InstalledPetPackage installed)
    {
        string path = Path.Combine(installed.RootPath, MarkerFileName);
        try
        {
            EditorMarker? marker = JsonSerializer.Deserialize<EditorMarker>(File.ReadAllBytes(path));
            return marker is { SchemaVersion: 1 } && string.Equals(
                marker.PackageId,
                installed.Package.Manifest.Id,
                StringComparison.Ordinal);
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException or JsonException)
        {
            return false;
        }
    }

    public async Task<InstalledPetPackage> CreatePetAsync(
        UserPetCreationRequest request,
        CancellationToken cancellationToken = default)
    {
        ValidDetails details = ValidateDetails(
            request.DisplayName,
            request.Version,
            request.Author,
            request.Description);
        string animationName = ValidateAnimationName(request.AnimationName);
        ValidateFrames(request.Frames);
        UserPetBuiltAtlas atlas = await _atlasBuilder.BuildAsync(request.Frames, cancellationToken);
        string packageId = $"kr.mapleroom.monglepet.user.{Guid.NewGuid():N}";

        return WithWorkspace(workspace =>
        {
            string atlasPath = "assets/spritesheet.png";
            WriteAsset(workspace, atlasPath, atlas.PngBytes);
            WriteAsset(workspace, "preview.png", atlas.PreviewPngBytes);
            var manifest = new PetPackageManifest(
                1,
                packageId,
                details.DisplayName,
                details.Version,
                details.Author,
                details.Description,
                "preview.png",
                animationName,
                [new PetPackageAtlas("main", atlasPath, atlas.PixelWidth, atlas.PixelHeight)],
                [new PetPackageMotion(animationName, "main", request.Loops, atlas.Frames)]);
            WriteManifest(workspace, manifest);
            WriteMarker(workspace, packageId);
            _loader.LoadDirectory(workspace);
            return _store.InstallEditableFromDirectory(workspace);
        });
    }

    public InstalledPetPackage CreateEditableCopy(
        InstalledPetPackage installed,
        string displayName)
    {
        if (IsEditable(installed))
        {
            throw Error(UserPetEditingError.PetIsAlreadyEditable, "이미 편집 가능한 펫입니다.");
        }
        string normalizedName = Required(displayName, UserPetEditingError.InvalidPetName, "펫 이름을 입력해 주세요.");
        string packageId = $"kr.mapleroom.monglepet.user.{Guid.NewGuid():N}";
        return EditCopy(installed, replace: false, (workspace, manifest) =>
        {
            PetPackageManifest updated = manifest with
            {
                Id = packageId,
                DisplayName = normalizedName,
            };
            WriteManifest(workspace, updated);
            WriteMarker(workspace, packageId);
        });
    }

    public InstalledPetPackage UpdateDetails(
        InstalledPetPackage installed,
        UserPetDetailsRequest request)
    {
        EnsureEditable(installed);
        ValidDetails details = ValidateDetails(
            request.DisplayName,
            request.Version,
            request.Author,
            request.Description);
        if (!installed.Package.Manifest.Motions.Any(value =>
            string.Equals(value.Id, request.DefaultMotionId, StringComparison.Ordinal)))
        {
            throw Error(UserPetEditingError.InvalidDefaultAnimation, "기본 애니메이션을 찾을 수 없습니다.");
        }
        return EditCopy(installed, replace: true, (workspace, manifest) =>
            WriteManifest(workspace, manifest with
            {
                DisplayName = details.DisplayName,
                Version = details.Version,
                Author = details.Author,
                Description = details.Description,
                DefaultMotion = request.DefaultMotionId,
            }));
    }

    public async Task<InstalledPetPackage> AddAnimationAsync(
        InstalledPetPackage installed,
        UserPetAnimationRequest request,
        CancellationToken cancellationToken = default)
    {
        EnsureEditable(installed);
        string name = ValidateAnimationName(request.AnimationName);
        EnsureUniqueMotion(installed.Package.Manifest, name, except: null);
        ValidateFrames(request.Frames);
        UserPetBuiltAtlas built = await _atlasBuilder.BuildAsync(request.Frames, cancellationToken);
        string resource = Guid.NewGuid().ToString("N");
        string atlasId = $"user-{resource}";
        string atlasPath = $"assets/user-{resource}.png";
        return EditCopy(installed, replace: true, (workspace, manifest) =>
        {
            WriteAsset(workspace, atlasPath, built.PngBytes);
            WriteManifest(workspace, manifest with
            {
                Atlases = [.. manifest.Atlases, new PetPackageAtlas(atlasId, atlasPath, built.PixelWidth, built.PixelHeight)],
                Motions = [.. manifest.Motions, new PetPackageMotion(name, atlasId, request.Loops, built.Frames)],
            });
        });
    }

    public async Task<InstalledPetPackage> UpdateAnimationAsync(
        InstalledPetPackage installed,
        UserPetAnimationUpdateRequest request,
        CancellationToken cancellationToken = default)
    {
        EnsureEditable(installed);
        PetPackageMotion original = installed.Package.Manifest.Motions.FirstOrDefault(value =>
            string.Equals(value.Id, request.AnimationId, StringComparison.Ordinal))
            ?? throw Error(UserPetEditingError.AnimationNotFound, "애니메이션을 찾을 수 없습니다.");
        string name = ValidateAnimationName(request.AnimationName);
        EnsureUniqueMotion(installed.Package.Manifest, name, request.AnimationId);
        ValidateFrames(request.Frames);
        UserPetBuiltAtlas built = await _atlasBuilder.BuildAsync(request.Frames, cancellationToken);
        string resource = Guid.NewGuid().ToString("N");
        string atlasId = $"user-{resource}";
        string atlasPath = $"assets/user-{resource}.png";
        return EditCopy(installed, replace: true, (workspace, manifest) =>
        {
            bool sharedAtlas = manifest.Motions.Any(value =>
                !string.Equals(value.Id, request.AnimationId, StringComparison.Ordinal) &&
                string.Equals(value.Atlas, original.Atlas, StringComparison.Ordinal));
            PetPackageAtlas? oldAtlas = manifest.Atlases.FirstOrDefault(value => value.Id == original.Atlas);
            IReadOnlyList<PetPackageAtlas> atlases = sharedAtlas
                ? [.. manifest.Atlases, new PetPackageAtlas(atlasId, atlasPath, built.PixelWidth, built.PixelHeight)]
                : [.. manifest.Atlases.Where(value => value.Id != original.Atlas), new PetPackageAtlas(atlasId, atlasPath, built.PixelWidth, built.PixelHeight)];
            WriteAsset(workspace, atlasPath, built.PngBytes);
            if (!sharedAtlas && oldAtlas is not null)
            {
                TryDeleteFile(Path.Combine(workspace, FromPackagePath(oldAtlas.Path)));
            }
            WriteManifest(workspace, manifest with
            {
                DefaultMotion = string.Equals(manifest.DefaultMotion, request.AnimationId, StringComparison.Ordinal)
                    ? name
                    : manifest.DefaultMotion,
                Atlases = atlases,
                Motions = manifest.Motions.Select(value =>
                    string.Equals(value.Id, request.AnimationId, StringComparison.Ordinal)
                        ? new PetPackageMotion(name, atlasId, request.Loops, built.Frames)
                        : value).ToArray(),
            });
        });
    }

    public InstalledPetPackage RemoveAnimation(InstalledPetPackage installed, string animationId)
    {
        EnsureEditable(installed);
        PetPackageManifest manifest = installed.Package.Manifest;
        PetPackageMotion removed = manifest.Motions.FirstOrDefault(value => value.Id == animationId)
            ?? throw Error(UserPetEditingError.AnimationNotFound, "애니메이션을 찾을 수 없습니다.");
        if (manifest.Motions.Count <= 1)
        {
            throw Error(UserPetEditingError.CannotDeleteLastAnimation, "마지막 남은 애니메이션은 삭제할 수 없습니다.");
        }
        if (string.Equals(installed.Package.DefaultMotionId, animationId, StringComparison.Ordinal))
        {
            throw Error(UserPetEditingError.CannotDeleteDefaultAnimation, "기본 애니메이션은 먼저 다른 기본값을 선택한 뒤 삭제할 수 있습니다.");
        }
        return EditCopy(installed, replace: true, (workspace, current) =>
        {
            PetPackageMotion[] motions = current.Motions.Where(value => value.Id != animationId).ToArray();
            bool atlasUsed = motions.Any(value => value.Atlas == removed.Atlas);
            PetPackageAtlas? oldAtlas = current.Atlases.FirstOrDefault(value => value.Id == removed.Atlas);
            if (!atlasUsed && oldAtlas is not null)
            {
                TryDeleteFile(Path.Combine(workspace, FromPackagePath(oldAtlas.Path)));
            }
            WriteManifest(workspace, current with
            {
                Motions = motions,
                Atlases = atlasUsed ? current.Atlases : current.Atlases.Where(value => value.Id != removed.Atlas).ToArray(),
            });
        });
    }

    private InstalledPetPackage EditCopy(
        InstalledPetPackage installed,
        bool replace,
        Action<string, PetPackageManifest> edit) =>
        WithWorkspace(workspace =>
        {
            CopyDirectory(installed.RootPath, workspace);
            PetPackageManifest manifest = installed.Package.Manifest;
            edit(workspace, manifest);
            _loader.LoadDirectory(workspace);
            return _store.InstallEditableFromDirectory(
                workspace,
                replace ? PetPackageInstallMode.Replace : PetPackageInstallMode.InstallSeparately,
                replace ? installed.InstallationId : null);
        }, createWorkspace: false);

    private T WithWorkspace<T>(Func<string, T> operation, bool createWorkspace = true)
    {
        _store.EnsureLibraryRoot();
        string workspace = Path.Combine(_store.LibraryRootPath, $".editor-{Guid.NewGuid():N}");
        try
        {
            if (createWorkspace)
            {
                Directory.CreateDirectory(workspace);
            }
            return operation(workspace);
        }
        catch (UserPetEditingException)
        {
            throw;
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException or
            PetPackageLoadException or PetPackageManifestException or PetLibraryException)
        {
            throw Error(UserPetEditingError.FileOperationFailed, "사용자 펫 패키지를 저장하지 못했습니다.", exception);
        }
        finally
        {
            TryDeleteDirectory(workspace);
        }
    }

    private static void ValidateFrames(IReadOnlyList<UserPetFrameSourceRequest> frames)
    {
        if (frames.Count == 0)
        {
            throw Error(UserPetEditingError.EmptyAnimation, "애니메이션에는 프레임이 하나 이상 필요합니다.");
        }
        if (frames.Any(value => value.DurationMilliseconds is < 16 or > 60_000))
        {
            throw Error(UserPetEditingError.InvalidFrameDuration, "프레임 간격은 16~60000ms 사이여야 합니다.");
        }
    }

    private static ValidDetails ValidateDetails(string name, string version, string author, string? description) =>
        new(
            Required(name, UserPetEditingError.InvalidPetName, "펫 이름을 입력해 주세요."),
            Required(version, UserPetEditingError.InvalidVersion, "펫 버전을 입력해 주세요."),
            Required(author, UserPetEditingError.InvalidAuthor, "제작자 이름을 입력해 주세요."),
            string.IsNullOrWhiteSpace(description) ? null : description.Trim());

    private static string ValidateAnimationName(string value) =>
        Required(value, UserPetEditingError.InvalidAnimationName, "애니메이션 이름을 입력해 주세요.");

    private static string Required(string value, UserPetEditingError error, string message) =>
        string.IsNullOrWhiteSpace(value) ? throw Error(error, message) : value.Trim();

    private static void EnsureUniqueMotion(PetPackageManifest manifest, string name, string? except)
    {
        if (manifest.Motions.Any(value =>
            !string.Equals(value.Id, except, StringComparison.Ordinal) &&
            string.Equals(value.Id, name, StringComparison.OrdinalIgnoreCase)))
        {
            throw Error(UserPetEditingError.DuplicateAnimationName, $"같은 이름의 애니메이션이 이미 있습니다: {name}");
        }
    }

    private void EnsureEditable(InstalledPetPackage installed)
    {
        if (!IsEditable(installed))
        {
            throw Error(UserPetEditingError.ImportedPackageIsReadOnly, "MonglePet에서 만든 편집 가능한 펫만 직접 수정할 수 있습니다.");
        }
    }

    private static void WriteManifest(string root, PetPackageManifest manifest) =>
        File.WriteAllBytes(Path.Combine(root, "pet.json"), PetPackageManifestWriter.Write(manifest));

    private static void WriteMarker(string root, string packageId) =>
        File.WriteAllBytes(
            Path.Combine(root, MarkerFileName),
            JsonSerializer.SerializeToUtf8Bytes(new EditorMarker(1, packageId)));

    private static void WriteAsset(string root, string packagePath, byte[] bytes)
    {
        string path = Path.Combine(root, FromPackagePath(packagePath));
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllBytes(path, bytes);
    }

    private static string FromPackagePath(string value) => value.Replace('/', Path.DirectorySeparatorChar);

    private static void CopyDirectory(string source, string destination)
    {
        Directory.CreateDirectory(destination);
        foreach (string directory in Directory.GetDirectories(source, "*", SearchOption.AllDirectories))
        {
            Directory.CreateDirectory(Path.Combine(destination, Path.GetRelativePath(source, directory)));
        }
        foreach (string file in Directory.GetFiles(source, "*", SearchOption.AllDirectories))
        {
            File.Copy(file, Path.Combine(destination, Path.GetRelativePath(source, file)));
        }
    }

    private static void TryDeleteFile(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); } catch (IOException) { } catch (UnauthorizedAccessException) { }
    }

    private static void TryDeleteDirectory(string path)
    {
        try { if (Directory.Exists(path)) Directory.Delete(path, recursive: true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
    }

    private static UserPetEditingException Error(
        UserPetEditingError error,
        string message,
        Exception? innerException = null) => new(error, message, innerException);

    private sealed record EditorMarker(
        [property: JsonPropertyName("schemaVersion")] int SchemaVersion,
        [property: JsonPropertyName("packageID")] string PackageId);
    private sealed record ValidDetails(string DisplayName, string Version, string Author, string? Description);
}
