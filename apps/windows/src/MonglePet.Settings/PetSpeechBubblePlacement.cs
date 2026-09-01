namespace MonglePet.Settings;

public readonly record struct PetSpeechBubblePoint(double X, double Y);

public readonly record struct PetSpeechBubbleSize(double Width, double Height);

public readonly record struct PetSpeechBubbleRect(
    double X,
    double Y,
    double Width,
    double Height)
{
    public double Left => X;

    public double Top => Y;

    public double Right => X + Width;

    public double Bottom => Y + Height;

    public double MidX => X + (Width / 2);

    public double MidY => Y + (Height / 2);
}

public enum PetSpeechBubbleTailEdge
{
    Top,
    Bottom,
}

public sealed record PetSpeechBubblePlacementResult(
    PetSpeechBubblePoint Origin,
    PetSpeechBubbleTailEdge TailEdge,
    double? TailAnchorX);

public readonly record struct PetSpeechBubbleTailMetrics(
    double TailHeight,
    double PlacementGap);

public static class PetSpeechBubbleTailLayout
{
    public static PetSpeechBubbleTailMetrics Calculate(
        bool showsTail,
        double baseTailHeight,
        double gap)
    {
        if (!double.IsFinite(baseTailHeight) || baseTailHeight < 0 ||
            !double.IsFinite(gap) || gap < 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(gap),
                "말풍선 꼬리 높이와 간격은 0 이상의 유한한 값이어야 합니다.");
        }

        return showsTail
            ? new PetSpeechBubbleTailMetrics(baseTailHeight, gap)
            : new PetSpeechBubbleTailMetrics(0, gap);
    }
}

public static class PetSpeechBubblePlacement
{
    public static PetSpeechBubblePlacementResult Calculate(
        PetSpeechBubbleRect parentFrame,
        PetSpeechBubbleSize bubbleSize,
        PetSpeechBubbleRect visibleFrame,
        PetSpeechBubblePlacementSettings settings,
        PetSpeechBubbleTailEdge? lockedAutomaticTailEdge = null)
    {
        ArgumentNullException.ThrowIfNull(settings);
        Validate(parentFrame, bubbleSize, visibleFrame);

        double naturalCenteredX = parentFrame.MidX - (bubbleSize.Width / 2);
        double centeredX = naturalCenteredX + settings.HorizontalOffset;
        double minimumX = visibleFrame.Left;
        double maximumX = Math.Max(minimumX, visibleFrame.Right - bubbleSize.Width);
        double x = Math.Clamp(centeredX, minimumX, maximumX);

        double aboveY = parentFrame.Top - settings.Gap - bubbleSize.Height;
        double belowY = parentFrame.Bottom + settings.Gap;
        bool canPlaceAbove = aboveY >= visibleFrame.Top;
        bool canPlaceBelow = belowY + bubbleSize.Height <= visibleFrame.Bottom;
        bool usesAbove = settings.PreferredPosition == PetSpeechBubblePreferredPosition.Automatic &&
            lockedAutomaticTailEdge is { } locked
                ? locked == PetSpeechBubbleTailEdge.Bottom
                    ? canPlaceAbove || !canPlaceBelow
                    : !canPlaceBelow && canPlaceAbove
                : settings.PreferredPosition switch
        {
            PetSpeechBubblePreferredPosition.Automatic or
                PetSpeechBubblePreferredPosition.Above =>
                canPlaceAbove || !canPlaceBelow,
            PetSpeechBubblePreferredPosition.Below =>
                !canPlaceBelow && canPlaceAbove,
            _ => canPlaceAbove || !canPlaceBelow,
        };

        double y;
        PetSpeechBubbleTailEdge tailEdge;
        if (usesAbove && canPlaceAbove)
        {
            y = aboveY;
            tailEdge = PetSpeechBubbleTailEdge.Bottom;
        }
        else if (!usesAbove && canPlaceBelow)
        {
            y = belowY;
            tailEdge = PetSpeechBubbleTailEdge.Top;
        }
        else
        {
            double maximumY = Math.Max(
                visibleFrame.Top,
                visibleFrame.Bottom - bubbleSize.Height);
            y = Math.Clamp(aboveY, visibleFrame.Top, maximumY);
            tailEdge = y + (bubbleSize.Height / 2) <= parentFrame.MidY
                ? PetSpeechBubbleTailEdge.Bottom
                : PetSpeechBubbleTailEdge.Top;
        }

        return new PetSpeechBubblePlacementResult(
            new PetSpeechBubblePoint(x, y),
            tailEdge,
            Math.Abs(x - naturalCenteredX) > 0.001
                ? parentFrame.MidX - x
                : null);
    }

    private static void Validate(
        PetSpeechBubbleRect parentFrame,
        PetSpeechBubbleSize bubbleSize,
        PetSpeechBubbleRect visibleFrame)
    {
        if (!Finite(parentFrame.X, parentFrame.Y, parentFrame.Width, parentFrame.Height) ||
            !Finite(bubbleSize.Width, bubbleSize.Height) ||
            !Finite(visibleFrame.X, visibleFrame.Y, visibleFrame.Width, visibleFrame.Height) ||
            parentFrame.Width <= 0 || parentFrame.Height <= 0 ||
            bubbleSize.Width <= 0 || bubbleSize.Height <= 0 ||
            visibleFrame.Width <= 0 || visibleFrame.Height <= 0)
        {
            throw new ArgumentException("말풍선 배치 영역과 크기가 올바르지 않습니다.");
        }
    }

    private static bool Finite(params double[] values) => values.All(double.IsFinite);
}
