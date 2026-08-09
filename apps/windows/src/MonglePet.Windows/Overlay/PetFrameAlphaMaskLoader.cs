using MonglePet.Core.Movement;
using MonglePet.Packages;
using Windows.Graphics.Imaging;
using Windows.Storage;
using Windows.Storage.Streams;

namespace MonglePet.Windows.Overlay;

internal sealed class PetFrameAlphaMaskLoader : IDisposable
{
    private readonly LoadedPetPackage _package;
    private readonly Dictionary<FrameKey, PetFrameAlphaMask> _cache = [];
    private readonly HashSet<FrameKey> _pending = [];
    private readonly HashSet<FrameKey> _failed = [];
    private readonly Queue<FrameKey> _queue = [];
    private bool _isProcessing;
    private bool _disposed;

    public PetFrameAlphaMaskLoader(LoadedPetPackage package)
    {
        ArgumentNullException.ThrowIfNull(package);
        _package = package;
    }

    public event EventHandler? StateChanged;

    public string Status { get; private set; } = "알파 마스크 대기";

    public bool TryGet(
        string atlasId,
        PetPackageFrame frame,
        out PetFrameAlphaMask? mask)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        var key = new FrameKey(
            atlasId,
            frame.X,
            frame.Y,
            frame.Width,
            frame.Height);
        if (_cache.TryGetValue(key, out mask))
        {
            return true;
        }
        if (!_pending.Contains(key) && !_failed.Contains(key))
        {
            Enqueue(key);
        }
        mask = null;
        return false;
    }

    public void Preload(string atlasId, IEnumerable<PetPackageFrame> frames)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        ArgumentException.ThrowIfNullOrWhiteSpace(atlasId);
        ArgumentNullException.ThrowIfNull(frames);
        foreach (PetPackageFrame frame in frames)
        {
            var key = new FrameKey(
                atlasId,
                frame.X,
                frame.Y,
                frame.Width,
                frame.Height);
            if (!_cache.ContainsKey(key) && !_pending.Contains(key) &&
                !_failed.Contains(key))
            {
                Enqueue(key);
            }
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }
        _disposed = true;
        _cache.Clear();
        _pending.Clear();
        _failed.Clear();
        _queue.Clear();
        StateChanged = null;
        GC.SuppressFinalize(this);
    }

    private void Enqueue(FrameKey key)
    {
        _pending.Add(key);
        _queue.Enqueue(key);
        if (!_isProcessing)
        {
            Status = "알파 마스크 디코딩 중";
            StateChanged?.Invoke(this, EventArgs.Empty);
            _ = ProcessQueueAsync();
        }
    }

    private async Task ProcessQueueAsync()
    {
        _isProcessing = true;
        try
        {
            while (!_disposed && _queue.TryDequeue(out FrameKey? key))
            {
                await LoadAsync(key);
            }
        }
        finally
        {
            _isProcessing = false;
        }
    }

    private async Task LoadAsync(FrameKey key)
    {
        try
        {
            LoadedPetAtlas atlas = _package.Atlases[key.AtlasId];
            PetFrameAlphaDecodeRegion region = PetFrameAlphaMask.DecodeRegion(
                atlas.Definition.PixelWidth,
                atlas.Definition.PixelHeight,
                key.X,
                key.Y,
                key.Width,
                key.Height);
            StorageFile file = await StorageFile.GetFileFromPathAsync(atlas.FilePath);
            using IRandomAccessStream stream = await file.OpenAsync(FileAccessMode.Read);
            BitmapDecoder decoder = await BitmapDecoder.CreateAsync(stream);
            var transform = new BitmapTransform
            {
                ScaledWidth = checked((uint)region.ScaledAtlasWidth),
                ScaledHeight = checked((uint)region.ScaledAtlasHeight),
                Bounds = new BitmapBounds
                {
                    X = checked((uint)region.CropX),
                    Y = checked((uint)region.CropY),
                    Width = checked((uint)region.CropWidth),
                    Height = checked((uint)region.CropHeight),
                },
                InterpolationMode = BitmapInterpolationMode.Fant,
            };
            PixelDataProvider provider = await decoder.GetPixelDataAsync(
                BitmapPixelFormat.Rgba8,
                BitmapAlphaMode.Straight,
                transform,
                ExifOrientationMode.IgnoreExifOrientation,
                ColorManagementMode.DoNotColorManage);
            PetFrameAlphaMask mask = PetFrameAlphaMask.FromRgba8(
                region.CropWidth,
                region.CropHeight,
                provider.DetachPixelData());
            if (!_disposed)
            {
                _cache[key] = mask;
                if (!Status.StartsWith("알파 마스크 준비", StringComparison.Ordinal))
                {
                    Status = $"알파 마스크 준비 {region.CropWidth}×{region.CropHeight}";
                    StateChanged?.Invoke(this, EventArgs.Empty);
                }
            }
        }
        catch (Exception exception)
        {
            if (!_disposed)
            {
                _failed.Add(key);
                if (!Status.StartsWith("알파 마스크 실패", StringComparison.Ordinal))
                {
                    Status = $"알파 마스크 실패: {exception.Message}";
                    StateChanged?.Invoke(this, EventArgs.Empty);
                }
            }
        }
        finally
        {
            if (!_disposed)
            {
                _pending.Remove(key);
            }
        }
    }

    private sealed record FrameKey(
        string AtlasId,
        int X,
        int Y,
        int Width,
        int Height);
}
