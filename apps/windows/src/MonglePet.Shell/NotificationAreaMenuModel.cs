namespace MonglePet.Shell;

public enum NotificationAreaCommand
{
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
    Separator,
}

public sealed record NotificationAreaState(
    bool IsPetAwake,
    string PetDisplayName,
    bool IsClickThrough);

public sealed record NotificationAreaMenuItem(
    NotificationAreaMenuItemKind Kind,
    string Title = "",
    NotificationAreaCommand? Command = null,
    bool IsChecked = false,
    bool IsEnabled = true);

public static class NotificationAreaMenuModel
{
    private const int MaximumVisiblePetNameLength = 40;

    public static IReadOnlyList<NotificationAreaMenuItem> Build(
        NotificationAreaState state)
    {
        ArgumentNullException.ThrowIfNull(state);

        return
        [
            new(
                NotificationAreaMenuItemKind.Label,
                $"현재 펫: {VisiblePetName(state.PetDisplayName)}",
                IsEnabled: false),
            new(NotificationAreaMenuItemKind.Separator),
            new(
                NotificationAreaMenuItemKind.Command,
                state.IsPetAwake ? "펫 재우기" : "펫 깨우기",
                NotificationAreaCommand.TogglePetAwake),
            new(
                NotificationAreaMenuItemKind.Command,
                "클릭 통과",
                NotificationAreaCommand.ToggleClickThrough,
                IsChecked: state.IsClickThrough),
            new(
                NotificationAreaMenuItemKind.Command,
                "펫을 현재 화면으로 가져오기",
                NotificationAreaCommand.BringPetToCurrentScreen),
            new(NotificationAreaMenuItemKind.Separator),
            new(
                NotificationAreaMenuItemKind.Command,
                "설정…",
                NotificationAreaCommand.OpenSettings),
            new(NotificationAreaMenuItemKind.Separator),
            new(
                NotificationAreaMenuItemKind.Command,
                "MonglePet 종료",
                NotificationAreaCommand.Quit),
        ];
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
