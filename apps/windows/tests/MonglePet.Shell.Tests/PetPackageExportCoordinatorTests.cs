using MonglePet.PetLibrary;
using MonglePet.Windows;

namespace MonglePet.Shell.Tests;

public sealed class PetPackageExportCoordinatorTests
{
    [Fact]
    public async Task ProgressAndSuccessfulResultSurviveUntilDismissed()
    {
        var coordinator = new PetPackageExportCoordinator();
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        int notifications = 0;
        coordinator.StateChanged += (_, _) => notifications++;

        Task<PetPackageExportResult> operation = coordinator.RunAsync(async (progress, _) =>
        {
            progress.Report(new(PetPackageExportStage.OptimizingImages, 0.42, 2, 5));
            await release.Task;
            return new("C:\\output.monglepet", 12_345);
        });
        await WaitForAsync(() => coordinator.State.Progress is not null);

        Assert.Equal(PetPackageExportCoordinatorStatus.Running, coordinator.State.Status);
        Assert.Equal(0.42, coordinator.State.Progress!.Fraction);
        await Assert.ThrowsAsync<InvalidOperationException>(() => coordinator.RunAsync(
            (_, _) => Task.FromResult(new PetPackageExportResult("ignored", 0))));

        release.SetResult();
        PetPackageExportResult result = await operation;
        Assert.Equal(PetPackageExportCoordinatorStatus.Succeeded, coordinator.State.Status);
        Assert.Equal(result, coordinator.State.Result);
        Assert.True(notifications >= 3);

        coordinator.DismissResult();
        Assert.Equal(PetPackageExportCoordinatorStatus.Idle, coordinator.State.Status);
    }

    [Fact]
    public async Task FailureRemainsInExportContextAndNeverBecomesSuccess()
    {
        var coordinator = new PetPackageExportCoordinator();

        await Assert.ThrowsAsync<InvalidDataException>(() => coordinator.RunAsync(
            (_, _) => Task.FromException<PetPackageExportResult>(
                new InvalidDataException("broken package"))));

        Assert.Equal(PetPackageExportCoordinatorStatus.Failed, coordinator.State.Status);
        Assert.Equal("broken package", coordinator.State.ErrorMessage);
        Assert.Null(coordinator.State.Result);
    }

    private static async Task WaitForAsync(Func<bool> condition)
    {
        DateTime deadline = DateTime.UtcNow.AddSeconds(5);
        while (!condition())
        {
            if (DateTime.UtcNow >= deadline) throw new TimeoutException();
            await Task.Delay(10);
        }
    }
}
