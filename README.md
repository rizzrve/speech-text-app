# SpeechTextApp

A native macOS app for transcribing audio to text entirely **on-device** — no cloud API, no network calls at inference time, no API keys.

## What it does

- Transcribes audio files or live microphone input into timestamped text segments.
- Transcribes in a selected language (English or Malay), chosen per job in the sidebar.
- Exports transcripts to `.txt`, `.srt`, `.json`, `.md`, `.html`, and `.pdf`.
- Runs basic QA/verification checks on the output and can generate a run report summarizing a transcription job.

## Backend / how transcription works

Speech-to-text is done locally using **[WhisperKit](https://github.com/argmaxinc/WhisperKit)**, Argmax's Core ML port of OpenAI's Whisper model. There is no server component — the model runs directly on the Mac's Neural Engine / GPU via Apple's CoreML framework.

- **Model**: Whisper `large-v3`, quantized and distributed by Argmax as Core ML packages via Hugging Face (`argmaxinc/whisperkit-coreml`). Two variants are offered:
  - `turbo` (~632MB) — fastest, used by default.
  - `large-v3` (~626MB) — most accurate, roughly 4–6x slower.
  - If the requested model fails to load, the app falls back to `turbo`.
- **Model delivery**: models are *not* bundled with the app. On first use, WhisperKit downloads the selected variant from Hugging Face Hub (via the `swift-transformers` `Hub` client) and caches it locally, so this is a one-time ~630MB download requiring internet access. Every run after that loads from the local cache.
- **Compute placement**: by default the mel-spectrogram step runs on CPU+GPU and the audio encoder / text decoder run on CPU+Apple Neural Engine (ANE), matching WhisperKit's own defaults. This is configurable (see `ComputeAssignment` in `TranscriptionEngine.swift`) and can be recalibrated per-device.
- **Inference flow** (`Sources/Engine/TranscriptionEngine.swift`): load audio → run through the WhisperKit pipeline with the selected language forced for every window (Whisper code `en`/`ms`) and hallucination safeguards (compression-ratio / average-logprob / no-speech thresholds) → stream back transcript segments as they're finalized, so the UI can render partial results instead of waiting for the whole file.

## Tech stack

- **Language / UI**: Swift, SwiftUI (macOS 15+ only — uses AppKit for file import and AVFoundation for microphone capture, both Apple-only frameworks).
- **ML runtime**: Core ML (Apple's on-device inference framework), used indirectly through WhisperKit. No PyTorch/ONNX/server-side inference of any kind.
- **Dependency management**: Swift Package Manager, with the project itself scaffolded via [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`.
- **Key dependencies** (see `project.yml` / `Package.resolved`):
  - `WhisperKit` — the transcription engine itself.
  - `swift-transformers` (Hugging Face) — used for its `Hub` module to download/cache models from Hugging Face Hub.

## Project structure

```
Sources/
├── App/            SwiftUI app entry point and main views
├── Audio/           File-based audio import (AppKit) and live mic recording (AVFoundation)
├── Engine/          TranscriptionEngine.swift — the WhisperKit wrapper (model load, inference)
│                    ModelCalibration.swift — per-device compute-unit calibration
├── Export/          Exporter.swift — writes txt/srt/json/md/html/pdf output
├── Models/          TranscriptSegment.swift — shared transcript data model
├── Queue/           JobQueue.swift — queues/runs transcription jobs
├── Report/          RunReport.swift — generates a summary report for a job
└── Verification/    QAVerification.swift — sanity checks on transcription output
```

## Platform note (for anyone porting this elsewhere)

This app is macOS/Apple-Silicon-specific end to end: SwiftUI + AppKit + AVFoundation for the app shell, and Core ML/Apple Neural Engine for inference. It will not run on Windows or Linux as-is. The concepts transfer directly, though — the equivalent building blocks on another OS would be:

- A local Whisper inference runtime such as [faster-whisper](https://github.com/SYSTRAN/faster-whisper) or [whisper.cpp](https://github.com/ggerganov/whisper.cpp) in place of WhisperKit/Core ML.
- A native or cross-platform UI framework in place of SwiftUI/AppKit.
- Any standard audio capture library (e.g. `sounddevice`/`pyaudio` in Python, or `cpal` in Rust) in place of AVFoundation.

See `INSTALLATION.md` for what's required to build/run this specific implementation.
