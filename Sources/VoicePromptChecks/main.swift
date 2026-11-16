import Foundation
import VoicePromptCore

var checks = 0
func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    guard value() else { fatalError(message) }
    checks += 1
}
func segment(_ start: Float, _ end: Float, _ text: String) -> SpeechSegment {
    SpeechSegment(start: start, end: end, text: text)
}

var stream = TranscriptAccumulator()
stream.update([segment(0, 1, "안녕")], offset: 0, duration: 2, final: false)
expect(stream.snapshot.confirmed.isEmpty, "Incomplete speech must remain tentative")
stream.update([segment(0, 2, "안녕하세요")], offset: 0, duration: 3, final: false)
expect(stream.snapshot.text == "안녕하세요", "Revised partial must replace the previous partial")
stream.update([segment(0, 2, "안녕하세요."), segment(2, 4, "SwiftUI 앱을")], offset: 0, duration: 5, final: false)
expect(stream.confirmedEnd == 2, "Only older segments may be committed")
expect(stream.snapshot.confirmed == "안녕하세요.", "Prefix must be committed once")
stream.update([segment(0, 3, "SwiftUI 앱을 만들어 주세요.")], offset: 2, duration: 3, final: true)
expect(stream.snapshot.text == "안녕하세요. SwiftUI 앱을 만들어 주세요.", "Final tail must be preserved without duplication")
expect(stream.snapshot.draft.isEmpty, "Final result cannot contain a tentative suffix")
stream.update([segment(0, 3, "SwiftUI 앱을 만들어 주세요.")], offset: 2, duration: 3, final: true)
expect(stream.snapshot.text == "안녕하세요. SwiftUI 앱을 만들어 주세요.", "Same timed result must not insert twice")

var repeated = TranscriptAccumulator()
repeated.update([segment(0, 1, "정말"), segment(1, 2, "정말 중요해요.")], offset: 0, duration: 3, final: true)
expect(repeated.snapshot.text == "정말 정말 중요해요.", "Intentional repetitions must remain verbatim")
var long = TranscriptAccumulator()
for index in 0..<90 {
    long.update([segment(0, 2, "문장\(index)")], offset: Float(index * 2), duration: 2, final: true)
}
expect(long.committed.count == 90 && long.confirmedEnd == 180, "Three-minute sequence must preserve all segments")
expect(!AudioGate.hasSignal(Array(repeating: 0, count: 16000)), "Silence must not reach decoder")
expect(!AudioGate.hasSignal([0.9, -0.9]), "A click alone must not trigger recognition")
expect(AudioGate.hasSignal(Array(repeating: 0.04, count: 16000)), "Audible input must reach decoder")
var quietClick = (0..<12800).map { index in Float(sin(Double(index))) * 0.004 }
for index in 800..<1100 { quietClick[index] += 0.25 * Float(exp(-Double(index - 800) / 50)) }
expect(!AudioGate.hasSignal(quietClick), "Room noise plus a hotkey click must not reach decoder")
let speech = Array(repeating: Float(0), count: 16000) + Array(repeating: 0.05, count: 16000)
expect(!AudioGate.hasSignal(speech, from: 0, to: 1), "A silent segment range has no voice")
expect(AudioGate.hasSignal(speech, from: 1, to: 2), "A spoken segment range has voice")
expect(Hallucination.isStockPhrase(" 감사합니다.") && Hallucination.isStockPhrase("감사합니다, 감사합니다."), "Stock closing phrases must be recognized")
expect(Hallucination.isStockPhrase("시청해 주셔서 감사합니다!"), "Spacing and punctuation must not hide a stock phrase")
expect(!Hallucination.isStockPhrase("이 함수를 리팩터링해 주세요. 감사합니다."), "Real requests ending in thanks must be kept")
var token = SessionToken()
let old = token.current
token.invalidate()
expect(!token.accepts(old), "Cancelled callbacks must be rejected")
expect(token.accepts(token.current), "Current session callback must be accepted")
var preview = LivePreview()
preview.acceptPartial(TranscriptSnapshot(draft: "오늘 회의 내용을 정리해 주세요"))
let previousSentence = preview.snapshot
expect(!preview.acceptPartial(TranscriptSnapshot(draft: "오늘")), "A restarted decoder pass must not erase the visible sentence")
expect(preview.snapshot == previousSentence, "Previous preview must remain until the next pass catches up")
expect(!preview.acceptPartial(TranscriptSnapshot()), "Empty token callbacks must not flash the placeholder")
preview.settle(TranscriptSnapshot())
expect(preview.snapshot == previousSentence, "An empty interim decoder result must not clear the view")
expect(preview.acceptPartial(TranscriptSnapshot(draft: "오늘 회의 내용을 정리해 주세요. 그리고")), "New speech must appear as soon as it extends the visible result")
expect(!preview.acceptPartial(TranscriptSnapshot(draft: "오늘 회의 내용을 정리해 주세요.")), "Out-of-order shorter callbacks must not rewind displayed text")
preview.settle(TranscriptSnapshot(confirmed: "회의 내용을 정리해 주세요."))
expect(preview.snapshot.text == "회의 내용을 정리해 주세요.", "A completed pass may legitimately correct and shorten speech")
preview.settle(TranscriptSnapshot(), final: true)
expect(preview.snapshot.text.isEmpty, "An authoritative silent final result must clear speculative text")
print("Passed \(checks) checks: streaming revisions, stable preview, timed deduplication, final flush, intentional repetition, long dictation, silence, hallucination, cancellation.")
