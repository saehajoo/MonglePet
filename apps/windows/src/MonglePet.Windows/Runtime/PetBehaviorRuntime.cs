using System.Diagnostics;
using Microsoft.UI.Dispatching;
using MonglePet.Core.Behavior;
using MonglePet.Packages;
using MonglePet.Settings;
using MonglePet.Windows.Overlay;

namespace MonglePet.Windows.Runtime;

internal sealed class PetBehaviorRuntime : IDisposable
{
    private readonly BehaviorResolver _resolver = new();
    private readonly MotionScheduler _baseScheduler;
    private readonly MotionScheduler _movementScheduler;
    private readonly MotionScheduler _ruleScheduler;
    private readonly MotionScheduler _interactionScheduler;
    private readonly IReadOnlyDictionary<string, TimeSpan> _cycleDurations;
    private readonly PetOverlayWindow _overlay;
    private readonly DispatcherQueueTimer _boundaryTimer;
    private readonly DispatcherQueueTimer _interactionTimer;
    private readonly long _originTimestamp = Stopwatch.GetTimestamp();
    private long _lastAdvancedTimestamp;
    private ScheduledMotion? _currentMotion;
    private string? _movementBehaviorId;
    private string? _interactionBehaviorId;
    private string? _displayedMotionId;
    private readonly RandomBehaviorSelector _randomSelector = new();
    private BehaviorProfile? _latestProfile;
    private PetPresentation _latestPresentation = PetPresentation.TuckedAway;
    private ActivitySnapshot _activitySnapshot = new(
        TimeSpan.Zero,
        TimeSpan.Zero,
        null,
        false,
        false);
    private bool _waitingForPlaybackReady;
    private bool _isUserPaused;
    private PlaybackLayer _playbackLayer = PlaybackLayer.Base;
    private bool _stationaryIsOverridden;
    private bool _disposed;

    public PetBehaviorRuntime(LoadedPetPackage package, PetOverlayWindow overlay)
    {
        ArgumentNullException.ThrowIfNull(package);
        ArgumentNullException.ThrowIfNull(overlay);
        _overlay = overlay;
        _cycleDurations = BuildCycleDurations(package);
        _baseScheduler = new MotionScheduler(package.DefaultMotionId, _cycleDurations);
        _movementScheduler = new MotionScheduler(package.DefaultMotionId, _cycleDurations);
        _ruleScheduler = new MotionScheduler(package.DefaultMotionId, _cycleDurations);
        _interactionScheduler = new MotionScheduler(package.DefaultMotionId, _cycleDurations);
        _boundaryTimer = DispatcherQueue.GetForCurrentThread().CreateTimer();
        _boundaryTimer.IsRepeating = false;
        _boundaryTimer.Tick += BoundaryTimer_Tick;
        _interactionTimer = DispatcherQueue.GetForCurrentThread().CreateTimer();
        _interactionTimer.IsRepeating = false;
        _interactionTimer.Tick += InteractionTimer_Tick;
        _overlay.StateChanged += Overlay_StateChanged;
        _lastAdvancedTimestamp = Stopwatch.GetTimestamp();
    }

    public string Status { get; private set; } = "행동 대기 중";

    public string? SequenceId => _currentMotion?.SequenceId;

    public int? StepIndex => _currentMotion?.StepIndex;

    public bool IsPaused => ActiveScheduler.IsPaused;

    public bool ShouldPauseMovement { get; private set; }

    public event EventHandler? StateChanged;

    public void SetUserPaused(bool paused)
    {
        ThrowIfDisposed();
        if (_isUserPaused == paused)
        {
            return;
        }
        _isUserPaused = paused;
        if (paused)
        {
            Pause("사용자가 모든 펫을 일시정지했습니다", Stopwatch.GetTimestamp());
        }
    }

