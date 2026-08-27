using System.Globalization;
using MonglePet.Core.Behavior;

namespace MonglePet.Settings;

public static class AppSettingsLimits
{
    public const double DefaultOverlayWidth = 192;
    public const double MinimumOverlayWidth = 19.2;
    public const double MaximumOverlayWidth = 384;
    public const int MaximumSequences = 100;
    public const int MaximumStepsPerSequence = 100;
    public const int MaximumAutomaticRules = 100;
    public const int MaximumActivePetInstances = 10_000;
    public const int MaximumBehaviorProfiles = 10_000;
    public const int MaximumPetNicknameLength = 80;
    public const int MaximumSpeechPhrases = 100;
    public const int MaximumSpeechTextLength = 120;
    public const long DefaultSpeechDisplayDurationMilliseconds = 3_000;
    public const long MinimumSpeechDisplayDurationMilliseconds = 1_000;
    public const long MaximumSpeechDisplayDurationMilliseconds = 30_000;
    public const long DefaultSpeechPeriodicIntervalMilliseconds = 60_000;
    public const long MinimumSpeechPeriodicIntervalMilliseconds = 5_000;
    public const long MaximumSpeechPeriodicIntervalMilliseconds = 3_600_000;
    public const double DefaultSpeechBubbleBackgroundOpacity = 0.96;
    public const double MinimumSpeechBubbleBackgroundOpacity = 0.65;
    public const double MaximumSpeechBubbleBackgroundOpacity = 1;
    public const double DefaultSpeechBubbleFontSize = 14;
    public const double MinimumSpeechBubbleFontSize = 11;
    public const double MaximumSpeechBubbleFontSize = 24;
    public const double DefaultSpeechBubbleContentPadding = 12;
    public const double MinimumSpeechBubbleContentPadding = 6;
    public const double MaximumSpeechBubbleContentPadding = 24;
    public const double DefaultSpeechBubbleCornerRadius = 14;
    public const double MinimumSpeechBubbleCornerRadius = 0;
    public const double MaximumSpeechBubbleCornerRadius = 28;
    public const double DefaultSpeechBubbleGap = 8;
    public const double MinimumSpeechBubbleGap = 0;
    public const double MaximumSpeechBubbleGap = 64;
    public const double DefaultSpeechBubbleHorizontalOffset = 0;
    public const double MinimumSpeechBubbleHorizontalOffset = -160;
    public const double MaximumSpeechBubbleHorizontalOffset = 160;
    public const double MinimumSpeechBubbleTextContrastRatio = 4.5;
    public const int MaximumRepeatCount = 100_000;
    public const long MaximumDurationMilliseconds = 86_400_000;
    public const double DefaultMovementSpeed = 160;
    public const double MinimumMovementSpeed = 20;
    public const double MaximumMovementSpeed = 1_000;
    public const double DefaultCursorDistance = 96;
    public const double MinimumCursorDistance = 0;
    public const double MaximumCursorDistance = 512;
    public const double DefaultCursorAvoidingDetectionDistance = 160;
    public const double MinimumCursorAvoidingDetectionDistance = 32;
    public const double MaximumCursorAvoidingDetectionDistance = 1_024;
    public const double DefaultCursorAvoidingSpeed = 320;
    public const double DefaultMovementStopRadius = 16;
    public const double MinimumMovementStopRadius = 0;
    public const double MaximumMovementStopRadius = 128;
    public const long DefaultFreeRoamingDwellMilliseconds = 6_000;
    public const long MinimumFreeRoamingDwellMilliseconds = 500;
    public const long MaximumFreeRoamingDwellMilliseconds = 300_000;
    public const double DefaultOverlayOpacity = 1;
    public const double MinimumOverlayOpacity = 0.1;
    public const double MaximumOverlayOpacity = 1;
    public const double DefaultPointerOverlapOpacity = 0.2;
    public const double MinimumPointerOverlapOpacity = 0.05;
    public const double MaximumPointerOverlapOpacity = 1;

