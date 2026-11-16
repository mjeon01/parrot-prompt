using VoicePrompt.Core;

var count = 0;
void Check(bool condition, string name) { if (!condition) throw new Exception(name); count++; }
var transcript = new Transcript();
transcript.Update([new(0, 1, "안녕하세요"), new(1, 4, "임시")], 0, 4, false);
Check(transcript.Text == "안녕하세요 임시" && transcript.ConfirmedEnd == 1, "older segment is stable");
transcript.Update([new(0, 3, "수정한 문장")], 1, 3, true);
Check(transcript.Text == "안녕하세요 수정한 문장", "final correction replaces draft");
transcript.Update([new(0, 1, "중복")], 0, 1, true);
Check(!transcript.Text.Contains("중복"), "old timestamp rejected");
transcript.Update([new(0, 1, "다시 다시")], 4, 1, true);
Check(transcript.Text.EndsWith("다시 다시"), "spoken repetition preserved");
transcript.AdvanceSilence(28);
Check(transcript.ConfirmedEnd == 28 && transcript.Text.EndsWith("다시 다시"), "silence advances without adding text");
Check(!AudioGate.HasSpeech(new float[16000]), "silence never decoded");
var click = new float[16000]; Array.Fill(click, 0.8f, 0, 320);
Check(!AudioGate.HasSpeech(click), "single click rejected");
var speech = Enumerable.Repeat(0.05f, 320 * 8).ToArray();
Check(AudioGate.HasSpeech(speech), "sustained signal accepted");
foreach (var (source, expected) in new[] {
    ("QON 모델", "Qwen 모델"), ("Qwen 2.57B 모델", "Qwen 2.5 7B 모델"),
    ("Qwen 2.5 7 빌리언 모델", "Qwen 2.5 7B 모델"), ("올라마", "Ollama"),
    ("2.57B", "2.57B"), ("https://qon.com/Qwen2.57B", "https://qon.com/Qwen2.57B"),
    ("`QON 모델`", "`QON 모델`"), ("ollama run qwen:7b", "ollama run qwen:7b"),
    ("Qwen-2.57B.gguf", "Qwen-2.57B.gguf"), ("QON 예시", "QON 예시"),
    ("큐웬 모델", "Qwen 모델"), ("알 에이 지", "RAG") })
    Check(Vocabulary.Normalize(source, true) == expected, "vocabulary: " + source);
Check(Vocabulary.Normalize("QON 모델", false) == "QON 모델", "vocabulary opt out");
Check(!Vocabulary.Normalize("안녕하세요", true).Contains("Qwen"), "hints never concatenated to speech");
Console.WriteLine($"PASS: {count} core regression checks");
