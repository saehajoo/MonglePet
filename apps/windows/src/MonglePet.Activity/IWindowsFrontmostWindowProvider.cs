using MonglePet.Core.Movement;

namespace MonglePet.Activity;

public interface IWindowsFrontmostWindowProvider
{
    string Status { get; }

    MovementRect? RepresentativeWindow(IReadOnlyList<MovementScreen> screens);

    void Invalidate();
}

public sealed record WindowsForegroundWindow(nint Handle, uint ProcessId);

public sealed record WindowsWindowSnapshot(
    uint ProcessId,
    bool IsVisible,
    bool HasOwner,
    bool IsToolWindow,
    bool IsCloaked,
    MovementRect Bounds);
