using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;

namespace VoicePrompt.Windows;

internal sealed class PreviewWindow : Window
{
    private readonly TextBlock title = new() { FontWeight = FontWeights.SemiBold, FontSize = 14 };
    private readonly TextBlock text = new() { FontSize = 16, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 12, 0, 12) };
    private readonly TextBlock hint = new() { FontSize = 12, Foreground = Brushes.DimGray };
    private readonly DispatcherTimer dismiss = new() { Interval = TimeSpan.FromSeconds(6) };
    public PreviewWindow()
    {
        Width = 400; Height = 230; ShowActivated = false; ShowInTaskbar = false; Topmost = true;
        WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
        FontFamily = new FontFamily("Malgun Gothic");
        var panel = new DockPanel();
        DockPanel.SetDock(title, Dock.Top); panel.Children.Add(title);
        DockPanel.SetDock(hint, Dock.Bottom); panel.Children.Add(hint);
        panel.Children.Add(new ScrollViewer { Content = text, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
        Content = new Border { Padding = new Thickness(20), BorderThickness = new Thickness(1), BorderBrush = Brushes.SeaGreen, Background = Brushes.White, Child = panel };
        dismiss.Tick += (_, _) => { dismiss.Stop(); Hide(); };
    }
    public void Update(string status, string transcript, bool autoHide = false)
    {
        dismiss.Stop();
        title.Text = status; text.Text = transcript;
        hint.Text = autoHide ? "결과는 VoicePrompt 창에서 다시 확인할 수 있어요." : "Ctrl + Shift + Space 완료 · Ctrl + Shift + Esc 취소";
        if (!IsVisible)
        {
            var area = SystemParameters.WorkArea;
            Left = area.Right - Width - 24; Top = area.Bottom - Height - 24;
            Show();
        }
        if (autoHide) dismiss.Start();
    }
}
