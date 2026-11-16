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

let inputSource = HotkeyChord(keyCode: 49, modifiers: HotkeyChord.control | HotkeyChord.option)
let emoji = HotkeyChord(keyCode: 49, modifiers: HotkeyChord.control | HotkeyChord.command)
let spotlight = HotkeyChord(keyCode: 49, modifiers: HotkeyChord.command)
let systemHotkeys: Set<HotkeyChord> = [inputSource, spotlight]
expect(inputSource.conflict(in: systemHotkeys) == .inputSource, "Legacy default must be rejected when input switching is enabled")
expect(inputSource.conflict(in: []) == nil, "Disabled input-switch bindings may be reused")
expect(emoji.conflict(in: []) == .characterViewer, "AppKit emoji shortcut must be detected even outside the symbolic list")
expect(spotlight.conflict(in: systemHotkeys) == .system, "Other enabled system shortcuts must be rejected")
expect(HotkeyChord.recommended.conflict(in: systemHotkeys) == nil, "Recommended shortcut must avoid the known conflicts")
expect(HotkeyChord.recommended.conflict(in: [.recommended]) == .system, "Recommended shortcut must still honor customized system bindings")
expect(HotkeyChord(keyCode: 49, modifiers: HotkeyChord.control | HotkeyChord.shift | (1 << 10)) == .recommended, "Caps Lock must not change the chord")

var presses = HotkeyPressFilter()
expect(presses.accept(id: 10, timestamp: 1), "First hotkey press must arrive")
expect(presses.accept(id: 10, timestamp: 1.1), "A missing key-up must not suppress the next press")
expect(!presses.accept(id: 10, timestamp: 1.1), "The same delivered event must not toggle twice")
expect(!presses.accept(id: 10, timestamp: 1), "Out-of-order stale presses must not toggle")
expect(presses.accept(id: 2, timestamp: 1.1), "Cancel and toggle have independent event identities")
expect(presses.accept(id: 11, timestamp: 1.1), "A newly registered shortcut must not inherit stale state")
expect(!presses.accept(id: 10, timestamp: .nan), "Invalid event timestamps must be rejected")
var accepted = 0
for index in 0..<100 {
    if presses.accept(id: 10, timestamp: 2 + Double(index) * 0.05) { accepted += 1 }
}
expect(accepted == 100, "All 100 successive presses must arrive without requiring release callbacks")

let vocabulary = TechnicalVocabulary.standard
let spellingCases: [(String, String)] = [
    ("QON 모델을 사용해", "Qwen 모델을 사용해"),
    ("QON2.57B 모델", "Qwen 2.5 7B 모델"),
    ("큐웬 2.5 7 빌리언 모델", "Qwen 2.5 7B 모델"),
    ("QWEN2.5 7b를 실행해", "Qwen 2.5 7B를 실행해"),
    ("Qwen 모델 2.57B", "Qwen 모델 2.5 7B"),
    ("QON 2.57B.", "Qwen 2.5 7B."),
    ("큐웬 2.5 7 빌리언?", "Qwen 2.5 7B?"),
    ("Qwen 2.5 7.2B", "Qwen 2.5 7.2B"),
    ("Qwen 2.58B", "Qwen 2.58B"),
    ("Qwen2,5 7B 모델", "Qwen 2.5 7B 모델"),
    ("Qwen2,5를 사용해", "Qwen 2.5를 사용해"),
    ("올라마에서 QON 2.57B 모델로 래그를 구축해", "Ollama에서 Qwen 2.5 7B 모델로 RAG를 구축해"),
    ("ollama와 rag 파이프라인", "Ollama와 RAG 파이프라인"),
    ("알 에이 지 검색을 써", "RAG 검색을 써"),
    ("rag", "RAG"),
    ("a rag for cleaning", "a rag for cleaning"),
    ("게임 렉이 심해", "게임 렉이 심해"),
    ("올라가는 길", "올라가는 길"),
    ("ollama run qwen2.5:7b", "ollama run qwen2.5:7b"),
    ("qwen2.5:7b", "qwen2.5:7b"),
    ("큐웬 2.5 칠 빌리언", "Qwen 2.5 7B"),
    ("Qwen 3 8 billion", "Qwen 3 8B"),
    ("Qwen 1.5b 모델", "Qwen 1.5B 모델"),
    ("7 빌리언 파라미터", "7B 파라미터"),
    ("매출은 7 billion 달러", "매출은 7 billion 달러"),
    ("2.57B를 유지해", "2.57B를 유지해"),
    ("QON 이라고 잘못 읽었어", "QON 이라고 잘못 읽었어"),
    ("큐원 설탕을 샀어", "큐원 설탕을 샀어"),
    ("myQwen2.57B", "myQwen2.57B"),
    ("Qwen2.5-7B-Instruct", "Qwen2.5-7B-Instruct"),
    ("Qwen/Qwen2.5-7B-Instruct", "Qwen/Qwen2.5-7B-Instruct"),
    ("https://example.com/QON2.57B", "https://example.com/QON2.57B"),
    ("QON2.57B@example.com", "QON2.57B@example.com"),
    ("QON2.57B.gguf", "QON2.57B.gguf"),
    ("`QON 모델 2.57B`와 QON 모델", "`QON 모델 2.57B`와 Qwen 모델"),
    ("```\nQON 모델 2.57B\n```", "```\nQON 모델 2.57B\n```"),
    ("Qwen 2.57B와 가격 2.57을 비교해", "Qwen 2.5 7B와 가격 2.57을 비교해"),
    ("안녕하세요. 오늘도 좋은 하루 보내세요.", "안녕하세요. 오늘도 좋은 하루 보내세요."),
    ("", "")
]
for (input, expected) in spellingCases {
    expect(vocabulary.normalize(input) == expected, "Vocabulary correction failed: \(input)")
    expect(vocabulary.normalize(expected) == expected, "Vocabulary correction must be idempotent: \(expected)")
}
expect(TechnicalVocabulary.disabled.normalize("QON 2.57B") == "QON 2.57B", "Disabling vocabulary must preserve the decoder output")
expect(TechnicalVocabulary.disabled.prompt.isEmpty, "Disabling vocabulary must also remove decoding hints")
let custom = TechnicalVocabulary(customTerms: "Gemma, vLLM\nGemma; FlashAttention")
expect(custom.customTerms == ["Gemma", "vLLM", "FlashAttention"], "Custom terms must be trimmed and deduplicated")
expect(custom.prompt.contains("Qwen 2.5 7B") && custom.prompt.contains("FlashAttention"), "Default and custom model names must reach the prompt")
expect(vocabulary.prompt.contains("Ollama") && vocabulary.prompt.contains("RAG"), "User-requested terms must be included in built-in hints")
let excessive = TechnicalVocabulary(customTerms: (0..<100).map { "Term\($0)" }.joined(separator: ","))
expect(excessive.customTerms.count == 24, "Custom vocabulary must remain bounded")
expect(vocabulary.normalize(TranscriptAccumulator.join(["QON", "2.57B 모델"])) == "Qwen 2.5 7B 모델", "Normalization must work across decoder segment boundaries")
print("Passed \(checks) checks: transcription, hotkeys, technical vocabulary, model sizes, preserved numbers and identifiers.")
