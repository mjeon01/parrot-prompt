$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$output = Join-Path $pwd 'dist/VoicePrompt-windows-x64'
if (Test-Path $output) { throw 'Output already exists. Move it aside before packaging to avoid including stale files.' }
dotnet publish Windows/VoicePrompt.Windows/VoicePrompt.Windows.csproj -c Release -r win-x64 --self-contained true -p:RestoreLockedMode=true -p:PublishSingleFile=false -p:DebugType=None -p:DebugSymbols=false -o $output
if ($LASTEXITCODE -ne 0) { throw 'Windows publish failed' }
Copy-Item public/README.md "$output/README.md"
Copy-Item public/LICENSE.txt "$output/LICENSE.txt"
Copy-Item public/docs "$output/docs" -Recurse
Copy-Item public/assets "$output/assets" -Recurse
Copy-Item public/licenses "$output/licenses" -Recurse
# Symbols/source and other platforms' native runtimes must not enter the archive.
Get-ChildItem $output -Filter '*.pdb' -Recurse | Remove-Item
if (Test-Path "$output/runtimes") {
    Get-ChildItem "$output/runtimes" -Directory | Where-Object Name -ne 'win-x64' | Remove-Item -Recurse
}
$forbidden = Get-ChildItem $output -Recurse -File | Where-Object { $_.Extension -in '.cs','.swift','.pfx','.p12','.key','.pdb' }
if ($forbidden) { throw 'Unexpected source, symbols or signing material in package' }
$version = ([xml](Get-Content Windows/VoicePrompt.Windows/VoicePrompt.Windows.csproj)).Project.PropertyGroup.Version
Compress-Archive -Path $output -DestinationPath "dist/VoicePrompt-$version-windows-x64.zip"