    public static int TextLength(string value) =>
        StringInfo.ParseCombiningCharacters(value).Length;
}

public enum MovementBoundaryMode { AllDisplays, SelectedDisplay, CustomArea }
public enum PetMovementMode { Fixed, CursorFollowing, FreeRoaming, CursorAvoiding }
public enum CursorAvoidingIdleBehavior { Stationary, FreeRoaming }
public enum PetSpeechBubbleColorStyle { System, Cream, Midnight, Mint, Peach, Custom }
public enum PetSpeechBubbleTailAlignment { Leading, Center, Trailing }
public enum PetSpeechBubblePreferredPosition { Automatic, Above, Below }
public enum PetSpeechDisplayMode { Timed, UntilNextPhrase }
public enum PetSpeechBehaviorChangePolicy { Dismiss, Keep }
public enum PetSpeechPeriodicOrder { Random, Sequential }

public sealed record NormalizedMovementRect(
    double X,
    double Y,
    double Width,
    double Height)
{
    public bool IsValid =>
        double.IsFinite(X) && double.IsFinite(Y) &&
        double.IsFinite(Width) && double.IsFinite(Height) &&
        X >= 0 && Y >= 0 && Width > 0 && Height > 0 &&
        X + Width <= 1 && Y + Height <= 1;
}

public sealed record MovementBoundarySettings(
    MovementBoundaryMode Mode,
    string? ScreenIdentifier,
    NormalizedMovementRect? NormalizedRect)
{
    public static readonly MovementBoundarySettings Default = new(
        MovementBoundaryMode.AllDisplays,
        null,
        null);
}

public sealed record DirectionalMotionIds(
    string? Left = null,
    string? Right = null,
    string? Up = null,
    string? Down = null,
    string? UpLeft = null,
    string? UpRight = null,
    string? DownLeft = null,
    string? DownRight = null)
{
    public IEnumerable<string?> All =>
        [Left, Right, Up, Down, UpLeft, UpRight, DownLeft, DownRight];
}

public sealed record MovementAnimationSettings(
    string? FallbackMotionId,
    bool UsesDirectionalMotions,
    bool UsesDiagonalMotions,
    DirectionalMotionIds DirectionMotionIds)
{
    public static readonly MovementAnimationSettings Default = new(
        null,
        false,
        false,
        new DirectionalMotionIds());
}

public sealed record DirectionalBehaviorIds(
    string? Left = null,
    string? Right = null,
    string? Up = null,
    string? Down = null,
    string? UpLeft = null,
    string? UpRight = null,
    string? DownLeft = null,
    string? DownRight = null)
{
    public IEnumerable<string?> All =>
        [Left, Right, Up, Down, UpLeft, UpRight, DownLeft, DownRight];
}

public sealed record MovementBehaviorSettings(
    string? FallbackBehaviorId,
    bool UsesDirectionalBehaviors,
    bool UsesDiagonalBehaviors,
    DirectionalBehaviorIds DirectionBehaviorIds)
{
    public static readonly MovementBehaviorSettings Default = new(
        null,
        false,
        false,
        new DirectionalBehaviorIds());

    public static MovementBehaviorSettings FromLegacy(MovementAnimationSettings value) => new(
        value.FallbackMotionId,
        value.UsesDirectionalMotions,
        value.UsesDiagonalMotions,
        new DirectionalBehaviorIds(
            value.DirectionMotionIds.Left,
            value.DirectionMotionIds.Right,
            value.DirectionMotionIds.Up,
            value.DirectionMotionIds.Down,
            value.DirectionMotionIds.UpLeft,
            value.DirectionMotionIds.UpRight,
            value.DirectionMotionIds.DownLeft,
            value.DirectionMotionIds.DownRight));
}

public sealed record CursorFollowingMovementSettings(
    double Speed,
    double CursorDistance,
    double StopRadius,
    MovementBehaviorSettings Behavior);

