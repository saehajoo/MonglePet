namespace MonglePet.Settings;

public sealed record PetSpeechPresentation(
    Guid PhraseId,
    string Text,
    long DisplayDurationMilliseconds,
    PetSpeechBubbleTheme Theme,
    PetSpeechBubblePlacementSettings Placement);

public interface IPetSpeechScheduler
{
    void Schedule(TimeSpan delay, Action action);

    void Cancel();
}

public sealed class PetSpeechRuntime : IDisposable
{
    public delegate PetSpeechPhrase? PhrasePicker(
        IReadOnlyList<PetSpeechPhrase> phrases,
        Guid? excludedId);

    private enum PresentationSourceKind
    {
        Periodic,
        Behavior,
    }

    private sealed record ActivePresentation(
        PetSpeechPresentation Presentation,
        PresentationSourceKind Source,
        string? SequenceId,
        PetSpeechDisplayMode DisplayMode);

    private PetSpeechSettings _settings = PetSpeechSettings.Default;
    private readonly IPetSpeechScheduler _periodicScheduler;
    private readonly IPetSpeechScheduler _dismissalScheduler;
    private readonly PhrasePicker _phrasePicker;
    private readonly Action<PetSpeechPresentation?> _onPresentationChange;
    private readonly Dictionary<string, Guid> _lastBehaviorPhraseIds =
        new(StringComparer.Ordinal);
    private bool _isAwake;
    private bool _isSystemSuspended;
    private string? _lastSequenceId;
    private Guid? _lastPeriodicPhraseId;
    private ActivePresentation? _activePresentation;
    private bool _isPeriodicScheduled;
    private bool _disposed;

    public PetSpeechRuntime(
        IPetSpeechScheduler periodicScheduler,
        IPetSpeechScheduler dismissalScheduler,
        Action<PetSpeechPresentation?> onPresentationChange,
        PhrasePicker? phrasePicker = null)
    {
        ArgumentNullException.ThrowIfNull(periodicScheduler);
        ArgumentNullException.ThrowIfNull(dismissalScheduler);
        ArgumentNullException.ThrowIfNull(onPresentationChange);
        _periodicScheduler = periodicScheduler;
        _dismissalScheduler = dismissalScheduler;
        _onPresentationChange = onPresentationChange;
        _phrasePicker = phrasePicker ?? PickRandomPhrase;
    }

    public string Status
    {
        get
        {
            int periodicPhraseCount = PeriodicPhrases().Count;
            if (!_settings.IsEnabled)
            {
                return "말풍선 사용 안 함";
            }
            if (!_isAwake)
            {
                return "펫이 자는 중";
            }
            if (_isSystemSuspended)
            {
                return "잠금 또는 절전으로 일시 정지";
            }
            if (!_settings.PeriodicIsEnabled)
            {
                return "주기 대사 사용 안 함";
            }
            if (periodicPhraseCount == 0)
            {
                return "등록된 주기 대사 없음";
            }
            if (_activePresentation is { } active)
            {
                return $"대사 표시 중 · {active.Presentation.Text}";
            }
            return _isPeriodicScheduled
                ? $"다음 주기 대사 예약됨 · {_settings.PeriodicIntervalMilliseconds / 1_000d:0.#}초"
                : "주기 대사 예약 대기 중";
        }
    }

    public void Update(PetSpeechSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        ThrowIfDisposed();
        if (settings == _settings)
        {
            return;
        }

        _settings = settings;
        CancelPeriodic();
        CancelDismissal();
        _lastSequenceId = null;
        _lastPeriodicPhraseId = null;
        _lastBehaviorPhraseIds.Clear();
        DismissCurrentPresentation();
        ScheduleNextPeriodicPresentation();
    }

