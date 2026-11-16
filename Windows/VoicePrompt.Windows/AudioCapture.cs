using NAudio.Wave;

namespace VoicePrompt.Windows;

public sealed class AudioCapture : IDisposable
{
    public const int Rate = 16000;
    public const int MaximumSeconds = 600;
    private readonly object gate = new();
    private readonly List<float> samples = [];
    private WaveInEvent? input;
    private TaskCompletionSource stopped = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private bool accepting;
    public Exception? Failure { get; private set; }
    public DateTime LastBuffer { get; private set; }
    public int Count { get { lock (gate) return samples.Count; } }
    public float Level { get; private set; }
    public bool IsStopped => stopped.Task.IsCompleted;

    public void Start()
    {
        if (WaveInEvent.DeviceCount == 0) throw new InvalidOperationException("마이크를 연결하고 Windows 마이크 접근 권한을 허용해 주세요.");
        samples.Clear(); Failure = null; accepting = true; LastBuffer = DateTime.UtcNow;
        stopped = new(TaskCreationOptions.RunContinuationsAsynchronously);
        input = new WaveInEvent { DeviceNumber = -1, WaveFormat = new WaveFormat(Rate, 16, 1), BufferMilliseconds = 50 };
        input.DataAvailable += (_, e) =>
        {
            lock (gate)
            {
                if (!accepting) return;
                double energy = 0;
                for (var i = 0; i + 1 < e.BytesRecorded && samples.Count < Rate * MaximumSeconds; i += 2)
                {
                    var value = BitConverter.ToInt16(e.Buffer, i) / 32768f;
                    samples.Add(value); energy += value * value;
                }
                Level = (float)Math.Min(1, Math.Sqrt(energy / Math.Max(1, e.BytesRecorded / 2)) * 12);
                LastBuffer = DateTime.UtcNow;
            }
        };
        input.RecordingStopped += (_, e) => { Failure = e.Exception; stopped.TrySetResult(); };
        try { input.StartRecording(); }
        catch { input.Dispose(); input = null; accepting = false; stopped.TrySetResult(); throw; }
    }

    public float[] Snapshot(int offset, int maximum = Rate * 28)
    {
        lock (gate)
        {
            offset = Math.Clamp(offset, 0, samples.Count);
            return samples.GetRange(offset, Math.Min(maximum, samples.Count - offset)).ToArray();
        }
    }

    public async Task StopAsync()
    {
        if (input is null || stopped.Task.IsCompleted) return;
        input.StopRecording();
        await stopped.Task.WaitAsync(TimeSpan.FromSeconds(3));
        lock (gate) accepting = false;
    }

    public void Dispose()
    {
        lock (gate) accepting = false;
        input?.Dispose(); input = null;
        lock (gate) { samples.Clear(); Level = 0; }
    }
}