public sealed record FreeRoamingMovementSettings(
    double Speed,
    double StopRadius,
    long DwellMilliseconds,
    bool RandomizesDwell,
    long DwellMinimumMilliseconds,
    bool PrefersFrontmostWindow,
    MovementBehaviorSettings Behavior);

public sealed record CursorAvoidingMovementSettings(
    CursorAvoidingIdleBehavior IdleBehavior,
    double DetectionDistance,
    double Speed,
    double StopRadius,
    MovementBehaviorSettings Behavior,
    FreeRoamingMovementSettings IdleFreeRoaming);

public sealed record PetMovementSettings(
    PetMovementMode Mode,
    double Speed,
    double CursorDistance,
    double StopRadius,
    long FreeRoamingDwellMilliseconds,
    bool PrefersFrontmostWindow,
    MovementAnimationSettings CursorFollowingAnimation,
    MovementAnimationSettings FreeRoamingAnimation,
    CursorAvoidingIdleBehavior CursorAvoidingIdleBehavior,
    double CursorAvoidingDetectionDistance,
    double CursorAvoidingSpeed,
    MovementAnimationSettings CursorAvoidingAnimation,
    CursorFollowingMovementSettings? CursorFollowingSettings = null,
    FreeRoamingMovementSettings? FreeRoamingSettings = null,
    CursorAvoidingMovementSettings? CursorAvoidingSettings = null)
{
    public static readonly PetMovementSettings Default = new(
        PetMovementMode.Fixed,
        AppSettingsLimits.DefaultMovementSpeed,
        AppSettingsLimits.DefaultCursorDistance,
        AppSettingsLimits.DefaultMovementStopRadius,
        AppSettingsLimits.DefaultFreeRoamingDwellMilliseconds,
        true,
        MovementAnimationSettings.Default,
        MovementAnimationSettings.Default,
        CursorAvoidingIdleBehavior.Stationary,
        AppSettingsLimits.DefaultCursorAvoidingDetectionDistance,
        AppSettingsLimits.DefaultCursorAvoidingSpeed,
        MovementAnimationSettings.Default);

    public CursorFollowingMovementSettings CursorFollowing => CursorFollowingSettings ?? new(
        Speed,
        CursorDistance,
        StopRadius,
        MovementBehaviorSettings.FromLegacy(CursorFollowingAnimation));

    public FreeRoamingMovementSettings FreeRoaming => FreeRoamingSettings ?? new(
        Speed,
        StopRadius,
        FreeRoamingDwellMilliseconds,
        false,
        Math.Max(AppSettingsLimits.MinimumFreeRoamingDwellMilliseconds, FreeRoamingDwellMilliseconds / 2),
        PrefersFrontmostWindow,
        MovementBehaviorSettings.FromLegacy(FreeRoamingAnimation));

    public CursorAvoidingMovementSettings CursorAvoiding => CursorAvoidingSettings ?? new(
        CursorAvoidingIdleBehavior,
        CursorAvoidingDetectionDistance,
        CursorAvoidingSpeed,
        StopRadius,
        MovementBehaviorSettings.FromLegacy(CursorAvoidingAnimation),
        FreeRoaming);
}

public sealed record PetSpeechColor(double Red, double Green, double Blue)
{
    public static readonly PetSpeechColor White = new(1, 1, 1);
    public static readonly PetSpeechColor Black = new(0, 0, 0);

    public bool IsValid =>
        double.IsFinite(Red) && double.IsFinite(Green) && double.IsFinite(Blue) &&
        Red is >= 0 and <= 1 && Green is >= 0 and <= 1 && Blue is >= 0 and <= 1;

    public double ContrastRatio(PetSpeechColor other)
    {
        double lighter = Math.Max(RelativeLuminance(), other.RelativeLuminance());
        double darker = Math.Min(RelativeLuminance(), other.RelativeLuminance());
        return (lighter + 0.05) / (darker + 0.05);
    }

