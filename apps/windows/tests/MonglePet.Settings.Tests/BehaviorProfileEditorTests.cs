using MonglePet.Core.Behavior;

namespace MonglePet.Settings.Tests;

public sealed class BehaviorProfileEditorTests
{
    [Fact]
    public void AnimationConnectionCreatesOrAppendsOneRepeatStep()
    {
        BehaviorProfile profile = Profile();

        BehaviorProfile created = BehaviorProfileEditor.AddSequenceForMotion(
            profile,
            "인사",
            "wave",
            Guid.Parse("11111111-2222-3333-4444-555555555555"));
        string createdId = created.Sequences[^1].Id;
        BehaviorProfile appended = BehaviorProfileEditor.AppendMotionStep(
            created,
            created.Sequences[0].Id,
            "wave");

        Assert.Equal("인사", created.Sequences[^1].DisplayName);
        Assert.Equal(new BehaviorStep("wave", 1), created.Sequences[^1].Steps.Single());
        Assert.Contains(createdId, created.Sequences.Select(sequence => sequence.Id));
        Assert.Equal(new BehaviorStep("wave", 1), appended.Sequences[0].Steps[^1]);
    }

    [Fact]
    public void AddsTrimmedUniqueSequenceWithDefaultStep()
    {
        Guid id = Guid.Parse("90000000-0000-0000-0000-000000000001");
        BehaviorProfile result = BehaviorProfileEditor.AddSequence(Profile(), "  focus  ", id);
        BehaviorSequence sequence = Assert.Single(result.Sequences, value => value.Id == id.ToString("D"));
        Assert.Equal("focus", sequence.DisplayName);
        Assert.Equal(BehaviorMotionReferences.CurrentPetDefault, Assert.Single(sequence.Steps).MotionId);
        Assert.False(sequence.Repeats);
    }

    [Fact]
    public void RejectsCaseInsensitiveDuplicateSequence()
    {
        BehaviorProfile profile = BehaviorProfileEditor.AddSequence(Profile(), "focus");
        BehaviorProfileEditException error = Assert.Throws<BehaviorProfileEditException>(() =>
            BehaviorProfileEditor.AddSequence(profile, "FOCUS"));
        Assert.Equal(BehaviorProfileEditError.DuplicateSequenceName, error.Error);
    }

    [Fact]
    public void ProtectsDefaultSequenceFromDeletion()
    {
        BehaviorProfileEditException error = Assert.Throws<BehaviorProfileEditException>(() =>
            BehaviorProfileEditor.RemoveSequence(
                Profile(),
                BehaviorMotionReferences.DefaultSequence));
        Assert.Equal(BehaviorProfileEditError.ProtectedSequence, error.Error);
    }

    [Fact]
    public void RemovingSequenceRepairsManualSelectionRulesAndSpeech()
    {
        Guid keptPhraseId = Guid.NewGuid();
        Guid removedPhraseId = Guid.NewGuid();
        BehaviorProfile added = BehaviorProfileEditor.AddSequence(Profile(), "focus");
        string focusId = added.Sequences.Single(sequence => sequence.DisplayName == "focus").Id;
        BehaviorProfile profile = added with
        {
            StationarySequenceId = focusId,
            AutomaticRules =
            [
                new(Guid.NewGuid(), true, 1, new RuleCondition.IdleAtLeast(60_000), focusId),
            ],
            Speech = PetSpeechSettings.Default with
            {
                Phrases =
                [
                    new(removedPhraseId, "focus", 3_000, new PetSpeechTrigger.Sequence(focusId), PetSpeechDisplayMode.Timed),
                    new(keptPhraseId, "periodic", 3_000, new PetSpeechTrigger.Periodic(), PetSpeechDisplayMode.Timed),
                ],
            },
        };

        BehaviorProfile result = BehaviorProfileEditor.RemoveSequence(profile, focusId);
        Assert.Null(result.StationarySequenceId);
        Assert.Empty(result.AutomaticRules);
        Assert.Equal(keptPhraseId, Assert.Single(result.Speech.Phrases).Id);
    }

