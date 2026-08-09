using MonglePet.Core.Behavior;

namespace MonglePet.Settings.Tests;

public sealed class BehaviorProfileEditorTests
{
    [Fact]
    public void AddsTrimmedUniqueSequenceWithDefaultStep()
    {
        BehaviorProfile result = BehaviorProfileEditor.AddSequence(Profile(), "  focus  ");
        BehaviorSequence sequence = Assert.Single(result.Sequences, value => value.Id == "focus");
        Assert.Equal(BehaviorMotionReferences.CurrentPetDefault, Assert.Single(sequence.Steps).MotionId);
        Assert.True(sequence.Repeats);
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
        BehaviorProfile profile = BehaviorProfileEditor.AddSequence(Profile(), "focus") with
        {
            ManualSequenceId = "focus",
            AutomaticRules =
            [
                new(Guid.NewGuid(), true, 1, new RuleCondition.IdleAtLeast(60_000), "focus"),
            ],
            Speech = PetSpeechSettings.Default with
            {
                Phrases =
                [
                    new(removedPhraseId, "focus", 3_000, new PetSpeechTrigger.Sequence("focus"), PetSpeechDisplayMode.Timed),
                    new(keptPhraseId, "periodic", 3_000, new PetSpeechTrigger.Periodic(), PetSpeechDisplayMode.Timed),
                ],
            },
        };

        BehaviorProfile result = BehaviorProfileEditor.RemoveSequence(profile, "focus");
        Assert.Equal(BehaviorMotionReferences.DefaultSequence, result.ManualSequenceId);
        Assert.Empty(result.AutomaticRules);
        Assert.Equal(keptPhraseId, Assert.Single(result.Speech.Phrases).Id);
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
            2,
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
    [InlineData(1441)]
    public void RejectsInvalidIdleRuleMinutes(int minutes)
    {
        BehaviorProfileEditException error = Assert.Throws<BehaviorProfileEditException>(() =>
            BehaviorProfileEditor.AddIdleRule(
                Profile(),
                minutes,
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
        PetBehaviorKey.BuiltInKey);
}
