using MonglePet.Settings;

namespace MonglePet.Settings.Tests;

public sealed class PetSpeechRuntimeTests
{
    [Fact]
    public void PeriodicTimedPhraseWaitsThenDismissesAndReschedules()
    {
        var periodic = new ManualScheduler();
        var dismissal = new ManualScheduler();
        var presentations = new List<PetSpeechPresentation?>();
        PetSpeechPhrase phrase = Phrase("안녕하세요", new PetSpeechTrigger.Periodic());
        using var runtime = Runtime(periodic, dismissal, presentations, (phrases, _) => phrases[0]);

        runtime.Update(Settings([phrase], periodic: true));
        runtime.SetAwake(true);

        Assert.Equal(TimeSpan.FromSeconds(60), periodic.Delay);
        periodic.Fire();
        Assert.Equal(phrase.Id, Assert.Single(presentations)!.PhraseId);
        Assert.Equal(TimeSpan.FromSeconds(3), dismissal.Delay);

        dismissal.Fire();
        Assert.Null(presentations[^1]);
        Assert.Equal(TimeSpan.FromSeconds(60), periodic.Delay);
    }

    [Fact]
    public void BehaviorPhrasePreemptsPeriodicAndSameSequenceDoesNotRepeat()
    {
        var periodic = new ManualScheduler();
        var dismissal = new ManualScheduler();
        var presentations = new List<PetSpeechPresentation?>();
        PetSpeechPhrase periodicPhrase = Phrase("주기", new PetSpeechTrigger.Periodic());
        PetSpeechPhrase behaviorPhrase = Phrase("집중", new PetSpeechTrigger.Sequence("focus"));
        using var runtime = Runtime(periodic, dismissal, presentations, (phrases, _) => phrases[0]);
        runtime.Update(Settings([periodicPhrase, behaviorPhrase], periodic: true));
        runtime.SetAwake(true);

        periodic.Fire();
        runtime.BehaviorSequenceDidChange("focus");
        runtime.BehaviorSequenceDidChange("focus");

        Assert.Equal([periodicPhrase.Id, behaviorPhrase.Id], presentations
            .Where(value => value is not null)
            .Select(value => value!.PhraseId));
        Assert.False(periodic.IsScheduled);
    }

    [Fact]
    public void DismissPolicyClearsPhraseWhenBehaviorHasNoSpeech()
    {
        var periodic = new ManualScheduler();
        var dismissal = new ManualScheduler();
        var presentations = new List<PetSpeechPresentation?>();
        PetSpeechPhrase phrase = Phrase(
            "집중",
            new PetSpeechTrigger.Sequence("focus"),
            PetSpeechDisplayMode.UntilNextPhrase);
        using var runtime = Runtime(periodic, dismissal, presentations, (phrases, _) => phrases[0]);
        runtime.Update(Settings([phrase]));
        runtime.SetAwake(true);
        runtime.BehaviorSequenceDidChange("focus");

        runtime.BehaviorSequenceDidChange("rest");

        Assert.Null(presentations[^1]);
    }

    [Fact]
    public void KeepPolicyRetainsPhraseAndSchedulesPeriodicReplacement()
    {
        var periodic = new ManualScheduler();
        var dismissal = new ManualScheduler();
        var presentations = new List<PetSpeechPresentation?>();
        PetSpeechPhrase behavior = Phrase(
            "집중",
            new PetSpeechTrigger.Sequence("focus"),
            PetSpeechDisplayMode.UntilNextPhrase);
        PetSpeechPhrase periodicPhrase = Phrase(
            "쉬어요",
            new PetSpeechTrigger.Periodic(),
            PetSpeechDisplayMode.UntilNextPhrase);
        PetSpeechSettings settings = Settings([behavior, periodicPhrase], periodic: true) with
        {
            BehaviorChangePolicy = PetSpeechBehaviorChangePolicy.Keep,
        };
        using var runtime = Runtime(periodic, dismissal, presentations, (phrases, _) => phrases[0]);
        runtime.Update(settings);
        runtime.SetAwake(true);
        runtime.BehaviorSequenceDidChange("focus");

        runtime.BehaviorSequenceDidChange("rest");

        Assert.Equal(behavior.Id, presentations[^1]!.PhraseId);
        Assert.True(periodic.IsScheduled);
    }

