using MonglePet.Shell;

namespace MonglePet.Shell.Tests;

public sealed class NotificationAreaMenuModelTests
{
    [Fact]
    public void BuildsGlobalCommandsBeforePerPetCommands()
    {
        Guid instanceId = Guid.NewGuid();
        IReadOnlyList<NotificationAreaMenuItem> items = NotificationAreaMenuModel.Build(
            new NotificationAreaState(
                [new NotificationAreaPetState(instanceId, "몽글이", true, true, true)],
                false));
        IReadOnlyList<NotificationAreaMenuItem> all = Flatten(items);

        Assert.Equal(NotificationAreaCommand.WakeAllPets, items[0].Command);
        Assert.False(items[0].IsEnabled);
        Assert.Equal(NotificationAreaCommand.TuckAwayAllPets, items[1].Command);
        Assert.Equal(NotificationAreaCommand.ToggleAllPetsPaused, items[2].Command);
        NotificationAreaMenuItem pet = Assert.Single(all, value =>
            value.Command == NotificationAreaCommand.SelectPet);
        Assert.Equal(instanceId, pet.InstanceId);
        Assert.Contains(items, value =>
            value.Kind == NotificationAreaMenuItemKind.Submenu && value.IsChecked);
        Assert.Contains(all, value =>
            value.Command == NotificationAreaCommand.ToggleClickThrough &&
            value.InstanceId == instanceId && value.IsChecked);
        Assert.Equal(NotificationAreaCommand.Quit, items[^1].Command);
    }

    [Fact]
    public void BuildsIndependentCommandsForEveryPet()
    {
        Guid first = Guid.NewGuid();
        Guid second = Guid.NewGuid();
        IReadOnlyList<NotificationAreaMenuItem> items = NotificationAreaMenuModel.Build(
            new NotificationAreaState(
                [
                    new NotificationAreaPetState(first, "첫째", true, false, true),
                    new NotificationAreaPetState(second, "둘째", false, true, false),
                ],
                true,
                HasResourceWarning: true));
        IReadOnlyList<NotificationAreaMenuItem> all = Flatten(items);

        Assert.Equal(2, all.Count(value => value.Command == NotificationAreaCommand.SelectPet));
        Assert.Contains(all, value =>
            value.Command == NotificationAreaCommand.TogglePetAwake &&
            value.InstanceId == second && value.Title.Contains("깨우기", StringComparison.Ordinal));
        Assert.Contains(items, value =>
            value.Command == NotificationAreaCommand.ToggleAllPetsPaused && value.IsChecked);
        Assert.Contains(items, value => value.Title.Contains("성능", StringComparison.Ordinal));
    }

    [Fact]
    public void TrimsAndTruncatesLongPetName()
    {
        IReadOnlyList<NotificationAreaMenuItem> items = NotificationAreaMenuModel.Build(
            new NotificationAreaState(
                [new NotificationAreaPetState(Guid.NewGuid(), $"  {new string('가', 41)}  ", true, false, true)],
                false));

        Assert.Contains(items, value => value.Title == $"현재 펫: {new string('가', 40)}…");
    }

    [Fact]
    public void ExposesSafeStartWithoutAddingAutomaticRecoveryCommand()
    {
        IReadOnlyList<NotificationAreaMenuItem> items = NotificationAreaMenuModel.Build(
            new NotificationAreaState([], false, IsSafeStart: true));

        Assert.Contains(items, value => value.Title.Contains("안전 시작", StringComparison.Ordinal));
        Assert.DoesNotContain(items, value => value.Command == NotificationAreaCommand.TogglePetAwake);
        Assert.Contains(items, value => value.Command == NotificationAreaCommand.OpenSettings);
    }

    private static IReadOnlyList<NotificationAreaMenuItem> Flatten(
        IEnumerable<NotificationAreaMenuItem> items) => items
        .SelectMany(item => new[] { item }.Concat(Flatten(item.Children ?? [])))
        .ToList();
}
