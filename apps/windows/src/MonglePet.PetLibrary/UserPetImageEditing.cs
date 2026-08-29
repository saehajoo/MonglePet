using MonglePet.Packages;

namespace MonglePet.PetLibrary;

public enum UserPetCropHandle
{
    Move,
    TopLeft,
    Top,
    TopRight,
    Right,
    BottomRight,
    Bottom,
    BottomLeft,
    Left,
}

public readonly record struct UserPetPixelRect(int X, int Y, int Width, int Height)
{
    public int Right => checked(X + Width);

    public int Bottom => checked(Y + Height);
}

public sealed record UserPetCanvasPlacement(
    int CanvasWidth,
    int CanvasHeight,
    int X,
    int Y,
    int Width,
    int Height);

public sealed record UserPetBackgroundRemoval(
    byte Red,
    byte Green,
    byte Blue,
    byte Tolerance);

public sealed record UserPetProcessedFrame(
    int Width,
    int Height,
    byte[] BgraPixels);

public sealed record UserPetVisibleFrameGeometry(
    int Width,
    int Height,
    UserPetPixelRect VisibleBounds);

public static class UserPetImageEditingGeometry
{
    public const double MinimumZoom = 1;
    public const double MaximumZoom = 8;

    public static double ClampZoom(double zoom) =>
        double.IsFinite(zoom)
            ? Math.Clamp(zoom, MinimumZoom, MaximumZoom)
            : MinimumZoom;

    public static bool CanPan(double zoom) => ClampZoom(zoom) > MinimumZoom;

    public static UserPetPixelRect ClampCrop(
        UserPetPixelRect crop,
        int imageWidth,
        int imageHeight)
    {
        ValidateImageSize(imageWidth, imageHeight);
        int width = Math.Clamp(crop.Width, 1, imageWidth);
        int height = Math.Clamp(crop.Height, 1, imageHeight);
        int x = Math.Clamp(crop.X, 0, imageWidth - width);
        int y = Math.Clamp(crop.Y, 0, imageHeight - height);
        return new UserPetPixelRect(x, y, width, height);
    }

    public static UserPetPixelRect DragCrop(
        UserPetPixelRect original,
        UserPetCropHandle handle,
        int deltaX,
        int deltaY,
        int imageWidth,
        int imageHeight)
    {
        UserPetPixelRect crop = ClampCrop(original, imageWidth, imageHeight);
        if (handle == UserPetCropHandle.Move)
        {
            return ClampCrop(
                crop with { X = crop.X + deltaX, Y = crop.Y + deltaY },
                imageWidth,
                imageHeight);
        }

        int left = crop.X;
        int top = crop.Y;
        int right = crop.Right;
        int bottom = crop.Bottom;
        if (handle is UserPetCropHandle.TopLeft or UserPetCropHandle.Left or UserPetCropHandle.BottomLeft)
        {
            left = Math.Clamp(left + deltaX, 0, right - 1);
        }
        if (handle is UserPetCropHandle.TopLeft or UserPetCropHandle.Top or UserPetCropHandle.TopRight)
        {
            top = Math.Clamp(top + deltaY, 0, bottom - 1);
        }
        if (handle is UserPetCropHandle.TopRight or UserPetCropHandle.Right or UserPetCropHandle.BottomRight)
        {
            right = Math.Clamp(right + deltaX, left + 1, imageWidth);
        }
        if (handle is UserPetCropHandle.BottomLeft or UserPetCropHandle.Bottom or UserPetCropHandle.BottomRight)
        {
            bottom = Math.Clamp(bottom + deltaY, top + 1, imageHeight);
        }
        return new UserPetPixelRect(left, top, right - left, bottom - top);
    }

