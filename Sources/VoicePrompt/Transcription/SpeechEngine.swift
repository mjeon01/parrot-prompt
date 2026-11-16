import Foundation
import WhisperKit
import VoicePromptCore

actor SpeechEngine {
    static let variant = "large-v3-v20240930_turbo"
    private var whisper: WhisperKit?

    static var dataDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["VOICEPROMPT_DATA_DIR"] {
            return URL(fileURLWithPath: override)
        }
        // A portable build can ship a prepared model beside the .app.
        let portable = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("VoicePromptData")
        if FileManager.default.fileExists(atPath: portable.appendingPathComponent("model-path.txt").path) { return portable }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoicePrompt", isDirectory: true)
    }

    static var installedModel: URL? {
        let root = dataDirectory
        guard let path = try? String(contentsOf: root.appendingPathComponent("model-path.txt"), encoding: .utf8) else { return nil }
        let folder = root.appendingPathComponent(path.trimmingCharacters(in: .whitespacesAndNewlines))
        return FileManager.default.fileExists(atPath: folder.appendingPathComponent("AudioEncoder.mlmodelc").path) ? folder : nil
    }

    func prepare(allowDownload: Bool, progress: @escaping @Sendable (Double?, String) -> Void) async throws {
        if whisper != nil { return }
        let root = Self.dataDirectory
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var folder = Self.installedModel
        if folder == nil {
            guard allowDownload else { throw EngineError.modelMissing }
            progress(0, "음성 모델 다운로드 중")
            folder = try await WhisperKit.download(variant: Self.variant, downloadBase: root) { value in
                progress(value.fractionCompleted, "음성 모델 다운로드 중")
            }
        }
        guard let folder else { throw EngineError.modelMissing }
        let hub = HubApiWrapper(downloadBase: root)
        let tokenizerRepo = HubApiWrapper.Repo(id: "openai/whisper-large-v3")
        let tokenizerFolder = hub.localRepoLocation(tokenizerRepo)
        if allowDownload {
            progress(nil, "언어 사전 다운로드 중")
            _ = try await hub.snapshot(from: tokenizerRepo, matching: ["tokenizer.json", "tokenizer_config.json", "config.json"])
        }
        // Load the tokenizer explicitly from disk. The SDK's default loader can
        // fall back to the network when a cached tokenizer is damaged.
        _ = try await AutoTokenizerWrapper.from(modelFolder: tokenizerFolder)
        let localTokenizer = try await ModelUtilities.loadTokenizer(for: .largev3, tokenizerFolder: root)
        progress(nil, "Mac에 맞게 모델 준비 중 · 처음에는 시간이 걸립니다")
        let cpuOnly = ProcessInfo.processInfo.environment["VOICEPROMPT_COMPUTE"] == "cpu"
        let compute = cpuOnly ? ModelComputeOptions(melCompute: .cpuOnly, audioEncoderCompute: .cpuOnly, textDecoderCompute: .cpuOnly) : ModelComputeOptions()
        let config = WhisperKitConfig(modelFolder: folder.path, tokenizerFolder: root, computeOptions: compute,
            verbose: false, prewarm: false, load: false, download: false)
        let loaded = try await WhisperKit(config)
        loaded.tokenizer = localTokenizer
        loaded.textDecoder.isModelMultilingual = true
        try await loaded.loadModels()
        try Task.checkCancellation()
        whisper = loaded
        let relative = folder.path.replacingOccurrences(of: root.path + "/", with: "")
        try relative.write(to: root.appendingPathComponent("model-path.txt"), atomically: true, encoding: .utf8)
        progress(1, "로컬 모델 준비 완료")
    }

    /// `interim` passes are previews that the next pass replaces, so they skip
    /// temperature fallback retries, which can double or triple a pass.
    func transcribe(_ samples: [Float], interim: Bool = false, vocabulary: TechnicalVocabulary = .standard,
                    onProgress: (@Sendable (String) -> Void)? = nil) async throws -> [SpeechSegment] {
        guard let whisper else { throw EngineError.modelMissing }
        guard AudioGate.hasSignal(samples) else { return [] }
        let promptTokens = vocabulary.enabled ? whisper.tokenizer.map { tokenizer in
            Array(tokenizer.encode(text: vocabulary.prompt).filter { $0 < tokenizer.specialTokens.specialTokenBegin }.prefix(160))
        } : nil
        let options = DecodingOptions(verbose: false, task: .transcribe, language: "ko",
            temperatureFallbackCount: interim ? 0 : 2, detectLanguage: false, skipSpecialTokens: true,
            withoutTimestamps: false, wordTimestamps: false, windowClipTime: 0,
            promptTokens: promptTokens,
            suppressBlank: true, concurrentWorkerCount: 1)
        let results = try await whisper.transcribe(audioArray: samples, decodeOptions: options) { progress in
            if Task.isCancelled { return false }
            onProgress?(vocabulary.normalize(progress.text.trimmingCharacters(in: .whitespacesAndNewlines)))
            return nil
        }
        try Task.checkCancellation()
        return results.flatMap(\.segments).filter {
            $0.noSpeechProb < 0.6 && $0.avgLogprob > -1.2 && $0.compressionRatio < 2.4
                // A spoken "감사합니다" keeps its voice energy; an invented one has none.
                && !(Hallucination.isStockPhrase($0.text) && !AudioGate.hasSignal(samples, from: $0.start, to: $0.end))
        }.map { SpeechSegment(start: $0.start, end: $0.end, text: $0.text) }
    }

    enum EngineError: LocalizedError {
        case modelMissing
        var errorDescription: String? { "음성 모델이 없습니다. 설정에서 모델을 다운로드해 주세요." }
    }
}
