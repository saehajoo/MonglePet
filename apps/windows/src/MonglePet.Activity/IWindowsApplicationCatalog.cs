namespace MonglePet.Activity;

public interface IWindowsApplicationCatalog
{
    IReadOnlyList<WindowsApplicationChoice> GetRunningApplications();

    WindowsApplicationChoice InspectExecutable(string path);
}

public enum WindowsApplicationCatalogError
{
    NotExecutable,
    FileUnavailable,
    MonglePetCannotBeSelected,
}

public sealed class WindowsApplicationCatalogException(
    WindowsApplicationCatalogError error,
    string message,
    Exception? innerException = null) : Exception(message, innerException)
{
    public WindowsApplicationCatalogError Error { get; } = error;
}
