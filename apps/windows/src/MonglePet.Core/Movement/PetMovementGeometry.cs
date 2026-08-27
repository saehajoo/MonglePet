namespace MonglePet.Core.Movement;

public readonly record struct MovementPoint(double X, double Y)
{
    public bool IsFinite => double.IsFinite(X) && double.IsFinite(Y);
}

public readonly record struct MovementSize(double Width, double Height)
{
    public bool IsValid =>
        double.IsFinite(Width) && Width > 0 &&
        double.IsFinite(Height) && Height > 0;
}

public readonly record struct MovementRect(double X, double Y, double Width, double Height)
{
    public double Left => X;
    public double Top => Y;
    public double Right => X + Width;
    public double Bottom => Y + Height;
    public double CenterX => X + (Width / 2);
    public double CenterY => Y + (Height / 2);
    public bool IsValid =>
        double.IsFinite(X) && double.IsFinite(Y) &&
        double.IsFinite(Width) && Width > 0 &&
        double.IsFinite(Height) && Height > 0 &&
        double.IsFinite(Right) && double.IsFinite(Bottom);

    public bool Contains(MovementPoint point) =>
        IsValid && point.IsFinite &&
        point.X >= Left && point.X <= Right &&
        point.Y >= Top && point.Y <= Bottom;
}

public sealed record MovementScreen(string Identifier, MovementRect WorkArea);

public readonly record struct MovementOriginBounds(
    double MinimumX,
    double MaximumX,
    double MinimumY,
    double MaximumY)
{
    public MovementPoint Clamp(MovementPoint point) => new(
        Math.Clamp(point.X, MinimumX, MaximumX),
        Math.Clamp(point.Y, MinimumY, MaximumY));

    public MovementPoint Point(double horizontal, double vertical) => new(
        MinimumX + ((MaximumX - MinimumX) * Unit(horizontal)),
        MinimumY + ((MaximumY - MinimumY) * Unit(vertical)));

    public MovementOriginBounds? Intersection(MovementOriginBounds other)
    {
        double minimumX = Math.Max(MinimumX, other.MinimumX);
        double maximumX = Math.Min(MaximumX, other.MaximumX);
        double minimumY = Math.Max(MinimumY, other.MinimumY);
        double maximumY = Math.Min(MaximumY, other.MaximumY);
        return minimumX <= maximumX && minimumY <= maximumY
            ? new MovementOriginBounds(minimumX, maximumX, minimumY, maximumY)
            : null;
    }

    private static double Unit(double value) =>
        double.IsFinite(value) ? Math.Clamp(value, 0, 1) : 0;
}

public readonly record struct MovementAdvance(
    MovementPoint Origin,
    bool DidMove,
    bool HasArrived);

public readonly record struct MovementRandomSample(
    double Screen,
    double Horizontal,
    double Vertical);

public enum MovementDirection
{
    Left,
    Right,
    Up,
    Down,
    UpLeft,
    UpRight,
    DownLeft,
    DownRight,
}

public static class PetMovementGeometry
{
    public const double DefaultScreenInset = 8;

    public static MovementOriginBounds? SafeOriginBounds(
        MovementRect workArea,
        MovementSize petSize,
        double inset = DefaultScreenInset)
    {
        if (!workArea.IsValid || !petSize.IsValid || !double.IsFinite(inset))
        {
            return null;
        }

        double safeInset = Math.Max(0, inset);
        double minimumX = workArea.Left + safeInset;
        double maximumX = workArea.Right - safeInset - petSize.Width;
        double minimumY = workArea.Top + safeInset;
        double maximumY = workArea.Bottom - safeInset - petSize.Height;
        double centeredX = workArea.CenterX - (petSize.Width / 2);
        double centeredY = workArea.CenterY - (petSize.Height / 2);
        return new MovementOriginBounds(
            minimumX <= maximumX ? minimumX : centeredX,
            minimumX <= maximumX ? maximumX : centeredX,
            minimumY <= maximumY ? minimumY : centeredY,
            minimumY <= maximumY ? maximumY : centeredY);
    }