    public static PetSpeechColor PreferredTextColor(PetSpeechColor background) =>
        background.ContrastRatio(Black) >= background.ContrastRatio(White)
            ? Black
            : White;

    private double RelativeLuminance() =>
        (0.2126 * Linearized(Red)) +
        (0.7152 * Linearized(Green)) +
        (0.0722 * Linearized(Blue));

    private static double Linearized(double component) =>
        component <= 0.04045
            ? component / 12.92
            : Math.Pow((component + 0.055) / 1.055, 2.4);
}

public sealed record PetSpeechBubbleTheme(
    PetSpeechBubbleColorStyle ColorStyle,
    PetSpeechColor CustomBackgroundColor,
    PetSpeechColor CustomTextColor,
    double BackgroundOpacity,
    double FontSize,
    double ContentPadding,
    double CornerRadius,
    bool ShowsTail,
    PetSpeechBubbleTailAlignment TailAlignment)
{
    public static readonly PetSpeechBubbleTheme Default = new(
        PetSpeechBubbleColorStyle.System,
        PetSpeechColor.White,
        PetSpeechColor.Black,
        AppSettingsLimits.DefaultSpeechBubbleBackgroundOpacity,
        AppSettingsLimits.DefaultSpeechBubbleFontSize,
        AppSettingsLimits.DefaultSpeechBubbleContentPadding,
        AppSettingsLimits.DefaultSpeechBubbleCornerRadius,
        false,
        PetSpeechBubbleTailAlignment.Center);
}

public sealed record PetSpeechBubblePlacementSettings(
    PetSpeechBubblePreferredPosition PreferredPosition,
    double HorizontalOffset,
    double Gap)
{
    public static readonly PetSpeechBubblePlacementSettings Default = new(
        PetSpeechBubblePreferredPosition.Automatic,
        AppSettingsLimits.DefaultSpeechBubbleHorizontalOffset,
        AppSettingsLimits.DefaultSpeechBubbleGap);
}

public abstract record PetSpeechTrigger
{
    private PetSpeechTrigger() { }
    public sealed record Periodic : PetSpeechTrigger;
    public sealed record Sequence(string SequenceId) : PetSpeechTrigger;
}

public sealed record PetSpeechPhrase(
    Guid Id,
    string Text,
    long DisplayDurationMilliseconds,
    PetSpeechTrigger Trigger,
    PetSpeechDisplayMode DisplayMode);

public sealed record PetSpeechSettings(
    bool IsEnabled,
    bool PeriodicIsEnabled,
    long PeriodicIntervalMilliseconds,
    PetSpeechPeriodicOrder PeriodicOrder,
    PetSpeechBehaviorChangePolicy BehaviorChangePolicy,
    IReadOnlyList<PetSpeechPhrase> Phrases,
    PetSpeechBubbleTheme Theme,
    PetSpeechBubblePlacementSettings Placement)
{
    public static readonly PetSpeechSettings Default = new(
        false,
        false,
        AppSettingsLimits.DefaultSpeechPeriodicIntervalMilliseconds,
        PetSpeechPeriodicOrder.Random,
        PetSpeechBehaviorChangePolicy.Dismiss,
        [],
        PetSpeechBubbleTheme.Default,
        PetSpeechBubblePlacementSettings.Default);
}

public abstract record PetBehaviorKey
{
    private PetBehaviorKey() { }
    public sealed record BuiltIn : PetBehaviorKey;
    public sealed record Installed(Guid InstallationId) : PetBehaviorKey;

    public static readonly PetBehaviorKey BuiltInKey = new BuiltIn();
}