    [Fact]
    public void SequentialPeriodicOrderWrapsAround()
    {
        var periodic = new ManualScheduler();
        var dismissal = new ManualScheduler();
        var presentations = new List<PetSpeechPresentation?>();
        PetSpeechPhrase first = Phrase(
            "하나",
            new PetSpeechTrigger.Periodic(),
            PetSpeechDisplayMode.UntilNextPhrase);
        PetSpeechPhrase second = Phrase(
            "둘",
            new PetSpeechTrigger.Periodic(),
            PetSpeechDisplayMode.UntilNextPhrase);
        PetSpeechSettings settings = Settings([first, second], periodic: true) with
        {
            PeriodicOrder = PetSpeechPeriodicOrder.Sequential,
        };
        using var runtime = Runtime(periodic, dismissal, presentations);
        runtime.Update(settings);
        runtime.SetAwake(true);

        periodic.Fire();
        periodic.Fire();
        periodic.Fire();

        Assert.Equal([first.Id, second.Id, first.Id], presentations.Select(value => value!.PhraseId));
    }

    [Fact]
    public void BehaviorPhraseUntilNextSchedulesPeriodicReplacement()
    {
        var periodic = new ManualScheduler();
        var dismissal = new ManualScheduler();
        var presentations = new List<PetSpeechPresentation?>();
        PetSpeechPhrase behavior = Phrase(
            "집중 중이에요",
            new PetSpeechTrigger.Sequence("focus"),
            PetSpeechDisplayMode.UntilNextPhrase);
        PetSpeechPhrase periodicPhrase = Phrase(
            "잠깐 쉬어도 좋아요",
            new PetSpeechTrigger.Periodic(),
            PetSpeechDisplayMode.UntilNextPhrase);
        using var runtime = Runtime(periodic, dismissal, presentations, (phrases, _) => phrases[0]);
        runtime.Update(Settings([behavior, periodicPhrase], periodic: true));
        runtime.SetAwake(true);

        runtime.BehaviorSequenceDidChange("focus");

        Assert.True(periodic.IsScheduled);
        Assert.Equal(TimeSpan.FromSeconds(60), periodic.Delay);
        periodic.Fire();
        Assert.Equal(periodicPhrase.Id, presentations[^1]!.PhraseId);
        Assert.True(periodic.IsScheduled);
    }

    [Fact]
    public void UpdatingPeriodicIntervalCancelsOldReservationAndUsesNewInterval()
    {
        var periodic = new ManualScheduler();
        var dismissal = new ManualScheduler();
        var presentations = new List<PetSpeechPresentation?>();
        PetSpeechPhrase phrase = Phrase("안녕하세요", new PetSpeechTrigger.Periodic());
        using var runtime = Runtime(periodic, dismissal, presentations, (phrases, _) => phrases[0]);
        runtime.Update(Settings([phrase], periodic: true));
        runtime.SetAwake(true);

        runtime.Update(Settings([phrase], periodic: true) with
        {
            PeriodicIntervalMilliseconds = 5_000,
        });

        Assert.True(periodic.IsScheduled);
        Assert.Equal(TimeSpan.FromSeconds(5), periodic.Delay);
    }

    [Fact]
    public void SleepAndSystemSuspensionCancelAndHideSpeech()
    {
        var periodic = new ManualScheduler();
        var dismissal = new ManualScheduler();
        var presentations = new List<PetSpeechPresentation?>();
        PetSpeechPhrase phrase = Phrase("안녕하세요", new PetSpeechTrigger.Periodic());
        using var runtime = Runtime(periodic, dismissal, presentations, (phrases, _) => phrases[0]);
        runtime.Update(Settings([phrase], periodic: true));
        runtime.SetAwake(true);
        periodic.Fire();

        runtime.SetSystemSuspended(true);

        Assert.Null(presentations[^1]);
        Assert.False(periodic.IsScheduled);
        Assert.False(dismissal.IsScheduled);

        runtime.SetSystemSuspended(false);
        Assert.True(periodic.IsScheduled);
        runtime.SetAwake(false);
        Assert.False(periodic.IsScheduled);
    }

    [Fact]
    public void PetChangeDismissesEvenWhenNextSettingsWouldMatch()
    {
        var periodic = new ManualScheduler();
        var dismissal = new ManualScheduler();
        var presentations = new List<PetSpeechPresentation?>();
        PetSpeechPhrase phrase = Phrase("안녕하세요", new PetSpeechTrigger.Periodic());
        using var runtime = Runtime(periodic, dismissal, presentations, (phrases, _) => phrases[0]);
        runtime.Update(Settings([phrase], periodic: true));
        runtime.SetAwake(true);
        periodic.Fire();

        runtime.PrepareForPetChange();

        Assert.Null(presentations[^1]);
        Assert.False(periodic.IsScheduled);
        Assert.False(dismissal.IsScheduled);
    }

