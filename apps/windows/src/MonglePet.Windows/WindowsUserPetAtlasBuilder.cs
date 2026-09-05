using MonglePet.Packages;
using MonglePet.PetLibrary;
using Windows.Graphics.Imaging;
using Windows.Storage;
using Windows.Storage.Streams;

namespace MonglePet.Windows;

internal sealed class WindowsUserPetAtlasBuilder : IUserPetAtlasBuilder
{
    public async Task<UserPetBuiltAtlas> BuildAsync(
        IReadOnlyList<UserPetFrameSourceRequest> frames,
        CancellationToken cancellationToken = default)
    {
        if (frames.Count == 0)
        {
            throw new UserPetEditingException(
                UserPetEditingError.EmptyAnimation,
                "애니메이션에는 프레임이 하나 이상 필요합니다.");
        }

        var decodedSources = new Dictionary<string, DecodedFrame>(
            StringComparer.OrdinalIgnoreCase);
        var decoded = new List<DecodedFrame>(frames.Count);
        foreach (UserPetFrameSourceRequest frame in frames)
        {
            cancellationToken.ThrowIfCancellationRequested();
            string path = Path.GetFullPath(frame.ImagePath);
            if (!decodedSources.TryGetValue(path, out DecodedFrame? source))
            {
                source = await DecodeAsync(path, cancellationToken);
                decodedSources.Add(path, source);
            }
            UserPetProcessedFrame processed = await Task.Run(() =>
                UserPetPixelProcessor.Process(
                    source.Pixels,
                    source.Width,
                    source.Height,
                    frame.SourceFrame,
                    frame.FlipsHorizontally,
                    frame.FlipsVertically,
                    frame.CanvasPlacement,
                    frame.BackgroundRemoval),
                cancellationToken);
            decoded.Add(new DecodedFrame(
                processed.Width,
                processed.Height,
                processed.BgraPixels));
        }

        BuiltAtlasPixels built = await Task.Run(
            () => BuildAtlasPixels(decoded, frames, cancellationToken),
            cancellationToken);
        byte[] atlasPng = await EncodePngAsync(
            built.Width,
            built.Height,
            built.Pixels);
        DecodedFrame preview = decoded[0];
        byte[] previewPng = await EncodePngAsync(preview.Width, preview.Height, preview.Pixels);
        return new UserPetBuiltAtlas(
            atlasPng,
            previewPng,
            built.Width,
            built.Height,
            built.Definitions);
    }

    private static BuiltAtlasPixels BuildAtlasPixels(
        IReadOnlyList<DecodedFrame> decoded,
        IReadOnlyList<UserPetFrameSourceRequest> frames,
        CancellationToken cancellationToken)
    {
        IReadOnlyList<AtlasPlacement> placements = Arrange(decoded);
        int atlasWidth = placements.Max(value => value.X + value.Frame.Width);
        int atlasHeight = placements.Max(value => value.Y + value.Frame.Height);
        if (atlasWidth is <= 0 or > PetPackageManifestReader.MaximumImageDimension ||
            atlasHeight is <= 0 or > PetPackageManifestReader.MaximumImageDimension ||
            (long)atlasWidth * atlasHeight > PetPackageLoader.MaximumDecodedPixels)
        {
            throw new UserPetEditingException(
                UserPetEditingError.FileOperationFailed,
                "프레임을 합친 이미지가 최대 8192×8192 크기를 넘습니다. 프레임 수나 이미지 크기를 줄여 주세요.");
        }

        var atlasPixels = new byte[checked(atlasWidth * atlasHeight * 4)];
        var definitions = new List<PetPackageFrame>(decoded.Count);
        foreach ((AtlasPlacement placement, UserPetFrameSourceRequest request) in placements.Zip(frames))
        {
            cancellationToken.ThrowIfCancellationRequested();
            DecodedFrame image = placement.Frame;
            for (int row = 0; row < image.Height; row++)
            {
                System.Buffer.BlockCopy(
                    image.Pixels,
                    row * image.Width * 4,
                    atlasPixels,
                    ((((placement.Y + row) * atlasWidth) + placement.X) * 4),
                    image.Width * 4);
            }
            definitions.Add(new PetPackageFrame(
                placement.X,
                placement.Y,
                image.Width,
                image.Height,
                request.DurationMilliseconds));
        }
        return new BuiltAtlasPixels(atlasWidth, atlasHeight, atlasPixels, definitions);
    }

