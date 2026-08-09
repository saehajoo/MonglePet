using MonglePet.Core.Movement;

namespace MonglePet.Activity;

public static class WindowsFrontmostWindowResolver
{
    public const double MinimumWindowDimension = 64;
    public const double FullScreenCoverageThreshold = 0.98;

    public static MovementRect? RepresentativeWindow(
        uint? frontmostProcessId,
        IEnumerable<WindowsWindowSnapshot> snapshots,
        IReadOnlyList<MovementScreen> screens)
    {
        ArgumentNullException.ThrowIfNull(snapshots);
        ArgumentNullException.ThrowIfNull(screens);
        if (frontmostProcessId is not > 0)
        {
            return null;
        }

        MovementRect[] workAreas = screens
            .Select(screen => screen.WorkArea)
            .Where(area => area.IsValid)
            .ToArray();
        if (workAreas.Length == 0)
        {
            return null;
        }

        Candidate[] candidates = snapshots
            .Where(snapshot =>
                snapshot.ProcessId == frontmostProcessId &&
                snapshot.IsVisible &&
                !snapshot.HasOwner &&
                !snapshot.IsToolWindow &&
                !snapshot.IsCloaked &&
                snapshot.Bounds.IsValid &&
                snapshot.Bounds.Width >= MinimumWindowDimension &&
                snapshot.Bounds.Height >= MinimumWindowDimension)
            .Select(snapshot => new Candidate(
                snapshot.Bounds,
                workAreas.Sum(area => IntersectionArea(snapshot.Bounds, area)),
                workAreas.Any(area => IsFullScreen(snapshot.Bounds, area))))
            .Where(candidate => candidate.VisibleArea > 0)
            .ToArray();
        if (candidates.Any(candidate => candidate.IsFullScreen))
        {
            return null;
        }
        return candidates.MaxBy(candidate => candidate.VisibleArea)?.Bounds;
    }

    private static bool IsFullScreen(MovementRect window, MovementRect workArea)
    {
        double workAreaSize = workArea.Width * workArea.Height;
        double windowSize = window.Width * window.Height;
        return workAreaSize > 0 &&
            windowSize >= workAreaSize * FullScreenCoverageThreshold &&
            IntersectionArea(window, workArea) / workAreaSize >=
                FullScreenCoverageThreshold;
    }

    private static double IntersectionArea(MovementRect left, MovementRect right)
    {
        double width = Math.Max(0, Math.Min(left.Right, right.Right) -
            Math.Max(left.Left, right.Left));
        double height = Math.Max(0, Math.Min(left.Bottom, right.Bottom) -
            Math.Max(left.Top, right.Top));
        return width * height;
    }

    private sealed record Candidate(
        MovementRect Bounds,
        double VisibleArea,
        bool IsFullScreen);
}
