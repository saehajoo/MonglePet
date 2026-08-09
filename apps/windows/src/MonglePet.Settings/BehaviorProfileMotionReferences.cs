using MonglePet.Core.Behavior;

namespace MonglePet.Settings;

public static class BehaviorProfileMotionReferences
{
    public static BehaviorProfile Replacing(
        BehaviorProfile profile,
        string motionId,
        string? replacementMotionId)
    {
        ArgumentNullException.ThrowIfNull(profile);
        ArgumentException.ThrowIfNullOrWhiteSpace(motionId);
        string? replacement = string.IsNullOrWhiteSpace(replacementMotionId)
            ? null
            : replacementMotionId.Trim();

        string Required(string value) => string.Equals(value, motionId, StringComparison.Ordinal)
            ? replacement ?? BehaviorMotionReferences.CurrentPetDefault
            : value;
        string? Optional(string? value) => string.Equals(value, motionId, StringComparison.Ordinal)
            ? replacement
            : value;
        MovementAnimationSettings Animation(MovementAnimationSettings value) => value with
        {
            FallbackMotionId = Optional(value.FallbackMotionId),
            DirectionMotionIds = value.DirectionMotionIds with
            {
                Left = Optional(value.DirectionMotionIds.Left),
                Right = Optional(value.DirectionMotionIds.Right),
                Up = Optional(value.DirectionMotionIds.Up),
                Down = Optional(value.DirectionMotionIds.Down),
                UpLeft = Optional(value.DirectionMotionIds.UpLeft),
                UpRight = Optional(value.DirectionMotionIds.UpRight),
                DownLeft = Optional(value.DirectionMotionIds.DownLeft),
                DownRight = Optional(value.DirectionMotionIds.DownRight),
            },
        };

        return profile with
        {
            Sequences = profile.Sequences.Select(sequence => sequence with
            {
                Steps = sequence.Steps.Select(step => step with
                {
                    MotionId = Required(step.MotionId),
                }).ToArray(),
            }).ToArray(),
            Movement = profile.Movement with
            {
                CursorFollowingAnimation = Animation(profile.Movement.CursorFollowingAnimation),
                FreeRoamingAnimation = Animation(profile.Movement.FreeRoamingAnimation),
                CursorAvoidingAnimation = Animation(profile.Movement.CursorAvoidingAnimation),
            },
            PettingMotionId = Optional(profile.PettingMotionId),
        };
    }
}