public sealed record BehaviorProfile(
    Guid ProfileId,
    PetBehaviorKey PetKey,
    BehaviorMode Mode,
    string? ManualSequenceId,
    IReadOnlyList<BehaviorSequence> Sequences,
    IReadOnlyList<AutomaticRule> AutomaticRules,
    PetMovementSettings Movement,
    string? PettingMotionId,
    PetSpeechSettings Speech,
    IReadOnlyList<string>? RandomSequenceIds = null,
    IReadOnlyList<AutomaticRuleKind>? AutomaticRulePriorityOrder = null,
    string? PettingBehaviorId = null)
{
    public IReadOnlyList<string> RandomSequences => RandomSequenceIds ?? Array.Empty<string>();

    public IReadOnlyList<AutomaticRuleKind> RulePriorityOrder =>
        AutomaticRulePriorityOrder ??
        [AutomaticRuleKind.Movement, AutomaticRuleKind.Idle, AutomaticRuleKind.Application];

    public string? EffectivePettingBehaviorId => PettingBehaviorId ?? PettingMotionId;
}

public sealed record ActivePetInstance(
    Guid InstanceId,
    Guid BehaviorProfileId,
    PetBehaviorKey PetKey,
    string? Nickname,
    PetPresentation Presentation,
    OverlaySettings Overlay,
    int DisplayOrder);

public sealed record OverlaySettings(
    string? ScreenIdentifier,
    double OriginX,
    double OriginY,
    double Width,
    bool ClickThrough,
    double Opacity,
    bool PointerOverlapFadeEnabled,
    double PointerOverlapOpacity,
    bool PixelArtRendering,
    MovementBoundarySettings MovementBoundary)
{
    public static readonly OverlaySettings Default = new(
        null,
        0,
        0,
        AppSettingsLimits.DefaultOverlayWidth,
        false,
        AppSettingsLimits.DefaultOverlayOpacity,
        false,
        AppSettingsLimits.DefaultPointerOverlapOpacity,
        false,
        MovementBoundarySettings.Default);
}

