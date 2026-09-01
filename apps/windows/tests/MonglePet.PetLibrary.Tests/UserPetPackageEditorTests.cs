using MonglePet.Packages;

namespace MonglePet.PetLibrary.Tests;

public sealed class UserPetPackageEditorTests
{
    [Fact]
    public async Task CreatesEditablePetAndPreservesTrustedMarker()
    {
        using var workspace = new Workspace();
        var store = workspace.CreateStore();
        var editor = new UserPetPackageEditor(store, new FixtureAtlasBuilder());

        InstalledPetPackage installed = await editor.CreatePetAsync(new UserPetCreationRequest(
            "구름이",
            "기본",
            true,
            [Frame()],
            "1.0.0",
            "테스터",
            "설명"));

        Assert.True(editor.IsEditable(installed));
        Assert.True(File.Exists(Path.Combine(installed.RootPath, UserPetPackageEditor.MarkerFileName)));
        Assert.Equal("구름이", installed.Package.Manifest.DisplayName);
        Assert.Equal("기본", installed.Package.DefaultMotionId);
    }

    [Fact]
    public async Task AddsRenamesAndRemovesAnimationAtomically()
    {
        using var workspace = new Workspace();
        var store = workspace.CreateStore();
        var editor = new UserPetPackageEditor(store, new FixtureAtlasBuilder());
        InstalledPetPackage installed = await editor.CreatePetAsync(Request());

        installed = await editor.AddAnimationAsync(
            installed,
            new UserPetAnimationRequest("걷기", true, [Frame(80)]));
        installed = await editor.UpdateAnimationAsync(
            installed,
            new UserPetAnimationUpdateRequest("걷기", "산책", false, [Frame(90)]));

        Assert.Contains(installed.Package.Manifest.Motions, value => value.Id == "산책" && !value.Loop);
        Assert.DoesNotContain(installed.Package.Manifest.Motions, value => value.Id == "걷기");

        installed = editor.RemoveAnimation(installed, "산책");
        Assert.Single(installed.Package.Manifest.Motions);
        Assert.True(editor.IsEditable(installed));
        Assert.DoesNotContain(
            Directory.EnumerateDirectories(workspace.LibraryPath),
            value => Path.GetFileName(value).StartsWith(".editor-", StringComparison.Ordinal));
    }

    [Fact]
    public async Task UpdatesDetailsAndProtectsDefaultAndLastAnimation()
    {
        using var workspace = new Workspace();
        var store = workspace.CreateStore();
        var editor = new UserPetPackageEditor(store, new FixtureAtlasBuilder());
        InstalledPetPackage installed = await editor.CreatePetAsync(Request());

        installed = editor.UpdateDetails(installed, new UserPetDetailsRequest(
            "새 이름",
            "2.0.0",
            "새 제작자",
            null,
            "기본"));

        Assert.Equal("새 이름", installed.Package.Manifest.DisplayName);
        UserPetEditingException exception = Assert.Throws<UserPetEditingException>(
            () => editor.RemoveAnimation(installed, "기본"));
        Assert.Equal(UserPetEditingError.CannotDeleteLastAnimation, exception.Error);
    }

    [Fact]
    public void ImportedPetRequiresIndependentEditableCopy()
    {
        using var workspace = new Workspace();
        var store = workspace.CreateStore();
        var editor = new UserPetPackageEditor(store, new FixtureAtlasBuilder());
        InstalledPetPackage imported = store.InstallFromDirectory(FixturePath());

        InstalledPetPackage copy = editor.CreateEditableCopy(imported, "샘플 사본");

        Assert.False(editor.IsEditable(imported));
        Assert.True(editor.IsEditable(copy));
        Assert.Equal("샘플 사본", copy.Package.Manifest.DisplayName);
        Assert.NotEqual(imported.Package.Manifest.Id, copy.Package.Manifest.Id);
    }

    [Fact]
    public void ImportedPetCanBecomeEditableInPlaceWithoutChangingInstallationIdentity()
    {
        using var workspace = new Workspace();
        var store = workspace.CreateStore();
        var editor = new UserPetPackageEditor(store, new FixtureAtlasBuilder());
        InstalledPetPackage imported = store.InstallFromDirectory(FixturePath());

        InstalledPetPackage editable = editor.MakeEditableInPlace(imported);

        Assert.Equal(imported.InstallationId, editable.InstallationId);
        Assert.Equal(imported.Package.Manifest.Id, editable.Package.Manifest.Id);
        Assert.True(editor.IsEditable(editable));
    }

