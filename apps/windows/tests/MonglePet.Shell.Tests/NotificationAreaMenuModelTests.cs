using MonglePet.Shell;

namespace MonglePet.Shell.Tests;

public sealed class NotificationAreaMenuModelTests
{
    [Fact]
    public void BuildsMacParityCommandOrderAndCheckedState()
    {
        IReadOnlyList<NotificationAreaMenuItem> items = NotificationAreaMenuModel.Build(
            new NotificationAreaState(true, "몽글이", true));

        Assert.Equal(9, items.Count);
        Assert.Equal("현재 펫: 몽글이", items[0].Title);
        Assert.Equal(NotificationAreaMenuItemKind.Separator, items[1].Kind);
        Assert.Equal("펫 재우기", items[2].Title);
        Assert.Equal(NotificationAreaCommand.TogglePetAwake, items[2].Command);
        Assert.Equal(NotificationAreaCommand.ToggleClickThrough, items[3].Command);
        Assert.True(items[3].IsChecked);
        Assert.Equal(NotificationAreaCommand.BringPetToCurrentScreen, items[4].Command);
        Assert.Equal(NotificationAreaCommand.OpenSettings, items[6].Command);
        Assert.Equal(NotificationAreaCommand.Quit, items[8].Command);
    }

    [Fact]
    public void UsesWakeTitleForSleepingPet()
    {
        IReadOnlyList<NotificationAreaMenuItem> items = NotificationAreaMenuModel.Build(
            new NotificationAreaState(false, "몽글이", false));

        Assert.Equal("펫 깨우기", items[2].Title);
        Assert.False(items[3].IsChecked);
    }

    [Fact]
    public void TrimsAndTruncatesLongPetName()
    {
        string value = $"  {new string('가', 41)}  ";

        IReadOnlyList<NotificationAreaMenuItem> items = NotificationAreaMenuModel.Build(
            new NotificationAreaState(true, value, false));

        Assert.Equal($"현재 펫: {new string('가', 40)}…", items[0].Title);
    }

    [Fact]
    public void RecoversMissingPetName()
    {
        IReadOnlyList<NotificationAreaMenuItem> items = NotificationAreaMenuModel.Build(
            new NotificationAreaState(true, "  ", false));

        Assert.Equal("현재 펫: 알 수 없는 펫", items[0].Title);
        Assert.False(items[0].IsEnabled);
    }
}
