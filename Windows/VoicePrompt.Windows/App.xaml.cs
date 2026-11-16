using System.Windows;

namespace VoicePrompt.Windows;

public partial class App : Application
{
    private Mutex? singleInstance;
    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        if (e.Args.Length > 0)
        {
            try { Shutdown(await Diagnostics.RunAsync(e.Args)); }
            catch (Exception ex) { Console.Error.WriteLine(ex); Shutdown(1); }
            return;
        }
        singleInstance = new Mutex(true, "Local\\VoicePrompt.Windows", out var first);
        if (!first)
        {
            MessageBox.Show("VoicePrompt가 이미 실행 중입니다. 작업 표시줄의 숨겨진 아이콘을 확인해 주세요.", "VoicePrompt");
            Shutdown(); return;
        }
        var window = new MainWindow();
        MainWindow = window;
        window.Show();
    }
    protected override void OnExit(ExitEventArgs e) { singleInstance?.Dispose(); base.OnExit(e); }
}
