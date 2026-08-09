using MonglePet.Core.Behavior;

namespace MonglePet.Activity;

public sealed class ActivitySnapshotFactory(IWindowsActivityReader reader)
{
    private readonly IWindowsActivityReader _reader =
        reader ?? throw new ArgumentNullException(nameof(reader));

    public ActivitySnapshot Create(
        TimeSpan capturedAt,
        WindowsActivitySystemState systemState)
    {
        ArgumentNullException.ThrowIfNull(systemState);
        if (systemState.IsScreenLocked || systemState.IsSystemSleeping)
        {
            return new ActivitySnapshot(
                capturedAt,
                TimeSpan.Zero,
                null,
                systemState.IsScreenLocked,
                systemState.IsSystemSleeping);
        }

        TimeSpan idleDuration = _reader.ReadIdleDuration();
        return new ActivitySnapshot(
            capturedAt,
            idleDuration < TimeSpan.Zero ? TimeSpan.Zero : idleDuration,
            _reader.ReadFrontmostApplicationId(),
            false,
            false);
    }
}
