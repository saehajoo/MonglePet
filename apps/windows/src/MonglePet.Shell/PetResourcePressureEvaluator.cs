namespace MonglePet.Shell;

public sealed record PetResourceSample(
    double CpuPercent,
    long PrivateMemoryBytes,
    int ActivePetCount,
    int MovingPetCount);

public sealed record PetResourceWarning(
    PetResourceSample Sample,
    bool CpuPressure,
    bool MemoryPressure);

public sealed class PetResourcePressureEvaluator(
    double cpuWarningPercent = 30,
    long privateMemoryWarningBytes = 512L * 1024 * 1024,
    int consecutiveSamples = 3)
{
    private int _pressureCount;

    public PetResourceWarning? Observe(PetResourceSample sample)
    {
        ArgumentNullException.ThrowIfNull(sample);
        bool cpuPressure = double.IsFinite(sample.CpuPercent) &&
            sample.CpuPercent >= cpuWarningPercent;
        bool memoryPressure = sample.PrivateMemoryBytes >= privateMemoryWarningBytes;
        bool observesMultiplePets = sample.ActivePetCount >= 2;
        if (!observesMultiplePets || (!cpuPressure && !memoryPressure))
        {
            _pressureCount = 0;
            return null;
        }

        _pressureCount++;
        return _pressureCount >= consecutiveSamples
            ? new PetResourceWarning(sample, cpuPressure, memoryPressure)
            : null;
    }

    public void Reset() => _pressureCount = 0;
}
