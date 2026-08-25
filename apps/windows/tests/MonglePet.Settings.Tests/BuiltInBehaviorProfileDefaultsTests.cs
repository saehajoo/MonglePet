using MonglePet.Core.Behavior;

namespace MonglePet.Settings.Tests;

public sealed class BuiltInBehaviorProfileDefaultsTests
{
    [Fact]
    public void FreshBuiltInUsesMongleRecommendedProfileAndWindowsCodexRule()
    {
        Guid profileId = Guid.Parse("10000000-0000-0000-0000-000000000001");
        var ids = new Queue<Guid>(
        [
            Guid.Parse("10000000-0000-0000-0000-000000000002"),
            Guid.Parse("10000000-0000-0000-0000-000000000003"),
        ]);

        BehaviorProfile profile = BuiltInBehaviorProfileDefaults.Create(
            profileId,
            () => ids.Dequeue());

        Assert.Equal(profileId, profile.ProfileId);
        Assert.Equal(BehaviorMode.Automatic, profile.Mode);
        Assert.Equal(
            [BehaviorMotionReferences.DefaultSequence, "수면 중", "일해라"],
            profile.Sequences.Select(sequence => sequence.Id));
        Assert.Equal(
            [BehaviorMotionReferences.CurrentPetDefault, "물뿜기", "정면"],
            profile.Sequences[0].Steps.Select(step => step.MotionId));
        AutomaticRule codex = Assert.IsType<RuleCondition.Application>(
            profile.AutomaticRules[0].Condition) is RuleCondition.Application condition
                ? profile.AutomaticRules[0]
                : throw new InvalidOperationException();
        Assert.Equal(0, codex.Priority);
        Assert.Equal(
            BuiltInBehaviorProfileDefaults.WindowsCodexApplicationId,
            Assert.IsType<RuleCondition.Application>(codex.Condition).ApplicationId);
        Assert.Equal(60_000, Assert.IsType<RuleCondition.IdleAtLeast>(
            profile.AutomaticRules[1].Condition).Milliseconds);
        Assert.Equal(PetMovementMode.CursorAvoiding, profile.Movement.Mode);
        Assert.Equal("보글보글", profile.Movement.CursorAvoidingAnimation.FallbackMotionId);
        Assert.Equal("오른쪽", profile.Movement.CursorAvoidingAnimation.DirectionMotionIds.Right);
        Assert.Equal("해피", profile.PettingMotionId);
        Assert.False(profile.Speech.IsEnabled);
    }

    [Fact]
    public void InstalledPetKeepsNeutralDefault()
    {
        BehaviorProfile profile = BehaviorProfileDefaults.Create(
            new PetBehaviorKey.Installed(Guid.NewGuid()));

        Assert.Single(profile.Sequences);
        Assert.Empty(profile.AutomaticRules);
        Assert.Equal(PetMovementMode.Fixed, profile.Movement.Mode);
        Assert.Null(profile.PettingMotionId);
    }

    [Fact]
    public void OnlyExactLegacyNeutralBuiltInIsUpgraded()
    {
        Guid profileId = Guid.NewGuid();
        BehaviorProfile neutral = BehaviorProfileDefaults.Create(
            new PetBehaviorKey.Installed(Guid.NewGuid()),
            profileId) with { PetKey = PetBehaviorKey.BuiltInKey };
        Guid modifiedProfileId = Guid.NewGuid();
        BehaviorProfile modified = neutral with
        {
            ProfileId = modifiedProfileId,
            Movement = neutral.Movement with { Speed = 200 },
        };
        Guid firstInstanceId = Guid.NewGuid();
        Guid secondInstanceId = Guid.NewGuid();
        var settings = new AppSettings(
            [
                new ActivePetInstance(firstInstanceId, profileId, PetBehaviorKey.BuiltInKey, null, PetPresentation.Awake, OverlaySettings.Default, 0),
                new ActivePetInstance(secondInstanceId, modifiedProfileId, PetBehaviorKey.BuiltInKey, null, PetPresentation.Awake, OverlaySettings.Default, 1),
            ],
            [neutral, modified],
            firstInstanceId);

        AppSettings upgraded = BuiltInBehaviorProfileDefaults.UpgradeLegacyNeutralProfiles(settings);

        Assert.Equal(3, upgraded.BehaviorProfiles[0].Sequences.Count);
        Assert.Equal(profileId, upgraded.BehaviorProfiles[0].ProfileId);
        Assert.Equal(200, upgraded.BehaviorProfiles[1].Movement.Speed);
    }
}
