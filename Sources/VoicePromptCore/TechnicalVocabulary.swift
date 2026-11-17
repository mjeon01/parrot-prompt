import Foundation

/// Local decoder hints and narrowly scoped spelling rules, not a text rewriter.
public struct TechnicalVocabulary: Sendable {
    public let enabled: Bool
    public let customTerms: [String]
    public static let standard = TechnicalVocabulary()
    public static let disabled = TechnicalVocabulary(enabled: false)
    // Spellings checked against the official sources in docs/TECHNICAL_VOCABULARY.md.
    public static let defaultTerms = [
        "README", "GitHub", "Markdown", "JSON", "API", "SDK", "CLI", "Python",
        "JavaScript", "TypeScript", "React", "Docker", "SQL", "npm",
        "Qwen", "Qwen 2.5 7B", "Ollama", "RAG", "LLM", "Llama", "Gemma", "DeepSeek",
        "LoRA", "QLoRA", "GGUF", "MLX", "vLLM", "Hugging Face", "Transformers",
        "embedding", "tokenizer", "토큰", "파라미터", "임베딩", "벡터 검색", "양자화", "파인튜닝"
    ]

    public init(enabled: Bool = true, customTerms: String = "") {
        self.enabled = enabled
        var seen = Set<String>()
        self.customTerms = customTerms.components(separatedBy: CharacterSet(charactersIn: ",\n;"))
            .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .prefix(24).map { $0 }
    }

    public var prompt: String {
        guard enabled else { return "" }
        // Vocabulary only: Whisper conditioning is prior text, not an LLM
        // instruction. The engine also limits the encoded prompt to 160 tokens.
        return (Self.defaultTerms + customTerms).joined(separator: ", ")
    }