    [Fact]
    public void PlacementUsesAboveThenFallsBelowAtTopEdge()
    {
        var visible = new PetSpeechBubbleRect(-1920, 0, 1920, 1080);
        var size = new PetSpeechBubbleSize(240, 80);
        var aboveParent = new PetSpeechBubbleRect(-1200, 400, 192, 192);
        var topParent = new PetSpeechBubbleRect(-1200, 10, 192, 192);

        PetSpeechBubblePlacementResult above = PetSpeechBubblePlacement.Calculate(
            aboveParent,
            size,
            visible,
            PetSpeechBubblePlacementSettings.Default);
        PetSpeechBubblePlacementResult below = PetSpeechBubblePlacement.Calculate(
            topParent,
            size,
            visible,
            PetSpeechBubblePlacementSettings.Default);

        Assert.Equal(PetSpeechBubbleTailEdge.Bottom, above.TailEdge);
        Assert.Equal(312, above.Origin.Y);
        Assert.Equal(PetSpeechBubbleTailEdge.Top, below.TailEdge);
        Assert.Equal(210, below.Origin.Y);
    }

    [Fact]
    public void AutomaticPlacementKeepsLockedSideForCurrentPresentation()
    {
        var visible = new PetSpeechBubbleRect(0, 0, 1000, 800);
        var size = new PetSpeechBubbleSize(240, 80);
        PetSpeechBubblePlacementResult initial = PetSpeechBubblePlacement.Calculate(
            new PetSpeechBubbleRect(400, 10, 100, 100),
            size,
            visible,
            PetSpeechBubblePlacementSettings.Default);
        PetSpeechBubblePlacementResult moved = PetSpeechBubblePlacement.Calculate(
            new PetSpeechBubbleRect(400, 400, 100, 100),
            size,
            visible,
            PetSpeechBubblePlacementSettings.Default,
            initial.TailEdge);

        Assert.Equal(PetSpeechBubbleTailEdge.Top, initial.TailEdge);
        Assert.Equal(PetSpeechBubbleTailEdge.Top, moved.TailEdge);
        Assert.Equal(508, moved.Origin.Y);
    }

    [Fact]
    public void PlacementClampsHorizontalOffsetAndPointsTailAtPet()
    {
        var parent = new PetSpeechBubbleRect(900, 500, 100, 100);
        var visible = new PetSpeechBubbleRect(0, 0, 1000, 800);
        var settings = PetSpeechBubblePlacementSettings.Default with
        {
            HorizontalOffset = 160,
        };

        PetSpeechBubblePlacementResult result = PetSpeechBubblePlacement.Calculate(
            parent,
            new PetSpeechBubbleSize(240, 80),
            visible,
            settings);

        Assert.Equal(760, result.Origin.X);
        Assert.Equal(190, result.TailAnchorX);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(8)]
    [InlineData(64)]
    public void VisibleTailKeepsItsHeightAndMovesWithBubble(double gap)
    {
        PetSpeechBubbleTailMetrics metrics = PetSpeechBubbleTailLayout.Calculate(
            showsTail: true,
            baseTailHeight: 13,
            gap);

        Assert.Equal(13, metrics.TailHeight);
        Assert.Equal(gap, metrics.PlacementGap);
    }

    [Fact]
    public void HiddenTailKeepsGapAsEmptyPlacementSpace()
    {
        PetSpeechBubbleTailMetrics metrics = PetSpeechBubbleTailLayout.Calculate(
            showsTail: false,
            baseTailHeight: 13,
            gap: 24);

        Assert.Equal(0, metrics.TailHeight);
        Assert.Equal(24, metrics.PlacementGap);
    }

    private static PetSpeechRuntime Runtime(
        ManualScheduler periodic,
        ManualScheduler dismissal,
        List<PetSpeechPresentation?> presentations,
        PetSpeechRuntime.PhrasePicker? picker = null) =>
        new(periodic, dismissal, presentations.Add, picker);

    private static PetSpeechSettings Settings(
        IReadOnlyList<PetSpeechPhrase> phrases,
        bool periodic = false) =>
        new(
            true,
            periodic,
            60_000,
            PetSpeechPeriodicOrder.Random,
            PetSpeechBehaviorChangePolicy.Dismiss,
            phrases,
            PetSpeechBubbleTheme.Default,
            PetSpeechBubblePlacementSettings.Default);

    private static PetSpeechPhrase Phrase(
        string text,
        PetSpeechTrigger trigger,
        PetSpeechDisplayMode displayMode = PetSpeechDisplayMode.Timed) =>
        new(Guid.NewGuid(), text, 3_000, trigger, displayMode);

    private sealed class ManualScheduler : IPetSpeechScheduler
    {
        private Action? _action;

        public TimeSpan? Delay { get; private set; }

        public bool IsScheduled => _action is not null;

        public void Schedule(TimeSpan delay, Action action)
        {
            Delay = delay;
            _action = action;
        }

        public void Cancel()
        {
            Delay = null;
            _action = null;
        }

        public void Fire()
        {
            Action action = _action ?? throw new InvalidOperationException("예약된 작업이 없습니다.");
            _action = null;
            Delay = null;
            action();
        }
    }
}
