namespace MonglePet.Core.Presentation;

public readonly record struct PetFrameViewport(
    double Scale,
    double Left,
    double Top,
    double Width,
    double Height,
    double RightInset,
    double BottomInset);

public static class PetFrameViewportGeometry
{
    public static PetFrameViewport AspectFit(
        double viewportWidth,
        double viewportHeight,
        int frameWidth,
        int frameHeight)
    {
        if (!double.IsFinite(viewportWidth) || viewportWidth <= 0 ||
            !double.IsFinite(viewportHeight) || viewportHeight <= 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(viewportWidth),
                "The viewport dimensions must be finite and greater than zero.");
        }
        if (frameWidth <= 0 || frameHeight <= 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(frameWidth),
                "The frame dimensions must be greater than zero.");
        }

        double scale = Math.Min(
            viewportWidth / frameWidth,
            viewportHeight / frameHeight);
        double width = frameWidth * scale;
        double height = frameHeight * scale;
        double left = (viewportWidth - width) / 2;
        double top = (viewportHeight - height) / 2;
        return new PetFrameViewport(
            scale,
            left,
            top,
            width,
            height,
            Math.Max(0, viewportWidth - left - width),
            Math.Max(0, viewportHeight - top - height));
    }
}
