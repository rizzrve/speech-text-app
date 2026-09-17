# Requirements & Setup

This app only runs on macOS. Summary of what it needs:

## Requirements

- **macOS 15.0+** on Apple Silicon (uses Core ML + Apple Neural Engine for inference).
- **Xcode** (recent version, with command-line tools).
- **[XcodeGen](https://github.com/yonaskolb/XcodeGen)** — generates the `.xcodeproj` from `project.yml` (`brew install xcodegen`).
- **Internet access on first run** — no model is bundled with the app. WhisperKit downloads the Whisper `large-v3` Core ML model package (~630MB) from Hugging Face Hub the first time it's needed, then caches it locally for all subsequent runs.
- **Microphone permission** — required for live recording (declared via `NSMicrophoneUsageDescription`); not needed if you only transcribe existing audio files.

## Build & run

```bash
xcodegen generate        # generates SpeechTextApp.xcodeproj from project.yml
open SpeechTextApp.xcodeproj
```

Then build and run the `SpeechTextApp` scheme in Xcode (⌘R). Swift Package Manager will resolve `WhisperKit` and `swift-transformers` automatically on first build.

## What "local AI speech-to-text" requires here

If you're building an equivalent app on another platform, the pieces that matter are:

1. **A Whisper model** — this app uses the quantized `large-v3` Core ML build (`turbo` and full variants) published at `argmaxinc/whisperkit-coreml` on Hugging Face. Any Whisper checkpoint (or a runtime that ships its own, like faster-whisper/whisper.cpp) works the same way in principle.
2. **A local inference runtime** capable of running that model on-device — here, Core ML via WhisperKit.
3. **A model cache/download step** — the model isn't shipped with the app binary; it's fetched once and cached, which is what keeps the app itself small.

No API keys, accounts, or paid services are involved anywhere in this implementation.
