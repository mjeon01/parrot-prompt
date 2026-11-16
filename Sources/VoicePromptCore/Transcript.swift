import Foundation

public struct TranscriptSnapshot: Equatable, Sendable {
    public var confirmed: String
    public var draft: String
    public init(confirmed: String = "", draft: String = "") {
        self.confirmed = confirmed
        self.draft = draft
    }
    public var text: String {
        [confirmed, draft].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

public struct SpeechSegment: Sendable {
    public var start: Float
    public var end: Float
    public var text: String
    public init(start: Float, end: Float, text: String) {
        self.start = start; self.end = end; self.text = text
    }
}

/// The decoder always replaces the tentative suffix. Only timed, older segments
/// are committed; repeated words in real speech are deliberately preserved.
public struct TranscriptAccumulator: Sendable {
    public private(set) var committed: [SpeechSegment] = []
    public private(set) var confirmedEnd: Float = 0
    public private(set) var snapshot = TranscriptSnapshot()
    public init() {}

    public mutating func update(_ segments: [SpeechSegment], offset: Float, duration: Float, final: Bool) {
        let valid = segments.filter { $0.end > $0.start && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var pending: [String] = []
        for (index, segment) in valid.enumerated() {
            let absoluteEnd = offset + segment.end
            guard absoluteEnd > confirmedEnd + 0.01 else { continue }
            if final || (index < valid.count - 1 && segment.end <= duration - 2) {
                committed.append(SpeechSegment(start: offset + segment.start, end: absoluteEnd, text: segment.text))
                confirmedEnd = absoluteEnd
            } else {
                pending.append(segment.text)
            }
        }
        snapshot = TranscriptSnapshot(confirmed: Self.join(committed.map(\.text)), draft: Self.join(pending))
    }

    public static func join(_ parts: [String]) -> String {
        parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
}

public enum AudioGate {
    static let frame = 320            // 20 ms at 16 kHz
    static let voicedRMS: Float = 0.012
    static let minimumVoicedFrames = 8 // 160 ms of voice-level energy

    /// Whisper invents stock phrases ("감사합니다.") for near-silence and its
    /// confidence stays high, so require sustained voice-level energy first.
    /// A key click or room noise has too few loud frames to pass.
    public static func hasSignal(_ samples: [Float]) -> Bool {
        voicedFrames(samples[...]) >= minimumVoicedFrames
    }

    /// Checks one decoded segment's own audio range (seconds, 16 kHz).
    public static func hasSignal(_ samples: [Float], from start: Float, to end: Float) -> Bool {
        let lower = min(samples.count, max(0, Int(start * 16000)))
        let upper = min(samples.count, max(lower, Int(end * 16000)))
        return voicedFrames(samples[lower..<upper]) >= minimumVoicedFrames
    }

    static func voicedFrames(_ samples: ArraySlice<Float>) -> Int {
        var voiced = 0
        var index = samples.startIndex
        while index + frame <= samples.endIndex {
            var energy: Float = 0
            for sample in samples[index..<(index + frame)] { energy += sample * sample }
            if (energy / Float(frame)).squareRoot() > voicedRMS { voiced += 1 }
            index += frame
        }
        return voiced
    }
}

public enum Hallucination {
    /// Closing lines from subtitled videos that Whisper emits for silence.
    static let stock: [String] = [
        "감사합니다", "고맙습니다", "시청해주셔서감사합니다", "시청해주셔서고맙습니다",
        "구독과좋아요부탁드립니다", "구독과좋아요", "다음영상에서만나요", "다음시간에만나요",
        "thankyou", "thanksforwatching"
    ]

    /// True when the text is only stock phrases, possibly repeated.
    public static func isStockPhrase(_ text: String) -> Bool {
        var rest = Substring(text.lowercased().filter { $0.isLetter || $0.isNumber })
        guard !rest.isEmpty else { return false }
        while !rest.isEmpty {
            guard let phrase = stock.first(where: { rest.hasPrefix($0) }) else { return false }
            rest = rest.dropFirst(phrase.count)
        }
        return true
    }
}

public struct SessionToken: Sendable {
    public private(set) var current = UUID()
    public init() {}
    @discardableResult public mutating func invalidate() -> UUID {
        current = UUID(); return current
    }
    public func accepts(_ token: UUID) -> Bool { current == token }
}
