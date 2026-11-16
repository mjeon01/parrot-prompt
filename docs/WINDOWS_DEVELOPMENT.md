# Windows development (private source)

The public repository is `mjeon01/voiceprompt`; this source belongs only in the existing private `mjeon01/parrot-prompt` repository.
Never change the private repository visibility or push its history to the public remote.

## Build

.NET 10 SDK, Windows 11 x64 (or a Mac for cross compilation). Whisper.net CPU runtime requires AVX2/FMA/F16C and a recent Visual C++ x64 runtime on Windows.

```powershell
dotnet run --project Windows/VoicePrompt.Checks -c Release
dotnet restore Windows/VoicePrompt.Windows -r win-x64 --locked-mode
./scripts/package-windows.ps1
```

`VoicePrompt.Core` contains timestamp accumulation, silence detection and bounded vocabulary rules.
`VoicePrompt.Windows` contains microphone capture, explicit-download model store, Whisper adapter, WPF UI, Win32 hotkeys and Unicode insertion.
`VoicePrompt.Checks` is a dependency-free regression executable. `packages.lock.json` pins NuGet dependencies.
Windows and Swift vocabulary normalization are deliberately narrow and separately tested; the initial Windows implementation supports a smaller set of rules.

Audio stays in a bounded in-memory buffer. Model download uses a temporary file and verifies its exact length and SHA-256 before promotion.
Normal offline loading hashes the installed model without network fallback. No automatic updater, analytics or transcript log is implemented.
Cancellation waits for the processor before accepting a new session. UI Automation must identify the same non-password input target before Unicode batches are sent.
The app never sends Enter. Unicode insertion does not use the clipboard; Copy is explicit.

## Verification and release

The manual `Windows private build` workflow runs only in the private repository and creates a self-contained x64 archive.
It checks core regressions, WPF construction, native INPUT layout, a rendered UI, and CPU inference on the public JFK sample using the same small model distributed to users.
These are not hardware microphone or physical keyboard tests. Review `var/qa/windows-*` artifacts before publication.
The job has a 20-minute timeout and 2-day artifact retention; private Actions uses the account's included/paid compute.

Public docs are authored under `public/`. `scripts/public-files.txt` is the explicit allowlist.
`python3 scripts/export-public.py var/public-export` refuses nonempty destinations, checks links and sensitive patterns,
and copies only approved documents/images/license texts. Initialize a **new** Git repository in that output directory;
do not copy `.git`, attach the public remote to the private source root, or copy CI artifacts indiscriminately.
Only the audited `.zip` application archives and `SHA256SUMS.txt` go in public Releases.

The macOS archive is created by `bash scripts/package-macos-public.sh`; it uses an ad-hoc signature, maps source paths,
and never reads the private signing directory or replaces the user's installed app. Code signing/notarization is future work.
