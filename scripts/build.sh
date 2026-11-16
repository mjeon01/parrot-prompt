#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache"
options=(--disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security")
# Swift 6.4's default SwiftBuild requires full Xcode. The native backend works
# with Command Line Tools; older Swift versions already use it by default.
if swift build --help | /usr/bin/grep -q 'swiftbuild'; then options+=(--build-system native); fi
swift build "${options[@]}" -c release --product VoicePrompt
bin_dir=$(swift build "${options[@]}" -c release --show-bin-path)
app="$PWD/dist/VoicePrompt.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
chmod -R u+w "$app/Contents"
cp "$bin_dir/VoicePrompt" "$app/Contents/MacOS/VoicePrompt.new"
mv -f "$app/Contents/MacOS/VoicePrompt.new" "$app/Contents/MacOS/VoicePrompt"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp THIRD_PARTY_NOTICES.md Resources/AppIcon.icns Resources/MenuIcon.png Resources/MenuIcon@2x.png Resources/Mascot.png "$app/Contents/Resources/"
cp .build/checkouts/argmax-oss-swift/LICENSE "$app/Contents/Resources/WhisperKit-LICENSE.md"
signing_root="$PWD/.local-signing"
if [ -n "${VOICEPROMPT_SIGNING_IDENTITY:-}" ]; then
  codesign --force --sign "$VOICEPROMPT_SIGNING_IDENTITY" "$app"
elif [ -f "$signing_root/VoicePrompt.keychain-db" ] && [ -f "$signing_root/identity.txt" ]; then
  password=$(cat "$signing_root/password")
  identity=$(cat "$signing_root/identity.txt")
  security unlock-keychain -p "$password" "$signing_root/VoicePrompt.keychain-db"
  codesign --force --timestamp=none --keychain "$signing_root/VoicePrompt.keychain-db" \
    --sign "$identity" \
    --requirements "=designated => identifier \"local.voiceprompt.mac\" and anchor H\"$identity\"" "$app"
else
  codesign --force --sign - "$app"
  printf '임시 서명입니다. 권한을 빌드 간 유지하려면 ./scripts/setup-signing.sh를 한 번 실행하세요.\n'
fi
codesign --verify --deep --strict "$app"
printf '\nBuilt: %s\n' "$app"
"$app/Contents/MacOS/VoicePrompt" --version
printf '실행 중인 앱에 적용: ./scripts/restart.sh\n'
