using MonglePet.Activity;
using MonglePet.Core.Behavior;
using MonglePet.Packages;
using MonglePet.Settings;
using MonglePet.Shell;
using MonglePet.Windows.Activity;

namespace MonglePet.Windows.Runtime;

internal sealed record PetInstanceRestoreIssue(Guid InstanceId, string Message);

internal sealed class PetInstanceManager : IDisposable
{
    private readonly Dictionary<Guid, PetRuntimeContext> _contexts = [];
    private readonly Func<PetBehaviorKey, LoadedPetPackage> _packageResolver;
    private readonly WindowsMonitorPlacementService _monitorPlacement;
    private readonly PetDesktopEnvironment _desktopEnvironment;
    private readonly WindowsFrontmostWindowProvider _frontmostWindowProvider = new();
    private readonly WindowsActivityMonitor _activityMonitor = new();
    private readonly PetRestoreJournal _restoreJournal;
    private readonly HashSet<Guid> _pausedInstanceIds = [];
    private bool _isPaused;
    private bool _disposed;

    public PetInstanceManager(
        Func<PetBehaviorKey, LoadedPetPackage> packageResolver,
        WindowsMonitorPlacementService monitorPlacement,
        PetRestoreJournal restoreJournal)
    {
        _packageResolver = packageResolver ?? throw new ArgumentNullException(nameof(packageResolver));
        _monitorPlacement = monitorPlacement ?? throw new ArgumentNullException(nameof(monitorPlacement));
        _desktopEnvironment = new PetDesktopEnvironment(monitorPlacement);
        _restoreJournal = restoreJournal ?? throw new ArgumentNullException(nameof(restoreJournal));
        _activityMonitor.SnapshotChanged += ActivityMonitor_SnapshotChanged;
    }

    public Guid? SelectedInstanceId { get; private set; }

    public PetRuntimeContext? SelectedContext => SelectedInstanceId is Guid id &&
        _contexts.TryGetValue(id, out PetRuntimeContext? context)
            ? context
            : null;

    public IReadOnlyList<PetRuntimeContext> Contexts => _contexts.Values
        .OrderBy(context => context.Instance.DisplayOrder)
        .ToList();

    public IReadOnlyList<PetRuntimeSnapshot> Snapshots => Contexts
        .Select(context => context.Snapshot)
        .ToList();

    public IReadOnlyList<PetInstanceRestoreIssue> RestoreIssues { get; private set; } = [];

    public ActivitySnapshot? LatestActivitySnapshot => _activityMonitor.LatestSnapshot;

    public bool IsPaused => _isPaused;

    public event EventHandler? StateChanged;

    public event EventHandler<PetOverlayChangedEventArgs>? OverlayChanged;

