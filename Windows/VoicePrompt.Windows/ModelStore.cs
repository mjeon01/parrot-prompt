using System.Net.Http;
using System.Security.Cryptography;

namespace VoicePrompt.Windows;

public sealed class ModelStore
{
    public static string DirectoryPath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "VoicePrompt");
    public static string ModelPath => Path.Combine(DirectoryPath, "models", "ggml-small.bin");
    public const long ModelBytes = 487601967;
    public const string ModelSha256 = "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b";
    public bool Exists => File.Exists(ModelPath) && new FileInfo(ModelPath).Length == ModelBytes;

    public async Task EnsureAsync(bool download, IProgress<string> progress, CancellationToken token)
    {
        if (Exists)
        {
            progress.Report("저장된 모델 무결성을 확인하고 있어요.");
            if (await ValidAsync(ModelPath, token)) return;
            if (!download) throw new IOException("모델 파일이 손상되었습니다. 모델 준비를 다시 눌러 주세요.");
        }
        else if (!download) throw new FileNotFoundException("처음 한 번 모델을 다운로드해 주세요.");

        Directory.CreateDirectory(Path.GetDirectoryName(ModelPath)!);
        var temporary = ModelPath + "." + Guid.NewGuid().ToString("N") + ".download";
        try
        {
            using var http = new HttpClient { Timeout = TimeSpan.FromMinutes(30) };
            using var response = await http.GetAsync("https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin", HttpCompletionOption.ResponseHeadersRead, token);
            response.EnsureSuccessStatusCode();
            await using (var input = await response.Content.ReadAsStreamAsync(token))
            await using (var output = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 81920, true))
            {
                var buffer = new byte[81920];
                long count = 0;
                var lastPercent = -1;
                int read;
                while ((read = await input.ReadAsync(buffer, token)) > 0)
                {
                    count += read;
                    if (count > ModelBytes) throw new IOException("예상한 모델 크기와 다릅니다.");
                    await output.WriteAsync(buffer.AsMemory(0, read), token);
                    var percent = (int)(count * 100 / ModelBytes);
                    if (percent != lastPercent) { progress.Report($"모델 다운로드 {percent}% · 약 488 MB"); lastPercent = percent; }
                }
            }
            if (!await ValidAsync(temporary, token)) throw new IOException("모델 검증에 실패했습니다. 연결을 확인한 뒤 다시 시도해 주세요.");
            File.Move(temporary, ModelPath, true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }

    private static async Task<bool> ValidAsync(string path, CancellationToken token)
    {
        if (new FileInfo(path).Length != ModelBytes) return false;
        await using var stream = File.OpenRead(path);
        var hash = await SHA256.HashDataAsync(stream, token);
        return Convert.ToHexString(hash).Equals(ModelSha256, StringComparison.OrdinalIgnoreCase);
    }
}
