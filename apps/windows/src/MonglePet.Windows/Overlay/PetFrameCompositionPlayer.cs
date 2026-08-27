using System.Diagnostics;
using System.Numerics;
using Microsoft.UI.Composition;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml.Media;
using MonglePet.Core.Behavior;
using MonglePet.Core.Movement;
using MonglePet.Packages;

namespace MonglePet.Windows.Overlay;

internal sealed class PetFrameCompositionPlayer : IDisposable
{
    private readonly LoadedPetPackage _package;
    private readonly SpriteVisual _visual;
    private readonly CompositionSurfaceBrush _brush;
    private readonly DispatcherQueueTimer _timer;
    private readonly PetFrameAlphaMaskLoader _alphaMaskLoader;
    private PetPackageMotion _motion;
    private PetFramePlaybackState _state;
    private PetImageSurfaceLease? _surface;
    private PetImageSurfaceLease? _displayedSurface;
    private string? _loadedAtlasId;
    private bool _disposed;
    private bool _requestedSurfaceLoadCompleted;
    private bool _isPaused;
    private bool _alphaMaskObservationEnabled;
    private long _playbackStartedAtTimestamp;
    private TimeSpan _playbackOffset;

    public PetFrameCompositionPlayer(
        Compositor compositor,
        LoadedPetPackage package,
        Vector2 visualSize,
        Vector3 visualOffset)
    {
        _package = package;
        _motion = package.DefaultMotion;
        _state = new PetFramePlaybackState(_motion, loops: true);
        _alphaMaskLoader = new PetFrameAlphaMaskLoader(package);
        _alphaMaskLoader.StateChanged += AlphaMaskLoader_StateChanged;
        _visual = compositor.CreateSpriteVisual();
        _visual.Size = visualSize;
        _visual.Offset = visualOffset;

        _brush = compositor.CreateSurfaceBrush();
        _brush.Stretch = CompositionStretch.None;
        _brush.HorizontalAlignmentRatio = 0;
        _brush.VerticalAlignmentRatio = 0;
        _brush.SnapToPixels = true;

        _timer = DispatcherQueue.GetForCurrentThread().CreateTimer();
        _timer.IsRepeating = false;
        _timer.Tick += Timer_Tick;
        LoadAtlasForCurrentMotion();
    }

    public event EventHandler? StateChanged;

    public SpriteVisual Visual => _visual;

    public string Status { get; private set; } = "이미지 디코딩 중";

    public string MotionId => _motion.Id;

    public int CurrentFrameIndex => _state.CurrentFrameIndex;

    public int FrameCount => _motion.Frames.Count;

    public bool IsPlaying => !_isPaused && _state.IsPlaying && Status == "재생 중";

    public bool IsReady => _requestedSurfaceLoadCompleted;

    public string AlphaMaskStatus => _alphaMaskLoader.Status;

