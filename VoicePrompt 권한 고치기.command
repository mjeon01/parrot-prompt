#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
trap 'printf "\n설정에 실패했습니다. 위 오류 문구를 확인해 주세요.\n"; read -r -p "Enter를 누르면 닫습니다. "' ERR
./scripts/setup-signing.sh
./scripts/build.sh
# Drop only VoicePrompt's obsolete ad-hoc accessibility grant, once. The user
# will grant the new certificate-backed identity through System Settings.
if [ ! -f .local-signing/accessibility-reset-v1 ]; then
  /usr/bin/tccutil reset Accessibility local.voiceprompt.mac
  touch .local-signing/accessibility-reset-v1
fi
./scripts/restart.sh
/usr/bin/open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'
/usr/bin/open -R "$PWD/dist/VoicePrompt.app"
printf '\n시스템 설정의 손쉬운 사용에 VoicePrompt.app을 추가하고 켜 주세요.\n같은 서명으로 다음 업데이트부터 권한을 유지합니다.\n'
