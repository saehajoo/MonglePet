namespace MonglePet.Core.Behavior;

public sealed class RandomBehaviorSelector
{
    private readonly BehaviorShuffleBag _bag;

    public RandomBehaviorSelector(Random? random = null)
    {
        _bag = new BehaviorShuffleBag(random);
    }

    public string? CurrentSequenceId { get; private set; }

    public string? Update(IEnumerable<string> availableSequenceIds, bool sequenceCompleted)
    {
        ArgumentNullException.ThrowIfNull(availableSequenceIds);
        string[] available = availableSequenceIds
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .Distinct(StringComparer.Ordinal)
            .ToArray();
        if (available.Length == 0)
        {
            Reset();
            return null;
        }

        if (sequenceCompleted ||
            CurrentSequenceId is null ||
            !available.Contains(CurrentSequenceId, StringComparer.Ordinal))
        {
            CurrentSequenceId = _bag.Next(available);
        }
        return CurrentSequenceId;
    }

    public void Reset()
    {
        CurrentSequenceId = null;
        _bag.Reset();
    }
}