    private static IReadOnlyList<AtlasPlacement> Arrange(IReadOnlyList<DecodedFrame> frames)
    {
        var result = new List<AtlasPlacement>(frames.Count);
        int x = 0;
        int y = 0;
        int rowHeight = 0;
        foreach (DecodedFrame frame in frames)
        {
            if (frame.Width > PetPackageManifestReader.MaximumImageDimension ||
                frame.Height > PetPackageManifestReader.MaximumImageDimension)
            {
                throw new UserPetEditingException(
                    UserPetEditingError.FileOperationFailed,
                    "프레임 한 장의 크기가 최대 8192×8192를 넘습니다.");
            }
            if (x > 0 && x + frame.Width > PetPackageManifestReader.MaximumImageDimension)
            {
                x = 0;
                y += rowHeight;
                rowHeight = 0;
            }
            if (y + frame.Height > PetPackageManifestReader.MaximumImageDimension)
            {
                throw new UserPetEditingException(
                    UserPetEditingError.FileOperationFailed,
                    "프레임을 배치한 atlas가 최대 8192×8192 크기를 넘습니다. 프레임 수나 이미지 크기를 줄여 주세요.");
            }
            result.Add(new AtlasPlacement(frame, x, y));
            x += frame.Width;
            rowHeight = Math.Max(rowHeight, frame.Height);
        }
        return result;
    }

    private static async Task<DecodedFrame> DecodeAsync(
        string imagePath,
        CancellationToken cancellationToken)
    {
        StorageFile file = await StorageFile.GetFileFromPathAsync(imagePath);
        using IRandomAccessStream stream = await file.OpenAsync(FileAccessMode.Read);
        BitmapDecoder decoder = await BitmapDecoder.CreateAsync(stream);
        cancellationToken.ThrowIfCancellationRequested();
        using SoftwareBitmap bitmap = await decoder.GetSoftwareBitmapAsync(
            BitmapPixelFormat.Bgra8,
            BitmapAlphaMode.Premultiplied,
            new BitmapTransform(),
            ExifOrientationMode.IgnoreExifOrientation,
            ColorManagementMode.DoNotColorManage);
        int width = bitmap.PixelWidth;
        int height = bitmap.PixelHeight;
        int byteCount = checked(width * height * 4);
        var buffer = new global::Windows.Storage.Streams.Buffer((uint)byteCount);
        bitmap.CopyToBuffer(buffer);
        var pixels = new byte[byteCount];
        using DataReader reader = DataReader.FromBuffer(buffer);
        reader.ReadBytes(pixels);
        return new DecodedFrame(width, height, pixels);
    }

    private static async Task<byte[]> EncodePngAsync(int width, int height, byte[] pixels)
    {
        using var stream = new InMemoryRandomAccessStream();
        BitmapEncoder encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, stream);
        encoder.SetPixelData(
            BitmapPixelFormat.Bgra8,
            BitmapAlphaMode.Premultiplied,
            (uint)width,
            (uint)height,
            96,
            96,
            pixels);
        await encoder.FlushAsync();
        stream.Seek(0);
        if (stream.Size > uint.MaxValue)
        {
            throw new UserPetEditingException(
                UserPetEditingError.FileOperationFailed,
                "생성된 PNG 파일이 너무 큽니다.");
        }
        using var reader = new DataReader(stream.GetInputStreamAt(0));
        await reader.LoadAsync((uint)stream.Size);
        var bytes = new byte[(int)stream.Size];
        reader.ReadBytes(bytes);
        return bytes;
    }

    private sealed record DecodedFrame(int Width, int Height, byte[] Pixels);
    private sealed record AtlasPlacement(DecodedFrame Frame, int X, int Y);
    private sealed record BuiltAtlasPixels(
        int Width,
        int Height,
        byte[] Pixels,
        IReadOnlyList<PetPackageFrame> Definitions);
}
