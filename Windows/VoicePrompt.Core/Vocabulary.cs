using System.Text.RegularExpressions;

namespace VoicePrompt.Core;

public static class Vocabulary
{
    public const string Prompt = "Qwen, Qwen 2.5 7B, Ollama, RAG, LLM, Llama, Gemma, DeepSeek, LoRA, QLoRA, GGUF, MLX, vLLM, Hugging Face, Transformers, embedding, tokenizer, 토큰, 파라미터, 임베딩, 벡터 검색, 양자화, 파인튜닝";
    private static readonly Regex Protected = new(@"(?s:```.*?(?:```|$))|`[^`\n]*(?:`|$)|https?://\S+|\S*[/_@]\S*|(?<![A-Za-z0-9_])ollama\s+(?:run|serve|pull|list|ps|show|create|rm|stop|push|cp)\b[^\n]*|[A-Za-z0-9][A-Za-z0-9._-]*:[A-Za-z0-9][A-Za-z0-9._-]*|[A-Za-z][A-Za-z0-9.]*-[A-Za-z0-9][A-Za-z0-9._-]*|[A-Za-z0-9][A-Za-z0-9._-]*\.(?:gguf|safetensors|json|py|swift)\b", RegexOptions.IgnoreCase);
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
        return text;
    }
}