    public static MovementPoint? ClampToNearestScreen(
        MovementPoint requestedOrigin,
        MovementSize petSize,
        IReadOnlyList<MovementScreen> screens,
        double inset = DefaultScreenInset)
    {
        MovementScreen? screen = ScreenContainingOrNearest(
            new MovementPoint(
                requestedOrigin.X + (petSize.Width / 2),
                requestedOrigin.Y + (petSize.Height / 2)),
            screens);
        MovementOriginBounds? bounds = screen is null
            ? null
            : SafeOriginBounds(screen.WorkArea, petSize, inset);
        return bounds?.Clamp(requestedOrigin);
    }

    public static MovementPoint? CursorFollowingTarget(
        MovementPoint pointer,
        MovementPoint currentOrigin,
        MovementSize petSize,
        double cursorDistance,
        IReadOnlyList<MovementScreen> screens,
        double inset = DefaultScreenInset)
    {
        if (!pointer.IsFinite || !currentOrigin.IsFinite || !petSize.IsValid ||
            !double.IsFinite(cursorDistance) || cursorDistance < 0)
        {
            return null;
        }

        MovementScreen? screen = ScreenContainingOrNearest(pointer, screens);
        MovementOriginBounds? bounds = screen is null
            ? null
            : SafeOriginBounds(screen.WorkArea, petSize, inset);
        if (bounds is null)
        {
            return null;
        }

        double centerX = currentOrigin.X + (petSize.Width / 2);
        double centerY = currentOrigin.Y + (petSize.Height / 2);
        double deltaX = pointer.X - centerX;
        double deltaY = pointer.Y - centerY;
        double distance = Math.Sqrt((deltaX * deltaX) + (deltaY * deltaY));
        double targetCenterX = pointer.X;
        double targetCenterY = pointer.Y;
        if (distance > 0.0001)
        {
            targetCenterX -= (deltaX / distance) * cursorDistance;
            targetCenterY -= (deltaY / distance) * cursorDistance;
        }

        return bounds.Value.Clamp(new MovementPoint(
            targetCenterX - (petSize.Width / 2),
            targetCenterY - (petSize.Height / 2)));
    }

    public static MovementPoint? FreeRoamingTarget(
        IReadOnlyList<MovementScreen> screens,
        MovementSize petSize,
        MovementRandomSample sample,
        double inset = DefaultScreenInset,
        MovementRect? preferredWindow = null)
    {
        MovementScreen[] valid = screens.Where(screen => screen.WorkArea.IsValid).ToArray();
        if (valid.Length == 0 || !petSize.IsValid)
        {
            return null;
        }

        if (preferredWindow is { } window &&
            PreferredOriginBounds(window, valid, petSize, inset) is { } preferredBounds)
        {
            return preferredBounds.Point(sample.Horizontal, sample.Vertical);
        }

        int index = Math.Min(
            valid.Length - 1,
            (int)Math.Floor(Unit(sample.Screen) * valid.Length));
        MovementOriginBounds? bounds = SafeOriginBounds(valid[index].WorkArea, petSize, inset);
        return bounds?.Point(sample.Horizontal, sample.Vertical);
    }

    public static double? DistanceFromPointerToPet(
        MovementPoint pointer,
        MovementPoint petOrigin,
        MovementSize petSize)
    {
        if (!pointer.IsFinite || !petOrigin.IsFinite || !petSize.IsValid)
        {
            return null;
        }

        double nearestX = Math.Clamp(pointer.X, petOrigin.X, petOrigin.X + petSize.Width);
        double nearestY = Math.Clamp(pointer.Y, petOrigin.Y, petOrigin.Y + petSize.Height);
        double deltaX = pointer.X - nearestX;
        double deltaY = pointer.Y - nearestY;
        return Math.Sqrt((deltaX * deltaX) + (deltaY * deltaY));
    }

