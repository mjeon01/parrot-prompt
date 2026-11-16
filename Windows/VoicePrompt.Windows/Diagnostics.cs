using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using VoicePrompt.Core;
using Whisper.net;

namespace VoicePrompt.Windows;

internal static class Diagnostics
{
    public static async Task<int> RunAsync(string[] args)
    {
        if (args[0] == "--version") return 0;
        if (args[0] == "--self-test" && args.Length == 2)
        {
            if (Marshal.SizeOf<Native.Input>() != 40) throw new InvalidOperationException("Unexpected x64 INPUT layout.");
            var input = Native.Unicode('한', false);
            if (input.Data.Keyboard.Key != 0 || input.Data.Keyboard.Scan != '한' || input.Data.Keyboard.Flags != 4)
                throw new InvalidOperationException("Unicode input encoding failed.");
            var window = new MainWindow();
            window.Measure(new Size(600, 750)); window.Arrange(new Rect(0, 0, 600, 750)); window.UpdateLayout();
            if (window.RecordButton.IsEnabled || window.CancelButton.IsEnabled) throw new InvalidOperationException("Recording must be disabled before preparation.");
            if (window.AutoInsert.IsChecked != true) throw new InvalidOperationException("Default preference mismatch.");
            File.WriteAllText(args[1], "PASS: x64 input layout, Unicode events, WPF construction and initial recording state.");
            return 0;
        }
        if (args[0] == "--render-preview" && args.Length == 2)
        {
            var window = new MainWindow();
            window.SetupStatus.Text = "준비 완료 · 인터넷 없이 사용할 수 있어요.";
            window.SetupExpander.Header = "01  준비 완료 · 로컬 음성 모델";
            window.SetupExpander.IsExpanded = false;
            window.SetupButton.IsEnabled = false;
            window.RecordButton.IsEnabled = true;
            window.Status.Text = "입력창에 커서를 놓고 단축키를 눌러 주세요.";
            window.HotkeyStatus.Text = "전역 단축키 준비 완료";
            window.Result.Text = "Qwen 2.5 7B 모델을 Ollama로 실행하고 싶어요.";
            var content = (FrameworkElement)window.Content;
            content.Measure(new Size(600, 750)); content.Arrange(new Rect(0, 0, 600, 750)); content.UpdateLayout();
            var bitmap = new RenderTargetBitmap(600, 750, 96, 96, PixelFormats.Pbgra32);
            bitmap.Render(content);
            var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
            using var file = File.Create(args[1]); encoder.Save(file);
            return 0;
        }
        if (args[0] == "--smoke-test" && args.Length == 4)
        {
            var timer = System.Diagnostics.Stopwatch.StartNew();
            using var factory = WhisperFactory.FromPath(args[1], new WhisperFactoryOptions { UseGpu = false });
            await using var processor = factory.CreateBuilder().WithLanguage("en").WithNoContext().WithThreads(2).Build();
            using var wave = File.OpenRead(args[2]);
            var parts = new List<string>();
            await foreach (var segment in processor.ProcessAsync(wave)) parts.Add(segment.Text.Trim());
            var text = string.Join(" ", parts);
            File.WriteAllText(args[3], text);
            if (!text.Contains("country", StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Speech smoke test did not recognize the expected fixture.");
            using var process = System.Diagnostics.Process.GetCurrentProcess();
            File.AppendAllText(args[3], $"\nElapsed including model load: {timer.Elapsed.TotalSeconds:F2}s\nPeak working set: {process.PeakWorkingSet64 / 1048576.0:F1} MiB\nCPU threads available: {Environment.ProcessorCount}\n");
            return 0;
        }
        throw new ArgumentException("Supported: --self-test OUTPUT, --render-preview PNG, --smoke-test MODEL WAV OUTPUT");
    }
}
