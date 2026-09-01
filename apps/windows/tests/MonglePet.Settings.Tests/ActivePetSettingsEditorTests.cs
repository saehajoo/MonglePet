using MonglePet.Core.Behavior;
using MonglePet.Settings;

namespace MonglePet.Settings.Tests;

public sealed class ActivePetSettingsEditorTests
{
    [Fact]
    public void AddsSamePetWithIndependentCopiedProfileAndOffsetOverlay()
    {
        AppSettings original = AppSettings.CreateDefault(() => Guid.NewGuid());
        ActivePetInstance source = original.SelectedPetInstance!;
        BehaviorProfile sourceProfile = original.SelectedBehaviorProfile! with
        {
            StationaryBehaviorMode = StationaryBehaviorMode.Random,
        };
        original = original.WithSelectedBehaviorProfile(sourceProfile);
        Guid newInstanceId = Guid.NewGuid();
        Guid newProfileId = Guid.NewGuid();
        var ids = new Queue<Guid>([newInstanceId, newProfileId]);

        AppSettings added = ActivePetSettingsEditor.AddSamePet(
            original,
            copiesSelectedSettings: true,
            () => ids.Dequeue());

        Assert.Equal(2, added.ActivePetInstances.Count);
        Assert.Equal(newInstanceId, added.SelectedPetInstanceId);
        ActivePetInstance instance = added.SelectedPetInstance!;
        Assert.Equal(newProfileId, instance.BehaviorProfileId);
        Assert.Equal(source.PetKey, instance.PetKey);
        Assert.Equal(source.Overlay.OriginX + 24, instance.Overlay.OriginX);
        Assert.Equal(0, instance.DisplayOrder);
        Assert.Equal(1, added.ActivePetInstances.Single(value => value.InstanceId == source.InstanceId).DisplayOrder);
        Assert.Equal(StationaryBehaviorMode.Random, added.SelectedBehaviorProfile!.StationaryBehaviorMode);
        Assert.NotEqual(sourceProfile.ProfileId, added.SelectedBehaviorProfile.ProfileId);
    }

    [Fact]
    public void EditingOneInstanceDoesNotChangeTheOtherInstance()
    {
        AppSettings original = AppSettings.CreateDefault();
        Guid sourceId = original.SelectedPetInstanceId;
        AppSettings added = ActivePetSettingsEditor.AddSamePet(original, true);
        Guid addedId = added.SelectedPetInstanceId;
        BehaviorProfile updatedProfile = added.SelectedBehaviorProfile! with
        {
            StationaryBehaviorMode = StationaryBehaviorMode.Random,
        };
        added = ActivePetSettingsEditor.SetBehaviorProfile(added, addedId, updatedProfile);
        added = ActivePetSettingsEditor.SetOverlay(
            added,
            addedId,
            added.SelectedPetInstance!.Overlay with { Width = 320 });

        ActivePetInstance source = added.ActivePetInstances.Single(value => value.InstanceId == sourceId);
        BehaviorProfile sourceProfile = added.BehaviorProfiles.Single(value => value.ProfileId == source.BehaviorProfileId);
        Assert.Equal(StationaryBehaviorMode.Fixed, sourceProfile.StationaryBehaviorMode);
        Assert.Equal(AppSettingsLimits.DefaultOverlayWidth, source.Overlay.Width);
        Assert.Equal(StationaryBehaviorMode.Random, added.SelectedBehaviorProfile!.StationaryBehaviorMode);
        Assert.Equal(320, added.SelectedPetInstance!.Overlay.Width);
    }

    [Fact]
    public void ReordersAndRenumbersDisplayOrder()
    {
        AppSettings settings = ActivePetSettingsEditor.AddSamePet(AppSettings.CreateDefault(), false);
        Guid moving = settings.ActivePetInstances.OrderBy(value => value.DisplayOrder).Last().InstanceId;

        AppSettings reordered = ActivePetSettingsEditor.Move(settings, moving, 0);

        Assert.Equal(moving, reordered.ActivePetInstances.OrderBy(value => value.DisplayOrder).First().InstanceId);
        Assert.Equal([0, 1], reordered.ActivePetInstances.OrderBy(value => value.DisplayOrder).Select(value => value.DisplayOrder));
    }

    [Fact]
    public void RemovingSelectedInstanceKeepsOneAndDropsOnlyItsProfile()
    {
        AppSettings settings = ActivePetSettingsEditor.AddSamePet(AppSettings.CreateDefault(), true);
        Guid removingId = settings.SelectedPetInstanceId;
        Guid removingProfileId = settings.SelectedPetInstance!.BehaviorProfileId;

        AppSettings removed = ActivePetSettingsEditor.Remove(settings, removingId);

        Assert.Single(removed.ActivePetInstances);
        Assert.DoesNotContain(removed.BehaviorProfiles, value => value.ProfileId == removingProfileId);
        Assert.Equal(removed.ActivePetInstances[0].InstanceId, removed.SelectedPetInstanceId);
    }

    [Fact]
    public void RefusesToRemoveTheLastActivePet()
    {
        AppSettings settings = AppSettings.CreateDefault();

        Assert.Throws<InvalidOperationException>(() =>
            ActivePetSettingsEditor.Remove(settings, settings.SelectedPetInstanceId));
    }

