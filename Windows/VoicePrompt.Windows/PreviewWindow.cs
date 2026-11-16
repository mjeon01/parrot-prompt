using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace VoicePrompt.Windows;

internal sealed class PreviewWindow : Window
{
    private readonly TextBlock title = new() { FontWeight = FontWeights.SemiBold, FontSize = 14 };
    private readonly TextBlock text = new() { FontSize = 16, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 12, 0, 12) };
    public PreviewWindow()
    {
        Width = 400; Height = 230; ShowActivated = false; ShowInTaskbar = false; Topmost = true;
        WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
        FontFamily = new FontFamily("Malgun Gothic");
        var panel = new DockPanel();
        DockPanel.SetDock(title, Dock.Top); panel.Children.Add(title);
        var hint = new TextBlock { Text = "Ctrl + Shift + Space 완료 · Ctrl + Shift + Esc 취소", FontSize = 12, Foreground = Brushes.DimGray };
        DockPanel.SetDock(hint, Dock.Bottom); panel.Children.Add(hint);
        panel.Children.Add(new ScrollViewer { Content = text, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
        Content = new Border { Padding = new Thickness(20), BorderThickness = new Thickness(1), BorderBrush = Brushes.SeaGreen, Background = Brushes.White, Child = panel };
    }
    public void Update(string status, string transcript)
    {
        title.Text = status; text.Text = transcript;
        if (!IsVisible)
        {
            var area = SystemParameters.WorkArea;
            Left = area.Right - Width - 24; Top = area.Bottom - Height - 24;
            Show();
        }
    }
}