    public static UserPetPixelRect? FindVisibleBounds(
        ReadOnlySpan<byte> bgraPixels,
        int width,
        int height,
        byte minimumAlpha = 1)
    {
        ValidatePixels(bgraPixels, width, height);
        int left = width;
        int top = height;
        int right = -1;
        int bottom = -1;
        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                if (bgraPixels[((y * width + x) * 4) + 3] < minimumAlpha)
                {
                    continue;
                }
                left = Math.Min(left, x);
                top = Math.Min(top, y);
                right = Math.Max(right, x);
                bottom = Math.Max(bottom, y);
            }
        }
        return right < left || bottom < top
            ? null
            : new UserPetPixelRect(left, top, right - left + 1, bottom - top + 1);
    }

    internal static void ValidatePixels(ReadOnlySpan<byte> pixels, int width, int height)
    {
        ValidateImageSize(width, height);
        if (pixels.Length != checked(width * height * 4))
        {
            throw new ArgumentException("BGRA 픽셀 크기가 이미지 크기와 일치하지 않습니다.", nameof(pixels));
        }
    }

    private static void ValidateImageSize(int width, int height)
    {
        if (width <= 0 || height <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(width), "이미지 크기는 1px 이상이어야 합니다.");
        }
    }

    public static IReadOnlyList<UserPetCanvasPlacement> CreateCommonCanvasPlacements(
        IReadOnlyList<UserPetVisibleFrameGeometry> frames)
    {
        ArgumentNullException.ThrowIfNull(frames);
        if (frames.Count == 0)
        {
            return [];
        }
        foreach (UserPetVisibleFrameGeometry frame in frames)
        {
            ValidateImageSize(frame.Width, frame.Height);
            if (frame.Width > PetPackageManifestReader.MaximumImageDimension ||
                frame.Height > PetPackageManifestReader.MaximumImageDimension ||
                ClampCrop(frame.VisibleBounds, frame.Width, frame.Height) != frame.VisibleBounds)
            {
                throw new ArgumentOutOfRangeException(nameof(frames));
            }
        }

        int leftMargin = frames.Max(frame => frame.VisibleBounds.X);
        int topMargin = frames.Max(frame => frame.VisibleBounds.Y);
        int visibleWidth = frames.Max(frame => frame.VisibleBounds.Width);
        int visibleHeight = frames.Max(frame => frame.VisibleBounds.Height);
        int rightMargin = frames.Max(frame => frame.Width - frame.VisibleBounds.Right);
        int bottomMargin = frames.Max(frame => frame.Height - frame.VisibleBounds.Bottom);
        int canvasWidth = checked(leftMargin + visibleWidth + rightMargin);
        int canvasHeight = checked(topMargin + visibleHeight + bottomMargin);
        if (canvasWidth > PetPackageManifestReader.MaximumImageDimension ||
            canvasHeight > PetPackageManifestReader.MaximumImageDimension)
        {
            canvasWidth = frames.Max(frame => frame.Width);
            canvasHeight = frames.Max(frame => frame.Height);
            return frames.Select(frame => new UserPetCanvasPlacement(
                canvasWidth,
                canvasHeight,
                (canvasWidth - frame.Width) / 2,
                (canvasHeight - frame.Height) / 2,
                frame.Width,
                frame.Height)).ToArray();
        }
        return frames.Select(frame => new UserPetCanvasPlacement(
            canvasWidth,
            canvasHeight,
            leftMargin + ((visibleWidth - frame.VisibleBounds.Width) / 2) - frame.VisibleBounds.X,
            topMargin + ((visibleHeight - frame.VisibleBounds.Height) / 2) - frame.VisibleBounds.Y,
            frame.Width,
            frame.Height)).ToArray();
    }
}

