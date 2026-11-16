using System.ComponentModel;
using System.Diagnostics;
using System.Text.Json;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Threading;
using VoicePrompt.Core;
using Forms = System.Windows.Forms;

namespace VoicePrompt.Windows;

public partial class MainWindow : Window
{
    private readonly SpeechEngine engine = new();
    private readonly ModelStore models = new();
    private readonly PreviewWindow preview = new();
    private readonly DispatcherTimer meter = new() { Interval = TimeSpan.FromMilliseconds(150) };
    private readonly Forms.NotifyIcon tray;
    private GlobalHotkey? hotkey;
    private AudioCapture? capture;
    private CancellationTokenSource? cancellation;
    private CancellationTokenSource? preparation;
    private Task? session;
    private Task? preparing;
    private bool ready, recording, busy, quitting, closing;
    private nint handle;

    public MainWindow()
    {
        InitializeComponent();
        LoadSettings();
        tray = new Forms.NotifyIcon { Text = "VoicePrompt", Icon = System.Drawing.SystemIcons.Application, Visible = true };
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("VoicePrompt 열기", null, (_, _) => Dispatcher.Invoke(ShowSettings));
        menu.Items.Add("종료", null, (_, _) => Dispatcher.Invoke(() => _ = QuitAsync()));
        tray.ContextMenuStrip = menu;
        tray.DoubleClick += (_, _) => Dispatcher.Invoke(ShowSettings);
        meter.Tick += (_, _) =>
        {
            if (capture is null) return;
            LevelMeter.Value = capture.Level;
            if (recording && capture.Count >= AudioCapture.Rate * AudioCapture.MaximumSeconds) _ = StopAsync();
            if (recording && (capture.IsStopped || DateTime.UtcNow - capture.LastBuffer > TimeSpan.FromSeconds(4)))
                CancelSession("마이크 연결이 끊겼어요. 연결 상태와 마이크 권한을 확인해 주세요.");
        };
        SourceInitialized += (_, _) =>
        {
            handle = new WindowInteropHelper(this).Handle;
            hotkey = new GlobalHotkey(handle);
            hotkey.Toggle += () => _ = ToggleAsync(true);
            hotkey.Cancel += () => CancelSession();
            HotkeyStatus.Text = hotkey.Registered ? "전역 단축키 준비 완료" : "다른 앱이 단축키를 사용 중입니다. 그 앱의 단축키를 해제하고 VoicePrompt를 다시 실행하거나 녹음 버튼을 사용하세요.";
        };
        Loaded += async (_, _) => { if (models.Exists) await PrepareAsync(false); };
    }

    private void ShowSettings() { Show(); WindowState = WindowState.Normal; Activate(); }
    private async void PrepareClick(object sender, RoutedEventArgs e) => await PrepareAsync(true);
    private async Task PrepareAsync(bool download)
    {
        if (preparing is { IsCompleted: false } || ready || quitting) return;
        preparation = new CancellationTokenSource();
        SetupButton.IsEnabled = false;
        preparing = PrepareCoreAsync(download, preparation.Token);
        await preparing;
    }
    private async Task PrepareCoreAsync(bool download, CancellationToken token)
    {
        try
        {
            await models.EnsureAsync(download, new Progress<string>(s => { if (!quitting) SetupStatus.Text = s; }), token);
            SetupStatus.Text = "로컬 모델을 메모리에 올리고 있어요.";
            await Task.Run(() => engine.Load(ModelStore.ModelPath), token);
            token.ThrowIfCancellationRequested();
            ready = true; SetupStatus.Text = "준비 완료 · 이제 인터넷 없이 사용할 수 있어요.";
            Status.Text = "입력창에 커서를 놓고 단축키를 눌러 주세요.";
            RecordButton.IsEnabled = true;
        }
        catch (OperationCanceledException) { }
        catch (Exception ex) { SetupStatus.Text = Friendly(ex); }
        finally { SetupButton.IsEnabled = !ready; }
    }
    private static string Friendly(Exception ex) => ex is DllNotFoundException or TypeInitializationException
        ? "음성 엔진을 불러오지 못했어요. 다운로드한 폴더 전체를 유지하고 Microsoft Visual C++ 2015–2022 x64 런타임을 설치해 주세요."
        : "처리하지 못했어요: " + ex.Message;

