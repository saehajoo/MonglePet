namespace MonglePet.Core.Movement;

/// <summary>
/// Keeps sub-pixel movement between native window position updates.
/// HWND coordinates are integers, so deriving every step from the last rounded
/// window position would discard slow movement before it can accumulate.
/// </summary>
public sealed class MovementPositionAccumulator
{
    public MovementPositionAccumulator(MovementPoint origin)
    {
        if (!origin.IsFinite)
        {
            throw new ArgumentOutOfRangeException(nameof(origin));
        }
        Origin = origin;
    }

    public MovementPoint Origin { get; private set; }

    public MovementAdvance Advance(
        MovementPoint target,
        double speed,
        double elapsedSeconds,
        double stopRadius)
    {
        MovementAdvance advance = PetMovementGeometry.Advance(
            Origin,
            target,
            speed,
            elapsedSeconds,
            stopRadius);
        if (advance.DidMove)
        {
            Origin = advance.Origin;
        }
        return advance;
    }

    public void SetOrigin(MovementPoint origin)
    {
        if (!origin.IsFinite)
        {
            throw new ArgumentOutOfRangeException(nameof(origin));
        }
        Origin = origin;
    }

    public bool SynchronizeObservedPixelOrigin(MovementPoint observedOrigin)
    {
        if (!observedOrigin.IsFinite)
        {
            throw new ArgumentOutOfRangeException(nameof(observedOrigin));
        }

        (int expectedX, int expectedY) = RoundedPixelOrigin();
        if (expectedX == (int)Math.Round(observedOrigin.X) &&
            expectedY == (int)Math.Round(observedOrigin.Y))
        {
            return false;
        }

        Origin = observedOrigin;
        return true;
    }

    public (int X, int Y) RoundedPixelOrigin() =>
        ((int)Math.Round(Origin.X), (int)Math.Round(Origin.Y));
}
