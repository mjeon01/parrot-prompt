namespace VoicePrompt.Core;

public record SpeechSegment(double Start, double End, string Text);

/// <summary>Only time-aligned older segments become permanent; repeated words are preserved.</summary>
public sealed class Transcript
{
    private readonly List<string> committed = [];
    public double ConfirmedEnd { get; private set; }
    public string Text { get; private set; } = "";

    public void Update(IReadOnlyList<SpeechSegment> segments, double offset, double duration, bool final)
    {
        var valid = segments.Where(s => s.End > s.Start && !string.IsNullOrWhiteSpace(s.Text)).ToList();
        var draft = new List<string>();
        for (var i = 0; i < valid.Count; i++)
        {
            var segment = valid[i];
            var end = offset + segment.End;
            if (end <= ConfirmedEnd + 0.01) continue;
            if (final || (i < valid.Count - 1 && segment.End <= duration - 2))
            {
                committed.Add(segment.Text.Trim());
                ConfirmedEnd = end;
            }
            else draft.Add(segment.Text.Trim());
        }
        Text = string.Join(" ", committed.Concat(draft));
    }

    public void AdvanceSilence(double end) => ConfirmedEnd = Math.Max(ConfirmedEnd, end);
}

public static class AudioGate
{
    public static bool HasSpeech(ReadOnlySpan<float> samples)
    {
        var voiced = 0;
        for (var start = 0; start + 320 <= samples.Length; start += 320)
        {
            double energy = 0;
            foreach (var sample in samples.Slice(start, 320)) energy += sample * sample;
            if (Math.Sqrt(energy / 320) > 0.012 && ++voiced >= 8) return true;
        }
        return false;
    }
}
