using MonglePet.Settings;

namespace MonglePet.Settings.Tests;

public sealed class FreeRoamingDwellPolicyTests
{
    [Fact]
    public void DisabledRandomRangeIgnoresHiddenEditorAndClampsStoredMinimum()
    {
        long minimum = FreeRoamingDwellPolicy.ResolveMinimum(
            maximumMilliseconds: 3_000,
            dwellMode: FreeRoamingDwellMode.Fixed,
            storedMinimumMilliseconds: 6_000,
            editedMinimumMilliseconds: 10_000);

        Assert.Equal(3_000, minimum);
    }

    [Fact]
    public void EnabledRandomRangeUsesEditedMinimum()
    {
        long minimum = FreeRoamingDwellPolicy.ResolveMinimum(
            maximumMilliseconds: 6_000,
            dwellMode: FreeRoamingDwellMode.Random,
            storedMinimumMilliseconds: 2_000,
            editedMinimumMilliseconds: 3_500);

        Assert.Equal(3_500, minimum);
    }

    [Fact]
    public void EnabledRandomRangeClampsEditedMinimumToMaximum()
    {
        long minimum = FreeRoamingDwellPolicy.ResolveMinimum(
            maximumMilliseconds: 2_500,
            dwellMode: FreeRoamingDwellMode.Random,
            storedMinimumMilliseconds: 1_000,
            editedMinimumMilliseconds: 4_000);

        Assert.Equal(2_500, minimum);
    }
}
