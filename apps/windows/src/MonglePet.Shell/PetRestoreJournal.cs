using System.Text.Json;

namespace MonglePet.Shell;

public sealed record PetRestoreRecoveryState(
    Guid InstanceId,
    int DisplayOrder,
    DateTimeOffset StartedAtUtc);

public sealed class PetRestoreJournal(string path)
{
    public const int MaximumFileSize = 4 * 1024;

    public string Path { get; } = System.IO.Path.GetFullPath(
        path ?? throw new ArgumentNullException(nameof(path)));

    public PetRestoreRecoveryState? Load()
    {
        if (!File.Exists(Path))
        {
            return null;
        }
        var info = new FileInfo(Path);
        if (info.Length is <= 0 or > MaximumFileSize)
        {
            return new PetRestoreRecoveryState(Guid.Empty, -1, info.LastWriteTimeUtc);
        }

        try
        {
            JournalDocument? document = JsonSerializer.Deserialize<JournalDocument>(
                File.ReadAllText(Path));
            return document is { SchemaVersion: 1 } &&
                Guid.TryParse(document.InstanceId, out Guid instanceId) &&
                instanceId != Guid.Empty &&
                document.DisplayOrder >= 0
                    ? new PetRestoreRecoveryState(
                        instanceId,
                        document.DisplayOrder,
                        document.StartedAtUtc)
                    : new PetRestoreRecoveryState(Guid.Empty, -1, info.LastWriteTimeUtc);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or JsonException)
        {
            return new PetRestoreRecoveryState(Guid.Empty, -1, info.LastWriteTimeUtc);
        }
    }

    public void Begin(Guid instanceId, int displayOrder)
    {
        if (instanceId == Guid.Empty)
        {
            throw new ArgumentException("A non-empty instance identifier is required.", nameof(instanceId));
        }
        if (displayOrder < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(displayOrder));
        }

        string? directory = System.IO.Path.GetDirectoryName(Path);
        if (string.IsNullOrWhiteSpace(directory))
        {
            throw new InvalidOperationException("The restore journal path has no parent directory.");
        }
        Directory.CreateDirectory(directory);
        string temporaryPath = $"{Path}.{Guid.NewGuid():N}.tmp";
        try
        {
            string json = JsonSerializer.Serialize(new JournalDocument(
                1,
                instanceId.ToString("D"),
                displayOrder,
                DateTimeOffset.UtcNow));
            File.WriteAllText(temporaryPath, json);
            File.Move(temporaryPath, Path, overwrite: true);
        }
        finally
        {
            try
            {
                if (File.Exists(temporaryPath))
                {
                    File.Delete(temporaryPath);
                }
            }
            catch (IOException)
            {
            }
        }
    }

    public void Complete()
    {
        if (File.Exists(Path))
        {
            File.Delete(Path);
        }
    }

    private sealed record JournalDocument(
        int SchemaVersion,
        string InstanceId,
        int DisplayOrder,
        DateTimeOffset StartedAtUtc);
}
