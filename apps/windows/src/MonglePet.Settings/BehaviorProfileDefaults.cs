using MonglePet.Core.Behavior;

namespace MonglePet.Settings;

public static class BehaviorProfileDefaults
{
    public static BehaviorProfile Create(PetBehaviorKey petKey, Guid? profileId = null)
    {
        ArgumentNullException.ThrowIfNull(petKey);
        var defaultSequence = new BehaviorSequence(
            BehaviorMotionReferences.DefaultSequence,
            [new BehaviorStep(BehaviorMotionReferences.CurrentPetDefault, 1)],
            true);
        return new BehaviorProfile(
            profileId is { } id && id != Guid.Empty ? id : Guid.NewGuid(),
            petKey,
            BehaviorMode.Automatic,
            defaultSequence.Id,
            [defaultSequence],
            [],
            PetMovementSettings.Default,
            null,
            PetSpeechSettings.Default);
    }

    public static PetBehaviorKey KeyForInstallation(Guid? installationId) =>
        installationId is Guid id
            ? new PetBehaviorKey.Installed(id)
            : PetBehaviorKey.BuiltInKey;
}