public static class UserPetPixelProcessor
{
    public static UserPetProcessedFrame Process(
        ReadOnlySpan<byte> sourceBgraPixels,
        int sourceWidth,
        int sourceHeight,
        PetPackageFrame? sourceCrop = null,
        bool flipsHorizontally = false,
        bool flipsVertically = false,
        UserPetCanvasPlacement? placement = null,
        UserPetBackgroundRemoval? backgroundRemoval = null)
    {
        UserPetImageEditingGeometry.ValidatePixels(
            sourceBgraPixels,
            sourceWidth,
            sourceHeight);
        UserPetPixelRect crop = sourceCrop is null
            ? new UserPetPixelRect(0, 0, sourceWidth, sourceHeight)
            : new UserPetPixelRect(
                sourceCrop.X,
                sourceCrop.Y,
                sourceCrop.Width,
                sourceCrop.Height);
        if (UserPetImageEditingGeometry.ClampCrop(crop, sourceWidth, sourceHeight) != crop)
        {
            throw new ArgumentOutOfRangeException(nameof(sourceCrop), "crop 영역이 원본 이미지를 벗어났습니다.");
        }

        int canvasWidth = placement?.CanvasWidth ?? crop.Width;
        int canvasHeight = placement?.CanvasHeight ?? crop.Height;
        int targetX = placement?.X ?? 0;
        int targetY = placement?.Y ?? 0;
        int targetWidth = placement?.Width ?? crop.Width;
        int targetHeight = placement?.Height ?? crop.Height;
        ValidatePlacement(canvasWidth, canvasHeight, targetX, targetY, targetWidth, targetHeight);

        var result = new byte[checked(canvasWidth * canvasHeight * 4)];
        int destinationLeft = (int)Math.Max(0L, targetX);
        int destinationTop = (int)Math.Max(0L, targetY);
        int destinationRight = (int)Math.Min((long)canvasWidth, (long)targetX + targetWidth);
        int destinationBottom = (int)Math.Min((long)canvasHeight, (long)targetY + targetHeight);
        for (int destinationY = destinationTop; destinationY < destinationBottom; destinationY++)
        {
            int targetLocalY = destinationY - targetY;
            int sampledY = Math.Min(
                crop.Height - 1,
                (int)((long)targetLocalY * crop.Height / targetHeight));
            if (flipsVertically)
            {
                sampledY = crop.Height - 1 - sampledY;
            }
            for (int destinationX = destinationLeft; destinationX < destinationRight; destinationX++)
            {
                int targetLocalX = destinationX - targetX;
                int sampledX = Math.Min(
                    crop.Width - 1,
                    (int)((long)targetLocalX * crop.Width / targetWidth));
                if (flipsHorizontally)
                {
                    sampledX = crop.Width - 1 - sampledX;
                }
                int sourceOffset = (((crop.Y + sampledY) * sourceWidth) + crop.X + sampledX) * 4;
                int targetOffset = (((destinationY * canvasWidth) + destinationX) * 4);
                ReadOnlySpan<byte> pixel = sourceBgraPixels.Slice(sourceOffset, 4);
                if (backgroundRemoval is not null && IsBackground(pixel, backgroundRemoval))
                {
                    result.AsSpan(targetOffset, 4).Clear();
                }
                else
                {
                    pixel.CopyTo(result.AsSpan(targetOffset, 4));
                }
            }
        }
        return new UserPetProcessedFrame(canvasWidth, canvasHeight, result);
    }

    private static bool IsBackground(
        ReadOnlySpan<byte> premultipliedBgra,
        UserPetBackgroundRemoval removal)
    {
        byte alpha = premultipliedBgra[3];
        if (alpha == 0)
        {
            return true;
        }
        int blue = Math.Min(255, ((premultipliedBgra[0] * 255) + (alpha / 2)) / alpha);
        int green = Math.Min(255, ((premultipliedBgra[1] * 255) + (alpha / 2)) / alpha);
        int red = Math.Min(255, ((premultipliedBgra[2] * 255) + (alpha / 2)) / alpha);
        return Math.Abs(red - removal.Red) <= removal.Tolerance &&
            Math.Abs(green - removal.Green) <= removal.Tolerance &&
            Math.Abs(blue - removal.Blue) <= removal.Tolerance;
    }

    private static void ValidatePlacement(
        int canvasWidth,
        int canvasHeight,
        int x,
        int y,
        int width,
        int height)
    {
        const int maximumPlacementDimension = PetPackageManifestReader.MaximumImageDimension * 4;
        if (canvasWidth <= 0 || canvasHeight <= 0 ||
            canvasWidth > PetPackageManifestReader.MaximumImageDimension ||
            canvasHeight > PetPackageManifestReader.MaximumImageDimension ||
            width <= 0 || height <= 0 ||
            width > maximumPlacementDimension || height > maximumPlacementDimension ||
            x < -maximumPlacementDimension || x > maximumPlacementDimension ||
            y < -maximumPlacementDimension || y > maximumPlacementDimension)
        {
            throw new ArgumentOutOfRangeException(nameof(width), "공통 캔버스 배치 값이 허용 범위를 벗어났습니다.");
        }
    }
}

