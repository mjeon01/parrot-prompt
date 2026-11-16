#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
verify_only=false
case "${1:-}" in
  "") ;;
  --verify-only) verify_only=true ;;
  *) printf '사용법: %s [--verify-only]\n' "$0" >&2; exit 2 ;;
esac
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache"
options=(--disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security")
# Swift 6.4's default SwiftBuild requires full Xcode. The native backend works
# with Command Line Tools; older Swift versions already use it by default.
if swift build --help | /usr/bin/grep -q 'swiftbuild'; then options+=(--build-system native); fi
swift build "${options[@]}" -c release --product VoicePrompt
bin_dir=$(swift build "${options[@]}" -c release --show-bin-path)
install_app="$PWD/dist/VoicePrompt.app"
mkdir -p "$PWD/dist"
staging=$(mktemp -d "$PWD/dist/.VoicePrompt-build.XXXXXX")
trap 'rm -rf "$staging"' EXIT
app="$staging/VoicePrompt.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
chmod -R u+w "$app/Contents"
cp "$bin_dir/VoicePrompt" "$app/Contents/MacOS/VoicePrompt.new"
mv -f "$app/Contents/MacOS/VoicePrompt.new" "$app/Contents/MacOS/VoicePrompt"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp docs/THIRD_PARTY_NOTICES.md Resources/Icons/AppIcon.icns Resources/Icons/MenuIcon.png Resources/Icons/MenuIcon@2x.png Resources/Images/Mascot.png "$app/Contents/Resources/"
cp .build/checkouts/argmax-oss-swift/LICENSE "$app/Contents/Resources/WhisperKit-LICENSE.md"
signing_root="$PWD/.local-signing"
if [ "$verify_only" = true ]; then
  # Validate packaging in a temporary bundle without accessing the private
  # signing identity or replacing the installed app.
  codesign --force --sign - "$app"
elif [ -n "${VOICEPROMPT_SIGNING_IDENTITY:-}" ]; then
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
"$app/Contents/MacOS/VoicePrompt" --version
if [ "$verify_only" = true ]; then
  printf 'Release 컴파일·임시 앱 패키징·서명 무결성 검사 완료. 설치 앱은 교체하지 않았습니다.\n'
  exit 0
fi
# Never replace the installed app with an unsigned/partially signed build if
# access to the local keychain fails. Publish only after validation succeeds.
if [ -e "$install_app" ]; then mv "$install_app" "$staging/previous.app"; fi
if ! mv "$app" "$install_app"; then
  if [ -e "$staging/previous.app" ]; then mv "$staging/previous.app" "$install_app"; fi
  exit 1
fi
printf '\nBuilt: %s\n' "$install_app"
printf '실행 중인 앱에 적용: ./scripts/restart.sh\n'
