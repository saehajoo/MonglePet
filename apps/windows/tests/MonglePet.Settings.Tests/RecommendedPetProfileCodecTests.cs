using System.Text;
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
        Assert.Equal(BehaviorMode.Manual, profile.Mode);
        Assert.Equal("walk", profile.Movement.CursorFollowingAnimation.FallbackMotionId);
        Assert.Equal("idle", profile.Movement.FreeRoamingAnimation.FallbackMotionId);
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
    public void VersionSevenRoundTripsAndCanExcludeApplicationRules()
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

        byte[] data = RecommendedPetProfileCodec.Encode(profile, ["idle"], false);
        BehaviorProfile decoded = RecommendedPetProfileCodec.Decode(data, TargetKey, ["idle"]);

        AutomaticRule rule = Assert.Single(decoded.AutomaticRules);
        Assert.IsType<RuleCondition.IdleAtLeast>(rule.Condition);
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
