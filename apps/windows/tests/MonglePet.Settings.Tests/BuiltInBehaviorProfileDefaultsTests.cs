using MonglePet.Core.Behavior;

namespace MonglePet.Settings.Tests;

public sealed class BuiltInBehaviorProfileDefaultsTests
{
    [Fact]
    public void FreshBuiltInUsesCommonMongleVersionTenRecommendedProfile()
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
        Assert.Equal(12, profile.Sequences.Count);
        BehaviorSequence defaultSequence = profile.Sequences.Single(
            sequence => sequence.Id == BehaviorMotionReferences.DefaultSequence);
        Assert.Equal(BehaviorMotionReferences.CurrentPetDefault,
            Assert.Single(defaultSequence.Steps).MotionId);
        AutomaticRule idle = Assert.Single(profile.AutomaticRules);
        Assert.Equal(60_000, Assert.IsType<RuleCondition.IdleAtLeast>(
            idle.Condition).Milliseconds);
        Assert.DoesNotContain(profile.AutomaticRules,
            rule => rule.Condition is RuleCondition.Application);
        Assert.Equal(PetMovementMode.CursorAvoiding, profile.Movement.Mode);
        Assert.True(profile.Movement.CursorAvoiding.Behavior.UsesDirectionalBehaviors);
        string rightBehaviorId = Assert.IsType<string>(
            profile.Movement.CursorAvoiding.Behavior.DirectionBehaviorIds.Right);
        Assert.Equal("오른쪽 보글보글", Assert.Single(profile.Sequences.Single(
            sequence => sequence.Id == rightBehaviorId).Steps).MotionId);
        string pettingBehaviorId = Assert.IsType<string>(profile.PettingBehaviorId);
        Assert.Equal("행복", Assert.Single(profile.Sequences.Single(
            sequence => sequence.Id == pettingBehaviorId).Steps).MotionId);
        Assert.False(profile.Speech.IsEnabled);
    }

    [Fact]
    public void InstalledPetKeepsNeutralDefault()
    {
        BehaviorProfile profile = BehaviorProfileDefaults.Create(
            new PetBehaviorKey.Installed(Guid.NewGuid()));

        Assert.Single(profile.Sequences);
        Assert.Equal("기본", profile.Sequences[0].DisplayName);
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

        Assert.Equal(12, upgraded.BehaviorProfiles[0].Sequences.Count);
        Assert.Equal(profileId, upgraded.BehaviorProfiles[0].ProfileId);
        Assert.Equal(200, upgraded.BehaviorProfiles[1].Movement.Speed);
    }
}
