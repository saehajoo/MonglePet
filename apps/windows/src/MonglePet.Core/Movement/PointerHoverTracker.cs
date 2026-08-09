namespace MonglePet.Core.Movement;

public sealed class PointerHoverTracker
{
    public const long DefaultDwellMilliseconds = 300;

    private readonly long _dwellMilliseconds;
    private long? _enteredAt;
    private PointerHoverState _state = PointerHoverState.NeedsExit;

    public PointerHoverTracker(long dwellMilliseconds = DefaultDwellMilliseconds)
    {
        if (dwellMilliseconds < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(dwellMilliseconds));
        }
        _dwellMilliseconds = dwellMilliseconds;
    }

    public bool Update(
        long timestampMilliseconds,
        bool isInsidePanel,
        bool isOverVisibleContent,
        bool pointerMoved,
        bool isEnabled,
        bool isDragging)
    {
        if (timestampMilliseconds < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(timestampMilliseconds));
        }
        if (!isEnabled || isDragging)
        {
            Reset();
            return false;
        }
        if (!isInsidePanel)
        {
            _enteredAt = null;
            _state = PointerHoverState.Armed;
            return false;
        }

        switch (_state)
        {
            case PointerHoverState.NeedsExit:
                return false;
            case PointerHoverState.Armed:
                if (!isOverVisibleContent || !pointerMoved)
                {
                    return false;
                }
                _enteredAt = timestampMilliseconds;
                _state = PointerHoverState.Dwelling;
                return false;
            case PointerHoverState.Dwelling:
                if (!isOverVisibleContent)
                {
                    _enteredAt = null;
                    _state = PointerHoverState.NeedsExit;
                    return false;
                }
                if (_enteredAt is not long enteredAt ||
                    timestampMilliseconds - enteredAt < _dwellMilliseconds)
                {
                    return false;
                }
                _enteredAt = null;
                _state = PointerHoverState.NeedsExit;
                return true;
            default:
                throw new InvalidOperationException("Unknown pointer hover state.");
        }
    }

    public void Reset()
    {
        _enteredAt = null;
        _state = PointerHoverState.NeedsExit;
    }

    private enum PointerHoverState
    {
        NeedsExit,
        Armed,
        Dwelling,
    }
}
