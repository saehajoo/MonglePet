namespace MonglePet.Shell;

public readonly record struct ScreenPoint(int X, int Y);

public sealed record MonitorWorkArea(
    string Identifier,
    int Left,
    int Top,
    int Right,
    int Bottom)
{
    public int Width => Math.Max(0, Right - Left);

    public int Height => Math.Max(0, Bottom - Top);
}

public sealed record PetScreenPlacement(string ScreenIdentifier, int X, int Y);

public static class PetScreenPlacementCalculator
{
    public const int DefaultRightMargin = 48;
    public const int DefaultBottomMargin = 40;

    public static PetScreenPlacement BottomRight(
        MonitorWorkArea workArea,
        int petWidth,
        int petHeight,
        int rightMargin = DefaultRightMargin,
        int bottomMargin = DefaultBottomMargin)
    {
        Validate(workArea, petWidth, petHeight);
        int x = workArea.Right - petWidth - Math.Max(0, rightMargin);
        int y = workArea.Bottom - petHeight - Math.Max(0, bottomMargin);
        return Clamp(workArea, x, y, petWidth, petHeight);
    }

    public static PetScreenPlacement Clamp(
        MonitorWorkArea workArea,
        int requestedX,
        int requestedY,
        int petWidth,
        int petHeight)
    {
        Validate(workArea, petWidth, petHeight);
        int maximumX = Math.Max(workArea.Left, workArea.Right - petWidth);
        int maximumY = Math.Max(workArea.Top, workArea.Bottom - petHeight);
        return new PetScreenPlacement(
            workArea.Identifier,
            Math.Clamp(requestedX, workArea.Left, maximumX),
            Math.Clamp(requestedY, workArea.Top, maximumY));
    }

    private static void Validate(
        MonitorWorkArea workArea,
        int petWidth,
        int petHeight)
    {
        ArgumentNullException.ThrowIfNull(workArea);
        if (string.IsNullOrWhiteSpace(workArea.Identifier) ||
            workArea.Width <= 0 ||
            workArea.Height <= 0 ||
            petWidth <= 0 ||
            petHeight <= 0)
        {
            throw new ArgumentException("모니터 작업 영역과 펫 크기가 올바르지 않습니다.");
        }
    }
}