    private async void RecordClick(object sender, RoutedEventArgs e) => await ToggleAsync(false);
    private async Task ToggleAsync(bool fromHotkey)
    {
        if (recording) { await StopAsync(); return; }
        if (busy || quitting) return;
        if (!ready) { ShowSettings(); Status.Text = "먼저 음성 모델을 준비해 주세요."; return; }
        var target = fromHotkey && AutoInsert.IsChecked == true ? TextInsertion.Capture(handle) : null;
        var insert = fromHotkey && AutoInsert.IsChecked == true;
        var vocabulary = UseVocabulary.IsChecked == true;
        cancellation?.Dispose(); cancellation = new();
        busy = true; Result.Text = "";
        AutoInsert.IsEnabled = UseVocabulary.IsEnabled = false;
        CancelButton.IsEnabled = true;
        session = RunSessionAsync(target, insert, vocabulary, cancellation.Token);
        await session;
    }

    private async Task RunSessionAsync(InputTarget? target, bool insert, bool vocabulary, CancellationToken token)
    {
        var transcript = new Transcript();
        var finalizedThrough = 0;
        try
        {
            capture = new AudioCapture(); capture.Start();
            recording = true; meter.Start(); RecordButton.Content = "녹음 완료";
            var cancelRegistered = hotkey?.EnableCancel(true) ?? false;
            Status.Text = cancelRegistered ? "듣고 있어요. 단축키를 다시 누르면 완료합니다." : "듣고 있어요. 취소 단축키가 사용 중이므로 창의 취소 버튼을 사용하세요.";
            var lastDecoded = 0;
            while (recording)
            {
                await Task.Delay(200, token);
                if (capture.Failure is { } failure) throw failure;
                var count = capture.Count;
                if (count - lastDecoded < AudioCapture.Rate * 2) continue;
                var offset = Math.Max(finalizedThrough, (int)(transcript.ConfirmedEnd * AudioCapture.Rate));
                var audio = capture.Snapshot(offset);
                var full = audio.Length >= AudioCapture.Rate * 28;
                var segments = await Task.Run(() => engine.TranscribeAsync(audio, vocabulary, token), token);
                token.ThrowIfCancellationRequested();
                transcript.Update(segments, offset / (double)AudioCapture.Rate, audio.Length / (double)AudioCapture.Rate, full);
                if (full) { finalizedThrough = offset + audio.Length; transcript.AdvanceSilence(finalizedThrough / (double)AudioCapture.Rate); }
                Result.Text = Vocabulary.Normalize(transcript.Text, vocabulary);
                preview.Update($"듣고 있어요 · {capture.Count / AudioCapture.Rate}초 / 600초", Result.Text.Length == 0 ? "말한 내용이 여기에 표시됩니다." : Result.Text);
                lastDecoded = count;
            }
            await capture.StopAsync();
            token.ThrowIfCancellationRequested();
            if (capture.Failure is { } finalFailure) throw finalFailure;
            Status.Text = "마지막 문장을 처리하고 있어요.";
            var finalOffset = Math.Max(finalizedThrough, (int)(transcript.ConfirmedEnd * AudioCapture.Rate));
            while (finalOffset < capture.Count)
            {
                var audio = capture.Snapshot(finalOffset);
                var segments = await Task.Run(() => engine.TranscribeAsync(audio, vocabulary, token), token);
                token.ThrowIfCancellationRequested();
                transcript.Update(segments, finalOffset / (double)AudioCapture.Rate, audio.Length / (double)AudioCapture.Rate, true);
                finalOffset += audio.Length;
            }
            Result.Text = Vocabulary.Normalize(transcript.Text, vocabulary);
            preview.Hide();
            if (Result.Text.Length == 0) Status.Text = "인식된 음성이 없어요. 마이크와 거리를 확인해 주세요.";
            else if (insert) Status.Text = await TextInsertion.InsertAsync(Result.Text, target, token);
            else Status.Text = "인식을 마쳤어요. 결과를 복사해 원하는 입력창에 붙여 넣으세요.";
            if (!IsVisible) { preview.Update(Status.Text, Result.Text); }
        }
        catch (OperationCanceledException) { Result.Clear(); preview.Hide(); }
        catch (Exception ex) { Status.Text = Friendly(ex); preview.Hide(); if (!quitting) ShowSettings(); }
        finally
        {
            recording = false; meter.Stop(); capture?.Dispose(); capture = null;
            hotkey?.EnableCancel(false); busy = false; LevelMeter.Value = 0;
            AutoInsert.IsEnabled = UseVocabulary.IsEnabled = true;
            RecordButton.Content = "녹음 시작"; RecordButton.IsEnabled = ready; CancelButton.IsEnabled = false;
        }
    }

