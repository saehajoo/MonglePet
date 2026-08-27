namespace MonglePet.Core.Behavior;

public sealed class BehaviorShuffleBag
{
    private readonly Random _random;
    private readonly List<string> _remaining = [];
    private string[] _source = [];
    private string? _last;

    public BehaviorShuffleBag(Random? random = null)
    {
        _random = random ?? Random.Shared;
    }

    public string? Next(IEnumerable<string> sequenceIds)
    {
        ArgumentNullException.ThrowIfNull(sequenceIds);
        string[] source = sequenceIds
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .Distinct(StringComparer.Ordinal)
            .ToArray();
        if (!source.SequenceEqual(_source, StringComparer.Ordinal))
        {
            _source = source;
            _remaining.Clear();
            _last = null;
        }
        if (_source.Length == 0)
        {
            return null;
        }
        if (_remaining.Count == 0)
        {
            _remaining.AddRange(_source);
            Shuffle(_remaining);
            if (_remaining.Count > 1 && string.Equals(_remaining[^1], _last, StringComparison.Ordinal))
            {
                (_remaining[^1], _remaining[0]) = (_remaining[0], _remaining[^1]);
            }
        }
        string selected = _remaining[^1];
        _remaining.RemoveAt(_remaining.Count - 1);
        _last = selected;
        return selected;
    }

    public void Reset()
    {
        _source = [];
        _remaining.Clear();
        _last = null;
    }

    private void Shuffle(List<string> values)
    {
        for (int index = values.Count - 1; index > 0; index--)
        {
            int other = _random.Next(index + 1);
            (values[index], values[other]) = (values[other], values[index]);
        }
    }
}
