using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace MonglePet.Windows;

public sealed partial class QuickGuideControl : UserControl
{
    private static readonly Uri WebGuideUri =
        new("https://mapleroom.kr/monglepet/guide");

    public QuickGuideControl()
    {
        InitializeComponent();
    }

    private void GuideTermsGrid_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        // SizeChanged can be raised while InitializeComponent is still assigning
        // the named child fields. Wait for the complete visual tree before
        // applying the responsive two-column layout.
        if (GuideTermAnimation is null ||
            GuideTermBehavior is null ||
            GuideTermStationary is null ||
            GuideTermRules is null ||
            GuideTermCreatorSettings is null)
        {
            return;
        }

        bool wide = e.NewSize.Width >= 640;
        Grid.SetRow(GuideTermAnimation, 0);
        Grid.SetColumn(GuideTermAnimation, 0);
        Grid.SetColumnSpan(GuideTermAnimation, 1);
        Grid.SetRow(GuideTermBehavior, wide ? 0 : 1);
        Grid.SetColumn(GuideTermBehavior, wide ? 1 : 0);
        Grid.SetColumnSpan(GuideTermBehavior, 1);
        Grid.SetRow(GuideTermStationary, wide ? 1 : 2);
        Grid.SetColumn(GuideTermStationary, 0);
        Grid.SetColumnSpan(GuideTermStationary, 1);
        Grid.SetRow(GuideTermRules, wide ? 1 : 3);
        Grid.SetColumn(GuideTermRules, wide ? 1 : 0);
        Grid.SetColumnSpan(GuideTermRules, 1);
        Grid.SetRow(GuideTermCreatorSettings, wide ? 2 : 4);
        Grid.SetColumn(GuideTermCreatorSettings, 0);
        Grid.SetColumnSpan(GuideTermCreatorSettings, wide ? 2 : 1);
    }

    public event EventHandler<string>? SectionRequested;

    private void SectionButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string section })
        {
            SectionRequested?.Invoke(this, section);
        }
    }

    private async void OpenWebGuideButton_Click(object sender, RoutedEventArgs e)
    {
        bool opened = false;
        try
        {
            opened = await global::Windows.System.Launcher.LaunchUriAsync(WebGuideUri);
        }
        catch
        {
        }
        WebGuideErrorInfoBar.IsOpen = !opened;
    }
}