    private async Task StopAsync()
    {
        if (!recording) return;
        recording = false; RecordButton.IsEnabled = false; Status.Text = "마지막 문장을 처리하고 있어요.";
        try { if (capture is not null) await capture.StopAsync(); }
        catch (Exception ex) { CancelSession(Friendly(ex)); }
    }
    private void CancelSession(string message = "녹음을 취소했어요.")
    {
        if (!busy) { preview.Hide(); return; }
        Status.Text = message; recording = false; cancellation?.Cancel();
        if (capture is not null) _ = StopCaptureQuietlyAsync(capture);
    }
    private static async Task StopCaptureQuietlyAsync(AudioCapture audio) { try { await audio.StopAsync(); } catch { /* Finalizer disposes capture. */ } }
    private void CancelClick(object sender, RoutedEventArgs e) => CancelSession();
    private void CopyClick(object sender, RoutedEventArgs e)
    {
        if (Result.Text.Length == 0) { Status.Text = "복사할 내용이 아직 없어요."; return; }
        try { Clipboard.SetText(Result.Text); Status.Text = "복사했어요. 원하는 입력창에 Ctrl + V로 붙여 넣으세요."; }
        catch (System.Runtime.InteropServices.COMException) { Status.Text = "다른 앱이 클립보드를 사용 중입니다. 다시 눌러 주세요."; }
    }
    private void HideClick(object sender, RoutedEventArgs e) { SaveSettings(); Hide(); }
    private void MicrophoneClick(object sender, RoutedEventArgs e)
    {
        try { Process.Start(new ProcessStartInfo("ms-settings:privacy-microphone") { UseShellExecute = true }); }
        catch (Exception) { Status.Text = "Windows 설정 → 개인정보 및 보안 → 마이크에서 데스크톱 앱의 접근을 허용해 주세요."; }
    }
    private void OnClosing(object? sender, CancelEventArgs e)
    {
        if (closing) return;
        e.Cancel = true; SaveSettings(); Hide();
    }
    private async void ExitClick(object sender, RoutedEventArgs e) => await QuitAsync();
    private async Task QuitAsync()
    {
        if (quitting) return;
        quitting = true; CancelSession(); preparation?.Cancel();
        if (session is not null) await session;
        if (preparing is not null) await preparing;
        SaveSettings(); hotkey?.Dispose(); engine.Dispose(); tray.Dispose();
        preview.Close(); closing = true; Close();
        cancellation?.Dispose(); preparation?.Dispose();
        Application.Current.Shutdown();
    }
    private record Preferences(bool AutoInsert = true, bool Vocabulary = true);
    private static string SettingsPath => Path.Combine(ModelStore.DirectoryPath, "settings.json");
    private void LoadSettings()
    {
        try
        {
            if (File.Exists(SettingsPath) && JsonSerializer.Deserialize<Preferences>(File.ReadAllText(SettingsPath)) is { } preferences)
            { AutoInsert.IsChecked = preferences.AutoInsert; UseVocabulary.IsChecked = preferences.Vocabulary; }
        }
        catch (Exception ex) when (ex is IOException or JsonException or UnauthorizedAccessException) { }
    }
    private void SaveSettings()
    {
        try
        {
            Directory.CreateDirectory(ModelStore.DirectoryPath);
            var temporary = SettingsPath + ".tmp";
            File.WriteAllText(temporary, JsonSerializer.Serialize(new Preferences(AutoInsert.IsChecked == true, UseVocabulary.IsChecked == true)));
            File.Move(temporary, SettingsPath, true);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { Status.Text = "설정을 저장하지 못했어요. 저장 폴더 권한을 확인해 주세요."; }
    }
}
