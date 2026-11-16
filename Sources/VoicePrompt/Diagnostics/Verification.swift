import AppKit
import SwiftUI
import WhisperKit
import VoicePromptCore

/// Opt-in developer checks. Never records a microphone or inserts text.
enum Verification {
    @MainActor static func renderViews(to directory: String) throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let root = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = AppModel(registerHotkeys: false)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            try render(SettingsView(model: model), size: NSSize(width: 600, height: 730), appearance: appearance, to: root.appendingPathComponent("settings-\(name).png"))
            model.phase = .recording
            model.elapsed = 14; model.level = 0.6
            model.transcript = TranscriptSnapshot(confirmed: "오늘 회의에서 나온 내용을 정리해 줘.", draft: "SwiftUI로 만든 앱에 실시간 음성 입력 기능을 추가하고 싶어.")
            try render(DictationView(model: model), size: NSSize(width: 360, height: 102), appearance: appearance, to: root.appendingPathComponent("preview-\(name).png"))
        }
        print("Rendered four UI previews in \(directory)")
    }

    @MainActor private static func render<V: View>(_ view: V, size: NSSize, appearance: NSAppearance.Name, to url: URL) throws {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw NSError(domain: "VoicePrompt.Render", code: 1) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "VoicePrompt.Render", code: 2) }
        try png.write(to: url)
    }

    static func streamFile(_ path: String, engine: SpeechEngine) async throws {
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: path)
        var accumulator = TranscriptAccumulator()
        var latencies: [Double] = []
        for count in stride(from: 8_000, through: samples.count, by: 8_000) {
            let offset = accumulator.confirmedEnd
            let slice = Array(samples[Int(offset * 16000)..<count])
            let start = Date()
            let segments = try await engine.transcribe(slice, interim: true) { partial in
                print("PARTIAL: " + partial)
            }
            latencies.append(Date().timeIntervalSince(start))
            accumulator.update(segments, offset: offset, duration: Float(slice.count) / 16000, final: false)
            print(String(format: "audio=%.1fs decode=%.2fs", Double(count) / 16000, latencies.last!) + " " + TechnicalVocabulary.standard.normalize(accumulator.snapshot.text))
        }
        let start = Date()
        let offset = accumulator.confirmedEnd
        let remaining = Array(samples.dropFirst(Int(offset * 16000)))
        let segments = try await engine.transcribe(remaining)
        accumulator.update(segments, offset: offset, duration: Float(remaining.count) / 16000, final: true)
        print("FINAL: " + TechnicalVocabulary.standard.normalize(accumulator.snapshot.text))
        print(String(format: "Final flush: %.2fs; mean preview decode: %.2fs", Date().timeIntervalSince(start), latencies.reduce(0, +) / Double(max(1, latencies.count))))
    }
}