    public void SetAwake(bool isAwake)
    {
        ThrowIfDisposed();
        if (isAwake == _isAwake)
        {
            return;
        }

        _isAwake = isAwake;
        if (isAwake)
        {
            ScheduleNextPeriodicPresentation();
        }
        else
        {
            CancelPeriodic();
            CancelDismissal();
            DismissCurrentPresentation();
            _lastSequenceId = null;
        }
    }

    public void SetSystemSuspended(bool isSuspended)
    {
        ThrowIfDisposed();
        if (isSuspended == _isSystemSuspended)
        {
            return;
        }

        _isSystemSuspended = isSuspended;
        if (isSuspended)
        {
            CancelPeriodic();
            CancelDismissal();
            DismissCurrentPresentation();
            _lastSequenceId = null;
        }
        else
        {
            ScheduleNextPeriodicPresentation();
        }
    }

    public void BehaviorSequenceDidChange(string? sequenceId)
    {
        ThrowIfDisposed();
        if (string.Equals(sequenceId, _lastSequenceId, StringComparison.Ordinal))
        {
            return;
        }

        _lastSequenceId = sequenceId;
        if (!CanPresent)
        {
            return;
        }

        if (sequenceId is not null && BehaviorPhrase(sequenceId) is { } phrase)
        {
            _lastBehaviorPhraseIds[sequenceId] = phrase.Id;
            Present(
                phrase,
                PresentationSourceKind.Behavior,
                sequenceId);
            return;
        }

        if (_settings.BehaviorChangePolicy == PetSpeechBehaviorChangePolicy.Dismiss)
        {
            DismissCurrentPresentation();
            ScheduleNextPeriodicPresentation();
            return;
        }

        if (_activePresentation is null)
        {
            EnsurePeriodicPresentationScheduled();
            return;
        }

        if (_activePresentation.Source == PresentationSourceKind.Behavior &&
            _activePresentation.DisplayMode == PetSpeechDisplayMode.UntilNextPhrase)
        {
            ScheduleNextPeriodicPresentation();
        }
    }

    public void PrepareForPetChange()
    {
        ThrowIfDisposed();
        Reset();
    }

    public void Stop()
    {
        ThrowIfDisposed();
        Reset();
        _isSystemSuspended = false;
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        Reset();
        _disposed = true;
        if (_periodicScheduler is IDisposable periodicDisposable)
        {
            periodicDisposable.Dispose();
        }
        if (!ReferenceEquals(_periodicScheduler, _dismissalScheduler) &&
            _dismissalScheduler is IDisposable dismissalDisposable)
        {
            dismissalDisposable.Dispose();
        }
        GC.SuppressFinalize(this);
    }

    private bool CanPresent =>
        _settings.IsEnabled && _isAwake && !_isSystemSuspended;

    private void ScheduleNextPeriodicPresentation()
    {
        CancelPeriodic();
        if (!CanPresent ||
            !_settings.PeriodicIsEnabled ||
            !PeriodicPhrases().Any())
        {
            return;
        }

        _isPeriodicScheduled = true;
        _periodicScheduler.Schedule(
            TimeSpan.FromMilliseconds(_settings.PeriodicIntervalMilliseconds),
            PeriodicTimerDidFire);
    }

    private void PeriodicTimerDidFire()
    {
        _isPeriodicScheduled = false;
        if (!CanPresent)
        {
            CancelPeriodic();
            return;
        }

        PetSpeechPhrase? phrase = NextPeriodicPhrase();
        if (phrase is null)
        {
            return;
        }

        _lastPeriodicPhraseId = phrase.Id;
        Present(phrase, PresentationSourceKind.Periodic, null);
    }

