using MonglePet.Shell;

namespace MonglePet.Shell.Tests;

public sealed class EditorDraftStateTests
{
    [Fact]
    public void DetectsMeaningfulChangeAndTreatsRevertedDraftAsClean()
    {
        string value = "initial";
        var state = new EditorDraftState(() => value);

        Assert.False(state.HasChanges);
        value = "changed";
        Assert.True(state.HasChanges);
        value = "initial";
        Assert.False(state.HasChanges);
    }
}
