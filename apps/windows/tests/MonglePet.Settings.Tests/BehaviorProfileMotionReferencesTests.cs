using MonglePet.Core.Behavior;

namespace MonglePet.Settings.Tests;

public sealed class BehaviorProfileMotionReferencesTests
{
    [Fact]
    public void RenameUpdatesBehaviorMovementAndPettingReferences()
    {
        BehaviorProfile source = Profile("walk");

        BehaviorProfile updated = BehaviorProfileMotionReferences.Replacing(
            source,
            "walk",
            "stroll");

        Assert.Equal("stroll", updated.Sequences[0].Steps[0].MotionId);
        Assert.Equal("stroll", updated.Movement.CursorFollowingAnimation.FallbackMotionId);
        Assert.Equal("stroll", updated.Movement.FreeRoamingAnimation.DirectionMotionIds.Left);
        Assert.Equal("stroll", updated.PettingMotionId);
    }

    [Fact]
    public void RemovalUsesCurrentDefaultForStepsAndClearsOptionalReferences()
    {
        BehaviorProfile source = Profile("walk");

        BehaviorProfile updated = BehaviorProfileMotionReferences.Replacing(
            source,
            "walk",
            replacementMotionId: null);

        Assert.Equal(BehaviorMotionReferences.CurrentPetDefault, updated.Sequences[0].Steps[0].MotionId);
        Assert.Null(updated.Movement.CursorFollowingAnimation.FallbackMotionId);
        Assert.Null(updated.Movement.FreeRoamingAnimation.DirectionMotionIds.Left);
        Assert.Null(updated.PettingMotionId);
    }

    private static BehaviorProfile Profile(string motionId) => new(
        Guid.Parse("11111111-1111-1111-1111-111111111111"),
        PetBehaviorKey.BuiltInKey,
        StationaryBehaviorMode.Fixed,
        "default",
        [new BehaviorSequence("default", [new BehaviorStep(motionId, 1)], true)],
        [],
        PetMovementSettings.Default with
        {
            CursorFollowingAnimation = MovementAnimationSettings.Default with
            {
                FallbackMotionId = motionId,
            },
            FreeRoamingAnimation = MovementAnimationSettings.Default with
            {
                UsesDirectionalMotions = true,
                DirectionMotionIds = new DirectionalMotionIds(Left: motionId),
            },
        },
        motionId,
        PetSpeechSettings.Default);
}
