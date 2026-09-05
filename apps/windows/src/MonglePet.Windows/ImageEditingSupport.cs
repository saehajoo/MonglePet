using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using MonglePet.PetLibrary;
using Windows.Graphics.Imaging;
using Windows.Storage;
using Windows.Storage.Streams;

namespace MonglePet.Windows;

internal sealed record WindowsDecodedImage(
    string Path,
    int Width,
    int Height,
    byte[] BgraPixels);

internal sealed class WindowsDecodedImageCache
{
    private readonly Dictionary<string, Task<WindowsDecodedImage>> _images =
        new(StringComparer.OrdinalIgnoreCase);

    public Task<WindowsDecodedImage> GetAsync(string path)
    {
        string fullPath = System.IO.Path.GetFullPath(path);
        if (!_images.TryGetValue(fullPath, out Task<WindowsDecodedImage>? image))
        {
            image = DecodeAsync(fullPath);
            _images.Add(fullPath, image);
        }
        return image;
    }

    private static async Task<WindowsDecodedImage> DecodeAsync(string path)
    {
        StorageFile file = await StorageFile.GetFileFromPathAsync(path);
        using IRandomAccessStream stream = await file.OpenAsync(FileAccessMode.Read);
        BitmapDecoder decoder = await BitmapDecoder.CreateAsync(stream);
        using SoftwareBitmap bitmap = await decoder.GetSoftwareBitmapAsync(
            BitmapPixelFormat.Bgra8,
            BitmapAlphaMode.Premultiplied,
            new BitmapTransform(),
            ExifOrientationMode.IgnoreExifOrientation,
            ColorManagementMode.DoNotColorManage);
        int byteCount = checked(bitmap.PixelWidth * bitmap.PixelHeight * 4);
        var buffer = new global::Windows.Storage.Streams.Buffer((uint)byteCount);
        bitmap.CopyToBuffer(buffer);
        var pixels = new byte[byteCount];
        using DataReader reader = DataReader.FromBuffer(buffer);
        reader.ReadBytes(pixels);
        return new WindowsDecodedImage(
            path,
            bitmap.PixelWidth,
            bitmap.PixelHeight,
            pixels);
    }
}

internal static class WindowsImagePreviewFactory
{
    public static UserPetProcessedFrame CenterOnCanvas(
        UserPetProcessedFrame frame,
        int canvasWidth,
        int canvasHeight)
    {
        if (canvasWidth < frame.Width || canvasHeight < frame.Height)
        {
            throw new ArgumentOutOfRangeException(
                nameof(canvasWidth),
                "공통 캔버스는 현재 프레임보다 작을 수 없습니다.");
        }

        var pixels = new byte[checked(canvasWidth * canvasHeight * 4)];
        int offsetX = (canvasWidth - frame.Width) / 2;
        int offsetY = (canvasHeight - frame.Height) / 2;
        for (int row = 0; row < frame.Height; row++)
        {
            System.Buffer.BlockCopy(
                frame.BgraPixels,
                row * frame.Width * 4,
                pixels,
                ((((offsetY + row) * canvasWidth) + offsetX) * 4),
                frame.Width * 4);
        }
        return new UserPetProcessedFrame(canvasWidth, canvasHeight, pixels);
    }

    public static Task<ImageSource> CreateTransparentAsync(
        UserPetProcessedFrame frame) => CreateSourceAsync(
            frame.BgraPixels,
            frame.Width,
            frame.Height);

    public static async Task<ImageSource> CreateCheckerboardAsync(
        UserPetProcessedFrame frame,
        int checkerSize = 10)
    {
        byte[] pixels = CompositeCheckerboard(
            frame.BgraPixels,
            frame.Width,
            frame.Height,
            checkerSize);
        return await CreateSourceAsync(pixels, frame.Width, frame.Height);
    }

    private static async Task<ImageSource> CreateSourceAsync(
        byte[] pixels,
        int width,
        int height)
    {
        var source = new WriteableBitmap(width, height);
        using Stream stream = source.PixelBuffer.AsStream();
        await stream.WriteAsync(pixels);
        source.Invalidate();
        return source;
    }

    public static UserPetProcessedFrame FullImage(WindowsDecodedImage image) =>
        new(image.Width, image.Height, image.BgraPixels);

    private static byte[] CompositeCheckerboard(
        byte[] source,
        int width,
        int height,
        int checkerSize)
    {
        bool usesDarkBackground = Microsoft.UI.Xaml.Application.Current.RequestedTheme ==
            Microsoft.UI.Xaml.ApplicationTheme.Dark;
        byte lighter = usesDarkBackground ? (byte)54 : (byte)240;
        byte darker = usesDarkBackground ? (byte)46 : (byte)230;
        var result = new byte[source.Length];
        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                int offset = ((y * width) + x) * 4;
                byte background = ((x / checkerSize) + (y / checkerSize)) % 2 == 0
                    ? lighter
                    : darker;
                int inverseAlpha = 255 - source[offset + 3];
                result[offset + 0] = (byte)Math.Min(255, source[offset + 0] + ((background * inverseAlpha + 127) / 255));
                result[offset + 1] = (byte)Math.Min(255, source[offset + 1] + ((background * inverseAlpha + 127) / 255));
                result[offset + 2] = (byte)Math.Min(255, source[offset + 2] + ((background * inverseAlpha + 127) / 255));
                result[offset + 3] = 255;
            }
        }
        return result;
    }
}