    public void Synchronize(AppSettings settings, ISet<Guid>? excludedInstanceIds = null)
    {
        ArgumentNullException.ThrowIfNull(settings);
        ThrowIfDisposed();
        excludedInstanceIds ??= new HashSet<Guid>();
        var desired = settings.ActivePetInstances
            .Where(instance => !excludedInstanceIds.Contains(instance.InstanceId))
            .OrderBy(instance => instance.DisplayOrder)
            .ToList();
        var desiredIds = desired.Select(instance => instance.InstanceId).ToHashSet();
        foreach (Guid removedId in _contexts.Keys.Where(id => !desiredIds.Contains(id)).ToList())
        {
            RemoveContext(removedId);
            _pausedInstanceIds.Remove(removedId);
        }

        var issues = new List<PetInstanceRestoreIssue>();
        foreach (ActivePetInstance instance in desired)
        {
            ActivePetInstance runtimeInstance = instance;
            BehaviorProfile? profile = settings.BehaviorProfiles.FirstOrDefault(value =>
                value.ProfileId == instance.BehaviorProfileId);
            if (profile is null)
            {
                issues.Add(new PetInstanceRestoreIssue(instance.InstanceId, "행동 프로필을 찾지 못했습니다."));
                continue;
            }

            if (_contexts.TryGetValue(instance.InstanceId, out PetRuntimeContext? existing) &&
                existing.Instance.PetKey != instance.PetKey)
            {
                RemoveContext(instance.InstanceId);
                existing = null;
            }
            if (existing is null)
            {
                try
                {
                    _restoreJournal.Begin(instance.InstanceId, instance.DisplayOrder);
                    LoadedPetPackage package = _packageResolver(instance.PetKey);
                    var created = new PetRuntimeContext(
                        instance,
                        profile,
                        package,
                        _monitorPlacement,
                        _desktopEnvironment,
                        _frontmostWindowProvider);
                    created.StateChanged += Context_StateChanged;
                    created.OverlayChanged += Context_OverlayChanged;
                    created.Overlay.ZOrderInvalidated += Overlay_ZOrderInvalidated;
                    _contexts.Add(instance.InstanceId, created);
                    _activityMonitor.Attach(created.Overlay);
                    existing = created;
                    runtimeInstance = created.Instance;
                }
                catch (Exception exception)
                {
                    issues.Add(new PetInstanceRestoreIssue(instance.InstanceId, exception.Message));
                    continue;
                }
            }

            existing.Apply(
                runtimeInstance,
                profile,
                LatestActivitySnapshot,
                _isPaused || _pausedInstanceIds.Contains(instance.InstanceId));
            if (runtimeInstance.Overlay != instance.Overlay)
            {
                OverlayChanged?.Invoke(
                    this,
                    new PetOverlayChangedEventArgs(
                        runtimeInstance.InstanceId,
                        runtimeInstance.Overlay));
            }
        }

        _restoreJournal.Complete();
        RestoreIssues = issues;
        SelectedInstanceId = desiredIds.Contains(settings.SelectedPetInstanceId)
            ? settings.SelectedPetInstanceId
            : desired.FirstOrDefault()?.InstanceId;
        _activityMonitor.SetShouldPoll(
            !_isPaused && desired.Any(instance =>
                instance.Presentation == PetPresentation.Awake &&
                !_pausedInstanceIds.Contains(instance.InstanceId)));
        ApplyDisplayOrder();
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void SetPaused(bool paused)
    {
        ThrowIfDisposed();
        if (_isPaused == paused)
        {
            return;
        }
        _isPaused = paused;
        foreach (PetRuntimeContext context in Contexts)
        {
            context.Apply(
                context.Instance,
                context.Profile,
                LatestActivitySnapshot,
                paused || _pausedInstanceIds.Contains(context.Instance.InstanceId));
        }
        _activityMonitor.SetShouldPoll(
            !paused && Contexts.Any(context =>
                context.Instance.Presentation == PetPresentation.Awake &&
                !_pausedInstanceIds.Contains(context.Instance.InstanceId)));
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void ToggleInstancePaused(Guid instanceId)
    {
        ThrowIfDisposed();
        PetRuntimeContext context = RequiredContext(instanceId);
        bool paused = !_pausedInstanceIds.Remove(instanceId);
        if (paused)
        {
            _pausedInstanceIds.Add(instanceId);
        }
        context.Apply(
            context.Instance,
            context.Profile,
            LatestActivitySnapshot,
            _isPaused || paused);
        _activityMonitor.SetShouldPoll(
            !_isPaused && Contexts.Any(value =>
                value.Instance.Presentation == PetPresentation.Awake &&
                !_pausedInstanceIds.Contains(value.Instance.InstanceId)));
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    public OverlaySettings BringToCurrentScreen(Guid instanceId)
    {
        ThrowIfDisposed();
        return RequiredContext(instanceId).BringToCurrentScreen();
    }

    public void SelectInstance(Guid instanceId)
    {
        ThrowIfDisposed();
        SelectedInstanceId = instanceId;
    }

    public LoadedPetPackage? PackageFor(Guid instanceId)
    {
        ThrowIfDisposed();
        return _contexts.TryGetValue(instanceId, out PetRuntimeContext? context)
            ? context.Package
            : null;
    }

    public void InvalidateInstance(Guid instanceId)
    {
        ThrowIfDisposed();
        RemoveContext(instanceId);
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }
        _disposed = true;
        _activityMonitor.SnapshotChanged -= ActivityMonitor_SnapshotChanged;
        _activityMonitor.Dispose();
        foreach (Guid instanceId in _contexts.Keys.ToList())
        {
            RemoveContext(instanceId);
        }
        GC.SuppressFinalize(this);
    }

    private void ApplyDisplayOrder()
    {
        nint precedingWindow = 0;
        foreach (PetRuntimeContext context in Contexts)
        {
            if (context.Overlay.IsVisible)
            {
                precedingWindow = context.Overlay.PlaceZOrderGroupAfter(precedingWindow);
            }
        }
    }

    private void RemoveContext(Guid instanceId)
    {
        if (!_contexts.Remove(instanceId, out PetRuntimeContext? context))
        {
            return;
        }
        _activityMonitor.Detach(context.Overlay);
        context.StateChanged -= Context_StateChanged;
        context.OverlayChanged -= Context_OverlayChanged;
        context.Overlay.ZOrderInvalidated -= Overlay_ZOrderInvalidated;
        context.Dispose();
    }

    private PetRuntimeContext RequiredContext(Guid instanceId) =>
        _contexts.TryGetValue(instanceId, out PetRuntimeContext? context)
            ? context
            : throw new InvalidOperationException("활성 펫 런타임을 찾지 못했습니다.");

    private void Context_StateChanged(object? sender, EventArgs e) =>
        StateChanged?.Invoke(this, EventArgs.Empty);

    private void Context_OverlayChanged(object? sender, PetOverlayChangedEventArgs e) =>
        OverlayChanged?.Invoke(this, e);

    private void Overlay_ZOrderInvalidated(object? sender, EventArgs e) =>
        ApplyDisplayOrder();

    private void ActivityMonitor_SnapshotChanged(
        object? sender,
        ActivitySnapshotChangedEventArgs e)
    {
        foreach (PetRuntimeContext context in Contexts)
        {
            context.UpdateActivity(e.Snapshot);
        }
    }

    private void ThrowIfDisposed() => ObjectDisposedException.ThrowIf(_disposed, this);
}