    public static MovementPoint? CursorAvoidingTarget(
        MovementPoint pointer,
        MovementPoint currentOrigin,
        MovementSize petSize,
        double safeDistance,
        IReadOnlyList<MovementScreen> screens,
        double inset = DefaultScreenInset)
    {
        if (!pointer.IsFinite || !currentOrigin.IsFinite || !petSize.IsValid ||
            !double.IsFinite(safeDistance) || safeDistance < 0)
        {
            return null;
        }

        double centerX = currentOrigin.X + (petSize.Width / 2);
        double centerY = currentOrigin.Y + (petSize.Height / 2);
        double awayX = centerX - pointer.X;
        double awayY = centerY - pointer.Y;
        double magnitude = Math.Sqrt((awayX * awayX) + (awayY * awayY));
        if (magnitude <= 0.0001)
        {
            awayX = 1;
            awayY = 0;
            magnitude = 1;
        }

        double travel = safeDistance + Math.Max(petSize.Width, petSize.Height);
        var desired = new MovementPoint(
            currentOrigin.X + ((awayX / magnitude) * travel),
            currentOrigin.Y + ((awayY / magnitude) * travel));
        var candidates = new List<MovementPoint>();
        foreach (MovementScreen screen in screens.Where(value => value.WorkArea.IsValid))
        {
            if (SafeOriginBounds(screen.WorkArea, petSize, inset) is not { } bounds)
            {
                continue;
            }
            MovementPoint direct = bounds.Clamp(desired);
            candidates.Add(direct);
            candidates.Add(bounds.Point(0, 0));
            candidates.Add(bounds.Point(0, 1));
            candidates.Add(bounds.Point(1, 0));
            candidates.Add(bounds.Point(1, 1));
        }

        if (candidates.Count == 0)
        {
            return null;
        }

        double unitX = awayX / magnitude;
        double unitY = awayY / magnitude;
        MovementPoint[] awayCandidates = candidates
            .Where(candidate =>
                ((candidate.X - currentOrigin.X) * unitX) +
                ((candidate.Y - currentOrigin.Y) * unitY) >= -0.0001)
            .Distinct()
            .ToArray();
        if (awayCandidates.Length == 0)
        {
            awayCandidates = candidates.Distinct().ToArray();
        }

        MovementPoint[] safeCandidates = awayCandidates.Where(candidate =>
            DistanceFromPointerToPet(pointer, candidate, petSize) >= safeDistance).ToArray();
        if (safeCandidates.Length > 0)
        {
            return safeCandidates.MinBy(candidate => SquaredDistance(candidate, currentOrigin));
        }
        return awayCandidates.MaxBy(candidate =>
            DistanceFromPointerToPet(pointer, candidate, petSize) ?? 0);
    }

    public static bool ShouldRefreshCursorAvoidingTarget(
        MovementPoint pointer,
        MovementPoint? pointerAnchor,
        bool hasTarget,
        double minimumPointerTravel = 24)
    {
        if (!pointer.IsFinite ||
            !double.IsFinite(minimumPointerTravel) || minimumPointerTravel < 0)
        {
            return true;
        }
        if (!hasTarget || pointerAnchor is not { IsFinite: true } anchor)
        {
            return true;
        }

        return SquaredDistance(pointer, anchor) >=
            minimumPointerTravel * minimumPointerTravel;
    }

    public static MovementAdvance Advance(
        MovementPoint currentOrigin,
        MovementPoint targetOrigin,
        double speed,
        double elapsedSeconds,
        double stopRadius)
    {
        if (!currentOrigin.IsFinite || !targetOrigin.IsFinite ||
            !double.IsFinite(speed) || speed <= 0 ||
            !double.IsFinite(elapsedSeconds) || elapsedSeconds <= 0 ||
            !double.IsFinite(stopRadius) || stopRadius < 0)
        {
            return new MovementAdvance(currentOrigin, false, false);
        }

        double deltaX = targetOrigin.X - currentOrigin.X;
        double deltaY = targetOrigin.Y - currentOrigin.Y;
        double distance = Math.Sqrt((deltaX * deltaX) + (deltaY * deltaY));
        if (distance <= stopRadius)
        {
            return new MovementAdvance(currentOrigin, false, true);
        }

        double travel = speed * elapsedSeconds;
        if (!double.IsFinite(travel) || travel <= 0)
        {
            return new MovementAdvance(currentOrigin, false, false);
        }
        if (travel >= distance)
        {
            return new MovementAdvance(targetOrigin, true, true);
        }

        double progress = travel / distance;
        return new MovementAdvance(
            new MovementPoint(
                currentOrigin.X + (deltaX * progress),
                currentOrigin.Y + (deltaY * progress)),
            true,
            (distance - travel) <= stopRadius);
    }

