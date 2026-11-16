# Third-party software and references

VoicePrompt uses Argmax WhisperKit / ArgmaxCore v1.1.1 under the MIT License.
Source: https://github.com/argmaxinc/argmax-oss-swift
Copyright © 2024 Argmax, Inc. All rights reserved.

The full dependency license is in `.build/checkouts/argmax-oss-swift/LICENSE`
and is included in packaged builds as `WhisperKit-LICENSE.md`.
The multilingual Whisper weights originate from OpenAI Whisper (MIT):
https://github.com/openai/whisper
Core ML conversions: https://huggingface.co/argmaxinc/whisperkit-coreml

Architecture references (no application source copied):
- VoxPrompt (MIT): https://github.com/charle-com/voxprompt — native menu bar,
  non-cloud dictation and clipboard insertion approach.
- VoiceInk: https://github.com/Beingpax/VoiceInk — dictation UX reference.
- WhisperDictation: https://github.com/JoshPetrenko/WhisperDictation — local workflow reference.

WhisperKit's AudioStreamTranscriber was consulted for the timed, confirmed versus
tentative streaming segment approach. VoicePrompt's capture, accumulator and
session lifecycle are independently implemented.