    [Fact]
    public async Task EditablePetCanAlsoCreateIndependentEditableCopy()
    {
        using var workspace = new Workspace();
        var store = workspace.CreateStore();
        var editor = new UserPetPackageEditor(store, new FixtureAtlasBuilder());
        InstalledPetPackage original = await editor.CreatePetAsync(Request());

        InstalledPetPackage copy = editor.CreateEditableCopy(original, "두 번째 구름이");

        Assert.True(editor.IsEditable(original));
        Assert.True(editor.IsEditable(copy));
        Assert.Equal("두 번째 구름이", copy.Package.Manifest.DisplayName);
        Assert.NotEqual(original.InstallationId, copy.InstallationId);
        Assert.NotEqual(original.Package.Manifest.Id, copy.Package.Manifest.Id);
    }

    [Fact]
    public async Task CanceledFrameEditLeavesInstalledPackageAndTemporaryWorkspaceUnchanged()
    {
        using var workspace = new Workspace();
        var store = workspace.CreateStore();
        var editor = new UserPetPackageEditor(store, new FixtureAtlasBuilder());
        InstalledPetPackage installed = await editor.CreatePetAsync(Request());
        string[] before = FileTree(installed.RootPath);
        var canceledEditor = new UserPetPackageEditor(store, new CancelingAtlasBuilder());

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            canceledEditor.UpdateAnimationAsync(
                installed,
                new UserPetAnimationUpdateRequest("기본", "기본", true, [Frame(450)]),
                new CancellationToken(canceled: true)));

        Assert.Equal(before, FileTree(installed.RootPath));
        Assert.DoesNotContain(
            Directory.EnumerateDirectories(workspace.LibraryPath),
            value => Path.GetFileName(value).StartsWith(".editor-", StringComparison.Ordinal));
    }

    private static UserPetCreationRequest Request() => new(
        "구름이",
        "기본",
        true,
        [Frame()],
        "1.0.0",
        "테스터",
        null);

    private static UserPetFrameSourceRequest Frame(int duration = 120) =>
        new(Path.Combine(FixturePath(), "preview.png"), duration);

    private static string FixturePath() => Path.Combine(
        AppContext.BaseDirectory,
        "Fixtures",
        "ReadOnlySample.monglepet");

    private static string[] FileTree(string root) => Directory
        .EnumerateFiles(root, "*", SearchOption.AllDirectories)
        .OrderBy(path => path, StringComparer.Ordinal)
        .Select(path => $"{Path.GetRelativePath(root, path)}|{Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(path)))}")
        .ToArray();

    private sealed class FixtureAtlasBuilder : IUserPetAtlasBuilder
    {
        public Task<UserPetBuiltAtlas> BuildAsync(
            IReadOnlyList<UserPetFrameSourceRequest> frames,
            CancellationToken cancellationToken = default)
        {
            byte[] png = File.ReadAllBytes(Path.Combine(FixturePath(), "preview.png"));
            var definitions = frames.Select((value, index) =>
                new PetPackageFrame(0, 0, 1254, 1254, value.DurationMilliseconds)).ToArray();
            return Task.FromResult(new UserPetBuiltAtlas(
                png,
                png,
                1254,
                1254,
                definitions));
        }
    }

    private sealed class CancelingAtlasBuilder : IUserPetAtlasBuilder
    {
        public Task<UserPetBuiltAtlas> BuildAsync(
            IReadOnlyList<UserPetFrameSourceRequest> frames,
            CancellationToken cancellationToken = default) =>
            Task.FromCanceled<UserPetBuiltAtlas>(
                cancellationToken.IsCancellationRequested
                    ? cancellationToken
                    : new CancellationToken(canceled: true));
    }

    private sealed class Workspace : IDisposable
    {
        private readonly Queue<Guid> _installationIds = new([
            Guid.Parse("aaaaaaaa-1000-0000-0000-000000000001"),
            Guid.Parse("aaaaaaaa-1000-0000-0000-000000000002"),
            Guid.Parse("aaaaaaaa-1000-0000-0000-000000000003"),
            Guid.Parse("aaaaaaaa-1000-0000-0000-000000000004"),
        ]);
        private int _operation;

        public Workspace()
        {
            RootPath = Path.Combine(Path.GetTempPath(), "MonglePet.UserPetEditor.Tests", Guid.NewGuid().ToString("N"));
            LibraryPath = Path.Combine(RootPath, "Library");
            Directory.CreateDirectory(RootPath);
        }

        public string RootPath { get; }
        public string LibraryPath { get; }

        public PetLibraryStore CreateStore() => new(
            LibraryPath,
            installationIdGenerator: () => _installationIds.Dequeue(),
            operationIdGenerator: () => Guid.Parse($"bbbbbbbb-0000-0000-0000-{++_operation:000000000000}"));

        public void Dispose()
        {
            if (Directory.Exists(RootPath))
            {
                Directory.Delete(RootPath, recursive: true);
            }
        }
    }
}