    public void SetMovementBehavior(string? behaviorId)
    {
        ThrowIfDisposed();
        if (string.Equals(_movementBehaviorId, behaviorId, StringComparison.Ordinal))
        {
            return;
        }
        _movementBehaviorId = behaviorId;
        if (_latestProfile is not null)
        {
            Update(_latestProfile, _latestPresentation);
        }
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void PlayInteraction(string behaviorId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(behaviorId);
        ThrowIfDisposed();
        if (_interactionBehaviorId is not null ||
            _latestProfile?.Sequences.FirstOrDefault(sequence =>
                string.Equals(sequence.Id, behaviorId, StringComparison.Ordinal)) is not { } behavior)
        {
            return;
        }

        long now = Stopwatch.GetTimestamp();
        AdvanceTo(now);
        _boundaryTimer.Stop();
        _baseScheduler.Pause();
        _movementScheduler.Pause();
        _ruleScheduler.Pause();
        _interactionBehaviorId = behaviorId;
        _interactionScheduler.Request(behavior, MotionSequencePlayback.Once);
        _interactionScheduler.Resume();
        _lastAdvancedTimestamp = now;
        EmitCurrentMotion(restart: true);
        ScheduleNextBoundary();
        Status = $"쓰다듬기 · {behavior.DisplayName}";
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void Update(BehaviorProfile profile, PetPresentation presentation)
    {
        ArgumentNullException.ThrowIfNull(profile);
        ThrowIfDisposed();
        _latestProfile = profile;
        _latestPresentation = presentation;
        long now = Stopwatch.GetTimestamp();
        AdvanceTo(now);
        string[] availableRandomSequences = [];
        bool randomSequenceCompleted =
            profile.StationaryBehaviorMode == StationaryBehaviorMode.Random &&
            _baseScheduler.Status is MotionSchedulerStatus.Completed;
        if (profile.StationaryBehaviorMode == StationaryBehaviorMode.Random)
        {
            availableRandomSequences = profile.RandomSequences
                .Where(id => profile.Sequences.Any(sequence =>
                    string.Equals(sequence.Id, id, StringComparison.Ordinal)))
                .ToArray();
            _randomSelector.Update(
                availableRandomSequences,
                randomSequenceCompleted);
        }
        else
        {
            _randomSelector.Reset();
        }
        if (_isUserPaused)
        {
            Pause("사용자가 모든 펫을 일시정지했습니다", now);
            return;
        }
        BehaviorConfiguration configuration = Configuration(profile);
        ActivitySnapshot currentSnapshot = _activitySnapshot with
        {
            CapturedAt = Stopwatch.GetElapsedTime(_originTimestamp, now),
        };
        BehaviorDecision stationaryDecision = _resolver.Resolve(
            configuration with { AutomaticRules = [] },
            currentSnapshot,
            new BehaviorRuntimeState(
                presentation,
                RandomSequenceId: _randomSelector.CurrentSequenceId));
        BehaviorDecision decision = _resolver.Resolve(
            configuration,
            currentSnapshot,
            new BehaviorRuntimeState(
                presentation,
                MovementSequenceId: _movementBehaviorId,
                RandomSequenceId: _randomSelector.CurrentSequenceId));
        bool stationaryIsOverridden = decision is BehaviorDecision.Sequence
        {
            Source: BehaviorSource.Movement or BehaviorSource.AutomaticRule,
        };
        bool randomWasInterrupted =
            profile.StationaryBehaviorMode == StationaryBehaviorMode.Random &&
            stationaryIsOverridden &&
            !_stationaryIsOverridden;
        if (randomWasInterrupted)
        {
            _randomSelector.Update(availableRandomSequences, sequenceCompleted: true);
            stationaryDecision = _resolver.Resolve(
                configuration with { AutomaticRules = [] },
                currentSnapshot,
                new BehaviorRuntimeState(
                    presentation,
                    RandomSequenceId: _randomSelector.CurrentSequenceId));
            decision = _resolver.Resolve(
                configuration,
                currentSnapshot,
                new BehaviorRuntimeState(
                    presentation,
                    MovementSequenceId: _movementBehaviorId,
                    RandomSequenceId: _randomSelector.CurrentSequenceId));
        }
        _stationaryIsOverridden = decision is BehaviorDecision.Sequence
        {
            Source: BehaviorSource.Movement or BehaviorSource.AutomaticRule,
        };
        Apply(
            stationaryDecision,
            decision,
            profile,
            now,
            randomWasInterrupted || randomSequenceCompleted);
    }

    public void UpdateActivity(ActivitySnapshot snapshot, BehaviorProfile profile, PetPresentation presentation)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        _activitySnapshot = snapshot;
        Update(profile, presentation);
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _boundaryTimer.Stop();
        _boundaryTimer.Tick -= BoundaryTimer_Tick;
        _interactionTimer.Stop();
        _interactionTimer.Tick -= InteractionTimer_Tick;
        _overlay.StateChanged -= Overlay_StateChanged;
        GC.SuppressFinalize(this);
    }

    private void Apply(
        BehaviorDecision stationaryDecision,
        BehaviorDecision decision,
        BehaviorProfile profile,
        long now,
        bool restartBaseSequence)
    {
        bool pauseMovement = decision is BehaviorDecision.Sequence
        {
            Source: BehaviorSource.AutomaticRule,
        } && _movementBehaviorId is not null;
        ShouldPauseMovement = pauseMovement;
        switch (decision)
        {
            case BehaviorDecision.TuckedAway:
                Pause("사용자가 펫을 숨겼습니다", now);
                break;
            case BehaviorDecision.Suspended:
                Pause("시스템 상태로 일시 정지했습니다", now);
                break;
            case BehaviorDecision.Sequence sequence:
                MotionSequencePlayback stationaryPlayback =
                    BehaviorPlaybackPolicy.ForStationary(profile.StationaryBehaviorMode);
                bool baseChanged = stationaryDecision is BehaviorDecision.Sequence stationarySequence &&
                    (restartBaseSequence
                        ? _baseScheduler.Restart(
                            stationarySequence.Value,
                            stationaryPlayback)
                        : _baseScheduler.Request(
                            stationarySequence.Value,
                            stationaryPlayback));
                if (stationaryDecision is not BehaviorDecision.Sequence)
                {
                    _baseScheduler.Stop();
                }
                bool movementChanged = false;
                if (_movementBehaviorId is { } movementBehaviorId &&
                    profile.Sequences.FirstOrDefault(value => string.Equals(
                        value.Id,
                        movementBehaviorId,
                        StringComparison.Ordinal)) is { } movementSequence)
                {
                    movementChanged = _movementScheduler.Request(
                        movementSequence,
                        MotionSequencePlayback.RepeatWhileRequested);
                }
                else
                {
                    _movementScheduler.Stop();
                }
                bool ruleChanged = sequence.Source is BehaviorSource.AutomaticRule
                    ? _ruleScheduler.Request(
                        sequence.Value,
                        MotionSequencePlayback.Once)
                    : StopScheduler(_ruleScheduler);
                PlaybackLayer nextLayer = sequence.Source switch
                {
                    BehaviorSource.Movement => PlaybackLayer.Movement,
                    BehaviorSource.AutomaticRule => PlaybackLayer.Rule,
                    _ => PlaybackLayer.Base,
                };
                bool layerChanged = SetPlaybackLayer(nextLayer);
                _lastAdvancedTimestamp = now;
                if (_interactionBehaviorId is not null)
                {
                    _baseScheduler.Pause();
                    _movementScheduler.Pause();
                    _ruleScheduler.Pause();
                }
                bool requestedChanged = nextLayer switch
                {
                    PlaybackLayer.Movement => movementChanged,
                    PlaybackLayer.Rule => ruleChanged,
                    _ => baseChanged,
                };
                bool runtimeChanged = EmitCurrentMotion(requestedChanged || layerChanged);
                if (_interactionBehaviorId is null &&
                    (requestedChanged || layerChanged || runtimeChanged ||
                        !_boundaryTimer.IsRunning))
                {
                    ScheduleNextBoundary();
                }
                break;
            case BehaviorDecision.Unavailable:
                _boundaryTimer.Stop();
                _interactionTimer.Stop();
                _interactionBehaviorId = null;
                _interactionScheduler.Stop();
                _baseScheduler.Stop();
                _movementScheduler.Stop();
                _ruleScheduler.Stop();
                _overlay.PausePlayback();
                _currentMotion = null;
                Status = "재생 가능한 행동 루틴이 없습니다";
                StateChanged?.Invoke(this, EventArgs.Empty);
                break;
        }
    }

    private void Pause(string status, long now)
    {
        bool changed = !_baseScheduler.IsPaused || !_movementScheduler.IsPaused ||
            !_ruleScheduler.IsPaused ||
            _interactionBehaviorId is not null ||
            !string.Equals(Status, status, StringComparison.Ordinal);
        _boundaryTimer.Stop();
        _interactionTimer.Stop();
        _interactionBehaviorId = null;
        _interactionScheduler.Stop();
        _baseScheduler.Pause();
        _movementScheduler.Pause();
        _ruleScheduler.Pause();
        _overlay.PausePlayback();
        _waitingForPlaybackReady = false;
        _lastAdvancedTimestamp = now;
        Status = status;
        if (changed)
        {
            StateChanged?.Invoke(this, EventArgs.Empty);
        }
    }

    private void BoundaryTimer_Tick(DispatcherQueueTimer sender, object args)
    {
        if (_disposed)
        {
            return;
        }

        AdvanceTo(Stopwatch.GetTimestamp());
        if (_interactionBehaviorId is not null &&
            _interactionScheduler.Status is MotionSchedulerStatus.Completed)
        {
            _interactionBehaviorId = null;
            _interactionScheduler.Stop();
            ActiveScheduler.Resume();
            _lastAdvancedTimestamp = Stopwatch.GetTimestamp();
        }
        EmitCurrentMotion(restart: false);
        if (_interactionBehaviorId is null &&
            _latestProfile?.StationaryBehaviorMode == StationaryBehaviorMode.Random &&
            _baseScheduler.Status is MotionSchedulerStatus.Completed)
        {
            Update(_latestProfile, _latestPresentation);
            return;
        }
        ScheduleNextBoundary();
    }

    private void InteractionTimer_Tick(DispatcherQueueTimer sender, object args)
    {
        if (_disposed || _interactionBehaviorId is null)
        {
            return;
        }

        _interactionBehaviorId = null;
        _interactionScheduler.Stop();
        ActiveScheduler.Resume();
        _lastAdvancedTimestamp = Stopwatch.GetTimestamp();
        RenderPreferredMotion(restart: true);
        EmitCurrentMotion(restart: false);
        ScheduleNextBoundary();
    }

    private void Overlay_StateChanged(object? sender, EventArgs e)
    {
        if (_disposed || !_waitingForPlaybackReady || !_overlay.IsPlaybackReady)
        {
            return;
        }

        _waitingForPlaybackReady = false;
        _lastAdvancedTimestamp = Stopwatch.GetTimestamp();
        ScheduleNextBoundary();
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    private void AdvanceTo(long timestamp)
    {
        TimeSpan elapsed = Stopwatch.GetElapsedTime(_lastAdvancedTimestamp, timestamp);
        _lastAdvancedTimestamp = timestamp;
        if (elapsed > TimeSpan.Zero && !_waitingForPlaybackReady)
        {
            if (_interactionBehaviorId is not null)
            {
                _interactionScheduler.Advance(elapsed);
            }
            else
            {
                ActiveScheduler.Advance(elapsed);
            }
        }
    }

    private bool EmitCurrentMotion(bool restart)
    {
        ScheduledMotion? previousMotion = _currentMotion;
        string previousStatus = Status;
        MotionSchedulerStatus schedulerStatus = _interactionBehaviorId is not null
            ? _interactionScheduler.Status
            : ActiveScheduler.Status;
        switch (schedulerStatus)
        {
            case MotionSchedulerStatus.Playing playing:
                bool changed = playing.Motion != _currentMotion;
                _currentMotion = playing.Motion;
                RenderPreferredMotion(restart || changed);
                _waitingForPlaybackReady = !_overlay.IsPlaybackReady;
                Status = _interactionBehaviorId is { } interaction
                    ? $"쓰다듬기 · {BehaviorDisplayName(interaction)}"
                    : $"{BehaviorDisplayName(playing.Motion.SequenceId)} · 단계 {playing.Motion.StepIndex + 1}" +
                        (playing.Motion.UsesFallback ? " · 기본 모션 대체" : string.Empty);
                break;
            case MotionSchedulerStatus.Completed completed:
                _currentMotion = null;
                RenderPreferredMotion(restart: false);
                Status = $"{BehaviorDisplayName(completed.SequenceId)} · 완료";
                break;
            case MotionSchedulerStatus.Unavailable:
                _currentMotion = null;
                RenderPreferredMotion(restart: false);
                Status = "행동 루틴의 모션을 해석할 수 없습니다";
                break;
            case MotionSchedulerStatus.Stopped:
                _currentMotion = null;
                RenderPreferredMotion(restart: false);
                Status = "행동 대기 중";
                break;
        }
        bool didChange = previousMotion != _currentMotion ||
            !string.Equals(previousStatus, Status, StringComparison.Ordinal);
        if (didChange)
        {
            StateChanged?.Invoke(this, EventArgs.Empty);
        }
        return didChange;
    }

    private string BehaviorDisplayName(string sequenceId) =>
        _latestProfile?.Sequences.FirstOrDefault(sequence => string.Equals(
            sequence.Id,
            sequenceId,
            StringComparison.Ordinal))?.DisplayName ?? "찾을 수 없는 행동";

    private void RenderPreferredMotion(bool restart)
    {
        MotionSchedulerStatus schedulerStatus = _interactionBehaviorId is not null
            ? _interactionScheduler.Status
            : ActiveScheduler.Status;
        if (schedulerStatus is MotionSchedulerStatus.Completed &&
            ActiveScheduler.CompletedMotion is { } completedMotion)
        {
            _overlay.HoldMotionLastFrame(completedMotion.ResolvedMotionId);
            _displayedMotionId = completedMotion.ResolvedMotionId;
            return;
        }
        string? desired = (schedulerStatus as MotionSchedulerStatus.Playing)?.Motion.ResolvedMotionId;
        if (desired is null)
        {
            _overlay.PausePlayback();
            _displayedMotionId = null;
            return;
        }
        if (restart || !string.Equals(_displayedMotionId, desired, StringComparison.Ordinal))
        {
            TimeSpan cycleElapsed = (_interactionBehaviorId is not null
                ? _interactionScheduler
                : ActiveScheduler).ActiveCycleElapsedDuration ?? TimeSpan.Zero;
            _overlay.PlayMotion(desired, restart: true, cycleElapsed);
            _displayedMotionId = desired;
        }
        _overlay.ResumePlayback();
    }

    private void ScheduleNextBoundary()
    {
        _boundaryTimer.Stop();
        if (_waitingForPlaybackReady)
        {
            return;
        }

        MotionScheduler active = _interactionBehaviorId is not null
            ? _interactionScheduler
            : ActiveScheduler;
        if (active.IsPaused ||
            active.ActiveCycleRemainingDuration is not { } remainingValue)
        {
            return;
        }

        _boundaryTimer.Interval = remainingValue > TimeSpan.Zero
            ? remainingValue
            : TimeSpan.FromMilliseconds(1);
        _boundaryTimer.Start();
    }

    private MotionScheduler ActiveScheduler => _playbackLayer switch
    {
        PlaybackLayer.Movement => _movementScheduler,
        PlaybackLayer.Rule => _ruleScheduler,
        _ => _baseScheduler,
    };

    private bool SetPlaybackLayer(PlaybackLayer layer)
    {
        bool changed = _playbackLayer != layer;
        _playbackLayer = layer;
        _baseScheduler.Pause();
        _movementScheduler.Pause();
        _ruleScheduler.Pause();
        if (_interactionBehaviorId is null)
        {
            ActiveScheduler.Resume();
        }
        return changed;
    }

    private static BehaviorConfiguration Configuration(BehaviorProfile profile)
    {
        string defaultSequenceId = profile.Sequences.Any(sequence =>
            string.Equals(
                sequence.Id,
                BehaviorMotionReferences.DefaultSequence,
                StringComparison.Ordinal))
            ? BehaviorMotionReferences.DefaultSequence
            : profile.Sequences.FirstOrDefault()?.Id ?? BehaviorMotionReferences.DefaultSequence;
        return new BehaviorConfiguration(
            profile.StationaryBehaviorMode,
            defaultSequenceId,
            profile.Sequences,
            profile.StationarySequenceId,
            profile.AutomaticRules,
            profile.RandomSequences,
            profile.RulePriorityOrder);
    }

    private static IReadOnlyDictionary<string, TimeSpan> BuildCycleDurations(
        LoadedPetPackage package)
    {
        var durations = new Dictionary<string, TimeSpan>(StringComparer.Ordinal);
        foreach (PetPackageMotion motion in package.Manifest.Motions)
        {
            long milliseconds = 0;
            checked
            {
                foreach (PetPackageFrame frame in motion.Frames)
                {
                    milliseconds += frame.DurationMs;
                }
            }
            durations.Add(motion.Id, TimeSpan.FromMilliseconds(milliseconds));
        }
        return durations;
    }

    private void ThrowIfDisposed() => ObjectDisposedException.ThrowIf(_disposed, this);

    private static bool StopScheduler(MotionScheduler scheduler)
    {
        bool changed = scheduler.Status is not MotionSchedulerStatus.Stopped;
        scheduler.Stop();
        return changed;
    }

    private enum PlaybackLayer
    {
        Base,
        Movement,
        Rule,
    }
}
