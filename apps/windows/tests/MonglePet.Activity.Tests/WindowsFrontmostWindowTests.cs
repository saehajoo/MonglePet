using MonglePet.Activity;
using MonglePet.Core.Movement;

namespace MonglePet.Activity.Tests;

public sealed class WindowsFrontmostWindowResolverTests
{
    private static readonly IReadOnlyList<MovementScreen> Screens =
        [new MovementScreen("main", new MovementRect(0, 0, 1440, 860))];

    [Fact]
    public void ResolverFiltersNonUserFacingWindowsAndChoosesLargestVisibleArea()
    {
        MovementRect? window = WindowsFrontmostWindowResolver.RepresentativeWindow(
            42,
            [
                Snapshot(7, new MovementRect(0, 0, 1000, 700)),
                Snapshot(42, new MovementRect(0, 0, 1200, 700), visible: false),
                Snapshot(42, new MovementRect(0, 0, 1200, 700), hasOwner: true),
                Snapshot(42, new MovementRect(0, 0, 1200, 700), tool: true),
                Snapshot(42, new MovementRect(0, 0, 1200, 700), cloaked: true),
                Snapshot(42, new MovementRect(0, 0, 40, 40)),
                Snapshot(42, new MovementRect(100, 100, 500, 400)),
                Snapshot(42, new MovementRect(300, 200, 200, 100)),
            ],
            Screens);

        Assert.Equal(new MovementRect(100, 100, 500, 400), window);
    }

    [Fact]
    public void ResolverReturnsNullWhenAnyCandidateCoversWorkArea()
    {
        MovementRect? window = WindowsFrontmostWindowResolver.RepresentativeWindow(
            42,
            [
                Snapshot(42, new MovementRect(0, 0, 1440, 900)),
                Snapshot(42, new MovementRect(200, 200, 400, 300)),
            ],
            Screens);

        Assert.Null(window);
    }

    [Fact]
    public void ResolverIgnoresWindowsOutsideKnownScreens()
    {
        MovementRect? window = WindowsFrontmostWindowResolver.RepresentativeWindow(
            42,
            [Snapshot(42, new MovementRect(5000, 5000, 800, 600))],
            Screens);

        Assert.Null(window);
    }

    private static WindowsWindowSnapshot Snapshot(
        uint processId,
        MovementRect bounds,
        bool visible = true,
        bool hasOwner = false,
        bool tool = false,
        bool cloaked = false) =>
        new(processId, visible, hasOwner, tool, cloaked, bounds);
}

public sealed class WindowsFrontmostWindowProviderTests
{
    private static readonly IReadOnlyList<MovementScreen> Screens =
        [new MovementScreen("main", new MovementRect(0, 0, 1440, 860))];

    [Fact]
    public void ProviderCachesSameForegroundWithinRefreshInterval()
    {
        TimeSpan now = TimeSpan.FromSeconds(10);
        int reads = 0;
        var provider = new WindowsFrontmostWindowProvider(
            minimumRefreshInterval: TimeSpan.FromSeconds(1),
            foregroundProvider: () => new WindowsForegroundWindow(100, 42),
            snapshotsProvider: () =>
            {
                reads++;
                return [Snapshot(42)];
            },
            uptimeProvider: () => now,
            currentProcessId: 9);

        Assert.NotNull(provider.RepresentativeWindow(Screens));
        now += TimeSpan.FromMilliseconds(900);
        Assert.NotNull(provider.RepresentativeWindow(Screens));
        Assert.Equal(1, reads);
        now += TimeSpan.FromMilliseconds(100);
        Assert.NotNull(provider.RepresentativeWindow(Screens));
        Assert.Equal(2, reads);
    }

    [Fact]
    public void ProviderRefreshesImmediatelyWhenForegroundChangesAndCanInvalidate()
    {
        TimeSpan now = TimeSpan.FromSeconds(10);
        var foreground = new WindowsForegroundWindow(100, 42);
        int reads = 0;
        var provider = new WindowsFrontmostWindowProvider(
            minimumRefreshInterval: TimeSpan.FromSeconds(10),
            foregroundProvider: () => foreground,
            snapshotsProvider: () =>
            {
                reads++;
                return [Snapshot(foreground.ProcessId)];
            },
            uptimeProvider: () => now,
            currentProcessId: 9);

        Assert.NotNull(provider.RepresentativeWindow(Screens));
        foreground = new WindowsForegroundWindow(200, 77);
        Assert.NotNull(provider.RepresentativeWindow(Screens));
        provider.Invalidate();
        Assert.NotNull(provider.RepresentativeWindow(Screens));
        Assert.Equal(3, reads);
    }

    [Fact]
    public void ProviderSkipsMonglePetWithoutEnumeratingWindows()
    {
        int reads = 0;
        var provider = new WindowsFrontmostWindowProvider(
            foregroundProvider: () => new WindowsForegroundWindow(100, 9),
            snapshotsProvider: () =>
            {
                reads++;
                return [Snapshot(9)];
            },
            currentProcessId: 9);

        Assert.Null(provider.RepresentativeWindow(Screens));
        Assert.Equal(0, reads);
        Assert.Equal("전면 창: MonglePet 제외", provider.Status);
    }

    private static WindowsWindowSnapshot Snapshot(uint processId) =>
        new(
            processId,
            IsVisible: true,
            HasOwner: false,
            IsToolWindow: false,
            IsCloaked: false,
            Bounds: new MovementRect(100, 100, 500, 400));
}
