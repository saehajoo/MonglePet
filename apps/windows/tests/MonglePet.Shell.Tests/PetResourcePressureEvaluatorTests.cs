using MonglePet.Shell;

namespace MonglePet.Shell.Tests;

public sealed class PetResourcePressureEvaluatorTests
{
    [Fact]
    public void WarnsOnlyAfterSustainedPressureWithMultiplePets()
    {
        var evaluator = new PetResourcePressureEvaluator(consecutiveSamples: 3);
        var pressure = new PetResourceSample(35, 128 * 1024 * 1024, 3, 2);

        Assert.Null(evaluator.Observe(pressure));
        Assert.Null(evaluator.Observe(pressure));
        PetResourceWarning warning = Assert.IsType<PetResourceWarning>(evaluator.Observe(pressure));

        Assert.True(warning.CpuPressure);
        Assert.False(warning.MemoryPressure);
    }

    [Fact]
    public void DoesNotWarnOrCarryPressureForOnePet()
    {
        var evaluator = new PetResourcePressureEvaluator(consecutiveSamples: 2);
        var pressure = new PetResourceSample(50, 1024L * 1024 * 1024, 1, 1);

        Assert.Null(evaluator.Observe(pressure));
        Assert.Null(evaluator.Observe(pressure with { ActivePetCount = 2 }));
    }
}
