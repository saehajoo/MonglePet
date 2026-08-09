namespace MonglePet.Activity;

public interface IWindowsActivityReader
{
    TimeSpan ReadIdleDuration();

    string? ReadFrontmostApplicationId();
}
