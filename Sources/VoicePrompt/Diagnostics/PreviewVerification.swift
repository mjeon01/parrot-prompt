import CoreML
import Foundation
import WhisperKit
import VoicePromptCore

/// Uses the installed tokenizer and the SDK's real prefill path, but no model
/// inference, microphone, clipboard or keyboard input.
enum PreviewVerification {
    static func run() async throws {
        let tokenizer = try await SpeechEngine.loadLocalTokenizer()
        let decoder = TextDecoder()
        decoder.tokenizer = tokenizer
        decoder.isModelMultilingual = true
        let special = tokenizer.specialTokens
        var checks = 0
        func require(_ passed: Bool, _ message: String) throws {
            guard passed else { throw NSError(domain: "VoicePrompt.PreviewVerification", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]) }
            checks += 1
        }
        func words(_ text: String) -> [Int] {
            tokenizer.encode(text: text).filter { $0 < special.specialTokenBegin }
        }
        func progress(_ tokens: [Int]) -> TranscriptionProgress {
            // Matches WhisperKit 1.1.1 TextDecoder's progress construction.
            TranscriptionProgress(timings: TranscriptionTimings(),
                text: tokenizer.decode(tokens: tokens.filter { $0 < special.specialTokenBegin }), tokens: tokens)
        }

        let vocabularies = [TechnicalVocabulary.standard,
            TechnicalVocabulary(customTerms: "FlashAttention, 나만의프로젝트"), .disabled]
        for vocabulary in vocabularies {
            for timestamps in [true, false] {
                var options = SpeechEngine.decodingOptions(interim: true, vocabulary: vocabulary, tokenizer: tokenizer)
                options.withoutTimestamps = !timestamps
                try require(options.prefixTokens == nil, "Dictation must not force a text prefix")
                try require(options.language == nil && options.detectLanguage, "Dictation must detect the spoken language instead of forcing Korean")
                try require(options.task == .transcribe, "Dictation must not translate the user's speech")
                if vocabulary.enabled {
                    let hint = tokenizer.decode(tokens: options.promptTokens ?? [])
                    try require(hint.contains("README") && hint.contains("GitHub"), "English developer terms must survive the prompt token budget")
                }
                // Prefill only reads initialPrompt and the first element of two
                // masks. Small ordinary arrays avoid allocating inference caches.
                func scalar() throws -> MLMultiArray { try MLMultiArray(shape: [1], dataType: .int32) }
                let inputs = try DecodingInputs(initialPrompt: [], inputIds: scalar(), cacheLength: scalar(),
                    keyCache: scalar(), valueCache: scalar(), alignmentWeights: scalar(),
                    kvCacheUpdateMask: scalar(), decoderKeyPaddingMask: scalar())
                let prefilled = try await decoder.prefillDecoderInputs(inputs, withOptions: options)
                let prefix = prefilled.initialPrompt
                let promptOnly = progress(prefix)
                if vocabulary.enabled {
                    try require(promptOnly.text.contains("Ollama"), "Fixture must reproduce the old prompt leak")
                }
                try require(StreamingTranscript.text(from: promptOnly, tokenizer: tokenizer, vocabulary: vocabulary) == nil,
                    "The conditioning vocabulary leaked before any audio text")

                for utterance in ["안녕하세요.", "오늘 회의 내용을 정리해 줘.", "QON 2.57B 모델을 써.",
                                  "Ollama와 RAG를 사용해.", "리듬위를 깃허브에 올려 줘.",
                                  "Please update the README on GitHub.", vocabulary.prompt] where !utterance.isEmpty {
                    var preview = LivePreview()
                    if let text = StreamingTranscript.text(from: promptOnly, tokenizer: tokenizer, vocabulary: vocabulary) {
                        preview.acceptPartial(TranscriptSnapshot(draft: text))
                    }
                    let speechTokens = words(utterance)
                    for count in 1...speechTokens.count {
                        let callback = progress(prefix + speechTokens.prefix(count))
                        if let text = StreamingTranscript.text(from: callback, tokenizer: tokenizer, vocabulary: vocabulary) {
                            preview.acceptPartial(TranscriptSnapshot(draft: text))
                        }
                    }
                    let expected = vocabulary.normalize(utterance)
                    let completed = progress(prefix + speechTokens + [special.endToken])
                    try require(StreamingTranscript.text(from: completed, tokenizer: tokenizer, vocabulary: vocabulary) == expected,
                        "Prompt isolation changed or concealed speech: \(utterance)")
                    try require(preview.snapshot.text == expected,
                        "A vocabulary prefix blocked the live preview: \(utterance)")
                    // A new decoding pass must not re-insert the hints or flash empty.
                    if let text = StreamingTranscript.text(from: promptOnly, tokenizer: tokenizer, vocabulary: vocabulary) {
                        preview.acceptPartial(TranscriptSnapshot(draft: text))
                    }
                    try require(preview.snapshot.text == expected, "A restarted pass replaced the spoken preview")
                }
                try require(StreamingTranscript.text(from: progress(words(vocabulary.prompt)), tokenizer: tokenizer, vocabulary: vocabulary) == nil,
                    "Progress without a transcript boundary must be ignored")
            }
        }
        print("Passed \(checks) preview checks with the installed Whisper tokenizer and SDK prefill.")
        print("Reproduced v0.4.0 prompt leakage; verified prompt-only suppression, immediate speech, spoken technical terms, custom hints and disabled hints.")
        print("This check does not measure microphone recognition accuracy.")
    }
}
