#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
trap 'printf "\n업데이트 중 오류가 났습니다. 위 오류 문구를 알려 주세요.\n"; read -r -p "Enter를 누르면 닫습니다. "' ERR
./scripts/check.sh
./scripts/build.sh
mkdir -p var/qa
if [ -f "$PWD/dist/VoicePromptData/model-path.txt" ]; then
  "$PWD/dist/VoicePrompt.app/Contents/MacOS/VoicePrompt" --check-preview 2>&1 | tee var/qa/preview-check.txt
fi
"$PWD/dist/VoicePrompt.app/Contents/MacOS/VoicePrompt" --check-hotkeys 2>&1 | tee var/qa/hotkey-check.txt
./scripts/restart.sh
printf '\n업데이트 완료. 설치한 버전은 다음과 같습니다.\n'
"$PWD/dist/VoicePrompt.app/Contents/MacOS/VoicePrompt" --version
printf '단축키 검사 → ⌃⇧Space를 5번 눌러 입력 감지 5회인지 확인 → 검사 끝내기.\n'
printf '그다음 입력창에서 ⌃⇧Space로 녹음을 시작하고 다시 눌러 마무리하세요.\n'
