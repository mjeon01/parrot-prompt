# 기본 기술 용어와 출처

2026-11-16 공식 프로젝트·문서에서 표기를 확인했습니다. 아래 목록은 로컬 Whisper에
전달하는 인식 힌트이며, 새로운 모델을 다운로드하거나 외부 API를 호출하지 않습니다.

| 용어 | 확인한 공식 자료 |
|---|---|
| Qwen, Qwen2.5, 7B | [Qwen2.5 발표와 모델 크기](https://qwenlm.github.io/blog/qwen2.5/) |
| Ollama | [Ollama 문서](https://docs.ollama.com/) |
| RAG, embedding, 임베딩, 벡터 검색 | [Ollama Embeddings](https://docs.ollama.com/capabilities/embeddings), [Transformers RAG](https://huggingface.co/docs/transformers/model_doc/rag) |
| Llama | [Meta Llama 모델 저장소](https://github.com/meta-llama/llama-models) |
| Gemma | [Google Gemma 개요](https://ai.google.dev/gemma/docs) |
| DeepSeek | [DeepSeek 공식 저장소](https://github.com/deepseek-ai/DeepSeek-V3) |
| LoRA, QLoRA, 양자화, 파인튜닝 | [Hugging Face PEFT](https://huggingface.co/docs/peft/developer_guides/quantization) |
| GGUF | [Hugging Face GGUF](https://huggingface.co/docs/hub/gguf) |
| MLX | [Apple MLX 문서](https://ml-explore.github.io/mlx/build/html/index.html) |
| vLLM | [vLLM 문서](https://docs.vllm.ai/en/latest/) |
| LLM, Hugging Face, Transformers, tokenizer, 토큰, 파라미터 | [Qwen의 Transformers 사용 예시](https://qwenlm.github.io/blog/qwen2.5/), [Transformers RAG](https://huggingface.co/docs/transformers/model_doc/rag) |

## 표시 규칙

v0.4.2 / Windows 0.5.0-preview.2부터 한국어 언어 고정을 해제하고 음성의 언어를 자동 감지합니다.
작업은 번역이 아닌 전사(`transcribe`)입니다. 한국어·영어가 섞이면 모델의 언어 판별만으로
고유 명사 철자를 보장할 수 없어, 영어 개발 용어 힌트와 제한적인 음차 보정을 함께 사용합니다.

`README`, `GitHub`, `Markdown`, `JSON`, `API`, `SDK`, `CLI`, `Python`, `JavaScript`,
`TypeScript`, `React`, `Docker`, `SQL`, `npm`을 힌트 앞부분에 추가했습니다. 특히
README와 GitHub가 160토큰 예산 안에서도 실제 디코더에 전달되는지 SDK 검사로 확인합니다.
README 명칭은 [GitHub의 README 안내](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes)를 참고했습니다.

| 인식된 예시 | 표시 결과 |
|---|---|
| 리듬위를 수정해 줘 | README를 수정해 줘 |
| 리드미에 사용법을 적어 줘 | README에 사용법을 적어 줘 |
| 깃허브에 올려 줘 | GitHub에 올려 줘 |
| 에이피아이 사용 예제 | API 사용 예제 |
| 제이슨 파일 | JSON 파일 |

완전한 용어 뒤에 구두점·공백·한국어 조사가 오는 경우를 구분합니다. `리드미컬한`, `리듬위주의`,
`리듬 위에`와 영어 일반 문장 `read me a story`, `react to the change`, `a python is a snake`는 바꾸지 않습니다.
사람 이름 `제이슨`은 파일·데이터 등 인접 문맥이 있을 때만 JSON으로 보정합니다.
`readme.md`, `리드미.md`, URL·경로·코드 등 명시적인 식별자는 그대로 둡니다.
새 표기 규칙은 두 플랫폼이 같은 `Tests/Fixtures/english-terms.json`을 읽어 검사합니다.

읽기 쉬운 받아쓰기 표기로 `Qwen 2.5 7B`를 사용합니다. 실제 저장소 ID
`Qwen/Qwen2.5-7B-Instruct`나 Ollama 태그 `qwen2.5:7b`는 그대로 보존합니다.

| 인식된 예시 | 표시 결과 |
|---|---|
| QON 모델 | Qwen 모델 |
| Qwen2,5 7B | Qwen 2.5 7B |
| Qwen 2.57B | Qwen 2.5 7B |
| 큐웬 2.5 7 빌리언 | Qwen 2.5 7B |
| 올라마 | Ollama |
| 래그를 구축해 | RAG를 구축해 |
| 알 에이 지 | RAG |

`QON`과 헷갈리는 한국어 표기는 모델·버전 문맥을 확인합니다. `rag`와 `래그`는
기술 문맥이나 단독 용어일 때 보정합니다. 영어 일반 명사인 `a rag`, 게임의 `렉`,
모델명 없는 `2.57B`, 파일명·경로·URL·코드 블록·Ollama 실행 명령은 유지합니다.
붙어 있는 숫자는 임의로 추측하지 않고 사용자가 보고한 Qwen 2.5 / 7B 조합만 분리합니다.

기본 목록과 규칙은 `Sources/VoicePromptCore/TechnicalVocabulary.swift`에 있습니다.
설정의 **추가할 용어**는 인식 힌트만 추가하며, 모든 새 용어를 자동 치환하지 않습니다.
**LLM 용어 보정**을 끄면 힌트와 표시 보정이 모두 꺼집니다.

v0.4.1에서는 실시간 콜백에서 힌트와 실제 전사 토큰을 분리합니다. v0.4.0은
SDK 콜백에 포함된 힌트를 그대로 표시해, 말하지 않은 용어 목록이 뜨는 문제가 있었습니다.
단어 목록을 삭제하는 필터가 아니므로 실제로 말한 기술 용어는 유지됩니다.
