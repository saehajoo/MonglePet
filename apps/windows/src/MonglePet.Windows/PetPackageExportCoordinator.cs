using MonglePet.PetLibrary;

namespace MonglePet.Windows;

public enum PetPackageExportCoordinatorStatus
{
    Idle,
    Running,
    Succeeded,
    Failed,
}

public sealed record PetPackageExportCoordinatorState(
    PetPackageExportCoordinatorStatus Status,
    PetPackageExportProgress? Progress = null,
    PetPackageExportResult? Result = null,
    string? ErrorMessage = null)
{
    public static PetPackageExportCoordinatorState Idle { get; } =
        new(PetPackageExportCoordinatorStatus.Idle);
}

public sealed class PetPackageExportCoordinator
{
    private PetPackageExportCoordinatorState _state = PetPackageExportCoordinatorState.Idle;

    public event EventHandler? StateChanged;

    public PetPackageExportCoordinatorState State => _state;

    public async Task<PetPackageExportResult> RunAsync(
        Func<IProgress<PetPackageExportProgress>, CancellationToken, Task<PetPackageExportResult>> operation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(operation);
        if (_state.Status == PetPackageExportCoordinatorStatus.Running)
        {
            throw new InvalidOperationException("이미 다른 펫의 공유 파일을 준비하고 있습니다.");
        }

        SetState(new(PetPackageExportCoordinatorStatus.Running));
        var progress = new Progress<PetPackageExportProgress>(value =>
        {
            if (_state.Status == PetPackageExportCoordinatorStatus.Running)
            {
                SetState(_state with { Progress = value });
            }
        });
        try
        {
            PetPackageExportResult result = await operation(progress, cancellationToken);
            SetState(new(PetPackageExportCoordinatorStatus.Succeeded, Result: result));
            return result;
        }
        catch (OperationCanceledException)
        {
            SetState(PetPackageExportCoordinatorState.Idle);
            throw;
        }
        catch (Exception exception)
        {
            SetState(new(
                PetPackageExportCoordinatorStatus.Failed,
                ErrorMessage: exception.Message));
            throw;
        }
    }

    public void DismissResult()
    {
        if (_state.Status != PetPackageExportCoordinatorStatus.Running)
        {
            SetState(PetPackageExportCoordinatorState.Idle);
        }
    }

    private void SetState(PetPackageExportCoordinatorState state)
    {
        _state = state;
        StateChanged?.Invoke(this, EventArgs.Empty);
    }
}
