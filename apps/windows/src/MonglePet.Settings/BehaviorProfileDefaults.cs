using MonglePet.Core.Behavior;
using System.Reflection;
using System.Text.Json.Nodes;

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
            true)
        {
            DisplayName = "기본",
        };
        return new BehaviorProfile(
            profileId is { } id && id != Guid.Empty ? id : Guid.NewGuid(),
            petKey,
            StationaryBehaviorMode.Fixed,
            null,
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
    private const string PreviousWindowsCodexApplicationId =
        "pfn:openai.codex_2p2nqsd0c76g0";
    public const string SleepSequenceId = "수면 중";
    public const string WorkSequenceId = "일해라";

    public static BehaviorProfile Create(
        Guid? profileId = null,
        Func<Guid>? idGenerator = null)
    {
        idGenerator ??= Guid.NewGuid;
        DecodedRecommendedPetProfile recommended = DecodeCommonProfile();
        BehaviorProfile profile = recommended.Profile;
        Guid resolvedProfileId = profileId is { } id && id != Guid.Empty
            ? id
            : NextNonEmptyGuid(idGenerator);
        return profile with { ProfileId = resolvedProfileId };
    }

    public static PortablePetDisplaySettings RecommendedDisplay =>
        DecodeCommonProfile().Display;

    private static DecodedRecommendedPetProfile DecodeCommonProfile()
    {
        using Stream petStream = OpenResource("MonglePet.BuiltIn.Mongle.pet.json");
        using Stream profileStream = OpenResource(
            "MonglePet.BuiltIn.Mongle.recommended-profile.json");
        JsonObject pet = JsonNode.Parse(petStream)?.AsObject()
            ?? throw new InvalidOperationException("The built-in Mongle manifest is invalid.");
        string[] motionIds = pet["motions"]?.AsArray()
            .OfType<JsonObject>()
            .Select(motion => motion["id"]?.GetValue<string>())
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .Select(id => id!)
            .ToArray() ?? [];
        using var buffer = new MemoryStream();
        profileStream.CopyTo(buffer);
        return RecommendedPetProfileCodec.DecodeWithDisplay(
            buffer.ToArray(),
            PetBehaviorKey.BuiltInKey,
            motionIds);
    }

    private static Stream OpenResource(string name) =>
        typeof(BuiltInBehaviorProfileDefaults).Assembly.GetManifestResourceStream(name)
        ?? throw new InvalidOperationException($"Missing embedded built-in resource: {name}");

    private static Guid NextNonEmptyGuid(Func<Guid> generator)
    {
        Guid id;
        do
        {
            id = generator();
        }
        while (id == Guid.Empty);
        return id;
    }

    public static bool IsLegacyNeutral(BehaviorProfile profile)
    {
        if (profile.PetKey is not PetBehaviorKey.BuiltIn ||
            profile.StationaryBehaviorMode != StationaryBehaviorMode.Fixed ||
            profile.StationarySequenceId is not null ||
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
        var upgradedProfileIds = new HashSet<Guid>();
        BehaviorProfile[] profiles = settings.BehaviorProfiles.Select(profile =>
        {
            if (profile.PetKey is not PetBehaviorKey.BuiltIn)
            {
                return profile;
            }
            if (IsLegacyNeutral(profile) || IsPreviousBuiltInDefault(profile))
            {
                changed = true;
                upgradedProfileIds.Add(profile.ProfileId);
                return Create(profile.ProfileId);
            }
            BehaviorProfile normalized = NormalizeRemovedMotionReferences(profile);
            changed |= normalized != profile;
            return normalized;
        }).ToArray();
        ActivePetInstance[] instances = settings.ActivePetInstances.Select(instance =>
        {
            if (!upgradedProfileIds.Contains(instance.BehaviorProfileId) ||
                instance.Overlay != OverlaySettings.Default)
            {
                return instance;
            }
            changed = true;
            return instance with
            {
                Overlay = RecommendedDisplay.ApplyTo(instance.Overlay),
            };
        }).ToArray();
        return changed ? settings with
        {
            BehaviorProfiles = profiles,
            ActivePetInstances = instances,
        } : settings;
    }

    private static bool IsPreviousBuiltInDefault(BehaviorProfile profile)
    {
        if (profile.StationaryBehaviorMode != StationaryBehaviorMode.Fixed ||
            profile.StationarySequenceId is not null ||
            profile.RandomSequences.Count != 0 ||
            !IsDefaultSpeech(profile.Speech) ||
            profile.Movement.Mode != PetMovementMode.CursorAvoiding ||
            profile.Movement.CursorAvoiding.IdleBehavior != CursorAvoidingIdleBehavior.Stationary ||
            profile.Movement.CursorAvoiding.DetectionDistance != 160 ||
            profile.Movement.CursorAvoiding.Speed != 320 ||
            profile.Movement.CursorAvoiding.StopRadius != 16)
        {
            return false;
        }
        BehaviorSequence? basic = profile.Sequences.FirstOrDefault(sequence =>
            sequence.Id == BehaviorMotionReferences.DefaultSequence);
        BehaviorSequence? sleep = profile.Sequences.FirstOrDefault(sequence =>
            sequence.Id == SleepSequenceId);
        BehaviorSequence? work = profile.Sequences.FirstOrDefault(sequence =>
            sequence.Id == WorkSequenceId);
        if (basic is null || sleep is null || work is null ||
            !basic.Steps.SequenceEqual(new[]
            {
                new BehaviorStep(BehaviorMotionReferences.CurrentPetDefault, 1),
                new BehaviorStep("물뿜기", 1),
                new BehaviorStep("정면", 1),
            }) ||
            !sleep.Steps.SequenceEqual([new BehaviorStep("자는중", 1)]) ||
            !work.Steps.SequenceEqual([new BehaviorStep("일하는 중", 1)]))
        {
            return false;
        }
        string[] promotedMotions = ["보글보글", "오른쪽", "위로", "정면", "해피"];
        if (profile.Sequences.Except([basic, sleep, work]).Any(sequence =>
            sequence.Steps.Count != 1 ||
            sequence.Steps[0].RepeatCount != 1 ||
            !promotedMotions.Contains(sequence.Steps[0].MotionId, StringComparer.Ordinal)))
        {
            return false;
        }
        if (profile.AutomaticRules.Count is < 1 or > 2 ||
            profile.AutomaticRules.Count(rule =>
                rule.IsEnabled &&
                rule.Condition is RuleCondition.IdleAtLeast { Milliseconds: 60_000 } &&
                rule.SequenceId == SleepSequenceId) != 1 ||
            profile.AutomaticRules.Any(rule => rule.Condition is RuleCondition.Application application &&
                (application.ApplicationId != PreviousWindowsCodexApplicationId ||
                 rule.SequenceId != WorkSequenceId)))
        {
            return false;
        }
        string? Resolve(string? id) => profile.Sequences.FirstOrDefault(sequence =>
            sequence.Id == id && sequence.Steps.Count == 1)?.Steps[0].MotionId;
        MovementBehaviorSettings avoiding = profile.Movement.CursorAvoiding.Behavior;
        return Resolve(avoiding.FallbackBehaviorId) == "보글보글" &&
            Resolve(avoiding.DirectionBehaviorIds.Left) == "보글보글" &&
            Resolve(avoiding.DirectionBehaviorIds.Right) == "오른쪽" &&
            Resolve(avoiding.DirectionBehaviorIds.Up) == "위로" &&
            Resolve(avoiding.DirectionBehaviorIds.Down) == "정면" &&
            Resolve(profile.PettingBehaviorId) == "해피";
    }

    private static BehaviorProfile NormalizeRemovedMotionReferences(BehaviorProfile profile)
    {
        var replacements = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["위로"] = "위",
            ["자는중"] = "자는 중",
            ["물뿜기"] = "물 뿜기",
            ["해피"] = "행복",
            ["보글보글"] = "왼쪽 보글보글",
        };
        bool changed = false;
        BehaviorSequence[] sequences = profile.Sequences.Select(sequence =>
        {
            BehaviorStep[] steps = sequence.Steps.Select(step =>
            {
                if (!replacements.TryGetValue(step.MotionId, out string? replacement))
                {
                    return step;
                }
                changed = true;
                return step with { MotionId = replacement };
            }).ToArray();
            return changed ? sequence with { Steps = steps } : sequence;
        }).ToArray();
        return changed ? profile with { Sequences = sequences } : profile;
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