    public static MovementDirection? Direction(
        double deltaX,
        double deltaY,
        bool usesDiagonals,
        MovementDirection? previousDirection = null,
        double hysteresisDegrees = 8)
    {
        if (!double.IsFinite(deltaX) || !double.IsFinite(deltaY) ||
            Math.Abs(deltaX) + Math.Abs(deltaY) <= 0.0001)
        {
            return null;
        }

        MovementDirection classified;
        if (!usesDiagonals)
        {
            classified = Math.Abs(deltaX) >= Math.Abs(deltaY)
                ? deltaX < 0 ? MovementDirection.Left : MovementDirection.Right
                : deltaY < 0 ? MovementDirection.Up : MovementDirection.Down;
        }
        else
        {
            double angle = Math.Atan2(deltaY, deltaX) * 180 / Math.PI;
            classified = angle switch
            {
                >= -22.5 and < 22.5 => MovementDirection.Right,
                >= 22.5 and < 67.5 => MovementDirection.DownRight,
                >= 67.5 and < 112.5 => MovementDirection.Down,
                >= 112.5 and < 157.5 => MovementDirection.DownLeft,
                >= 157.5 or < -157.5 => MovementDirection.Left,
                >= -157.5 and < -112.5 => MovementDirection.UpLeft,
                >= -112.5 and < -67.5 => MovementDirection.Up,
                _ => MovementDirection.UpRight,
            };
        }

        if (previousDirection is not { } previous ||
            (!usesDiagonals && IsDiagonal(previous)) ||
            !double.IsFinite(hysteresisDegrees) ||
            hysteresisDegrees <= 0)
        {
            return classified;
        }

        double currentAngle = Math.Atan2(deltaY, deltaX) * 180 / Math.PI;
        double halfSector = usesDiagonals ? 22.5 : 45;
        return AngularDistance(currentAngle, DirectionAngle(previous)) <=
            halfSector + hysteresisDegrees
                ? previous
                : classified;
    }

    public static IReadOnlyList<MovementDirection> CompatibleDirections(
        double deltaX,
        double deltaY,
        bool usesDiagonals,
        MovementDirection? previousDirection = null,
        double hysteresisDegrees = 8)
    {
        MovementDirection? exact = Direction(
            deltaX,
            deltaY,
            usesDiagonals,
            previousDirection,
            hysteresisDegrees);
        if (exact is null)
        {
            return Array.Empty<MovementDirection>();
        }

        double distance = Math.Sqrt((deltaX * deltaX) + (deltaY * deltaY));
        if (!double.IsFinite(distance) || distance <= 0.0001)
        {
            return Array.Empty<MovementDirection>();
        }

        MovementDirection[] stableOrder = usesDiagonals
            ? [
                MovementDirection.Left,
                MovementDirection.Right,
                MovementDirection.Up,
                MovementDirection.Down,
                MovementDirection.UpLeft,
                MovementDirection.UpRight,
                MovementDirection.DownLeft,
                MovementDirection.DownRight,
            ]
            : [
                MovementDirection.Left,
                MovementDirection.Right,
                MovementDirection.Up,
                MovementDirection.Down,
            ];
        return stableOrder
            .Select((direction, index) =>
            {
                (double X, double Y) vector = DirectionVector(direction);
                double similarity = ((deltaX / distance) * vector.X) +
                    ((deltaY / distance) * vector.Y);
                bool opposesX = Math.Abs(deltaX / distance) > 0.05 &&
                    vector.X != 0 && Math.Sign(vector.X) != Math.Sign(deltaX);
                bool opposesY = Math.Abs(deltaY / distance) > 0.05 &&
                    vector.Y != 0 && Math.Sign(vector.Y) != Math.Sign(deltaY);
                return (Direction: direction, Similarity: similarity, Index: index,
                    IsCompatible: similarity > 0.05 && !opposesX && !opposesY);
            })
            .Where(item => item.IsCompatible)
            .OrderByDescending(item => item.Direction == exact)
            .ThenByDescending(item => item.Similarity)
            .ThenBy(item => item.Index)
            .Select(item => item.Direction)
            .ToArray();
    }

