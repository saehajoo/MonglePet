namespace MonglePet.Core.Movement;

public readonly record struct CursorAvoidingPhaseChange(
    bool EnteredEscaping,
    bool EnteredIdle);

public sealed class CursorAvoidingPhaseState
{
    public bool IsEscaping { get; private set; }

    public bool ShouldEscape(
        double distance,
        double detectionDistance,
        double releaseDistance,
        bool hasActiveEscapeTarget)
    {
        if (!double.IsFinite(distance) ||
            !double.IsFinite(detectionDistance) || detectionDistance < 0 ||
            !double.IsFinite(releaseDistance) || releaseDistance < detectionDistance)
        {
            return false;
        }

        return distance <= detectionDistance ||
            (IsEscaping &&
                (hasActiveEscapeTarget || distance < releaseDistance));
    }

    public CursorAvoidingPhaseChange Update(bool shouldEscape)
    {
        if (shouldEscape == IsEscaping)
        {
            return default;
        }

        IsEscaping = shouldEscape;
        return shouldEscape
            ? new CursorAvoidingPhaseChange(EnteredEscaping: true, EnteredIdle: false)
            : new CursorAvoidingPhaseChange(EnteredEscaping: false, EnteredIdle: true);
    }

    public void Reset() => IsEscaping = false;
}
