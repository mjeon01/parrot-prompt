# 개발 안내

명령은 프로젝트 루트에서 실행합니다. Swift Package Manager가 `Sources`의 하위 폴더를
자동으로 포함합니다. 코어 검사 실행 파일은 `Tests/VoicePromptChecks`에 있습니다.

## 빌드와 검사

```sh
./scripts/check.sh                # 코어 회귀 검사
./scripts/build.sh --verify-only  # 임시 앱 패키징 검사; 설치 앱은 유지
./scripts/setup-signing.sh        # 개인용 고정 서명 준비, 처음 한 번
./scripts/build.sh                # 고정 서명 후 dist/VoicePrompt.app 교체
./scripts/restart.sh
```

`--verify-only`는 임시 번들을 ad-hoc 서명해 리소스 경로와 패키징을 검증합니다.
개인 인증서 서명이나 실제 마이크·키보드 작동까지 확인하는 검사는 아닙니다.
일반 빌드는 서명과 검증이 성공해야 설치된 앱을 교체합니다.

Finder에서 실행하려면 `scripts/launchers`의 업데이트·재실행·권한 복구 명령을
사용합니다. 실행한 터미널의 현재 폴더와 관계없이 프로젝트 루트를 찾습니다.

```sh
dist/VoicePrompt.app/Contents/MacOS/VoicePrompt --check-hotkeys
VOICEPROMPT_DATA_DIR="$PWD/dist/VoicePromptData" \
  dist/VoicePrompt.app/Contents/MacOS/VoicePrompt --stream-file /path/to/audio.wav
```

OS 단축키 전달은 앱 설정의 **단축키 검사**에서 수신 횟수를 확인합니다.
자세한 결과와 실행 환경의 제한은 [검증 기록](VERIFICATION.md)에 있습니다.

## 기술 용어 처리

`Sources/VoicePromptCore/TechnicalVocabulary.swift`에 기본 용어와 표기 규칙을 둡니다.
`SpeechEngine`은 용어를 토큰으로 변환해 WhisperKit의 `promptTokens`에 전달합니다.
`prefixTokens`로 출력 문장을 강제하지 않습니다. 힌트는 특수 토큰을 제외한 최대 160토큰이며,
추가 용어는 앞에서부터 최대 24개, 각 60글자로 제한합니다.

전사 누적에는 원본 구간과 시각을 유지하고, 화면 표시와 최종 붙여넣기에 같은 보정을 적용합니다.
보정은 Qwen·Ollama 이름, RAG 기술 문맥과 명시적인 모델 크기를 다룹니다. `2.57B`를 무조건 나누지 않으며,
사용자가 보고한 `Qwen 2.57B` 조합만 `Qwen 2.5 7B`로 교정합니다.
회귀 검사에는 비활성화, 문장 끝 구두점, 구간 경계, 숫자·코드·파일명 보존이 포함됩니다.
기본 용어와 공식 자료는 [기술 용어 사전](TECHNICAL_VOCABULARY.md)에 있습니다.

## 리소스

원본 로고는 `assets/branding/parrot.png`입니다. 아이콘을 다시 만들 때는 다음 명령을
사용합니다. 결과는 `Resources/Icons`와 `Resources/Images`에 저장됩니다.

```sh
swift scripts/assets/make-icon.swift
```

번들에는 빌드 스크립트가 필요한 아이콘·마스코트·라이선스를 복사합니다.
원본 이미지와 개발용 문서는 앱 번들에 포함하지 않습니다.

## 로컬 전용 파일

| 경로 | 내용 |
|---|---|
| `dist/VoicePrompt.app` | 실행 앱 |
| `dist/VoicePromptData` | 다운로드한 모델·사전 |
| `var/qa` | 검사용 음성·이벤트 검사 결과 |
| `.local-signing` | 개인 인증서·키체인·암호, 공유 금지 |
| `.build` | 빌드·의존성 캐시 |
| `.swiftpm` | 이 Mac에만 적용되는 SwiftPM 설정 |

위 폴더는 Git에서 제외합니다. 앱이 모델을 찾고 기존 권한을 유지할 수 있도록
`dist`와 `.local-signing`의 위치를 유지합니다. `Package.resolved`에는 공식 원격
저장소와 고정 버전을 기록하고, 개인 로컬 미러 설정은 커밋하지 않습니다.
