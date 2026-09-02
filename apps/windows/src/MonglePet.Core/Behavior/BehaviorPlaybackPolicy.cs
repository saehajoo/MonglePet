namespace MonglePet.Core.Behavior;

public static class BehaviorPlaybackPolicy
{
    public static MotionSequencePlayback ForStationary(StationaryBehaviorMode mode) =>
        mode == StationaryBehaviorMode.Fixed
            ? MotionSequencePlayback.RepeatWhileRequested
            : MotionSequencePlayback.Once;
}
