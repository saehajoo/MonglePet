namespace MonglePet.Shell;

public enum NotificationAreaCommand
{
    WakeAllPets,
    TuckAwayAllPets,
    ToggleAllPetsPaused,
    SelectPet,
    TogglePetAwake,
    ToggleClickThrough,
    BringPetToCurrentScreen,
    OpenSettings,
    Quit,
}

public enum NotificationAreaMenuItemKind
{
    Label,
    Command,
    Submenu,
    Separator,
}

public sealed record NotificationAreaPetState(
    Guid InstanceId,
    string DisplayName,
    bool IsAwake,
    bool IsClickThrough,
    bool IsSelected);

public sealed record NotificationAreaState(
    IReadOnlyList<NotificationAreaPetState> Pets,
    bool AreAllPetsPaused,
    bool HasResourceWarning = false,
    bool IsSafeStart = false)
{
    public NotificationAreaState(bool isPetAwake, string petDisplayName, bool isClickThrough)
        : this(
            [new NotificationAreaPetState(Guid.Empty, petDisplayName, isPetAwake, isClickThrough, true)],
            false)
    {
    }
}

public sealed record NotificationAreaMenuItem(
    NotificationAreaMenuItemKind Kind,
    string Title = "",
    NotificationAreaCommand? Command = null,
    Guid? InstanceId = null,
    bool IsChecked = false,
    bool IsEnabled = true,
    IReadOnlyList<NotificationAreaMenuItem>? Children = null);

public static class NotificationAreaMenuModel
{
    private const int MaximumVisiblePetNameLength = 40;

    public static IReadOnlyList<NotificationAreaMenuItem> Build(NotificationAreaState state)
    {
        ArgumentNullException.ThrowIfNull(state);
        var items = new List<NotificationAreaMenuItem>();
        if (state.IsSafeStart)
        {
            items.Add(new(NotificationAreaMenuItemKind.Label, "안전 시작: 설정에서 복원을 선택하세요", IsEnabled: false));
            items.Add(new(NotificationAreaMenuItemKind.Separator));
        }
        if (state.HasResourceWarning)
        {
            items.Add(new(NotificationAreaMenuItemKind.Label, "성능 사용량이 지속적으로 높습니다", IsEnabled: false));
            items.Add(new(NotificationAreaMenuItemKind.Separator));
        }

        items.Add(new(
            NotificationAreaMenuItemKind.Command,
            "모든 펫 깨우기",
            NotificationAreaCommand.WakeAllPets,
            IsEnabled: state.Pets.Any(pet => !pet.IsAwake)));
        items.Add(new(
            NotificationAreaMenuItemKind.Command,
            "모든 펫 재우기",
            NotificationAreaCommand.TuckAwayAllPets,
            IsEnabled: state.Pets.Any(pet => pet.IsAwake)));
        items.Add(new(
            NotificationAreaMenuItemKind.Command,
            state.AreAllPetsPaused ? "모든 펫 다시 시작" : "모든 펫 일시정지",
            NotificationAreaCommand.ToggleAllPetsPaused,
            IsChecked: state.AreAllPetsPaused));

        foreach (NotificationAreaPetState pet in state.Pets)
        {
            items.Add(new(NotificationAreaMenuItemKind.Separator));
            items.Add(new(
                NotificationAreaMenuItemKind.Submenu,
                $"{(pet.IsSelected ? "현재 펫" : "펫")}: {VisiblePetName(pet.DisplayName)}",
                IsChecked: pet.IsSelected,
                Children:
                [
                    new(
                        NotificationAreaMenuItemKind.Command,
                        "이 펫 설정 열기",
                        NotificationAreaCommand.SelectPet,
                        pet.InstanceId),
                    new(
                        NotificationAreaMenuItemKind.Command,
                        pet.IsAwake ? "재우기" : "깨우기",
                        NotificationAreaCommand.TogglePetAwake,
                        pet.InstanceId),
                    new(
                        NotificationAreaMenuItemKind.Command,
                        "클릭 통과",
                        NotificationAreaCommand.ToggleClickThrough,
                        pet.InstanceId,
                        IsChecked: pet.IsClickThrough),
                    new(
                        NotificationAreaMenuItemKind.Command,
                        "현재 화면으로 가져오기",
                        NotificationAreaCommand.BringPetToCurrentScreen,
                        pet.InstanceId),
                ]));
        }

        items.Add(new(NotificationAreaMenuItemKind.Separator));
        items.Add(new(
            NotificationAreaMenuItemKind.Command,
            "설정…",
            NotificationAreaCommand.OpenSettings));
        items.Add(new(NotificationAreaMenuItemKind.Separator));
        items.Add(new(
            NotificationAreaMenuItemKind.Command,
            "MonglePet 종료",
            NotificationAreaCommand.Quit));
        return items;
    }

    private static string VisiblePetName(string value)
    {
        string trimmed = value?.Trim() ?? string.Empty;
        if (trimmed.Length == 0)
        {
            return "알 수 없는 펫";
        }
        return trimmed.Length > MaximumVisiblePetNameLength
            ? $"{trimmed[..MaximumVisiblePetNameLength]}…"
            : trimmed;
    }
}
