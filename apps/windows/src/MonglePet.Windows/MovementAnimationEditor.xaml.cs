using System.Collections.ObjectModel;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using MonglePet.Core.Behavior;
using MonglePet.Settings;

namespace MonglePet.Windows;

public sealed partial class MovementAnimationEditor : UserControl
{
    private readonly ObservableCollection<MovementAnimationMotionOption> _motions = [];
    private bool _isRefreshing;

    public MovementAnimationEditor()
    {
        InitializeComponent();
        foreach (ComboBox comboBox in MotionComboBoxes())
        {
            comboBox.ItemsSource = _motions;
        }
    }

    public MovementBehaviorSettings Settings { get; private set; } =
        MovementBehaviorSettings.Default;

    public event EventHandler? SettingsChanged;

    public void SetState(
        string title,
        MovementBehaviorSettings settings,
        IEnumerable<BehaviorSequence> behaviors,
        bool canEdit)
    {
        _isRefreshing = true;
        try
        {
            EditorTitleText.Text = title;
            _motions.Clear();
            _motions.Add(new MovementAnimationMotionOption(string.Empty, "기존 행동 유지"));
            foreach (BehaviorSequence behavior in behaviors
                .DistinctBy(value => value.Id))
            {
                _motions.Add(new MovementAnimationMotionOption(
                    behavior.Id,
                    behavior.DisplayName));
            }

            Settings = settings;
            AnimationStyleComboBox.SelectedIndex = settings.UsesDirectionalBehaviors ? 1 : 0;
            UsesDiagonalsToggle.IsOn = settings.UsesDiagonalBehaviors;
            Select(FallbackMotionComboBox, settings.FallbackBehaviorId);
            Select(LeftMotionComboBox, settings.DirectionBehaviorIds.Left);
            Select(RightMotionComboBox, settings.DirectionBehaviorIds.Right);
            Select(UpMotionComboBox, settings.DirectionBehaviorIds.Up);
            Select(DownMotionComboBox, settings.DirectionBehaviorIds.Down);
            Select(UpLeftMotionComboBox, settings.DirectionBehaviorIds.UpLeft);
            Select(UpRightMotionComboBox, settings.DirectionBehaviorIds.UpRight);
            Select(DownLeftMotionComboBox, settings.DirectionBehaviorIds.DownLeft);
            Select(DownRightMotionComboBox, settings.DirectionBehaviorIds.DownRight);
            IsEnabled = canEdit;
            RefreshVisibility();
        }
        finally
        {
            _isRefreshing = false;
        }
    }

    private void AnimationControl_Changed(object sender, object e)
    {
        RefreshVisibility();
        if (_isRefreshing)
        {
            return;
        }

        bool directional = AnimationStyleComboBox.SelectedIndex == 1;
        Settings = new MovementBehaviorSettings(
            Selected(FallbackMotionComboBox),
            directional,
            directional && UsesDiagonalsToggle.IsOn,
            new DirectionalBehaviorIds(
                Selected(LeftMotionComboBox),
                Selected(RightMotionComboBox),
                Selected(UpMotionComboBox),
                Selected(DownMotionComboBox),
                Selected(UpLeftMotionComboBox),
                Selected(UpRightMotionComboBox),
                Selected(DownLeftMotionComboBox),
                Selected(DownRightMotionComboBox)));
        SettingsChanged?.Invoke(this, EventArgs.Empty);
    }

    private void RefreshVisibility()
    {
        bool directional = AnimationStyleComboBox.SelectedIndex == 1;
        DirectionalPanel.Visibility = directional ? Visibility.Visible : Visibility.Collapsed;
        FallbackMotionComboBox.Header = directional
            ? "기본 이동 행동"
            : "이동 중 행동";
        UsesDiagonalsToggle.IsEnabled = directional && IsEnabled;
        Visibility diagonalVisibility = directional && UsesDiagonalsToggle.IsOn
            ? Visibility.Visible
            : Visibility.Collapsed;
        UpLeftMotionComboBox.Visibility = diagonalVisibility;
        UpRightMotionComboBox.Visibility = diagonalVisibility;
        DownLeftMotionComboBox.Visibility = diagonalVisibility;
        DownRightMotionComboBox.Visibility = diagonalVisibility;
    }

    private IEnumerable<ComboBox> MotionComboBoxes()
    {
        yield return FallbackMotionComboBox;
        yield return LeftMotionComboBox;
        yield return RightMotionComboBox;
        yield return UpMotionComboBox;
        yield return DownMotionComboBox;
        yield return UpLeftMotionComboBox;
        yield return UpRightMotionComboBox;
        yield return DownLeftMotionComboBox;
        yield return DownRightMotionComboBox;
    }

    private void Select(ComboBox comboBox, string? motionId)
    {
        string id = motionId ?? string.Empty;
        MovementAnimationMotionOption? option = _motions.FirstOrDefault(value =>
            string.Equals(value.Id, id, StringComparison.Ordinal));
        if (option is null && !string.IsNullOrWhiteSpace(id))
        {
            option = new MovementAnimationMotionOption(id, $"{id} (찾을 수 없음)");
            _motions.Add(option);
        }
        comboBox.SelectedItem = option ?? _motions[0];
    }

    private static string? Selected(ComboBox comboBox) =>
        (comboBox.SelectedItem as MovementAnimationMotionOption)?.Id is { Length: > 0 } id
            ? id
            : null;
}

public sealed record MovementAnimationMotionOption(string Id, string DisplayName);
