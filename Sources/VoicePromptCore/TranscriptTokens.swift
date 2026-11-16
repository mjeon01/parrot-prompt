/// Separates Whisper's conditioning prompt from tokens for the current audio.
/// Removing special tokens alone would leave the ordinary words in the prompt.
public enum TranscriptTokens {
    public static func spoken(from tokens: [Int], startOfTranscript: Int,
                              endOfTranscript: Int, specialTokenBegin: Int) -> [Int] {
        guard let start = tokens.firstIndex(of: startOfTranscript) else { return [] }
        return tokens.dropFirst(start + 1)
            .prefix { $0 != endOfTranscript }
            .filter { $0 >= 0 && $0 < specialTokenBegin }
    }
}
