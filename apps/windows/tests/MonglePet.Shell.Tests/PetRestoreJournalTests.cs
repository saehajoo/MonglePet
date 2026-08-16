using MonglePet.Shell;

namespace MonglePet.Shell.Tests;

public sealed class PetRestoreJournalTests : IDisposable
{
    private readonly string _root = System.IO.Path.Combine(
        System.IO.Path.GetTempPath(),
        $"MonglePet.RestoreJournalTests.{Guid.NewGuid():N}");

    [Fact]
    public void RoundTripsAndClearsIncompleteRestore()
    {
        string path = System.IO.Path.Combine(_root, "restore-journal.json");
        var journal = new PetRestoreJournal(path);
        Guid instanceId = Guid.NewGuid();

        journal.Begin(instanceId, 3);
        PetRestoreRecoveryState state = Assert.IsType<PetRestoreRecoveryState>(journal.Load());
        Assert.Equal(instanceId, state.InstanceId);
        Assert.Equal(3, state.DisplayOrder);

        journal.Complete();
        Assert.Null(journal.Load());
    }

    [Fact]
    public void TreatsOversizedOrInvalidJournalAsSafeStartSignal()
    {
        string path = System.IO.Path.Combine(_root, "restore-journal.json");
        Directory.CreateDirectory(_root);
        File.WriteAllBytes(path, new byte[PetRestoreJournal.MaximumFileSize + 1]);

        PetRestoreRecoveryState state = Assert.IsType<PetRestoreRecoveryState>(
            new PetRestoreJournal(path).Load());

        Assert.Equal(Guid.Empty, state.InstanceId);
        Assert.Equal(-1, state.DisplayOrder);
    }

    public void Dispose()
    {
        if (Directory.Exists(_root))
        {
            Directory.Delete(_root, recursive: true);
        }
    }
}
