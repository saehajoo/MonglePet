namespace MonglePet.Core.Movement;

public sealed class PetFrameAlphaMask
{
    public const int DefaultMaximumDimension = 64;

    private readonly byte[] _alphaValues;

    public PetFrameAlphaMask(int width, int height, IEnumerable<byte> alphaValues)
    {
        ArgumentNullException.ThrowIfNull(alphaValues);
        if (width <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(width));
        }
        if (height <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(height));
        }

        _alphaValues = alphaValues.ToArray();
        if (_alphaValues.Length != checked(width * height))
        {
            throw new ArgumentException(
                "Alpha value count must match width × height.",
                nameof(alphaValues));
        }

        Width = width;
        Height = height;
    }

    public int Width { get; }

    public int Height { get; }

    public bool ContainsVisiblePixel(double normalizedX, double normalizedY)
    {
        if (!double.IsFinite(normalizedX) || !double.IsFinite(normalizedY) ||
            normalizedX < 0 || normalizedX > 1 ||
            normalizedY < 0 || normalizedY > 1)
        {
            return false;
        }

        int x = Math.Min((int)(normalizedX * Width), Width - 1);
        int y = Math.Min((int)(normalizedY * Height), Height - 1);
        return _alphaValues[(y * Width) + x] > 0;
    }

    public static MovementPoint? NormalizedContentPoint(
        double pointX,
        double pointY,
        double boundsWidth,
        double boundsHeight,
        double contentWidth,
        double contentHeight)
    {
        if (!double.IsFinite(pointX) || !double.IsFinite(pointY) ||
            !double.IsFinite(boundsWidth) || !double.IsFinite(boundsHeight) ||
            !double.IsFinite(contentWidth) || !double.IsFinite(contentHeight) ||
            boundsWidth <= 0 || boundsHeight <= 0 ||
            contentWidth <= 0 || contentHeight <= 0)
        {
            return null;
        }

        double scale = Math.Min(
            boundsWidth / contentWidth,
            boundsHeight / contentHeight);
        double displayedWidth = contentWidth * scale;
        double displayedHeight = contentHeight * scale;
        double minimumX = (boundsWidth - displayedWidth) / 2;
        double minimumY = (boundsHeight - displayedHeight) / 2;
        if (pointX < minimumX || pointX > minimumX + displayedWidth ||
            pointY < minimumY || pointY > minimumY + displayedHeight)
        {
            return null;
        }

        return new MovementPoint(
            (pointX - minimumX) / displayedWidth,
            (pointY - minimumY) / displayedHeight);
    }

    public static PetFrameAlphaMask FromRgba8(
        int width,
        int height,
        ReadOnlySpan<byte> pixels)
    {
        int pixelCount = checked(width * height);
        if (pixels.Length != checked(pixelCount * 4))
        {
            throw new ArgumentException(
                "RGBA byte count must match width × height × 4.",
                nameof(pixels));
        }

        var alpha = new byte[pixelCount];
        for (int index = 0; index < pixelCount; index++)
        {
            alpha[index] = pixels[(index * 4) + 3];
        }
        return new PetFrameAlphaMask(width, height, alpha);
    }

    public static PetFrameAlphaDecodeRegion DecodeRegion(
        int atlasWidth,
        int atlasHeight,
        int frameX,
        int frameY,
        int frameWidth,
        int frameHeight,
        int maximumDimension = DefaultMaximumDimension)
    {
        if (atlasWidth <= 0 || atlasHeight <= 0 ||
            frameX < 0 || frameY < 0 ||
            frameWidth <= 0 || frameHeight <= 0 ||
            maximumDimension <= 0 ||
            frameX > atlasWidth - frameWidth ||
            frameY > atlasHeight - frameHeight)
        {
            throw new ArgumentOutOfRangeException(nameof(frameWidth));
        }

        double scale = Math.Min(
            1,
            maximumDimension / (double)Math.Max(frameWidth, frameHeight));
        int scaledAtlasWidth = Math.Max(1, (int)Math.Round(atlasWidth * scale));
        int scaledAtlasHeight = Math.Max(1, (int)Math.Round(atlasHeight * scale));
        int cropX = Math.Clamp(
            (int)Math.Round(frameX * scale),
            0,
            scaledAtlasWidth - 1);
        int cropY = Math.Clamp(
            (int)Math.Round(frameY * scale),
            0,
            scaledAtlasHeight - 1);
        int cropRight = Math.Clamp(
            (int)Math.Round((frameX + frameWidth) * scale),
            cropX + 1,
            scaledAtlasWidth);
        int cropBottom = Math.Clamp(
            (int)Math.Round((frameY + frameHeight) * scale),
            cropY + 1,
            scaledAtlasHeight);
        return new PetFrameAlphaDecodeRegion(
            scaledAtlasWidth,
            scaledAtlasHeight,
            cropX,
            cropY,
            cropRight - cropX,
            cropBottom - cropY);
    }
}

public sealed record PetFrameAlphaDecodeRegion(
    int ScaledAtlasWidth,
    int ScaledAtlasHeight,
    int CropX,
    int CropY,
    int CropWidth,
    int CropHeight);
