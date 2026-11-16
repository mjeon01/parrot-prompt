import Foundation
import WhisperKit
import VoicePromptCore

enum StreamingTranscript {
    static func text(from progress: TranscriptionProgress, tokenizer: any WhisperTokenizer,
                     vocabulary: TechnicalVocabulary) -> String? {
        // WhisperKit 1.1.1 progress.text includes the prefilled vocabulary, even
        // before the first audio token. Its final results already omit that
        // prefix. Apply the same start-of-transcript boundary to live results.
        let special = tokenizer.specialTokens
        let tokens = TranscriptTokens.spoken(from: progress.tokens,
            startOfTranscript: special.startOfTranscriptToken,
            endOfTranscript: special.endToken, specialTokenBegin: special.specialTokenBegin)
        guard !tokens.isEmpty else { return nil }
        let text = vocabulary.normalize(tokenizer.decode(tokens: tokens).trimmingCharacters(in: .whitespacesAndNewlines))
        return text.isEmpty ? nil : text
    }
}
