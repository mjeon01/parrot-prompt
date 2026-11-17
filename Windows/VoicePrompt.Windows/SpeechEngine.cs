using VoicePrompt.Core;
using Whisper.net;

namespace VoicePrompt.Windows;

public sealed class SpeechEngine : IDisposable
{
    private WhisperFactory? factory;
    public void Load(string path)
    {
        if (!System.Runtime.Intrinsics.X86.Avx2.IsSupported || !System.Runtime.Intrinsics.X86.Fma.IsSupported)
            throw new PlatformNotSupportedException("이 배포본은 AVX2·FMA·F16C를 지원하는 x64 CPU가 필요합니다.");
        factory = WhisperFactory.FromPath(path, new WhisperFactoryOptions { UseGpu = false });
    }

    public async Task<IReadOnlyList<SpeechSegment>> TranscribeAsync(float[] audio, bool vocabulary, CancellationToken token)
    {
        if (factory is null) throw new InvalidOperationException("모델을 먼저 준비해 주세요.");
        if (!AudioGate.HasSpeech(audio)) return [];
        var builder = factory.CreateBuilder().WithLanguageDetection().WithNoContext()
            .WithThreads(Math.Max(1, Math.Min(8, Environment.ProcessorCount / 2)))
            .WithNoSpeechThreshold(0.6f).WithLogProbThreshold(-1.0f);
        if (vocabulary) builder.WithPrompt(Vocabulary.Prompt);
        await using var processor = builder.Build();
        var segments = new List<SpeechSegment>();
        // Only decoded segments reach the UI. The prompt and progress messages never do.
        await foreach (var segment in processor.ProcessAsync(audio, token))
            if (!string.IsNullOrWhiteSpace(segment.Text))
                segments.Add(new(segment.Start.TotalSeconds, segment.End.TotalSeconds, segment.Text));
        return segments;
    }

    public void Dispose() { factory?.Dispose(); factory = null; }
}
