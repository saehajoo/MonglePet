namespace MonglePet.Settings;

/// <summary>
/// Keeps an app-lifetime settings save failure while always persisting the
/// latest valid in-memory settings supplied by the owner.
/// </summary>
public sealed class LatestSettingsPersistence(
    Func<AppSettings> currentSettings,
    Action<AppSettings> save)
{
    private readonly Func<AppSettings> _currentSettings =
        currentSettings ?? throw new ArgumentNullException(nameof(currentSettings));
    private readonly Action<AppSettings> _save =
        save ?? throw new ArgumentNullException(nameof(save));

    public Exception? Failure { get; private set; }

    public event EventHandler? FailureChanged;

    public bool SaveLatest()
    {
        try
        {
            _save(_currentSettings());
            SetFailure(null);
            return true;
        }
        catch (Exception exception)
        {
            SetFailure(exception);
            return false;
        }
    }

    public bool Retry() => SaveLatest();

    private void SetFailure(Exception? failure)
    {
        if (ReferenceEquals(Failure, failure) ||
            (Failure is not null && failure is not null &&
             Failure.GetType() == failure.GetType() &&
             string.Equals(Failure.Message, failure.Message, StringComparison.Ordinal)))
        {
            Failure = failure;
            return;
        }

        Failure = failure;
        FailureChanged?.Invoke(this, EventArgs.Empty);
    }
}