    public bool ContainsVisibleContent(double pointX, double pointY)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        PetPackageFrame frame = _state.CurrentFrame;
        MovementPoint? normalized = PetFrameAlphaMask.NormalizedContentPoint(
            pointX,
            pointY,
            _visual.Size.X,
            _visual.Size.Y,
            frame.Width,
            frame.Height);
        if (normalized is not { } point ||
            !_alphaMaskLoader.TryGet(_motion.Atlas, frame, out PetFrameAlphaMask? mask) ||
            mask is null)
        {
            return false;
        }
        return mask.ContainsVisiblePixel(point.X, point.Y);
    }

    public void SetAlphaMaskObservationEnabled(bool enabled)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (enabled == _alphaMaskObservationEnabled)
        {
            return;
        }
        _alphaMaskObservationEnabled = enabled;
        if (enabled)
        {
            _alphaMaskLoader.Preload(_motion.Atlas, _motion.Frames);
        }
    }

    public bool PlayMotion(
        string requestedMotionId,
        bool restart,
        TimeSpan? cycleElapsed = null)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        PetPackageMotion motion = ResolveMotion(requestedMotionId);
        if (!restart && string.Equals(motion.Id, _motion.Id, StringComparison.Ordinal))
        {
            return false;
        }

        _timer.Stop();
        bool atlasChanged = !string.Equals(
            _loadedAtlasId,
            motion.Atlas,
            StringComparison.Ordinal);
        _motion = motion;
        _state = new PetFramePlaybackState(motion, loops: true);
        ResetPlaybackClock(cycleElapsed ?? TimeSpan.Zero);
        if (_alphaMaskObservationEnabled)
        {
            _alphaMaskLoader.Preload(motion.Atlas, motion.Frames);
        }
        if (atlasChanged || _surface is null)
        {
            LoadAtlasForCurrentMotion();
        }
        else if (_requestedSurfaceLoadCompleted &&
            _surface?.Status == LoadedImageSourceLoadStatus.Success)
        {
            StartPlaybackClock();
            Status = _isPaused ? "일시 정지" : "재생 중";
            RefreshFrameAndSchedule();
            StateChanged?.Invoke(this, EventArgs.Empty);
        }

        return true;
    }

    public void Pause()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (_isPaused)
        {
            return;
        }

        CapturePlaybackClock();
        _isPaused = true;
        _timer.Stop();
        if (_requestedSurfaceLoadCompleted)
        {
            Status = "일시 정지";
        }
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void Resume()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (!_isPaused)
        {
            return;
        }

        _isPaused = false;
        if (_requestedSurfaceLoadCompleted &&
            _surface?.Status == LoadedImageSourceLoadStatus.Success)
        {
            StartPlaybackClock();
            Status = "재생 중";
            RefreshFrameAndSchedule();
        }
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void Resize(Vector2 visualSize, Vector3 visualOffset)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        _visual.Size = visualSize;
        _visual.Offset = visualOffset;
        if (_requestedSurfaceLoadCompleted &&
            _surface?.Status == LoadedImageSourceLoadStatus.Success)
        {
            ApplyCurrentFrame();
        }
    }

    public void SetPixelArtRendering(bool enabled)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        _brush.BitmapInterpolationMode = enabled
            ? CompositionBitmapInterpolationMode.NearestNeighbor
            : CompositionBitmapInterpolationMode.Linear;
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _timer.Stop();
        _timer.Tick -= Timer_Tick;
        _alphaMaskLoader.StateChanged -= AlphaMaskLoader_StateChanged;
        _alphaMaskLoader.Dispose();
        if (_surface is not null)
        {
            _surface.StateChanged -= Surface_StateChanged;
        }
        _visual.Brush = null;
        _brush.Dispose();
        if (_surface is not null && !ReferenceEquals(_surface, _displayedSurface))
        {
            _surface.Dispose();
        }
        _displayedSurface?.Dispose();
        _surface = null;
        _displayedSurface = null;
        _visual.Dispose();
    }

    private void Surface_StateChanged(object? sender, EventArgs args)
    {
        if (_disposed)
        {
            return;
        }

        if (!ReferenceEquals(sender, _surface) || _surface is not { } surface)
        {
            return;
        }

        _requestedSurfaceLoadCompleted = true;
        if (surface.Status != LoadedImageSourceLoadStatus.Success)
        {
            Status = $"이미지 디코딩 실패: {surface.Status}";
            StateChanged?.Invoke(this, EventArgs.Empty);
            return;
        }

        surface.StateChanged -= Surface_StateChanged;
        PetImageSurfaceLease? previous = _displayedSurface;
        _brush.Surface = surface.Surface;
        _visual.Brush = _brush;
        _displayedSurface = surface;
        StartPlaybackClock();
        Status = _isPaused ? "일시 정지" : "재생 중";
        RefreshFrameAndSchedule();
        StateChanged?.Invoke(this, EventArgs.Empty);
        if (previous is not null && !ReferenceEquals(previous, surface))
        {
            previous.Dispose();
        }
    }

    private void AlphaMaskLoader_StateChanged(object? sender, EventArgs e) =>
        StateChanged?.Invoke(this, EventArgs.Empty);

    private void Timer_Tick(DispatcherQueueTimer sender, object args)
    {
        if (_disposed || _isPaused || !_requestedSurfaceLoadCompleted)
        {
            StateChanged?.Invoke(this, EventArgs.Empty);
            return;
        }

        RefreshFrameAndSchedule();
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    private void ApplyCurrentFrame()
    {
        PetPackageFrame frame = _state.CurrentFrame;
        float scale = MathF.Min(
            _visual.Size.X / frame.Width,
            _visual.Size.Y / frame.Height);
        float displayedWidth = frame.Width * scale;
        float displayedHeight = frame.Height * scale;
        float left = (_visual.Size.X - displayedWidth) / 2f;
        float top = (_visual.Size.Y - displayedHeight) / 2f;

        _brush.Scale = new Vector2(scale, scale);
        _brush.Offset = new Vector2(
            left - frame.X * scale,
            top - frame.Y * scale);
    }

    private void RefreshFrameAndSchedule()
    {
        if (_isPaused ||
            !_requestedSurfaceLoadCompleted ||
            _surface?.Status != LoadedImageSourceLoadStatus.Success)
        {
            return;
        }

        TimeSpan remaining = _state.Seek(CurrentPlaybackElapsed());
        ApplyCurrentFrame();
        if (!_state.NeedsScheduling)
        {
            return;
        }

        _timer.Interval = remaining > TimeSpan.Zero
            ? remaining
            : TimeSpan.FromMilliseconds(1);
        _timer.Start();
    }

    private TimeSpan CurrentPlaybackElapsed() =>
        _playbackStartedAtTimestamp == 0
            ? _playbackOffset
            : _playbackOffset + Stopwatch.GetElapsedTime(_playbackStartedAtTimestamp);

    private void CapturePlaybackClock()
    {
        if (_playbackStartedAtTimestamp == 0)
        {
            return;
        }

        _playbackOffset += Stopwatch.GetElapsedTime(_playbackStartedAtTimestamp);
        _playbackStartedAtTimestamp = 0;
        _state.Seek(_playbackOffset);
    }

    private void ResetPlaybackClock(TimeSpan offset)
    {
        _playbackOffset = offset < TimeSpan.Zero ? TimeSpan.Zero : offset;
        _playbackStartedAtTimestamp = 0;
        _state.Seek(_playbackOffset);
    }

    private void StartPlaybackClock()
    {
        if (!_isPaused && _playbackStartedAtTimestamp == 0)
        {
            _playbackStartedAtTimestamp = Stopwatch.GetTimestamp();
        }
    }

    private PetPackageMotion ResolveMotion(string requestedMotionId)
    {
        if (!string.Equals(
                requestedMotionId,
                BehaviorMotionReferences.CurrentPetDefault,
                StringComparison.Ordinal))
        {
            PetPackageMotion? requested = _package.Manifest.Motions.FirstOrDefault(value =>
                string.Equals(value.Id, requestedMotionId, StringComparison.Ordinal));
            if (requested is not null)
            {
                return requested;
            }
        }
        return _package.DefaultMotion;
    }

    private void LoadAtlasForCurrentMotion()
    {
        _timer.Stop();
        _playbackStartedAtTimestamp = 0;
        _requestedSurfaceLoadCompleted = false;
        if (_surface is not null && !ReferenceEquals(_surface, _displayedSurface))
        {
            _surface.StateChanged -= Surface_StateChanged;
            _surface.Dispose();
        }

        if (_displayedSurface is null)
        {
            _brush.Surface = null;
            _visual.Brush = null;
        }
        _loadedAtlasId = _motion.Atlas;
        LoadedPetAtlas atlas = _package.Atlases[_motion.Atlas];
        _surface = PetImageSurfaceCache.Acquire(atlas.FilePath);
        _surface.StateChanged += Surface_StateChanged;
        Status = _displayedSurface is null
            ? "이미지 디코딩 중"
            : "애니메이션 전환 중";
        if (_surface.IsCompleted)
        {
            Surface_StateChanged(_surface, EventArgs.Empty);
        }
    }
}