    [Fact]
    public void RemovingUnreferencedSequencePreservesEveryIndependentMovementSetting()
    {
        BehaviorProfile added = BehaviorProfileEditor.AddSequence(Profile(), "unused");
        string unusedId = added.Sequences.Single(sequence => sequence.DisplayName == "unused").Id;
        PetMovementSettings movement = IndependentMovementSettings(
            BehaviorMotionReferences.DefaultSequence,
            "other");
        BehaviorProfile profile = added with { Movement = movement };

        BehaviorProfile result = BehaviorProfileEditor.RemoveSequence(profile, unusedId);

        Assert.Equal(movement, result.Movement);
        Assert.Equal(FreeRoamingDwellMode.BehaviorCompletion, result.Movement.FreeRoaming.DwellMode);
        Assert.Equal(
            FreeRoamingDwellMode.BehaviorCompletion,
            result.Movement.CursorAvoiding.IdleFreeRoaming.DwellMode);
    }

    [Fact]
    public void RemovingSequenceClearsLegacyPettingReference()
    {
        BehaviorProfile added = BehaviorProfileEditor.AddSequence(Profile(), "legacy petting");
        string sequenceId = added.Sequences.Single(sequence =>
            sequence.DisplayName == "legacy petting").Id;
        BehaviorProfile profile = added with
        {
            PettingBehaviorId = null,
            PettingMotionId = sequenceId,
        };

        BehaviorSequenceRemovalImpact impact =
            BehaviorProfileEditor.AnalyzeSequenceRemoval(profile, sequenceId);
        BehaviorProfile result = BehaviorProfileEditor.RemoveSequence(profile, sequenceId);

        Assert.True(impact.ClearsPettingBehavior);
        Assert.Null(result.PettingMotionId);
        Assert.Null(result.EffectivePettingBehaviorId);
    }

    [Fact]
    public void RemovalImpactAndCleanupOnlyContainMatchingReferences()
    {
        Guid ruleId = Guid.Parse("60000000-0000-0000-0000-000000000001");
        Guid removedPhraseId = Guid.Parse("60000000-0000-0000-0000-000000000002");
        Guid keptPhraseId = Guid.Parse("60000000-0000-0000-0000-000000000003");
        BehaviorProfile added = BehaviorProfileEditor.AddSequence(Profile(), "focus");
        string focusId = added.Sequences.Single(sequence => sequence.DisplayName == "focus").Id;
        PetMovementSettings movement = IndependentMovementSettings(focusId, "keep");
        BehaviorProfile profile = added with
        {
            StationaryBehaviorMode = StationaryBehaviorMode.Random,
            StationarySequenceId = focusId,
            RandomSequenceIds = [focusId, BehaviorMotionReferences.DefaultSequence],
            Movement = movement,
            PettingBehaviorId = focusId,
            AutomaticRules =
            [
                new(ruleId, true, 0, new RuleCondition.IdleAtLeast(1_000), focusId),
            ],
            Speech = PetSpeechSettings.Default with
            {
                IsEnabled = true,
                Phrases =
                [
                    new(removedPhraseId, "집중할게", 3_000, new PetSpeechTrigger.Sequence(focusId), PetSpeechDisplayMode.Timed),
                    new(keptPhraseId, "안녕", 3_000, new PetSpeechTrigger.Periodic(), PetSpeechDisplayMode.Timed),
                ],
            },
        };

        BehaviorSequenceRemovalImpact impact =
            BehaviorProfileEditor.AnalyzeSequenceRemoval(profile, focusId);
        BehaviorProfile result = BehaviorProfileEditor.RemoveSequence(profile, focusId);

        Assert.Equal("focus", impact.DisplayName);
        Assert.True(impact.ReplacesFixedStationarySelection);
        Assert.True(impact.RemovesRandomSelection);
        Assert.True(impact.ClearsPettingBehavior);
        Assert.Equal(ruleId, Assert.Single(impact.RemovedRules).Id);
        Assert.Equal(removedPhraseId, Assert.Single(impact.RemovedSpeechPhrases).Id);
        Assert.Equal(5, impact.MovementReferences.Count);
        Assert.Contains(impact.MovementReferences, reference =>
            reference == new BehaviorMovementReferenceImpact(
                BehaviorMovementReferenceContext.CursorFollowing,
                BehaviorMovementReferenceDirection.Common));
        Assert.Contains(impact.MovementReferences, reference =>
            reference.Context == BehaviorMovementReferenceContext.CursorAvoidingIdleFreeRoaming);

        Assert.Null(result.StationarySequenceId);
        Assert.Equal(
            new[] { BehaviorMotionReferences.DefaultSequence },
            result.RandomSequences);
        Assert.Null(result.PettingBehaviorId);
        Assert.Empty(result.AutomaticRules);
        Assert.Equal(keptPhraseId, Assert.Single(result.Speech.Phrases).Id);
        Assert.DoesNotContain(
            result.Movement.CursorFollowing.Behavior.DirectionBehaviorIds.All,
            id => id == focusId);
        Assert.Contains("keep", result.Movement.CursorFollowing.Behavior.DirectionBehaviorIds.All);
        Assert.Equal(movement.CursorFollowing.Speed, result.Movement.CursorFollowing.Speed);
        Assert.Equal(movement.CursorFollowing.CursorDistance, result.Movement.CursorFollowing.CursorDistance);
        Assert.Equal(movement.FreeRoaming.DwellMode, result.Movement.FreeRoaming.DwellMode);
        Assert.Equal(
            movement.CursorAvoiding.IdleFreeRoaming with
            {
                Behavior = movement.CursorAvoiding.IdleFreeRoaming.Behavior with
                {
                    FallbackBehaviorId = null,
                },
            },
            result.Movement.CursorAvoiding.IdleFreeRoaming);
    }

