using MonglePet.Core.Behavior;

namespace MonglePet.Settings.Tests;

public sealed class LatestSettingsPersistenceTests
{
    [Fact]
    public void FailureKeepsLatestMemoryAndRetrySavesValueAtClickTime()
    {
        AppSettings current = AppSettings.Default;
        var saved = new List<AppSettings>();
        bool fails = true;
        var persistence = new LatestSettingsPersistence(
            () => current,
            settings =>
            {
                if (fails)
                {
                    throw new IOException("disk unavailable");
                }
                saved.Add(settings);
            });

        current = current.WithSelectedPresentation(PetPresentation.TuckedAway);
        Assert.False(persistence.SaveLatest());
        Assert.Equal("disk unavailable", persistence.Failure?.Message);

        current = current.WithSelectedPresentation(PetPresentation.Awake)
            .WithSelectedOverlay(current.Overlay with { Width = 271 });
        fails = false;

        Assert.True(persistence.Retry());
        Assert.Null(persistence.Failure);
        AppSettings written = Assert.Single(saved);
        Assert.Equal(PetPresentation.Awake, written.LastUserPresentation);
        Assert.Equal(271, written.Overlay.Width);
    }

    [Fact]
    public void RepeatedFailureRemainsVisibleUntilSuccessfulSave()
    {
        AppSettings current = AppSettings.Default;
        int attempts = 0;
        var persistence = new LatestSettingsPersistence(
            () => current,
            _ =>
            {
                attempts++;
                throw new InvalidOperationException($"failure {attempts}");
            });

        Assert.False(persistence.SaveLatest());
        Assert.False(persistence.Retry());

        Assert.Equal(2, attempts);
        Assert.Equal("failure 2", persistence.Failure?.Message);
    }
}
