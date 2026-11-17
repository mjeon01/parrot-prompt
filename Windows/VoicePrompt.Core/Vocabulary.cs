using System.Text.RegularExpressions;

namespace VoicePrompt.Core;

public static class Vocabulary
{
    public const string Prompt = "README, GitHub, Markdown, JSON, API, SDK, CLI, Python, JavaScript, TypeScript, React, Docker, SQL, npm, Qwen, Qwen 2.5 7B, Ollama, RAG, LLM, Llama, Gemma, DeepSeek, LoRA, QLoRA, GGUF, MLX, vLLM, Hugging Face, Transformers, embedding, tokenizer, 토큰, 파라미터, 임베딩, 벡터 검색, 양자화, 파인튜닝";
    private static readonly Regex Protected = new(@"(?s:```.*?(?:```|$))|`[^`\n]*(?:`|$)|https?://\S+|\S*[/_@]\S*|(?<![A-Za-z0-9_])ollama\s+(?:run|serve|pull|list|ps|show|create|rm|stop|push|cp)\b[^\n]*|[A-Za-z0-9][A-Za-z0-9._-]*:[A-Za-z0-9][A-Za-z0-9._-]*|[A-Za-z][A-Za-z0-9.]*-[A-Za-z0-9][A-Za-z0-9._-]*|[\p{L}\p{N}][\p{L}\p{N}._-]*\.(?:gguf|safetensors|json|py|swift|md|txt|rst|js|ts|tsx|jsx|yaml|yml|toml)(?![A-Za-z0-9_])", RegexOptions.IgnoreCase);
    private const string TermEnd = @"(?=$|[^\p{L}\p{N}_]|(?:에서|에게|으로|이라고|이라는|라고|라는|이랑|랑|처럼|보다|부터|까지|마저|조차|밖에|하고|이든|든지|든|이나|나|이며|이고|이|가|을|를|은|는|와|과|에|의|도|만|로|요|야)(?:은|는|도|만|요)?(?=$|[^\p{L}\p{N}_]))";
    private static readonly (Regex Pattern, string Spelling)[] EnglishSpellings = new (string Aliases, string Spelling)[] {
        (@"readme|리드\s*미|리듬위", "README"),
        (@"github|깃\s*허브|깃\s*헙|기트\s*허브", "GitHub"),
        (@"markdown|마크\s*다운", "Markdown"),
        (@"json|제이\s*에스\s*오\s*엔|제이\s*슨(?=(?:으로|로|의|을)?\s+(?:파일|데이터|객체|배열|형식|포맷|파싱|응답|변환))", "JSON"),
        (@"api|에이\s*피\s*아이", "API"),
        (@"sdk|에스\s*디\s*케이", "SDK"),
        (@"cli|씨\s*엘\s*아이|시\s*엘\s*아이", "CLI"),
        (@"파이썬|파이선", "Python"),
        (@"javascript|자바\s*스크립트", "JavaScript"),
        (@"typescript|타입\s*스크립트", "TypeScript"),
        (@"리액트", "React"),
        (@"docker|도커", "Docker"),
        (@"sql|에스\s*큐\s*엘", "SQL"),
        (@"npm|엔\s*피\s*엠", "npm")
    }.Select(term => (new Regex(@"(?<![\p{L}\p{N}_])(?:" + term.Aliases + ")" + TermEnd, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant), term.Spelling)).ToArray();
    private static string Replace(string text, string pattern, string replacement) => Regex.Replace(text, pattern, replacement, RegexOptions.IgnoreCase);

    public static string Normalize(string text, bool enabled)
    {
        if (!enabled) return text;
        var result = new System.Text.StringBuilder();
        var start = 0;
        foreach (Match match in Protected.Matches(text))
        {
            result.Append(Plain(text[start..match.Index]));
            result.Append(match.Value);
            start = match.Index + match.Length;
        }
        return result.Append(Plain(text[start..])).ToString();
    }

    private static string Plain(string text)
    {
        text = Replace(text, @"(?<![\p{L}\p{N}_])(?:qon|큐원|큐온|큐언|쿠엔)(?=\s*(?:모델|[0-9]))", "Qwen");
        text = Replace(text, @"(?<![\p{L}\p{N}_])(?:qwen|큐웬|큐엔|쿼엔)(?![A-Za-z_])", "Qwen");
        text = Replace(text, @"(?<![\p{L}\p{N}_])(?:ollama|올라마)(?![A-Za-z0-9_])", "Ollama");
        text = Replace(text, @"(?<![\p{L}\p{N}_])알\s*에이\s*지(?![A-Za-z0-9_])", "RAG");
        text = Replace(text, @"(?<![\p{L}\p{N}_])Qwen\s*2\s*,\s*5(?![0-9])", "Qwen 2.5");
        text = Replace(text, @"(?<![\p{L}\p{N}_])(Qwen(?:\s+모델)?)\s*2\.5\s*7\s*(?:billion|빌리언|B)(?![A-Za-z0-9]|\.[0-9])", "$1 2.5 7B");
        text = Replace(text, @"(?<![\p{L}\p{N}_])(Qwen(?:\s+모델)?)\s*(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)\s*(?:billion|빌리언|B)(?![A-Za-z0-9]|\.[0-9])", "$1 $2 $3B");
        foreach (var term in EnglishSpellings) text = term.Pattern.Replace(text, term.Spelling);
        return text;
    }
}