    [Fact]
    public void ReplacesEveryReferenceToDeletedInstallationWithIndependentProfiles()
    {
        Guid installationId = Guid.NewGuid();
        AppSettings settings = AppSettings.CreateDefault();
        settings = ActivePetSettingsEditor.ReplacePet(
            settings,
            settings.SelectedPetInstanceId,
            new PetBehaviorKey.Installed(installationId));
        settings = ActivePetSettingsEditor.AddSamePet(settings, true);

        AppSettings replaced = ActivePetSettingsEditor.ReplaceAllPetReferences(
            settings,
            new PetBehaviorKey.Installed(installationId),
            PetBehaviorKey.BuiltInKey);

        Assert.All(replaced.ActivePetInstances, instance =>
            Assert.Equal(PetBehaviorKey.BuiltInKey, instance.PetKey));
        Assert.Equal(2, replaced.ActivePetInstances.Select(value => value.BehaviorProfileId).Distinct().Count());
        Assert.All(replaced.ActivePetInstances, instance =>
            Assert.Contains(replaced.BehaviorProfiles, profile =>
                profile.ProfileId == instance.BehaviorProfileId &&
                profile.PetKey == PetBehaviorKey.BuiltInKey));
    }

    [Fact]
    public void ReplacingPetForEditableCopyPreservesTheCompleteSelectedProfile()
    {
        AppSettings settings = AppSettings.CreateDefault();
        ActivePetInstance sourceInstance = settings.SelectedPetInstance!;
        BehaviorProfile source = settings.SelectedBehaviorProfile! with
        {
            StationaryBehaviorMode = StationaryBehaviorMode.Random,
            StationarySequenceId = BuiltInBehaviorProfileDefaults.SleepSequenceId,
            RandomSequenceIds =
            [
                BuiltInBehaviorProfileDefaults.SleepSequenceId,
                BuiltInBehaviorProfileDefaults.WorkSequenceId,
            ],
            Movement = settings.SelectedBehaviorProfile!.Movement with
            {
                Mode = PetMovementMode.FreeRoaming,
            },
            Speech = settings.SelectedBehaviorProfile!.Speech with
            {
                IsEnabled = true,
            },
        };
        settings = settings.WithSelectedBehaviorProfile(source);
        Guid copiedInstallationId = Guid.NewGuid();
        Guid copiedProfileId = Guid.NewGuid();
        var copiedPetKey = new PetBehaviorKey.Installed(copiedInstallationId);

        AppSettings copied = ActivePetSettingsEditor.ReplacePetCopyingProfile(
            settings,
            sourceInstance.InstanceId,
            copiedPetKey,
            source,
            () => copiedProfileId);

        Assert.Equal(sourceInstance.Overlay, copied.SelectedPetInstance!.Overlay);
        Assert.Equal(copiedPetKey, copied.SelectedPetInstance.PetKey);
        Assert.Equal(copiedProfileId, copied.SelectedPetInstance.BehaviorProfileId);
        Assert.Equal(
            source with { ProfileId = copiedProfileId, PetKey = copiedPetKey },
            copied.SelectedBehaviorProfile);
        Assert.DoesNotContain(copied.BehaviorProfiles, profile =>
            profile.ProfileId == source.ProfileId);
    }

    [Fact]
    public void ReassigningSharedPetKeepsInstanceProfileOverlayAndSettings()
    {
        AppSettings settings = AppSettings.CreateDefault();
        ActivePetInstance originalInstance = settings.SelectedPetInstance!;
        BehaviorProfile originalProfile = settings.SelectedBehaviorProfile! with
        {
            Speech = settings.SelectedBehaviorProfile!.Speech with { IsEnabled = true },
        };
        settings = settings.WithSelectedBehaviorProfile(originalProfile);
        var replacement = new PetBehaviorKey.Installed(Guid.NewGuid());

        AppSettings reassigned = ActivePetSettingsEditor.ReassignPetKeepingIdentity(
            settings,
            originalInstance.InstanceId,
            replacement);

        Assert.Equal(originalInstance.InstanceId, reassigned.SelectedPetInstanceId);
        Assert.Equal(originalInstance.BehaviorProfileId, reassigned.SelectedPetInstance!.BehaviorProfileId);
        Assert.Equal(originalInstance.Overlay, reassigned.SelectedPetInstance.Overlay);
        Assert.Equal(replacement, reassigned.SelectedPetInstance.PetKey);
        Assert.Equal(originalProfile.ProfileId, reassigned.SelectedBehaviorProfile!.ProfileId);
        Assert.Equal(replacement, reassigned.SelectedBehaviorProfile.PetKey);
        Assert.True(reassigned.SelectedBehaviorProfile.Speech.IsEnabled);
    }

    [Fact]
    public void RecoversEachOrphanOnceAsSleepingAndReusesUnreferencedProfile()
    {
        Guid installationId = Guid.NewGuid();
        var petKey = new PetBehaviorKey.Installed(installationId);
        Guid profileId = Guid.NewGuid();
        AppSettings settings = AppSettings.CreateDefault();
        settings = settings with
        {
            BehaviorProfiles =
            [
                .. settings.BehaviorProfiles,
                BehaviorProfileDefaults.Create(petKey, profileId),
            ],
        };
        Guid selectedId = settings.SelectedPetInstanceId;

        AppSettings recovered = ActivePetSettingsEditor.RecoverUnreferencedInstallations(
            settings,
            [installationId]);
        AppSettings recoveredAgain = ActivePetSettingsEditor.RecoverUnreferencedInstallations(
            recovered,
            [installationId]);

        ActivePetInstance instance = Assert.Single(
            recovered.ActivePetInstances,
            value => value.PetKey == petKey);
        Assert.Equal(profileId, instance.BehaviorProfileId);
        Assert.Equal(PetPresentation.TuckedAway, instance.Presentation);
        Assert.Equal(selectedId, recovered.SelectedPetInstanceId);
        Assert.Equal(recovered, recoveredAgain);
    }
}
