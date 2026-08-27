namespace MonglePet.Packages;

public sealed class PetFramePlaybackState
{
    private readonly bool _loops;

    public PetFramePlaybackState(PetPackageMotion motion, bool? loops = null)
    {
        ArgumentNullException.ThrowIfNull(motion);
        if (motion.Frames.Count == 0)
        {
            throw new ArgumentException("A motion must have at least one frame.", nameof(motion));
        }

        Motion = motion;
        _loops = loops ?? motion.Loop;
        IsPlaying = true;
    }

    public PetPackageMotion Motion { get; }

    public int CurrentFrameIndex { get; private set; }

    public PetPackageFrame CurrentFrame => Motion.Frames[CurrentFrameIndex];

    public bool IsPlaying { get; private set; }

    public bool NeedsScheduling => IsPlaying && Motion.Frames.Count > 1;

    public TimeSpan CycleDuration => TimeSpan.FromMilliseconds(
        Motion.Frames.Sum(frame => (long)frame.DurationMs));

    public TimeSpan Seek(TimeSpan elapsed)
    {
        if (elapsed < TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(elapsed));
        }

        TimeSpan cycleDuration = CycleDuration;
        TimeSpan position;
        if (_loops)
        {
            position = TimeSpan.FromTicks(elapsed.Ticks % cycleDuration.Ticks);
            IsPlaying = true;
        }
        else if (elapsed >= cycleDuration)
        {
            CurrentFrameIndex = Motion.Frames.Count - 1;
            IsPlaying = false;
            return TimeSpan.Zero;
        }
        else
        {
            position = elapsed;
            IsPlaying = true;
        }

        for (int index = 0; index < Motion.Frames.Count; index++)
        {
            TimeSpan frameDuration = TimeSpan.FromMilliseconds(Motion.Frames[index].DurationMs);
            if (position < frameDuration)
            {
                CurrentFrameIndex = index;
                return frameDuration - position;
            }
            position -= frameDuration;
        }

        CurrentFrameIndex = 0;
        return TimeSpan.FromMilliseconds(Motion.Frames[0].DurationMs);
    }

    public bool Advance()
    {
        if (!IsPlaying)
        {
            return false;
        }

        int next = CurrentFrameIndex + 1;
        if (next < Motion.Frames.Count)
        {
            CurrentFrameIndex = next;
            return true;
        }

        if (_loops)
        {
            CurrentFrameIndex = 0;
            return true;
        }

        IsPlaying = false;
        return false;
    }
}
