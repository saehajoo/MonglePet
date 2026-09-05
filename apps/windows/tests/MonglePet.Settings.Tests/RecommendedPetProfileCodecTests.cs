using System.Text;
using System.Text.Json.Nodes;
using MonglePet.Core.Behavior;

namespace MonglePet.Settings.Tests;

public sealed class RecommendedPetProfileCodecTests
{
    private static readonly PetBehaviorKey TargetKey =
        new PetBehaviorKey.Installed(Guid.Parse("11111111-1111-1111-1111-111111111111"));

    [Fact]
    public void DecodesVersionOneMovementMotionIds()
    {
        byte[] data = Encoding.UTF8.GetBytes("""
        {
          "schemaVersion": 1,
          "behavior": {
            "mode": "manual",
            "manualSequenceID": "default",
            "sequences": [{
              "id": "default",
              "steps": [{"motionID": "idle", "repeatCount": 2}],
              "repeats": true
            }]
          },
          "movement": {
            "mode": "cursorFollowing",
            "speed": 160,
            "cursorDistance": 96,
            "stopRadius": 16,
            "freeRoamingDwellMilliseconds": 6000,
            "prefersFrontmostWindow": true,
            "cursorFollowingMotionID": "walk",
            "freeRoamingMotionID": "idle"
          },
          "pettingMotionID": null,
          "automaticRules": []
        }
        """);

        BehaviorProfile profile = RecommendedPetProfileCodec.Decode(
            data,
            TargetKey,
            ["idle", "walk"]);

        Assert.Equal(TargetKey, profile.PetKey);
        Assert.Equal(StationaryBehaviorMode.Fixed, profile.StationaryBehaviorMode);
        Assert.Equal("default", profile.StationarySequenceId);
        string followingBehavior = Assert.IsType<string>(
            profile.Movement.CursorFollowing.Behavior.FallbackBehaviorId);
        string roamingBehavior = Assert.IsType<string>(
            profile.Movement.FreeRoaming.Behavior.FallbackBehaviorId);
        Assert.Equal("walk", Assert.Single(profile.Sequences.Single(
            sequence => sequence.Id == followingBehavior).Steps).MotionId);
        Assert.Equal("idle", Assert.Single(profile.Sequences.Single(
            sequence => sequence.Id == roamingBehavior).Steps).MotionId);
        Assert.False(profile.Speech.IsEnabled);
    }

    [Fact]
    public void MigratesVersionFourPeriodicSpeechDefaults()
    {
        Guid phraseId = Guid.Parse("22222222-2222-2222-2222-222222222222");
        string json = $$"""
        {
          "schemaVersion": 4,
          "behavior": {
            "mode": "automatic",
            "manualSequenceID": "default",
            "sequences": [{
              "id": "default",
              "steps": [{"motionID": "__monglepet_current_pet_default__", "repeatCount": 1}],
              "repeats": true
            }]
          },
          "movement": {"mode": "fixed"},
          "pettingMotionID": null,
          "automaticRules": [],
          "speech": {
            "isEnabled": true,
            "periodicIntervalMilliseconds": 60000,
            "phrases": [{
              "id": "{{phraseId:D}}",
              "text": "hello",
              "displayDurationMilliseconds": 3000,
              "trigger": {"type": "periodic", "sequenceID": null}
            }]
          }
        }
        """;

        BehaviorProfile profile = RecommendedPetProfileCodec.Decode(
            Encoding.UTF8.GetBytes(json), TargetKey, ["idle"]);

        Assert.True(profile.Speech.PeriodicIsEnabled);
        Assert.Equal(PetSpeechPeriodicOrder.Random, profile.Speech.PeriodicOrder);
        Assert.Equal(PetSpeechDisplayMode.Timed, Assert.Single(profile.Speech.Phrases).DisplayMode);
    }

