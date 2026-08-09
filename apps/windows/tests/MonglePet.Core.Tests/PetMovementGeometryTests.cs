using MonglePet.Core.Movement;

namespace MonglePet.Core.Tests;

public sealed class PetMovementGeometryTests
{
    private static readonly MovementSize PetSize = new(100, 80);

    [Fact]
    public void SafeBoundsSupportNegativeDesktopCoordinates()
    {
        MovementOriginBounds? bounds = PetMovementGeometry.SafeOriginBounds(
            new MovementRect(-1920, -200, 1920, 1080),
            PetSize,
            10);

        Assert.Equal(new MovementOriginBounds(-1910, -110, -190, 790), bounds);
    }

    [Fact]
    public void CursorFollowingKeepsConfiguredDistanceAndClampsToWorkArea()
    {
        MovementPoint? target = PetMovementGeometry.CursorFollowingTarget(
            new MovementPoint(900, 400),
            new MovementPoint(100, 100),
            PetSize,
            100,
            [new MovementScreen("display", new MovementRect(0, 0, 1000, 600))],
            0);

        Assert.NotNull(target);
        Assert.InRange(target.Value.X, 750, 760);
        Assert.InRange(target.Value.Y, 320, 335);
    }

    [Fact]
    public void FreeRoamingUsesDeterministicScreenAndCoordinates()
    {
        MovementPoint? target = PetMovementGeometry.FreeRoamingTarget(
            [
                new MovementScreen("left", new MovementRect(-1000, 0, 1000, 800)),
                new MovementScreen("right", new MovementRect(0, 0, 1200, 900)),
            ],
            PetSize,
            new MovementRandomSample(0.75, 0.25, 0.5),
            0);

        Assert.Equal(new MovementPoint(275, 410), target);
    }

    [Fact]
    public void FreeRoamingPrefersWindowIntersectionWithWorkArea()
    {
        MovementPoint? target = PetMovementGeometry.FreeRoamingTarget(
            [new MovementScreen("display", new MovementRect(0, 0, 1000, 800))],
            PetSize,
            new MovementRandomSample(0.9, 0, 1),
            inset: 8,
            preferredWindow: new MovementRect(200, 100, 400, 300));

        Assert.Equal(new MovementPoint(200, 320), target);
    }

    [Fact]
    public void FreeRoamingFallsBackWhenPreferredWindowCannotFitPet()
    {
        MovementPoint? target = PetMovementGeometry.FreeRoamingTarget(
            [new MovementScreen("display", new MovementRect(0, 0, 1000, 800))],
            PetSize,
            new MovementRandomSample(0, 0.5, 0.5),
            inset: 0,
            preferredWindow: new MovementRect(200, 100, 50, 50));

        Assert.Equal(new MovementPoint(450, 360), target);
    }

    [Fact]
    public void CursorAvoidingChoosesAValidPointFartherFromPointer()
    {
        var pointer = new MovementPoint(520, 440);
        var origin = new MovementPoint(500, 400);
        IReadOnlyList<MovementScreen> screens =
            [new MovementScreen("display", new MovementRect(0, 0, 1000, 800))];

        MovementPoint? target = PetMovementGeometry.CursorAvoidingTarget(
            pointer,
            origin,
            PetSize,
            180,
            screens,
            0);

        Assert.NotNull(target);
        Assert.True(
            PetMovementGeometry.DistanceFromPointerToPet(pointer, target.Value, PetSize) >=
            PetMovementGeometry.DistanceFromPointerToPet(pointer, origin, PetSize));
        Assert.InRange(target.Value.X, 0, 900);
        Assert.InRange(target.Value.Y, 0, 720);
    }

    [Fact]
    public void AdvanceUsesSpeedElapsedTimeAndStopRadius()
    {
        MovementAdvance moving = PetMovementGeometry.Advance(
            new MovementPoint(0, 0),
            new MovementPoint(100, 0),
            40,
            0.5,
            5);
        MovementAdvance arrived = PetMovementGeometry.Advance(
            new MovementPoint(96, 0),
            new MovementPoint(100, 0),
            40,
            0.5,
            5);

        Assert.Equal(new MovementPoint(20, 0), moving.Origin);
        Assert.True(moving.DidMove);
        Assert.False(moving.HasArrived);
        Assert.False(arrived.DidMove);
        Assert.True(arrived.HasArrived);
    }

    [Fact]
    public void PositionAccumulatorPreservesSubPixelProgressAtSlowSpeed()
    {
        var accumulator = new MovementPositionAccumulator(new MovementPoint(0, 0));

        for (int tick = 0; tick < 100; tick++)
        {
            accumulator.Advance(
                new MovementPoint(100, 0),
                speed: 20,
                elapsedSeconds: 0.016,
                stopRadius: 0);
        }

        Assert.Equal(32, accumulator.Origin.X, precision: 8);
        Assert.Equal((32, 0), accumulator.RoundedPixelOrigin());
    }

    [Fact]
    public void PositionAccumulatorCanAdvanceAcrossMonitorGap()
    {
        var accumulator = new MovementPositionAccumulator(new MovementPoint(900, 100));
        var target = new MovementPoint(2100, 100);

        for (int tick = 0; tick < 120; tick++)
        {
            accumulator.Advance(target, speed: 300, elapsedSeconds: 0.05, stopRadius: 0);
        }

        Assert.Equal(target, accumulator.Origin);
    }

    [Theory]
    [InlineData(-10, 0, false, MovementDirection.Left)]
    [InlineData(10, 0, false, MovementDirection.Right)]
    [InlineData(0, -10, false, MovementDirection.Up)]
    [InlineData(0, 10, false, MovementDirection.Down)]
    [InlineData(10, -10, true, MovementDirection.UpRight)]
    [InlineData(-10, 10, true, MovementDirection.DownLeft)]
    public void DirectionUsesWindowsTopLeftCoordinateSystem(
        double deltaX,
        double deltaY,
        bool diagonals,
        MovementDirection expected)
    {
        Assert.Equal(expected, PetMovementGeometry.Direction(deltaX, deltaY, diagonals));
    }
}
