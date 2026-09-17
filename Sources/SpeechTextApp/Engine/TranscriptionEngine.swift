import CoreML
import Foundation
import Hub
import WhisperKit

/// The two model variants offered per job (see plan: memory footprint is
/// nearly identical at ~630MB either way, so this is purely a speed/accuracy
/// tradeoff, not a memory one).
enum TranscriptionModel: String, CaseIterable, Identifiable, Hashable {
    case turbo
    case largeV3

    var id: String { rawValue }

    /// Argmax's quantized (v20240930) WhisperKit model repo identifiers.
    var whisperKitIdentifier: String {
        switch self {
        case .turbo: return "openai_whisper-large-v3-v20240930_turbo_632MB"
        case .largeV3: return "openai_whisper-large-v3-v20240930_626MB"
        }
    }

    var displayName: String {
        switch self {
        case .turbo: return "Turbo (fastest)"
        case .largeV3: return "Large v3 (most accurate, ~4-6x slower)"
        }
    }
}

/// Which Core ML compute unit each pipeline stage should target. Defaults
/// mirror WhisperKit's own library defaults (ANE for encoder + decoder, GPU
/// for mel spectrogram, CPU for prefill) — see plan's compute assignment
/// table. `ModelCalibration` may override this after benchmarking on-device.
struct ComputeAssignment {
    var melCompute: MLComputeUnits = .cpuAndGPU
    var audioEncoderCompute: MLComputeUnits = .cpuAndNeuralEngine
    var textDecoderCompute: MLComputeUnits = .cpuAndNeuralEngine
    var prefillCompute: MLComputeUnits = .cpuOnly

    static let libraryDefault = ComputeAssignment()

    /// The alternative the plan calls out for comparison: encoder/decoder on GPU
    /// instead of ANE, since published ANE wins are from an M2 Ultra, not this machine.
    static let gpuOnly = ComputeAssignment(
        melCompute: .cpuAndGPU,
        audioEncoderCompute: .cpuAndGPU,
        textDecoderCompute: .cpuAndGPU,
        prefillCompute: .cpuOnly
    )

    var modelComputeOptions: ModelComputeOptions {
        ModelComputeOptions(
            melCompute: melCompute,
            audioEncoderCompute: audioEncoderCompute,
            textDecoderCompute: textDecoderCompute,
            prefillCompute: prefillCompute
        )
    }
}

enum TranscriptionEngineError: Error, LocalizedError {
    case modelLoadFailed(model: TranscriptionModel, underlying: Error)

    var errorDescription: String? {
        switch self {
        case let .modelLoadFailed(model, underlying):
            return "Failed to load \(model.displayName): \(underlying.localizedDescription)"
        }
    }
}

/// Result of a single `transcribe(fileURL:)` call: the mapped segments plus
/// the language WhisperKit auto-detected, for surfacing in `RunReport`.
struct TranscriptionOutcome {
    let segments: [TranscriptSegment]
    let detectedLanguage: String?
}

