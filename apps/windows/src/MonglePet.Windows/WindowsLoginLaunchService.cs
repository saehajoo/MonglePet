using Windows.ApplicationModel;

namespace MonglePet.Windows;

public enum LoginLaunchStatus
{
    Disabled,
    Enabled,
    DisabledByUser,
    DisabledByPolicy,
    EnabledByPolicy,
    Unavailable,
}

public sealed class WindowsLoginLaunchService
{
    public const string StartupTaskId = "MonglePetStartupTask";

    public async Task<LoginLaunchStatus> GetStatusAsync()
    {
        try
        {
            StartupTask task = await StartupTask.GetAsync(StartupTaskId);
            return Map(task.State);
        }
        catch (Exception exception) when (
            exception is ArgumentException or UnauthorizedAccessException or InvalidOperationException)
        {
            return LoginLaunchStatus.Unavailable;
        }
    }

    public async Task<LoginLaunchStatus> SetEnabledAsync(bool enabled)
    {
        StartupTask task = await StartupTask.GetAsync(StartupTaskId);
        if (enabled)
        {
            return Map(await task.RequestEnableAsync());
        }
        task.Disable();
        return Map(task.State);
    }

    public static LoginLaunchStatus Map(StartupTaskState state) => state switch
    {
        StartupTaskState.Disabled => LoginLaunchStatus.Disabled,
        StartupTaskState.Enabled => LoginLaunchStatus.Enabled,
        StartupTaskState.DisabledByUser => LoginLaunchStatus.DisabledByUser,
        StartupTaskState.DisabledByPolicy => LoginLaunchStatus.DisabledByPolicy,
        StartupTaskState.EnabledByPolicy => LoginLaunchStatus.EnabledByPolicy,
        _ => LoginLaunchStatus.Unavailable,
    };
}