public enum UserPetSpriteOrderingMode
{
    ReadingOrder,
    ClickOrder,
}

public static class UserPetSpriteSheetGeometry
{
    public static IReadOnlyList<UserPetPixelRect> CreateUniformGrid(
        int imageWidth,
        int imageHeight,
        int rows,
        int columns)
    {
        if (imageWidth <= 0 || imageHeight <= 0 ||
            rows is < 1 or > 32 || columns is < 1 or > 32 ||
            rows > imageHeight || columns > imageWidth)
        {
            throw new ArgumentOutOfRangeException(nameof(rows));
        }
        var result = new List<UserPetPixelRect>(checked(rows * columns));
        for (int row = 0; row < rows; row++)
        {
            int top = row * imageHeight / rows;
            int bottom = (row + 1) * imageHeight / rows;
            for (int column = 0; column < columns; column++)
            {
                int left = column * imageWidth / columns;
                int right = (column + 1) * imageWidth / columns;
                result.Add(new UserPetPixelRect(left, top, right - left, bottom - top));
            }
        }
        return result;
    }

    public static IReadOnlyList<T> ReadingOrder<T>(
        IEnumerable<T> values,
        Func<T, UserPetPixelRect> rectangle) => values
        .OrderBy(value => rectangle(value).Y)
        .ThenBy(value => rectangle(value).X)
        .ThenBy(value => rectangle(value).Height)
        .ThenBy(value => rectangle(value).Width)
        .ToArray();

    public static IReadOnlyList<Guid> ToggleClickOrder(
        IReadOnlyList<Guid> selectedIds,
        Guid id)
    {
        if (id == Guid.Empty)
        {
            throw new ArgumentException("프레임 ID가 비어 있습니다.", nameof(id));
        }
        return selectedIds.Contains(id)
            ? selectedIds.Where(value => value != id).ToArray()
            : [.. selectedIds, id];
    }

    public static (int Rows, int Columns) InferGridCounts(
        IEnumerable<UserPetPixelRect> rectangles)
    {
        UserPetPixelRect[] values = rectangles.ToArray();
        if (values.Length == 0)
        {
            return (1, 1);
        }
        int rows = values.Select(value => value.Y).Distinct().Count();
        int columns = values.Select(value => value.X).Distinct().Count();
        return (Math.Clamp(rows, 1, 32), Math.Clamp(columns, 1, 32));
    }

    public static double SuggestedCanvasHeight(
        int imageWidth,
        int imageHeight,
        double availableWidth,
        double availableHeight,
        double minimumHeight)
    {
        if (imageWidth <= 0 || imageHeight <= 0 ||
            availableWidth <= 0 || availableHeight <= 0 || minimumHeight <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(imageWidth));
        }
        double aspectHeight = availableWidth * imageHeight / imageWidth;
        return Math.Min(availableHeight, Math.Max(minimumHeight, aspectHeight));
    }
}

public sealed record UserPetSpriteBoundarySuggestion(
    IReadOnlyList<UserPetPixelRect> Frames,
    UserPetBackgroundRemoval? InferredBackground);