    public func normalize(_ text: String) -> String {
        guard enabled, !text.isEmpty else { return text }
        // Keep code, URLs, repository identifiers and file names verbatim.
        let matches = Self.protected.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var result = ""
        var start = text.startIndex
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            result += normalizePlain(String(text[start..<range.lowerBound]))
            result += text[range]
            start = range.upperBound
        }
        return result + normalizePlain(String(text[start...]))
    }

    private func normalizePlain(_ text: String) -> String {
        var result = text
        for (pattern, replacement) in Self.rules {
            result = pattern.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: replacement)
        }
        for (pattern, replacement) in Self.englishSpellings {
            result = pattern.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: replacement)
        }
        let range = NSRange(result.startIndex..., in: result)
        if Self.ragContext.firstMatch(in: result, range: range) != nil {
            result = Self.ragSpelling.stringByReplacingMatches(in: result, range: range, withTemplate: "RAG")
        }
        return result
    }

    private static let protected = try! NSRegularExpression(pattern:
        #"(?s:```.*?(?:```|$))|`[^`\n]*(?:`|$)|https?://\S+|\S*[/_@]\S*|(?<![A-Za-z0-9_])ollama\s+(?:run|serve|pull|list|ps|show|create|rm|stop|push|cp)\b[^\n]*|[A-Za-z0-9][A-Za-z0-9._-]*:[A-Za-z0-9][A-Za-z0-9._-]*|[A-Za-z][A-Za-z0-9.]*-[A-Za-z0-9][A-Za-z0-9._-]*|[\p{L}\p{N}][\p{L}\p{N}._-]*\.(?:gguf|safetensors|json|py|swift|md|txt|rst|js|ts|tsx|jsx|yaml|yml|toml)(?![A-Za-z0-9_])"#,
        options: [.caseInsensitive])
    private static let ragContext = try! NSRegularExpression(pattern:
        #"(?<![A-Za-z0-9_])(?:Qwen|Ollama|LLM|embedding)(?![A-Za-z0-9_])|검색|증강|임베딩|벡터|파이프라인|(?:rag|래그)(?:를|을|로|으로)?\s*(?:기반|시스템|구축|구현|적용|연결|사용|챗봇)|^\s*(?:rag|래그)[.!?]?\s*$"#,
        options: [.caseInsensitive])
    private static let ragSpelling = try! NSRegularExpression(pattern:
        #"(?<![\p{L}\p{N}_])(?:rag|래그)(?![A-Za-z0-9_])"#, options: [.caseInsensitive])

    // Match a whole term, optionally followed by Korean particles. Do not turn
    // 리드미컬, 리듬위주 or the ordinary phrase "read me a story" into README.
    private static let termEnd = #"(?=$|[^\p{L}\p{N}_]|(?:에서|에게|으로|이라고|이라는|라고|라는|이랑|랑|처럼|보다|부터|까지|마저|조차|밖에|하고|이든|든지|든|이나|나|이며|이고|이|가|을|를|은|는|와|과|에|의|도|만|로|요|야)(?:은|는|도|만|요)?(?=$|[^\p{L}\p{N}_]))"#
    private static let englishSpellings: [(NSRegularExpression, String)] = [
        (#"readme|리드\s*미|리듬위"#, "README"),
        (#"github|깃\s*허브|깃\s*헙|기트\s*허브"#, "GitHub"),
        (#"markdown|마크\s*다운"#, "Markdown"),
        (#"json|제이\s*에스\s*오\s*엔|제이\s*슨(?=(?:으로|로|의|을)?\s+(?:파일|데이터|객체|배열|형식|포맷|파싱|응답|변환))"#, "JSON"),
        (#"api|에이\s*피\s*아이"#, "API"),
        (#"sdk|에스\s*디\s*케이"#, "SDK"),
        (#"cli|씨\s*엘\s*아이|시\s*엘\s*아이"#, "CLI"),
        (#"파이썬|파이선"#, "Python"),
        (#"javascript|자바\s*스크립트"#, "JavaScript"),
        (#"typescript|타입\s*스크립트"#, "TypeScript"),
        (#"리액트"#, "React"),
        (#"docker|도커"#, "Docker"),
        (#"sql|에스\s*큐\s*엘"#, "SQL"),
        (#"npm|엔\s*피\s*엠"#, "npm")
    ].map { (try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}_])(?:"# + $0.0 + ")" + termEnd, options: [.caseInsensitive]), $0.1) }

    private static let rules: [(NSRegularExpression, String)] = [
        // The user-reported QON error and ambiguous Korean aliases require an
        // adjacent model/version cue. Ordinary Korean words are left alone.
        (#"(?<![\p{L}\p{N}_])(?:qon|큐원|큐온|큐언|쿠엔)(?=\s*(?:모델|[0-9]))"#, "Qwen"),
        (#"(?<![\p{L}\p{N}_])(?:qwen|큐웬|큐엔|쿼엔)(?![A-Za-z_])"#, "Qwen"),
        (#"(?<![\p{L}\p{N}_])(?:ollama|올라마)(?![A-Za-z0-9_])"#, "Ollama"),
        (#"(?<![\p{L}\p{N}_])알\s*에이\s*지(?![A-Za-z0-9_])"#, "RAG"),
        (#"(?<![\p{L}\p{N}_])Qwen\s*2\s*,\s*5(?![0-9])"#, "Qwen 2.5"),
        // This exact concatenation is the reported Qwen 2.5 / 7B confusion.
        // A bare 2.57B, or another model/version, is deliberately not split.
        (#"(?<![\p{L}\p{N}_])(Qwen(?:\s+모델)?)\s*2\.5\s*7\s*(?:billion|빌리언|B)(?![A-Za-z0-9]|\.[0-9])"#, "$1 2.5 7B"),
        (#"(?<![\p{L}\p{N}_])(Qwen(?:\s+모델)?)\s*(\d+(?:\.\d+)?)\s+(?:칠|세븐)\s*(?:빌리언|비|B)(?![A-Za-z0-9]|\.[0-9])"#, "$1 $2 7B"),
        (#"(?<![\p{L}\p{N}_])(Qwen(?:\s+모델)?)\s*(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)\s*(?:billion|빌리언|B)(?![A-Za-z0-9]|\.[0-9])"#, "$1 $2 $3B"),
        (#"(?<![\p{L}\p{N}_])(Qwen)\s*(\d+(?:\.\d+)?)\s*(?:billion|빌리언|B)(?![A-Za-z0-9]|\.[0-9])"#, "$1 $2B"),
        (#"(?<![\p{L}\p{N}_.])(\d+(?:\.\d+)?)\s*(?:billion|빌리언)\s*(?=모델|파라미터)"#, "$1B ")
    ].map { (try! NSRegularExpression(pattern: $0.0, options: [.caseInsensitive]), $0.1) }
}
