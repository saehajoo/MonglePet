namespace MonglePet.Core.Movement;

public enum FreeRoamingDwellWaitKind
{
    None,
    Timer,
    BehaviorCompletion,
    BehaviorFallback,
}

public sealed class FreeRoamingDwellState
{
    public FreeRoamingDwellWaitKind Kind { get; private set; }

    public long? UntilTimestamp { get; private set; }

    public void WaitForTimer(long untilTimestamp) =>
        Set(FreeRoamingDwellWaitKind.Timer, untilTimestamp);

    public void WaitForBehaviorCompletion() =>
        Set(FreeRoamingDwellWaitKind.BehaviorCompletion, null);

    public void WaitForBehaviorFallback(long untilTimestamp) =>
        Set(FreeRoamingDwellWaitKind.BehaviorFallback, untilTimestamp);

    public bool IsWaiting(long timestamp)
    {
        if ((Kind == FreeRoamingDwellWaitKind.Timer ||
             Kind == FreeRoamingDwellWaitKind.BehaviorFallback) &&
            UntilTimestamp is long until && timestamp >= until)
        {
            Cancel();
        }
        return Kind != FreeRoamingDwellWaitKind.None;
    }

    public bool CompleteBehavior()
    {
        if (Kind != FreeRoamingDwellWaitKind.BehaviorCompletion)
        {
            return false;
        }
        Cancel();
        return true;
    }

    public void Cancel()
    {
        Kind = FreeRoamingDwellWaitKind.None;
        UntilTimestamp = null;
    }

    private void Set(FreeRoamingDwellWaitKind kind, long? untilTimestamp)
    {
        Kind = kind;
        UntilTimestamp = untilTimestamp;
    }
}