    [Fact]
    public void AddsEditsMovesAndRemovesSteps()
    {
        BehaviorProfile profile = BehaviorProfileEditor.AddStep(
            Profile(),
            BehaviorMotionReferences.DefaultSequence);
        profile = BehaviorProfileEditor.ReplaceStep(
            profile,
            BehaviorMotionReferences.DefaultSequence,
            1,
            new BehaviorStep("focus", 3));
        profile = BehaviorProfileEditor.MoveStep(
            profile,
            BehaviorMotionReferences.DefaultSequence,
            1,
            0);
        BehaviorSequence moved = profile.Sequences[0];
        Assert.Equal("focus", moved.Steps[0].MotionId);
        Assert.Equal(3, moved.Steps[0].RepeatCount);

        profile = BehaviorProfileEditor.RemoveStep(
            profile,
            BehaviorMotionReferences.DefaultSequence,
            1);
        Assert.Single(profile.Sequences[0].Steps);
    }

    [Fact]
    public void CannotRemoveOnlyStep()
    {
        BehaviorProfileEditException error = Assert.Throws<BehaviorProfileEditException>(() =>
            BehaviorProfileEditor.RemoveStep(
                Profile(),
                BehaviorMotionReferences.DefaultSequence,
                0));
        Assert.Equal(BehaviorProfileEditError.CannotRemoveLastStep, error.Error);
    }

    [Fact]
    public void ChangesSequenceRepeatingFlag()
    {
        BehaviorProfile result = BehaviorProfileEditor.SetSequenceRepeats(
            Profile(),
            BehaviorMotionReferences.DefaultSequence,
            false);
        Assert.False(result.Sequences[0].Repeats);
    }

