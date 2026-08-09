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
