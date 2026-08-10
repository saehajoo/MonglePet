using Microsoft.Win32;
using MonglePet.Shell;
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
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string RunValueName = "MonglePet";
    private readonly bool _isPackaged;
    private readonly string? _executablePath;

    public WindowsLoginLaunchService()
    {
        _isPackaged = WindowsPackageIdentity.IsCurrentProcessPackaged();
        _executablePath = Environment.ProcessPath;
    }

    public async Task<LoginLaunchStatus> GetStatusAsync()
    {
        if (!_isPackaged)
        {
            return GetUnpackagedStatus();
        }

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
        if (!_isPackaged)
        {
            return SetUnpackagedEnabled(enabled);
        }

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

    private LoginLaunchStatus GetUnpackagedStatus()
    {
        if (string.IsNullOrWhiteSpace(_executablePath))
        {
            return LoginLaunchStatus.Unavailable;
        }

        try
        {
            using RegistryKey? key = Registry.CurrentUser.OpenSubKey(RunKeyPath);
            string? storedCommand = key?.GetValue(RunValueName) as string;
            return WindowsRunAtLoginCommand.Matches(storedCommand, _executablePath)
                ? LoginLaunchStatus.Enabled
                : LoginLaunchStatus.Disabled;
        }
        catch (Exception exception) when (
            exception is UnauthorizedAccessException or IOException or System.Security.SecurityException)
        {
            return LoginLaunchStatus.Unavailable;
        }
    }

    private LoginLaunchStatus SetUnpackagedEnabled(bool enabled)
    {
        if (string.IsNullOrWhiteSpace(_executablePath))
        {
            return LoginLaunchStatus.Unavailable;
        }

        try
        {
            using RegistryKey key = Registry.CurrentUser.CreateSubKey(RunKeyPath, writable: true);
            if (enabled)
            {
                key.SetValue(
                    RunValueName,
                    WindowsRunAtLoginCommand.Create(_executablePath),
                    RegistryValueKind.String);
            }
            else
            {
                string? storedCommand = key.GetValue(RunValueName) as string;
                if (WindowsRunAtLoginCommand.Matches(storedCommand, _executablePath))
                {
                    key.DeleteValue(RunValueName, throwOnMissingValue: false);
                }
            }
            return GetUnpackagedStatus();
        }
        catch (Exception exception) when (
            exception is UnauthorizedAccessException or IOException or System.Security.SecurityException)
        {
            return LoginLaunchStatus.Unavailable;
        }
    }
}