/// Wraps WhisperKit: loads the selected model under a given compute
/// assignment, transcribes a file, and maps results to the engine-agnostic
/// `TranscriptSegment` model. On load failure, falls back to a smaller model
/// (mirrors the existing `-ng` CPU fallback documented in the run reports).
actor TranscriptionEngine {
    private var pipe: WhisperKit?
    private var loadedModel: TranscriptionModel?
    private var loadedCompute: ComputeAssignment?

    /// Loads the requested model if not already loaded with the same compute assignment.
    /// Falls back to `.turbo` if `.largeV3` fails to load (e.g. memory pressure).
    ///
    /// `onProgress` reports human-readable status (download percentage, then
    /// on-device preparation) — the model package is ~630MB, and on a modest
    /// connection the one-time download can take several minutes, so callers
    /// must surface this rather than showing a bare, indefinite spinner.
    func ensureLoaded(
        model: TranscriptionModel,
        compute: ComputeAssignment = .libraryDefault,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> TranscriptionModel {
        if loadedModel == model, loadedCompute?.modelComputeOptions.audioEncoderCompute == compute.modelComputeOptions.audioEncoderCompute,
           loadedCompute?.modelComputeOptions.textDecoderCompute == compute.modelComputeOptions.textDecoderCompute
        {
            return model
        }

        do {
            try await load(model: model, compute: compute, onProgress: onProgress)
            return model
        } catch {
            guard model != .turbo else {
                throw TranscriptionEngineError.modelLoadFailed(model: model, underlying: error)
            }
            try await load(model: .turbo, compute: compute, onProgress: onProgress)
            return .turbo
        }
    }

    /// Downloads (with real progress) before constructing WhisperKit, rather than
    /// letting `WhisperKitConfig(model:download:)` download internally during
    /// `init` — that path offers no way to attach a progress callback since the
    /// instance doesn't exist yet while the download is in flight.
    ///
    /// Checks for a complete local copy first: `WhisperKit.download()` (via
    /// `HubApi.snapshot()`) re-fetches non-LFS-tracked files like `model.mil`
    /// unconditionally on every call, so calling it on every app relaunch — even
    /// once the model is fully cached — causes a real, repeated ~7.6MB network
    /// transfer and a misleading "Downloading" status each time.
    private func load(model: TranscriptionModel, compute: ComputeAssignment, onProgress: (@Sendable (String) -> Void)?) async throws {
        let modelFolder: URL
        if let cached = Self.completeLocalModelFolder(for: model) {
            modelFolder = cached
        } else {
            onProgress?("Downloading \(model.displayName) (~630MB, one-time)…")
            modelFolder = try await WhisperKit.download(
                variant: model.whisperKitIdentifier
            ) { progress in
                let percent = Int((progress.fractionCompleted * 100).rounded())
                onProgress?("Downloading \(model.displayName): \(percent)%")
            }
        }

        // Construct with load:false, then call loadModels() ourselves so a
        // modelStateCallback can be attached first — this is the step that
        // compiles/specializes the Core ML model for this Mac's chip, a real
        // (observed: ~6-7 minute) one-time cost on first use, previously
        // invisible to the user since it happens inside WhisperKit's own
        // init() before we'd otherwise have an instance to attach a callback to.
        let config = WhisperKitConfig(
            modelFolder: modelFolder.path,
            computeOptions: compute.modelComputeOptions,
            verbose: false,
            prewarm: false,
            load: false
        )
        let kit = try await WhisperKit(config)
        kit.modelStateCallback = { _, newState in
            switch newState {
            case .loading:
                onProgress?("Specializing \(model.displayName) for your Mac's chip (first time only — can take several minutes)…")
            case .loaded:
                onProgress?("\(model.displayName) ready")
            default:
                onProgress?("\(newState.description) \(model.displayName)…")
            }
        }
        try await kit.loadModels()
        pipe = kit
        loadedModel = model
        loadedCompute = compute
    }

    /// Transcribes an audio file. Auto-detects language (handles Malay/English
    /// code-switching per the existing reports) using WhisperKit's default
    /// hallucination safeguards (compression-ratio / logprob / no-speech thresholds).
    ///
    /// `onSegments` is called with the full transcript-so-far every time WhisperKit
    /// finalizes another window of audio, so callers can render live output
    /// instead of a blank screen for the whole transcription run.
    func transcribe(fileURL: URL, onSegments: (@Sendable ([TranscriptSegment]) -> Void)? = nil) async throws -> TranscriptionOutcome {
        guard let pipe else {
            preconditionFailure("ensureLoaded(model:) must be called before transcribe(fileURL:)")
        }

        let decodeOptions = DecodingOptions(
            task: .transcribe,
            temperatureFallbackCount: 5,
            usePrefillPrompt: true,
            detectLanguage: true
        )

        let audioArray = try AudioProcessor.loadAudioAsFloatArray(fromPath: fileURL.path, channelMode: pipe.audioInputConfig.channelMode)

        // segmentCallback fires per-window with only the segments discovered in
        // that window (not cumulative), so we accumulate them ourselves here.
        var discovered: [TranscriptionSegment] = []
        let results = try await pipe.transcribe(
            audioArray: audioArray,
            decodeOptions: decodeOptions,
            segmentCallback: { newSegments in
                discovered.append(contentsOf: newSegments)
                onSegments?(Self.mapSegments(discovered))
            }
        )

        let detectedLanguage = results.map(\.language).first { !$0.isEmpty }
        return TranscriptionOutcome(
            segments: Self.mapSegments(results.flatMap(\.segments)),
            detectedLanguage: detectedLanguage
        )
    }

    private static func mapSegments(_ segments: [TranscriptionSegment]) -> [TranscriptSegment] {
        segments.enumerated().map { index, segment in
            TranscriptSegment(
                id: index,
                start: TimeInterval(segment.start),
                end: TimeInterval(segment.end),
                text: segment.text,
                avgLogProb: Double(segment.avgLogprob),
                compressionRatio: Double(segment.compressionRatio),
                noSpeechProb: Double(segment.noSpeechProb)
            )
        }
    }

    /// The folder WhisperKit's own download path resolves to for this variant
    /// (`HubApi.localRepoLocation` + variant name), if it's already fully present
    /// on disk from a previous run — checked so `load()` can skip re-invoking
    /// `WhisperKit.download()` (and its unconditional network round-trip) entirely.
    ///
    /// `downloadBase` is injectable so tests can point this at a temp directory
    /// instead of the real `~/Documents/huggingface` cache; production callers
    /// omit it to get `HubApi`'s real default location.
    static func completeLocalModelFolder(for model: TranscriptionModel, downloadBase: URL? = nil) -> URL? {
        let repo = Hub.Repo(id: "argmaxinc/whisperkit-coreml", type: .models)
        let folder = HubApi(downloadBase: downloadBase).localRepoLocation(repo).appending(component: model.whisperKitIdentifier)

        let requiredComponents = ["MelSpectrogram", "AudioEncoder", "TextDecoder", "TextDecoderContextPrefill"]
        let fileManager = FileManager.default
        for component in requiredComponents {
            let weightsPath = folder
                .appendingPathComponent("\(component).mlmodelc")
                .appendingPathComponent("weights")
                .appendingPathComponent("weight.bin")
            guard let size = try? fileManager.attributesOfItem(atPath: weightsPath.path)[.size] as? Int,
                  size > 0
            else {
                return nil
            }
        }
        return folder
    }
}
