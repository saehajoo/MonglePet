namespace MonglePet.Activity;

public sealed record WindowsActivitySystemState(
    bool IsScreenLocked,
    bool IsSystemSleeping)
{
    public const uint SessionChangeMessage = 0x02B1;
    public const nuint SessionLock = 0x7;
    public const nuint SessionUnlock = 0x8;
    public const uint PowerBroadcastMessage = 0x0218;
    public const nuint PowerSuspend = 0x4;
    public const nuint PowerResumeSuspend = 0x7;
    public const nuint PowerResumeAutomatic = 0x12;

    public static WindowsActivitySystemState Available { get; } = new(false, false);

    public WindowsActivitySystemState ApplyNativeMessage(uint message, nuint parameter) =>
        (message, parameter) switch
        {
            (SessionChangeMessage, SessionLock) => this with { IsScreenLocked = true },
            (SessionChangeMessage, SessionUnlock) => this with { IsScreenLocked = false },
            (PowerBroadcastMessage, PowerSuspend) => this with { IsSystemSleeping = true },
            (PowerBroadcastMessage, PowerResumeSuspend or PowerResumeAutomatic) =>
                this with { IsSystemSleeping = false },
            _ => this,
        };
}
