using MonglePet.Shell;

namespace MonglePet.Shell.Tests;

public sealed class PetScreenPlacementCalculatorTests
{
    [Fact]
    public void PlacesPetAtBottomRightInsideWorkArea()
    {
        var workArea = new MonitorWorkArea("DISPLAY1", 0, 0, 1920, 1040);

        PetScreenPlacement result = PetScreenPlacementCalculator.BottomRight(
            workArea,
            160,
            173);

        Assert.Equal(new PetScreenPlacement("DISPLAY1", 1712, 827), result);
    }

    [Fact]
    public void SupportsNegativeVirtualDesktopCoordinates()
    {
        var workArea = new MonitorWorkArea("DISPLAY2", -1920, -200, 0, 880);

        PetScreenPlacement result = PetScreenPlacementCalculator.BottomRight(
            workArea,
            200,
            220);

        Assert.Equal(new PetScreenPlacement("DISPLAY2", -248, 620), result);
    }

    [Fact]
    public void ClampsRestoredPositionInsideWorkArea()
    {
        var workArea = new MonitorWorkArea("DISPLAY1", 100, 50, 1100, 850);

        PetScreenPlacement result = PetScreenPlacementCalculator.Clamp(
            workArea,
            -500,
            900,
            160,
            180);

        Assert.Equal(new PetScreenPlacement("DISPLAY1", 100, 670), result);
    }

    [Fact]
    public void KeepsOversizedPetAnchoredAtWorkAreaOrigin()
    {
        var workArea = new MonitorWorkArea("DISPLAY1", -100, -50, 100, 150);

        PetScreenPlacement result = PetScreenPlacementCalculator.Clamp(
            workArea,
            500,
            500,
            300,
            300);

        Assert.Equal(new PetScreenPlacement("DISPLAY1", -100, -50), result);
    }
}
