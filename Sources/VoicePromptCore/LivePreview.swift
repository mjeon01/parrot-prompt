import Foundation

/// A new decoder pass starts at the beginning of the unconfirmed audio. Keep
/// the previous visible sentence until that pass catches up, avoiding a repeated
/// erase/type cycle. Completed passes may correct or shorten a sentence.
public struct LivePreview: Sendable {
    public private(set) var snapshot = TranscriptSnapshot()
    public init() {}

    @discardableResult
    public mutating func acceptPartial(_ candidate: TranscriptSnapshot) -> Bool {
        guard !candidate.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              candidate.text.count >= snapshot.text.count,
              candidate != snapshot else { return false }
        snapshot = candidate
        return true
    }

    public mutating func settle(_ candidate: TranscriptSnapshot, final: Bool = false) {
        if final || !candidate.text.isEmpty { snapshot = candidate }
    }
}
