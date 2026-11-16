#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache"
options=(--disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security")
if swift build --help | /usr/bin/grep -q 'swiftbuild'; then options+=(--build-system native); fi
# Map private build paths out of executable metadata. Keep installed app and keys untouched.
swift build "${options[@]}" -c release --product VoicePrompt -Xswiftc -file-prefix-map -Xswiftc "$PWD=."
bin_dir=$(swift build "${options[@]}" -c release --show-bin-path)
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
stage="$PWD/dist/public-macos-$version"
if [ -e "$stage" ]; then printf 'Move existing package staging directory aside: %s\n' "$stage" >&2; exit 1; fi
app="$stage/VoicePrompt.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/licenses"
cp "$bin_dir/VoicePrompt" "$app/Contents/MacOS/VoicePrompt"
strip -S "$app/Contents/MacOS/VoicePrompt"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/Icons/AppIcon.icns Resources/Icons/MenuIcon.png Resources/Icons/MenuIcon@2x.png Resources/Images/Mascot.png "$app/Contents/Resources/"
cp public/docs/THIRD_PARTY_NOTICES.md public/LICENSE.txt "$app/Contents/Resources/"
cp public/licenses/WhisperKit-LICENSE.txt public/licenses/Argmax-NOTICES.txt public/licenses/swift-argument-parser-LICENSE.txt public/licenses/Whisper-LICENSE.txt "$app/Contents/Resources/licenses/"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
"$app/Contents/MacOS/VoicePrompt" --version
COPYFILE_DISABLE=1 ditto -c -k --norsrc --noextattr --keepParent "$app" "$PWD/dist/VoicePrompt-$version-macos-arm64.zip"
printf 'Public app archived: dist/VoicePrompt-%s-macos-arm64.zip\n' "$version"
