using Microsoft.UI.Xaml.Media;

namespace MonglePet.Windows.Overlay;

internal sealed class PetImageSurfaceLease : IDisposable
{
    private readonly string _key;
    private PetImageSurfaceCache.Entry? _entry;

    internal PetImageSurfaceLease(string key, PetImageSurfaceCache.Entry entry)
    {
        _key = key;
        _entry = entry;
        entry.StateChanged += Entry_StateChanged;
    }

    public LoadedImageSurface Surface => RequiredEntry.Surface;

    public LoadedImageSourceLoadStatus? Status => RequiredEntry.Status;

    public bool IsCompleted => Status is not null;

    public event EventHandler? StateChanged;

    public void Dispose()
    {
        PetImageSurfaceCache.Entry? entry = Interlocked.Exchange(ref _entry, null);
        if (entry is null)
        {
            return;
        }
        entry.StateChanged -= Entry_StateChanged;
        PetImageSurfaceCache.Release(_key, entry);
        StateChanged = null;
        GC.SuppressFinalize(this);
    }

    private PetImageSurfaceCache.Entry RequiredEntry => _entry
        ?? throw new ObjectDisposedException(nameof(PetImageSurfaceLease));

    private void Entry_StateChanged(object? sender, EventArgs e) =>
        StateChanged?.Invoke(this, EventArgs.Empty);
}

internal static class PetImageSurfaceCache
{
    private const int MaximumIdleEntries = 16;
    private static readonly object CacheLock = new();
    private static readonly Dictionary<string, Entry> Entries =
        new(StringComparer.OrdinalIgnoreCase);
    private static long _accessGeneration;

    public static PetImageSurfaceLease Acquire(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        string key = Path.GetFullPath(path);
        lock (CacheLock)
        {
            if (!Entries.TryGetValue(key, out Entry? entry))
            {
                entry = new Entry(key);
                Entries.Add(key, entry);
            }
            entry.ReferenceCount++;
            entry.LastAccessGeneration = ++_accessGeneration;
            return new PetImageSurfaceLease(key, entry);
        }
    }

    internal static void Release(string key, Entry entry)
    {
        lock (CacheLock)
        {
            entry.ReferenceCount--;
            entry.LastAccessGeneration = ++_accessGeneration;
            if (entry.ReferenceCount == 0 &&
                entry.Status is not null and not LoadedImageSourceLoadStatus.Success &&
                Entries.TryGetValue(key, out Entry? current) &&
                ReferenceEquals(current, entry))
            {
                Entries.Remove(key);
                entry.Dispose();
                return;
            }
            TrimIdleEntries();
        }
    }

    private static void TrimIdleEntries()
    {
        Entry[] idle = Entries.Values
            .Where(entry => entry.ReferenceCount == 0)
            .OrderByDescending(entry => entry.LastAccessGeneration)
            .ToArray();
        foreach (Entry entry in idle.Skip(MaximumIdleEntries))
        {
            Entries.Remove(entry.Path);
            entry.Dispose();
        }
    }

    internal sealed class Entry : IDisposable
    {
        public Entry(string path)
        {
            Path = path;
            Surface = LoadedImageSurface.StartLoadFromUri(new Uri(path));
            Surface.LoadCompleted += Surface_LoadCompleted;
        }

        public string Path { get; }

        public LoadedImageSurface Surface { get; }

        public LoadedImageSourceLoadStatus? Status { get; private set; }

        public int ReferenceCount { get; set; }

        public long LastAccessGeneration { get; set; }

        public event EventHandler? StateChanged;

        public void Dispose()
        {
            Surface.LoadCompleted -= Surface_LoadCompleted;
            StateChanged = null;
            Surface.Dispose();
        }

        private void Surface_LoadCompleted(
            LoadedImageSurface sender,
            LoadedImageSourceLoadCompletedEventArgs args)
        {
            Surface.LoadCompleted -= Surface_LoadCompleted;
            Status = args.Status;
            StateChanged?.Invoke(this, EventArgs.Empty);
        }
    }
}
