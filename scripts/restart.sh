#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="$PWD/dist/VoicePrompt.app"
executable="$app/Contents/MacOS/VoicePrompt"
if [ ! -x "$executable" ]; then
  printf '앱이 없습니다. 먼저 ./scripts/build.sh를 실행해 주세요.\n' >&2
  exit 1
fi
"$executable" --version
# Stop only this project's app, leaving other installations and CLI jobs alone.
for pid in $(/usr/bin/pgrep -x VoicePrompt || true); do
  actual=$(/bin/ps -p "$pid" -o comm= || true)
  if [ "$actual" = "$executable" ]; then
    /bin/kill -TERM "$pid"
    for attempt in {1..50}; do
      if ! /bin/kill -0 "$pid" 2>/dev/null; then break; fi
      sleep 0.1
    done
    if /bin/kill -0 "$pid" 2>/dev/null; then
      printf '앱이 아직 종료 중입니다. 잠시 후 다시 실행해 주세요.\n' >&2
      exit 1
    fi
  fi
done
/usr/bin/open -n "$app"
printf '새 버전을 실행했습니다. 설정 상단의 버전을 확인해 주세요.\n'