    [Fact]
    public void AddsApplicationAndIdleRulesWithIncreasingPriority()
    {
        BehaviorProfile profile = BehaviorProfileEditor.AddApplicationRule(
            Profile(),
            "pfn:editor_123",
            BehaviorMotionReferences.DefaultSequence,
            Guid.Parse("10000000-0000-0000-0000-000000000001"));
        profile = BehaviorProfileEditor.AddIdleRule(
            profile,
            120,
            BehaviorMotionReferences.DefaultSequence,
            Guid.Parse("10000000-0000-0000-0000-000000000002"));
        Assert.Equal(0, profile.AutomaticRules[0].Priority);
        Assert.Equal(1, profile.AutomaticRules[1].Priority);
        Assert.Equal(120_000, Assert.IsType<RuleCondition.IdleAtLeast>(profile.AutomaticRules[1].Condition).Milliseconds);
    }

    [Fact]
    public void ReplacesAndRemovesRule()
    {
        Guid id = Guid.NewGuid();
        BehaviorProfile profile = BehaviorProfileEditor.AddIdleRule(
            Profile(),
            1,
            BehaviorMotionReferences.DefaultSequence,
            id);
        AutomaticRule edited = profile.AutomaticRules[0] with
        {
            IsEnabled = false,
            Priority = 50,
            Condition = new RuleCondition.Application("exe:notepad.exe"),
        };
        profile = BehaviorProfileEditor.ReplaceRule(profile, edited);
        Assert.Equal(edited, Assert.Single(profile.AutomaticRules));
        Assert.Empty(BehaviorProfileEditor.RemoveRule(profile, id).AutomaticRules);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(86401)]
    public void RejectsInvalidIdleRuleSeconds(int seconds)
    {
        BehaviorProfileEditException error = Assert.Throws<BehaviorProfileEditException>(() =>
            BehaviorProfileEditor.AddIdleRule(
                Profile(),
                seconds,
                BehaviorMotionReferences.DefaultSequence));
        Assert.Equal(BehaviorProfileEditError.InvalidRule, error.Error);
    }

    [Fact]
    public void RejectsRuleWithMissingTargetSequence()
    {
        BehaviorProfileEditException error = Assert.Throws<BehaviorProfileEditException>(() =>
            BehaviorProfileEditor.AddApplicationRule(Profile(), "exe:test.exe", "missing"));
        Assert.Equal(BehaviorProfileEditError.InvalidRule, error.Error);
    }

    private static BehaviorProfile Profile() => BehaviorProfileDefaults.Create(
        new PetBehaviorKey.Installed(
            Guid.Parse("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")));

    private static PetMovementSettings IndependentMovementSettings(
        string removedId,
        string keptId)
    {
        static MovementBehaviorSettings Behavior(
            string? common,
            string? left,
            string? right) => new(
                common,
                true,
                true,
                new DirectionalBehaviorIds(Left: left, Right: right));

        var following = new CursorFollowingMovementSettings(
            111,
            222,
            33,
            Behavior(removedId, removedId, keptId));
        var roaming = new FreeRoamingMovementSettings(
            144,
            25,
            9_500,
            FreeRoamingDwellMode.BehaviorCompletion,
            1_750,
            false,
            Behavior(keptId, removedId, keptId));
        var idleRoaming = new FreeRoamingMovementSettings(
            177,
            19,
            12_500,
            FreeRoamingDwellMode.BehaviorCompletion,
            2_250,
            true,
            Behavior(removedId, keptId, keptId));
        var avoiding = new CursorAvoidingMovementSettings(
            CursorAvoidingIdleBehavior.FreeRoaming,
            333,
            444,
            27,
            Behavior(keptId, keptId, removedId),
            idleRoaming);
        return PetMovementSettings.Default with
        {
            Mode = PetMovementMode.CursorAvoiding,
            Speed = 901,
            CursorDistance = 402,
            StopRadius = 71,
            FreeRoamingDwellMilliseconds = 44_000,
            PrefersFrontmostWindow = false,
            CursorAvoidingDetectionDistance = 708,
            CursorAvoidingSpeed = 812,
            CursorFollowingSettings = following,
            FreeRoamingSettings = roaming,
            CursorAvoidingSettings = avoiding,
        };
    }
}
