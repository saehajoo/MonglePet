using MonglePet.Activity;

namespace MonglePet.Activity.Tests;

public sealed class WindowsActivityTests
{
    [Theory]
    [InlineData(" Microsoft.WindowsCalculator_8wekyb3d8bbwe ", "pfn:microsoft.windowscalculator_8wekyb3d8bbwe")]
    [InlineData("MONGLEPET_123", "pfn:monglepet_123")]
    public void PackageFamilyIdentifierIsTrimmedAndNormalized(
        string value,
        string expected) =>
        Assert.Equal(expected, WindowsApplicationIdentifier.FromPackageFamilyName(value));

    [Theory]
    [InlineData(@"C:\Windows\System32\NOTEPAD.EXE", "exe:notepad.exe")]
    [InlineData(" monglepet.windows.exe ", "exe:monglepet.windows.exe")]
    public void ExecutableIdentifierKeepsOnlyNormalizedFileName(
        string value,
        string expected) =>
        Assert.Equal(expected, WindowsApplicationIdentifier.FromExecutablePath(value));

    [Fact]
    public void EmptyApplicationIdentifiersAreUnavailable()
    {
        Assert.Null(WindowsApplicationIdentifier.FromPackageFamilyName("  "));
        Assert.Null(WindowsApplicationIdentifier.FromExecutablePath(null));
    }

    [Fact]
    public void NativeSessionAndPowerMessagesUpdateOnlyTheirState()
    {
        WindowsActivitySystemState state = WindowsActivitySystemState.Available;
        state = state.ApplyNativeMessage(
            WindowsActivitySystemState.SessionChangeMessage,
            WindowsActivitySystemState.SessionLock);
        Assert.True(state.IsScreenLocked);
        Assert.False(state.IsSystemSleeping);

        state = state.ApplyNativeMessage(
            WindowsActivitySystemState.PowerBroadcastMessage,
            WindowsActivitySystemState.PowerSuspend);
        Assert.True(state.IsScreenLocked);
        Assert.True(state.IsSystemSleeping);

        state = state.ApplyNativeMessage(
            WindowsActivitySystemState.SessionChangeMessage,
            WindowsActivitySystemState.SessionUnlock);
        state = state.ApplyNativeMessage(
            WindowsActivitySystemState.PowerBroadcastMessage,
            WindowsActivitySystemState.PowerResumeAutomatic);
        Assert.Equal(WindowsActivitySystemState.Available, state);
    }

    [Fact]
    public void UnknownNativeMessagePreservesState()
    {
        var state = new WindowsActivitySystemState(true, true);
        Assert.Same(state, state.ApplyNativeMessage(0xFFFF, 999));
    }

    [Fact]
    public void SnapshotFactoryReadsActivityOnlyWhenScreenIsAvailable()
    {
        var reader = new FakeReader(
            TimeSpan.FromSeconds(42),
            "exe:editor.exe");
        var factory = new ActivitySnapshotFactory(reader);

        var active = factory.Create(
            TimeSpan.FromSeconds(10),
            WindowsActivitySystemState.Available);
        Assert.Equal(TimeSpan.FromSeconds(42), active.IdleDuration);
        Assert.Equal("exe:editor.exe", active.FrontmostApplicationId);
        Assert.Equal(2, reader.ReadCount);

        var locked = factory.Create(
            TimeSpan.FromSeconds(11),
            new WindowsActivitySystemState(true, false));
        Assert.True(locked.IsScreenLocked);
        Assert.Equal(TimeSpan.Zero, locked.IdleDuration);
        Assert.Null(locked.FrontmostApplicationId);
        Assert.Equal(2, reader.ReadCount);
    }

    [Fact]
    public void SnapshotFactoryClampsNegativeIdleDuration()
    {
        var factory = new ActivitySnapshotFactory(
            new FakeReader(TimeSpan.FromSeconds(-1), null));
        var snapshot = factory.Create(
            TimeSpan.Zero,
            WindowsActivitySystemState.Available);
        Assert.Equal(TimeSpan.Zero, snapshot.IdleDuration);
    }

    private sealed class FakeReader(
        TimeSpan idleDuration,
        string? applicationId) : IWindowsActivityReader
    {
        public int ReadCount { get; private set; }

        public TimeSpan ReadIdleDuration()
        {
            ReadCount++;
            return idleDuration;
        }

        public string? ReadFrontmostApplicationId()
        {
            ReadCount++;
            return applicationId;
        }
    }
}
