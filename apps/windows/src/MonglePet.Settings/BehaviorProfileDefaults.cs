using MonglePet.Core.Behavior;

namespace MonglePet.Settings;

public static class BehaviorProfileDefaults
{
    public static BehaviorProfile Create(PetBehaviorKey petKey, Guid? profileId = null)
    {
        ArgumentNullException.ThrowIfNull(petKey);
        if (petKey is PetBehaviorKey.BuiltIn)
        {
            return BuiltInBehaviorProfileDefaults.Create(profileId);
        }
        return CreateNeutral(petKey, profileId);
    }

    internal static BehaviorProfile CreateNeutral(PetBehaviorKey petKey, Guid? profileId = null)
    {
        var defaultSequence = new BehaviorSequence(
            BehaviorMotionReferences.DefaultSequence,
            [new BehaviorStep(BehaviorMotionReferences.CurrentPetDefault, 1)],
            true);
        return new BehaviorProfile(
            profileId is { } id && id != Guid.Empty ? id : Guid.NewGuid(),
            petKey,
            BehaviorMode.Automatic,
            defaultSequence.Id,
            [defaultSequence],
            [],
            PetMovementSettings.Default,
            null,
            PetSpeechSettings.Default);
    }

    public static PetBehaviorKey KeyForInstallation(Guid? installationId) =>
        installationId is Guid id
            ? new PetBehaviorKey.Installed(id)
            : PetBehaviorKey.BuiltInKey;
}

public static class BuiltInBehaviorProfileDefaults
{
    public const string WindowsCodexApplicationId =
        "pfn:openai.codex_2p2nqsd0c76g0";
    public const string SleepSequenceId = "수면 중";
    public const string WorkSequenceId = "일해라";

    public static BehaviorProfile Create(
        Guid? profileId = null,
        Func<Guid>? idGenerator = null)
    {
        idGenerator ??= Guid.NewGuid;
        Guid NextId()
        {
            Guid id;
            do
            {
                id = idGenerator();
            }
            while (id == Guid.Empty);
            return id;
        }
        var defaultSequence = new BehaviorSequence(
            BehaviorMotionReferences.DefaultSequence,
            [
                new BehaviorStep(BehaviorMotionReferences.CurrentPetDefault, 1),
                new BehaviorStep("물뿜기", 1),
                new BehaviorStep("정면", 1),
            ],
            true);
        var sleep = new BehaviorSequence(
            SleepSequenceId,
            [new BehaviorStep("자는중", 1)],
            true);
        var work = new BehaviorSequence(
            WorkSequenceId,
            [new BehaviorStep("일하는 중", 1)],
            true);
        var avoidingAnimation = new MovementAnimationSettings(
            "보글보글",
            true,
            false,
            new DirectionalMotionIds(
                Left: "보글보글",
                Right: "오른쪽",
                Up: "위로",
                Down: "정면"));
        var movement = PetMovementSettings.Default with
        {
            Mode = PetMovementMode.CursorAvoiding,
            CursorAvoidingAnimation = avoidingAnimation,
        };
        return new BehaviorProfile(
            profileId is { } id && id != Guid.Empty ? id : NextId(),
            PetBehaviorKey.BuiltInKey,
            BehaviorMode.Automatic,
            defaultSequence.Id,
            [defaultSequence, sleep, work],
            [
                new AutomaticRule(
                    NextId(),
                    true,
                    0,
                    new RuleCondition.Application(WindowsCodexApplicationId),
                    WorkSequenceId),
                new AutomaticRule(
                    NextId(),
                    true,
                    1,
                    new RuleCondition.IdleAtLeast(60_000),
                    SleepSequenceId),
            ],
            movement,
            "해피",
            PetSpeechSettings.Default);
    }

    public static bool IsLegacyNeutral(BehaviorProfile profile)
    {
        if (profile.PetKey is not PetBehaviorKey.BuiltIn ||
            profile.Mode != BehaviorMode.Automatic ||
            profile.ManualSequenceId != BehaviorMotionReferences.DefaultSequence ||
            profile.Sequences.Count != 1 ||
            profile.AutomaticRules.Count != 0 ||
            profile.Movement != PetMovementSettings.Default ||
            profile.PettingMotionId is not null ||
            !IsDefaultSpeech(profile.Speech))
        {
            return false;
        }
        BehaviorSequence sequence = profile.Sequences[0];
        return sequence.Id == BehaviorMotionReferences.DefaultSequence &&
            sequence.Repeats &&
            sequence.Steps.Count == 1 &&
            sequence.Steps[0] == new BehaviorStep(
                BehaviorMotionReferences.CurrentPetDefault,
                1);
    }

    public static AppSettings UpgradeLegacyNeutralProfiles(AppSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        bool changed = false;
        BehaviorProfile[] profiles = settings.BehaviorProfiles.Select(profile =>
        {
            if (!IsLegacyNeutral(profile))
            {
                return profile;
            }
            changed = true;
            return Create(profile.ProfileId);
        }).ToArray();
        return changed ? settings with { BehaviorProfiles = profiles } : settings;
    }

    private static bool IsDefaultSpeech(PetSpeechSettings speech) =>
        !speech.IsEnabled &&
        !speech.PeriodicIsEnabled &&
        speech.PeriodicIntervalMilliseconds == AppSettingsLimits.DefaultSpeechPeriodicIntervalMilliseconds &&
        speech.PeriodicOrder == PetSpeechPeriodicOrder.Random &&
        speech.BehaviorChangePolicy == PetSpeechBehaviorChangePolicy.Dismiss &&
        speech.Phrases.Count == 0 &&
        speech.Theme == PetSpeechBubbleTheme.Default &&
        speech.Placement == PetSpeechBubblePlacementSettings.Default;
}
