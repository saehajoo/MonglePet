namespace MonglePet.Shell;

public sealed class EditorDraftState
{
    private readonly Func<string> _fingerprint;
    private readonly string _initialFingerprint;

    public EditorDraftState(Func<string> fingerprint)
    {
        _fingerprint = fingerprint ?? throw new ArgumentNullException(nameof(fingerprint));
        _initialFingerprint = fingerprint();
    }

    public bool HasChanges => !string.Equals(
        _initialFingerprint,
        _fingerprint(),
        StringComparison.Ordinal);
}
