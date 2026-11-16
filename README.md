<p align="center">
  <img src="assets/branding/parrot.png" alt="VoicePrompt 앵무새 로고" width="280">
</p>

<h1 align="center">VoicePrompt</h1>

<p align="center">단축키를 누르고 말하면, 말한 내용을 그대로 프롬프트 입력창에 적어 주는 macOS 앱</p>

## 무엇을 하나요

- **단축키 한 번으로 받아쓰기**: `⌃⇧Space`를 누르고 말한 뒤 다시 누르면, 커서가 있던 입력창에 문장이 들어갑니다.
  Claude Code, ChatGPT, 브라우저 등 어디서나 쓸 수 있습니다.
- **실시간 미리보기**: 말하는 동안 작은 카드에 인식 중인 글자가 바로 표시됩니다.
- **완전 로컬·무료**: 음성 인식이 Mac 안에서만 돌아갑니다. 음성이 외부로 나가지 않고,
  API 키나 구독이 필요 없습니다.
- 입력만 하고 Enter는 누르지 않으므로, 내용을 확인한 뒤 직접 전송하면 됩니다.
- **LLM 용어 인식**: Qwen·Ollama·RAG·LoRA·GGUF 등의 표기를 인식 힌트로 전달하고,
  반복되는 모델명 오인식과 `Qwen 2.5 7B` 띄어쓰기를 보정합니다.

## 어떻게 만들었나요

| 구성 | 사용한 것 | 만든 곳 |
|---|---|---|
| 음성 인식 모델 | **Whisper large-v3 turbo** (`large-v3-v20240930_turbo`, MIT 라이선스) | [OpenAI](https://github.com/openai/whisper) |
| 추론 엔진 | [WhisperKit](https://github.com/argmaxinc/WhisperKit) 1.1.1: Whisper를 Core ML로 Apple Silicon에서 실행 (MIT 라이선스) | [Argmax](https://www.argmaxinc.com) |
| 앱 | Swift + SwiftUI/AppKit 메뉴 막대 앱 (Swift Package Manager, Xcode 없이 명령줄 도구로 빌드) | 직접 개발 |
| 단축키 | Carbon 전역 단축키 | Apple (macOS 기본 API) |
| 자동 입력 | 손쉬운 사용(Accessibility)으로 포커스 확인 후 `⌘V` 붙여넣기, 기존 클립보드 복원 | Apple (macOS 기본 API) |

- **실시간 처리**: 새 음성이 0.3초 쌓일 때마다 다시 인식해, 약 0.5초 간격으로 미리보기를 갱신합니다.
  확정된 앞부분은 고정하고 뒷부분만 바꿉니다.
- **잘못된 문구 차단**: Whisper가 무음에서 "감사합니다." 같은 문구를 지어내는 현상을
  음성 크기 검사와 상투 문구 필터로 막습니다.

## 시작하기

Apple Silicon Mac, macOS 14 이상이 필요합니다.

```sh
./scripts/setup-signing.sh   # 처음 한 번: 빌드 후에도 자동 입력 권한이 유지되도록 로컬 서명 준비
./scripts/build.sh
open dist/VoicePrompt.app
```

1. 설정에서 **음성 인식 모델**(약 1.5 GB 다운로드), **마이크**, **자동 입력** 권한을 준비합니다.
2. 입력창을 클릭하고 `⌃⇧Space`를 누른 뒤 말합니다.
3. 다시 `⌃⇧Space`를 누르면 문장이 입력됩니다. `Esc`는 취소입니다.

단축키는 설정에서 바꿀 수 있습니다. 검증은 `./scripts/check.sh`로 실행합니다.

### 단축키가 잘 안 눌릴 때

v0.3.1부터 기본 조합은 **Control + Shift + Space**입니다. 이전 기본값인
`⌃⌥Space`는 macOS 입력 언어 전환과, `⌃⌘Space`는 이모지·기호 창과 겹칩니다.
앱이 시스템 충돌을 확인하면 추천 조합으로 바꾸고 설정에서 안내합니다.
시스템 설정 자체는 바꾸지 않습니다. 기존 조합은 앱 설정에 백업합니다.
다른 앱이 이미 등록한 조합은 오류를 표시하며 기존 단축키를 유지합니다.

1. `scripts/launchers/VoicePrompt 업데이트.command`를 Finder에서 실행해 빌드·이벤트 검사·재실행을 완료합니다.
2. 설정의 **단축키 검사**를 켜고 표시된 조합을 5번 누릅니다.
3. **입력 감지 5회**인지 확인하고 **검사 끝내기**를 누릅니다. 이 검사는 녹음하지 않습니다.
4. 다른 앱에 커서를 둔 상태에서도 검사한 뒤 실제 녹음 시작·완료를 확인하세요.

개발용 `dist/VoicePrompt.app/Contents/MacOS/VoicePrompt --check-hotkeys`는
Carbon 등록·충돌·누락된 키 해제·연속 100회 이벤트를 검사합니다.
실제 키보드 입력을 다른 앱에 보내지 않으며 물리 키보드 검사를 대신하지 않습니다.
키체인 서명이 실패하면 빌드는 기존 설치 앱을 교체하지 않습니다.

### 모델명과 전문 용어

v0.4.0의 **LLM 용어 보정**은 기본으로 켜져 있습니다. 예를 들어 `QON 모델`은
`Qwen 모델`로, `Qwen 2.57B`는 `Qwen 2.5 7B`로 표시합니다.
`7 빌리언`도 Qwen 모델명이나 파라미터 문맥에서 `7B`로 표기합니다.
모델 문맥이 없는 `2.57B`, 일반 숫자, 코드·URL·모델 파일명은 그대로 둡니다.

설정의 **추가할 용어**에 자주 쓰는 이름을 쉼표로 적으면 다음 녹음의 인식 힌트에
포함됩니다. 추가 용어는 강제 치환 사전이 아니므로 실제 음성에 따라 오인식이 남을 수 있습니다.
보정 기능을 끄면 용어 힌트와 표기 보정을 모두 중단합니다. 처리에는 로컬 Whisper만 사용합니다.
기본 목록, 보정 예시와 공식 출처는 [기술 용어 사전](docs/TECHNICAL_VOCABULARY.md)에 정리했습니다.

## 폴더 구조

```text
Sources/
  VoicePrompt/          # macOS 앱
    App/                # 시작점, 앱 상태, 버전
    Audio/              # 마이크 캡처
    Transcription/      # 로컬 음성 인식
    Input/              # 단축키, 커서 입력
    UI/                 # 설정, 미리보기
    Diagnostics/        # 앱 내부 검증 도구
  VoicePromptCore/      # 전사 누적, 입력 정책 등 공통 로직
Tests/VoicePromptChecks/ # 자동 검사
Resources/              # Info.plist, Icons/, Images/
assets/branding/        # 로고 원본
scripts/                # 빌드, 검사, 서명, 재실행
  launchers/            # Finder에서 실행하는 .command 파일
  assets/               # 아이콘 생성 도구
docs/                   # 개발 안내, 검증 기록, 라이선스 고지
```

로컬 실행 파일과 모델은 `dist/`, 검사 자료는 `var/qa/`, 개인 서명 키는
`.local-signing/`에 보관하며 Git에 올리지 않습니다.

Finder용 명령은 [scripts/launchers](scripts/launchers)에 모았습니다.
개발 방법은 [개발 안내](docs/DEVELOPMENT.md), 확인 결과는
[검증 기록](docs/VERIFICATION.md), 라이선스는
[서드파티 고지](docs/THIRD_PARTY_NOTICES.md)를 참고하세요.
