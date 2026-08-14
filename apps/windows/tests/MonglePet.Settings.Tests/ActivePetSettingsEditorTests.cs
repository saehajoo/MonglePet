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
            Mode = BehaviorMode.Manual,
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
        Assert.Equal(BehaviorMode.Manual, added.SelectedBehaviorProfile!.Mode);
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
            Mode = BehaviorMode.Manual,
        };
        added = ActivePetSettingsEditor.SetBehaviorProfile(added, addedId, updatedProfile);
        added = ActivePetSettingsEditor.SetOverlay(
            added,
            addedId,
            added.SelectedPetInstance!.Overlay with { Width = 320 });

        ActivePetInstance source = added.ActivePetInstances.Single(value => value.InstanceId == sourceId);
        BehaviorProfile sourceProfile = added.BehaviorProfiles.Single(value => value.ProfileId == source.BehaviorProfileId);
        Assert.Equal(BehaviorMode.Automatic, sourceProfile.Mode);
        Assert.Equal(AppSettingsLimits.DefaultOverlayWidth, source.Overlay.Width);
        Assert.Equal(BehaviorMode.Manual, added.SelectedBehaviorProfile!.Mode);
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
}
