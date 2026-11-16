using System.Runtime.InteropServices;
using System.Windows.Automation;
using System.Windows.Interop;

namespace VoicePrompt.Windows;

internal sealed class GlobalHotkey : IDisposable
{
    private readonly nint window;
    private readonly HwndSource source;
    public event Action? Toggle;
    public event Action? Cancel;
    public bool Registered { get; }
    public GlobalHotkey(nint window)
    {
        this.window = window;
        source = HwndSource.FromHwnd(window);
        source.AddHook(Hook);
        Registered = Native.RegisterHotKey(window, 1, 0x4000 | 0x2 | 0x4, 0x20);
    }
    public bool EnableCancel(bool enable)
    {
        Native.UnregisterHotKey(window, 2);
        return !enable || Native.RegisterHotKey(window, 2, 0x4000 | 0x2 | 0x4, 0x1B);
    }
    private nint Hook(nint hwnd, int message, nint wParam, nint lParam, ref bool handled)
    {
        if (message == 0x0312)
        {
            if (wParam == 1) { handled = true; Toggle?.Invoke(); }
            if (wParam == 2) { handled = true; Cancel?.Invoke(); }
        }
        return 0;
    }
    public void Dispose()
    {
        Native.UnregisterHotKey(window, 1); Native.UnregisterHotKey(window, 2);
        source.RemoveHook(Hook);
    }
}

internal record InputTarget(nint Window, int Process, int[] Element);

internal static class TextInsertion
{
    public static InputTarget? Capture(nint ownWindow)
    {
        try
        {
            var window = Native.GetForegroundWindow();
            if (window == 0 || window == ownWindow) return null;
            Native.GetWindowThreadProcessId(window, out var process);
            if (process == Environment.ProcessId) return null;
            var element = AutomationElement.FocusedElement;
            if (element is null || element.Current.IsPassword || !element.Current.IsEnabled) return null;
            if (element.Current.ProcessId != process) return null;
            if (element.TryGetCurrentPattern(ValuePattern.Pattern, out var value))
            {
                if (((ValuePattern)value).Current.IsReadOnly) return null;
            }
            else if (element.Current.ControlType != ControlType.Edit && element.Current.ControlType != ControlType.Document) return null;
            return new(window, process, element.GetRuntimeId());
        }
        catch (Exception ex) when (ex is ElementNotAvailableException or InvalidOperationException or COMException or UnauthorizedAccessException) { return null; }
    }

    private static bool Current(InputTarget target)
    {
        var current = Capture(0);
        return current is not null && current.Window == target.Window && current.Process == target.Process && current.Element.SequenceEqual(target.Element);
    }

    public static async Task<string> InsertAsync(string text, InputTarget? target, CancellationToken token)
    {
        if (target is null) return "입력창을 확인하지 못했어요. 결과를 복사해 붙여 넣어 주세요.";
        // Never synthesize Enter. This path does not put dictation on the clipboard.
        text = text.Replace('\r', ' ').Replace('\n', ' ');
        for (var i = 0; i < 20 && Native.ModifiersHeld; i++) await Task.Delay(50, token);
        if (Native.ModifiersHeld) return "단축키에서 손을 뗀 뒤 결과를 복사해 주세요.";
        for (var offset = 0; offset < text.Length; offset += 32)
        {
            token.ThrowIfCancellationRequested();
            if (!Current(target) || Native.ModifiersHeld)
                return offset == 0 ? "녹음 중 입력창이 바뀌었어요. 결과를 복사해 주세요." : "입력창이나 키 상태가 바뀌어 입력을 멈췄어요. 이미 입력된 부분을 확인해 주세요.";
            var chunk = text.Substring(offset, Math.Min(32, text.Length - offset));
            var inputs = chunk.SelectMany(c => new[] { Native.Unicode(c, false), Native.Unicode(c, true) }).ToArray();
            if (Native.SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<Native.Input>()) != inputs.Length)
                return "입력 요청이 차단됐어요. 일부 입력 여부를 확인하고 필요한 내용을 복사해 주세요.";
            await Task.Delay(10, token);
        }
        return "입력을 요청했어요. 대상 앱의 내용을 확인한 뒤 직접 전송하세요.";
    }
}

internal static class Native
{
    [DllImport("user32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool RegisterHotKey(nint hwnd, int id, uint modifiers, uint key);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool UnregisterHotKey(nint hwnd, int id);
    [DllImport("user32.dll")] internal static extern nint GetForegroundWindow();
    [DllImport("user32.dll")] internal static extern uint GetWindowThreadProcessId(nint hwnd, out int process);
    [DllImport("user32.dll")] internal static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll", SetLastError = true)] internal static extern uint SendInput(uint count, Input[] inputs, int size);
    internal static bool ModifiersHeld => new[] { 0x10, 0x11, 0x12, 0x5B, 0x5C }.Any(k => (GetAsyncKeyState(k) & 0x8000) != 0);
    [StructLayout(LayoutKind.Sequential)] internal struct Input { public uint Type; public InputUnion Data; }
    [StructLayout(LayoutKind.Explicit)] internal struct InputUnion
    {
        [FieldOffset(0)] public Keyboard Keyboard;
        [FieldOffset(0)] public Mouse Mouse;
    }
    [StructLayout(LayoutKind.Sequential)] internal struct Keyboard { public ushort Key, Scan; public uint Flags, Time; public nuint Extra; }
    [StructLayout(LayoutKind.Sequential)] internal struct Mouse { public int X, Y; public uint Data, Flags, Time; public nuint Extra; }
    internal static Input Unicode(char c, bool up) => new() { Type = 1, Data = new InputUnion { Keyboard = new Keyboard { Scan = c, Flags = up ? 0x0006u : 0x0004u } } };
}