    [Fact]
    public void VersionTwelveRoundTripsDwellModesAndCanExcludeApplicationRules()
    {
        BehaviorProfile profile = BehaviorProfileDefaults.Create(TargetKey) with
        {
            AutomaticRules =
            [
                new(Guid.Parse("33333333-3333-3333-3333-333333333333"), true, 1,
                    new RuleCondition.Application("exe:notepad.exe"), BehaviorMotionReferences.DefaultSequence),
                new(Guid.Parse("44444444-4444-4444-4444-444444444444"), true, 2,
                    new RuleCondition.IdleAtLeast(30_000), BehaviorMotionReferences.DefaultSequence),
            ],
        };

        FreeRoamingMovementSettings roaming = profile.Movement.FreeRoaming with
        {
            DwellMode = FreeRoamingDwellMode.BehaviorCompletion,
            DwellMilliseconds = 14_000,
            DwellMinimumMilliseconds = 4_000,
        };
        FreeRoamingMovementSettings avoidingRoaming =
            profile.Movement.CursorAvoiding.IdleFreeRoaming with
            {
                DwellMode = FreeRoamingDwellMode.Random,
                DwellMilliseconds = 10_000,
                DwellMinimumMilliseconds = 2_000,
            };
        profile = profile with
        {
            Movement = profile.Movement with
            {
                FreeRoamingSettings = roaming,
                CursorAvoidingSettings = profile.Movement.CursorAvoiding with
                {
                    IdleFreeRoaming = avoidingRoaming,
                },
            },
        };
        OverlaySettings overlay = OverlaySettings.Default with
        {
            Width = 96,
            ClickThrough = true,
            Opacity = 0.8,
            PointerOverlapFadeEnabled = true,
            PointerOverlapOpacity = 0.4,
            PixelArtRendering = true,
        };
        byte[] data = RecommendedPetProfileCodec.Encode(
            profile, ["idle"], false, overlay);
        DecodedRecommendedPetProfile package =
            RecommendedPetProfileCodec.DecodeWithDisplay(data, TargetKey, ["idle"]);
        BehaviorProfile decoded = package.Profile;

        AutomaticRule rule = Assert.Single(decoded.AutomaticRules);
        Assert.IsType<RuleCondition.IdleAtLeast>(rule.Condition);
        Assert.True(package.IncludesDisplaySettings);
        Assert.Equal(50, package.Display.ScalePercent);
        Assert.Equal(overlay.Width, package.Display.ApplyTo(OverlaySettings.Default).Width);
        Assert.True(package.Display.ClickThrough);
        Assert.Equal(StationaryBehaviorMode.Fixed, decoded.StationaryBehaviorMode);
        JsonObject stored = JsonNode.Parse(data)!.AsObject();
        Assert.Equal(12, stored["schemaVersion"]!.GetValue<int>());
        Assert.Equal(FreeRoamingDwellMode.BehaviorCompletion,
            decoded.Movement.FreeRoaming.DwellMode);
        Assert.Equal(14_000, decoded.Movement.FreeRoaming.DwellMilliseconds);
        Assert.Equal(FreeRoamingDwellMode.Random,
            decoded.Movement.CursorAvoiding.IdleFreeRoaming.DwellMode);
        Assert.NotNull(stored["behavior"]?["stationaryBehaviorMode"]);
        Assert.Null(stored["behavior"]?["mode"]);
        Assert.Null(stored["behavior"]?["manualSequenceID"]);
    }

    [Fact]
    public void VersionElevenLegacyDwellBooleansMigrateToIndependentModes()
    {
        BehaviorProfile profile = BehaviorProfileDefaults.Create(TargetKey);
        JsonObject source = JsonNode.Parse(RecommendedPetProfileCodec.Encode(
            profile, ["idle"], true))!.AsObject();
        source["schemaVersion"] = 11;
        JsonObject roaming = source["movement"]!["freeRoaming"]!.AsObject();
        roaming["randomizesDwell"] = false;
        roaming.Remove("dwellMode");
        JsonObject idleRoaming = source["movement"]!["cursorAvoiding"]!["idleFreeRoaming"]!.AsObject();
        idleRoaming["randomizesDwell"] = true;
        idleRoaming.Remove("dwellMode");

        BehaviorProfile decoded = RecommendedPetProfileCodec.Decode(
            Encoding.UTF8.GetBytes(source.ToJsonString()), TargetKey, ["idle"]);

        Assert.Equal(FreeRoamingDwellMode.Fixed,
            decoded.Movement.FreeRoaming.DwellMode);
        Assert.Equal(FreeRoamingDwellMode.Random,
            decoded.Movement.CursorAvoiding.IdleFreeRoaming.DwellMode);
    }