    private static bool IsDiagonal(MovementDirection direction) => direction is
        MovementDirection.UpLeft or MovementDirection.UpRight or
        MovementDirection.DownLeft or MovementDirection.DownRight;

    private static double DirectionAngle(MovementDirection direction) => direction switch
    {
        MovementDirection.Right => 0,
        MovementDirection.DownRight => 45,
        MovementDirection.Down => 90,
        MovementDirection.DownLeft => 135,
        MovementDirection.Left => 180,
        MovementDirection.UpLeft => -135,
        MovementDirection.Up => -90,
        MovementDirection.UpRight => -45,
        _ => 0,
    };

    private static (double X, double Y) DirectionVector(MovementDirection direction)
    {
        const double diagonal = 0.7071067811865476;
        return direction switch
        {
            MovementDirection.Left => (-1, 0),
            MovementDirection.Right => (1, 0),
            MovementDirection.Up => (0, -1),
            MovementDirection.Down => (0, 1),
            MovementDirection.UpLeft => (-diagonal, -diagonal),
            MovementDirection.UpRight => (diagonal, -diagonal),
            MovementDirection.DownLeft => (-diagonal, diagonal),
            MovementDirection.DownRight => (diagonal, diagonal),
            _ => (0, 0),
        };
    }

    private static double AngularDistance(double left, double right)
    {
        double delta = Math.Abs(left - right) % 360;
        return delta > 180 ? 360 - delta : delta;
    }

    private static MovementScreen? ScreenContainingOrNearest(
        MovementPoint point,
        IReadOnlyList<MovementScreen> screens)
    {
        MovementScreen[] valid = screens.Where(screen => screen.WorkArea.IsValid).ToArray();
        return valid.FirstOrDefault(screen => screen.WorkArea.Contains(point))
            ?? valid.MinBy(screen => SquaredDistanceToRect(point, screen.WorkArea));
    }

    private static MovementOriginBounds? PreferredOriginBounds(
        MovementRect window,
        IReadOnlyList<MovementScreen> screens,
        MovementSize petSize,
        double inset)
    {
        if (!window.IsValid ||
            window.Width < petSize.Width ||
            window.Height < petSize.Height)
        {
            return null;
        }

        MovementScreen? screen = screens
            .Where(value => value.WorkArea.IsValid)
            .MaxBy(value => IntersectionArea(value.WorkArea, window));
        if (screen is null || IntersectionArea(screen.WorkArea, window) <= 0 ||
            SafeOriginBounds(screen.WorkArea, petSize, inset) is not { } screenBounds ||
            SafeOriginBounds(window, petSize, 0) is not { } windowBounds)
        {
            return null;
        }
        return screenBounds.Intersection(windowBounds);
    }

    private static double IntersectionArea(MovementRect left, MovementRect right)
    {
        double width = Math.Max(0, Math.Min(left.Right, right.Right) -
            Math.Max(left.Left, right.Left));
        double height = Math.Max(0, Math.Min(left.Bottom, right.Bottom) -
            Math.Max(left.Top, right.Top));
        return width * height;
    }

    private static double SquaredDistanceToRect(MovementPoint point, MovementRect rect)
    {
        double x = Math.Clamp(point.X, rect.Left, rect.Right);
        double y = Math.Clamp(point.Y, rect.Top, rect.Bottom);
        return SquaredDistance(point, new MovementPoint(x, y));
    }

    private static double SquaredDistance(MovementPoint left, MovementPoint right)
    {
        double x = left.X - right.X;
        double y = left.Y - right.Y;
        return (x * x) + (y * y);
    }

    private static double Unit(double value) =>
        double.IsFinite(value) ? Math.Clamp(value, 0, 0.999999999) : 0;
}
