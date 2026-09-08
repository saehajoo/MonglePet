namespace MonglePet.Core.Behavior;

public static class BehaviorPlaybackPolicy
{
    public static MotionSequencePlayback ForStationary(StationaryBehaviorMode mode) =>
        mode == StationaryBehaviorMode.Fixed
            ? MotionSequencePlayback.RepeatWhileRequested
            : MotionSequencePlayback.Once;

    public static MotionSequencePlayback ForStationary(
        StationaryBehaviorMode mode,
        BehaviorSource source) => source is BehaviorSource.DefaultBehavior
            ? MotionSequencePlayback.RepeatWhileRequested
            : ForStationary(mode);

    public static MotionSequencePlayback ForAutomaticRule() =>
        MotionSequencePlayback.RepeatWhileRequested;
}