    private void Present(
        PetSpeechPhrase phrase,
        PresentationSourceKind source,
        string? sequenceId)
    {
        CancelDismissal();
        if (source == PresentationSourceKind.Behavior)
        {
            CancelPeriodic();
        }

        var presentation = new PetSpeechPresentation(
            phrase.Id,
            phrase.Text,
            phrase.DisplayDurationMilliseconds,
            _settings.Theme,
            _settings.Placement);
        _activePresentation = new ActivePresentation(
            presentation,
            source,
            sequenceId,
            phrase.DisplayMode);
        _onPresentationChange(presentation);

        if (phrase.DisplayMode == PetSpeechDisplayMode.Timed)
        {
            _dismissalScheduler.Schedule(
                TimeSpan.FromMilliseconds(phrase.DisplayDurationMilliseconds),
                () => DismissalTimerDidFire(phrase.Id));
        }
        else
        {
            ScheduleNextPeriodicPresentation();
        }
    }

    private void DismissalTimerDidFire(Guid phraseId)
    {
        if (_activePresentation?.Presentation.PhraseId != phraseId)
        {
            return;
        }

        DismissCurrentPresentation();
        ScheduleNextPeriodicPresentation();
    }

    private void DismissCurrentPresentation()
    {
        CancelDismissal();
        if (_activePresentation is null)
        {
            return;
        }

        _activePresentation = null;
        _onPresentationChange(null);
    }

    private void EnsurePeriodicPresentationScheduled()
    {
        if (!_isPeriodicScheduled)
        {
            ScheduleNextPeriodicPresentation();
        }
    }

    private void CancelPeriodic()
    {
        _periodicScheduler.Cancel();
        _isPeriodicScheduled = false;
    }

    private void CancelDismissal() => _dismissalScheduler.Cancel();

    private PetSpeechPhrase? BehaviorPhrase(string sequenceId)
    {
        IReadOnlyList<PetSpeechPhrase> phrases = _settings.Phrases
            .Where(phrase => phrase.Trigger is PetSpeechTrigger.Sequence trigger &&
                string.Equals(trigger.SequenceId, sequenceId, StringComparison.Ordinal))
            .ToList();
        if (phrases.Count == 0)
        {
            return null;
        }
        _lastBehaviorPhraseIds.TryGetValue(sequenceId, out Guid lastId);
        return _phrasePicker(phrases, lastId == Guid.Empty ? null : lastId);
    }

    private PetSpeechPhrase? NextPeriodicPhrase()
    {
        IReadOnlyList<PetSpeechPhrase> phrases = PeriodicPhrases();
        if (_settings.PeriodicOrder == PetSpeechPeriodicOrder.Random)
        {
            return _phrasePicker(phrases, _lastPeriodicPhraseId);
        }

        if (_lastPeriodicPhraseId is not Guid lastId)
        {
            return phrases.FirstOrDefault();
        }

        int index = phrases.ToList().FindIndex(phrase => phrase.Id == lastId);
        return index < 0 || index + 1 >= phrases.Count
            ? phrases.FirstOrDefault()
            : phrases[index + 1];
    }

    private IReadOnlyList<PetSpeechPhrase> PeriodicPhrases() =>
        _settings.Phrases
            .Where(phrase => phrase.Trigger is PetSpeechTrigger.Periodic)
            .ToList();

    private void Reset()
    {
        CancelPeriodic();
        CancelDismissal();
        DismissCurrentPresentation();
        _settings = PetSpeechSettings.Default;
        _isAwake = false;
        _lastSequenceId = null;
        _lastPeriodicPhraseId = null;
        _lastBehaviorPhraseIds.Clear();
    }

    private static PetSpeechPhrase? PickRandomPhrase(
        IReadOnlyList<PetSpeechPhrase> phrases,
        Guid? excludedId)
    {
        IReadOnlyList<PetSpeechPhrase> candidates =
            phrases.Count > 1 && excludedId is not null
                ? phrases.Where(phrase => phrase.Id != excludedId).ToList()
                : phrases;
        return candidates.Count == 0
            ? null
            : candidates[Random.Shared.Next(candidates.Count)];
    }

    private void ThrowIfDisposed() => ObjectDisposedException.ThrowIf(_disposed, this);
}