public static class UserPetSpriteBoundaryAnalyzer
{
    public static UserPetSpriteBoundarySuggestion Analyze(
        ReadOnlySpan<byte> bgraPixels,
        int width,
        int height,
        byte opaqueBackgroundTolerance = 12)
    {
        UserPetImageEditingGeometry.ValidatePixels(bgraPixels, width, height);
        bool hasAlphaPixel = false;
        for (int offset = 3; offset < bgraPixels.Length; offset += 4)
        {
            if (bgraPixels[offset] < 255)
            {
                hasAlphaPixel = true;
                break;
            }
        }

        UserPetBackgroundRemoval? background = hasAlphaPixel
            ? null
            : InferCornerBackground(bgraPixels, width, height, opaqueBackgroundTolerance);
        var occupiedColumns = new bool[width];
        var occupiedRows = new bool[height];
        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                int offset = ((y * width) + x) * 4;
                ReadOnlySpan<byte> pixel = bgraPixels.Slice(offset, 4);
                bool foreground = background is null
                    ? pixel[3] != 0
                    : !MatchesOpaqueBackground(pixel, background);
                if (foreground)
                {
                    occupiedColumns[x] = true;
                    occupiedRows[y] = true;
                }
            }
        }

        IReadOnlyList<(int Start, int Length)> columns = Runs(occupiedColumns);
        IReadOnlyList<(int Start, int Length)> rows = Runs(occupiedRows);
        if (columns.Count is 0 or > 32 || rows.Count is 0 or > 32)
        {
            return new UserPetSpriteBoundarySuggestion(
                [new UserPetPixelRect(0, 0, width, height)],
                background);
        }
        var frames = new List<UserPetPixelRect>();
        foreach ((int top, int frameHeight) in rows)
        {
            foreach ((int left, int frameWidth) in columns)
            {
                if (ContainsForeground(
                    bgraPixels,
                    width,
                    left,
                    top,
                    frameWidth,
                    frameHeight,
                    background))
                {
                    frames.Add(new UserPetPixelRect(left, top, frameWidth, frameHeight));
                }
            }
        }
        if (frames.Count == 0)
        {
            frames.Add(new UserPetPixelRect(0, 0, width, height));
        }
        return new UserPetSpriteBoundarySuggestion(frames, background);
    }

    private static UserPetBackgroundRemoval InferCornerBackground(
        ReadOnlySpan<byte> pixels,
        int width,
        int height,
        byte tolerance)
    {
        int[] offsets =
        [
            0,
            (width - 1) * 4,
            ((height - 1) * width) * 4,
            (((height * width) - 1) * 4),
        ];
        int bestOffset = offsets[0];
        int bestDistance = int.MaxValue;
        foreach (int candidate in offsets)
        {
            int distance = 0;
            foreach (int other in offsets)
            {
                distance += ColorDistance(pixels, candidate, other);
            }
            if (distance < bestDistance)
            {
                bestDistance = distance;
                bestOffset = candidate;
            }
        }
        return new UserPetBackgroundRemoval(
            pixels[bestOffset + 2],
            pixels[bestOffset + 1],
            pixels[bestOffset + 0],
            tolerance);
    }

    private static int ColorDistance(ReadOnlySpan<byte> pixels, int left, int right) =>
        Math.Abs(pixels[left + 0] - pixels[right + 0]) +
        Math.Abs(pixels[left + 1] - pixels[right + 1]) +
        Math.Abs(pixels[left + 2] - pixels[right + 2]);

    private static bool MatchesOpaqueBackground(
        ReadOnlySpan<byte> premultipliedBgra,
        UserPetBackgroundRemoval background) =>
        premultipliedBgra[3] != 0 &&
        Math.Abs(premultipliedBgra[2] - background.Red) <= background.Tolerance &&
        Math.Abs(premultipliedBgra[1] - background.Green) <= background.Tolerance &&
        Math.Abs(premultipliedBgra[0] - background.Blue) <= background.Tolerance;

    private static IReadOnlyList<(int Start, int Length)> Runs(bool[] occupied)
    {
        var result = new List<(int Start, int Length)>();
        int index = 0;
        while (index < occupied.Length)
        {
            while (index < occupied.Length && !occupied[index]) index++;
            int start = index;
            while (index < occupied.Length && occupied[index]) index++;
            if (index > start) result.Add((start, index - start));
        }
        return result;
    }

    private static bool ContainsForeground(
        ReadOnlySpan<byte> pixels,
        int imageWidth,
        int left,
        int top,
        int width,
        int height,
        UserPetBackgroundRemoval? background)
    {
        for (int y = top; y < top + height; y++)
        {
            for (int x = left; x < left + width; x++)
            {
                ReadOnlySpan<byte> pixel = pixels.Slice(((y * imageWidth) + x) * 4, 4);
                if (background is null ? pixel[3] != 0 : !MatchesOpaqueBackground(pixel, background))
                {
                    return true;
                }
            }
        }
        return false;
    }
}