    [Theory]
    [InlineData(FreeRoamingDwellMode.Fixed)]
    [InlineData(FreeRoamingDwellMode.Random)]
    [InlineData(FreeRoamingDwellMode.BehaviorCompletion)]
    public void VersionTwelveRoundTripsEveryDwellMode(FreeRoamingDwellMode mode)
    {
        BehaviorProfile profile = BehaviorProfileDefaults.Create(TargetKey);
        profile = profile with
        {
            Movement = profile.Movement with
            {
                FreeRoamingSettings = profile.Movement.FreeRoaming with
                {
                    DwellMode = mode,
                },
            },
        };

        BehaviorProfile decoded = RecommendedPetProfileCodec.Decode(
            RecommendedPetProfileCodec.Encode(profile, ["idle"], true),
            TargetKey,
            ["idle"]);

        Assert.Equal(mode, decoded.Movement.FreeRoaming.DwellMode);
    }

    [Fact]
    public void VersionTenManualSelectionMigratesAndDisablesDormantRules()
    {
        BehaviorProfile profile = BehaviorProfileDefaults.Create(TargetKey) with
        {
            AutomaticRules =
            [
                new(Guid.Parse("55555555-5555-5555-5555-555555555555"), true, 3,
                    new RuleCondition.IdleAtLeast(15_000), BehaviorMotionReferences.DefaultSequence),
            ],
        };
        JsonObject source = JsonNode.Parse(RecommendedPetProfileCodec.Encode(
            profile, ["idle"], true))!.AsObject();
        source["schemaVersion"] = 10;
        JsonObject behavior = source["behavior"]!.AsObject();
        behavior["mode"] = "manual";
        behavior["manualSequenceID"] = BehaviorMotionReferences.DefaultSequence;
        behavior.Remove("stationaryBehaviorMode");
        behavior.Remove("stationarySequenceID");

        BehaviorProfile decoded = RecommendedPetProfileCodec.Decode(
            Encoding.UTF8.GetBytes(source.ToJsonString()), TargetKey, ["idle"]);

        Assert.Equal(StationaryBehaviorMode.Fixed, decoded.StationaryBehaviorMode);
        Assert.Equal(BehaviorMotionReferences.DefaultSequence, decoded.StationarySequenceId);
        AutomaticRule rule = Assert.Single(decoded.AutomaticRules);
        Assert.False(rule.IsEnabled);
        Assert.Equal(15_000, Assert.IsType<RuleCondition.IdleAtLeast>(rule.Condition).Milliseconds);
    }

    [Fact]
    public void RejectsMissingMotionAndOversizedData()
    {
        BehaviorProfile profile = BehaviorProfileDefaults.Create(TargetKey) with
        {
            PettingMotionId = "missing",
        };
        RecommendedPetProfileException missing = Assert.Throws<RecommendedPetProfileException>(
            () => RecommendedPetProfileCodec.Encode(profile, ["idle"], false));
        Assert.Equal(RecommendedPetProfileError.MissingMotion, missing.Error);

        var oversized = new byte[RecommendedPetProfileCodec.MaximumFileSize + 1];
        RecommendedPetProfileException tooLarge = Assert.Throws<RecommendedPetProfileException>(
            () => RecommendedPetProfileCodec.Decode(oversized, TargetKey, ["idle"]));
        Assert.Equal(RecommendedPetProfileError.TooLarge, tooLarge.Error);
    }
}