public sealed record AppSettings(
    IReadOnlyList<ActivePetInstance> ActivePetInstances,
    IReadOnlyList<BehaviorProfile> BehaviorProfiles,
    Guid SelectedPetInstanceId)
{
    public static AppSettings Default => CreateDefault();

    public ActivePetInstance? SelectedPetInstance =>
        ActivePetInstances.FirstOrDefault(instance => instance.InstanceId == SelectedPetInstanceId)
        ?? ActivePetInstances.FirstOrDefault();

    public BehaviorProfile? SelectedBehaviorProfile => SelectedPetInstance is { } instance
        ? BehaviorProfiles.FirstOrDefault(profile => profile.ProfileId == instance.BehaviorProfileId)
        : null;

    // Temporary schema-v10 compatibility view for the existing single-pet WinUI/runtime.
    public Guid? SelectedPetInstallationId => SelectedPetInstance?.PetKey is PetBehaviorKey.Installed installed
        ? installed.InstallationId
        : null;

    public PetPresentation LastUserPresentation =>
        SelectedPetInstance?.Presentation ?? PetPresentation.Awake;

    public OverlaySettings Overlay => SelectedPetInstance?.Overlay ?? OverlaySettings.Default;

    public static AppSettings CreateDefault(Func<Guid>? idGenerator = null)
    {
        idGenerator ??= Guid.NewGuid;
        Guid instanceId = NextNonEmptyId(idGenerator);
        BehaviorProfile profile = BehaviorProfileDefaults.Create(
            PetBehaviorKey.BuiltInKey,
            NextNonEmptyId(idGenerator));
        return new AppSettings(
            [new ActivePetInstance(
                instanceId,
                profile.ProfileId,
                PetBehaviorKey.BuiltInKey,
                null,
                PetPresentation.Awake,
                OverlaySettings.Default,
                0)],
            [profile],
            instanceId);
    }

    public AppSettings WithSelectedPresentation(PetPresentation presentation) =>
        WithSelectedInstance(instance => instance with { Presentation = presentation });

    public AppSettings WithSelectedOverlay(OverlaySettings overlay) =>
        WithSelectedInstance(instance => instance with { Overlay = overlay });

    public AppSettings WithSelectedPetInstallationId(
        Guid? installationId,
        Func<Guid>? idGenerator = null)
    {
        ActivePetInstance? selected = SelectedPetInstance;
        if (selected is null)
        {
            return this;
        }

        PetBehaviorKey key = BehaviorProfileDefaults.KeyForInstallation(installationId);
        if (selected.PetKey == key)
        {
            return this;
        }

        idGenerator ??= Guid.NewGuid;
        var referencedByOtherInstances = ActivePetInstances
            .Where(instance => instance.InstanceId != selected.InstanceId)
            .Select(instance => instance.BehaviorProfileId)
            .ToHashSet();
        BehaviorProfile? profile = BehaviorProfiles.FirstOrDefault(candidate =>
            candidate.PetKey == key && !referencedByOtherInstances.Contains(candidate.ProfileId));
        IReadOnlyList<BehaviorProfile> profiles = BehaviorProfiles;
        if (profile is null)
        {
            profile = BehaviorProfileDefaults.Create(key, NextNonEmptyId(idGenerator));
            profiles = [.. BehaviorProfiles, profile];
        }

        AppSettings updated = WithSelectedInstance(instance => instance with
        {
            PetKey = key,
            BehaviorProfileId = profile.ProfileId,
        });
        return updated with { BehaviorProfiles = profiles };
    }

    public AppSettings WithSelectedBehaviorProfile(BehaviorProfile profile)
    {
        ArgumentNullException.ThrowIfNull(profile);
        ActivePetInstance? selected = SelectedPetInstance;
        if (selected is null || selected.BehaviorProfileId != profile.ProfileId || selected.PetKey != profile.PetKey)
        {
            throw new ArgumentException("The behavior profile does not belong to the selected pet instance.", nameof(profile));
        }

        return this with
        {
            BehaviorProfiles = BehaviorProfiles
                .Select(existing => existing.ProfileId == profile.ProfileId ? profile : existing)
                .ToList(),
        };
    }

    private AppSettings WithSelectedInstance(Func<ActivePetInstance, ActivePetInstance> update)
    {
        ActivePetInstance? selected = SelectedPetInstance;
        if (selected is null)
        {
            return this;
        }
        return this with
        {
            ActivePetInstances = ActivePetInstances
                .Select(instance => instance.InstanceId == selected.InstanceId ? update(instance) : instance)
                .ToList(),
            SelectedPetInstanceId = selected.InstanceId,
        };
    }

    internal static Guid NextNonEmptyId(Func<Guid> idGenerator)
    {
        for (int attempt = 0; attempt < 100; attempt++)
        {
            Guid id = idGenerator();
            if (id != Guid.Empty)
            {
                return id;
            }
        }
        throw new InvalidOperationException("A non-empty settings identifier could not be generated.");
    }
}

public enum SettingsRecoveryKind
{
    InvalidField,
    DroppedSequence,
    DroppedRule,
    DisabledRule,
    TruncatedCollection,
}

public sealed record SettingsRecoveryIssue(
    SettingsRecoveryKind Kind,
    string Field)
{
    public override string ToString() => Kind switch
    {
        SettingsRecoveryKind.InvalidField => $"올바르지 않은 설정을 복구했습니다: {Field}",
        SettingsRecoveryKind.DroppedSequence => $"올바르지 않은 행동 루틴을 제외했습니다: {Field}",
        SettingsRecoveryKind.DroppedRule => $"올바르지 않은 자동 규칙을 제외했습니다: {Field}",
        SettingsRecoveryKind.DisabledRule => $"실행할 수 없는 자동 규칙을 비활성화했습니다: {Field}",
        SettingsRecoveryKind.TruncatedCollection => $"설정 항목 수를 허용 범위로 줄였습니다: {Field}",
        _ => Field,
    };
}
