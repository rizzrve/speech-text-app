import Foundation

/// On-device engine gate (plan §Verification step 1): benchmarks WhisperKit
/// compute-unit configs against each other and against the whisper.cpp
/// baseline already measured on this machine (Mitra report: 2892.8s of audio
/// in ~3.6 minutes). WhisperKit only ships as the engine if a config clears
/// that baseline here — otherwise the plan's fallback (whisper.cpp + Core ML
/// encoder) applies instead.
enum ModelCalibration {
    /// 2892.8s audio / 216s wall time, from the Mitra report's accepted run.
    static let whisperCppBaselineRealTimeFactor: Double = 2892.8 / 216.0

    struct Result: Identifiable {
        let id = UUID()
        let configName: String
        let realTimeFactor: Double
        let wallTime: TimeInterval
        let audioDuration: TimeInterval
    }

    static func run(fileURL: URL, model: TranscriptionModel = .turbo) async throws -> [Result] {
        let configs: [(String, ComputeAssignment)] = [
            ("ANE (library default)", .libraryDefault),
            ("GPU only", .gpuOnly),
        ]

        var results: [Result] = []
        for (name, compute) in configs {
            let engine = TranscriptionEngine()
            let start = Date()
            _ = try await engine.ensureLoaded(model: model, compute: compute)
            let outcome = try await engine.transcribe(fileURL: fileURL, language: .malay)
            let wallTime = Date().timeIntervalSince(start)
            let audioDuration = outcome.segments.last?.end ?? 0
            let rtf = wallTime > 0 ? audioDuration / wallTime : 0
            results.append(Result(configName: name, realTimeFactor: rtf, wallTime: wallTime, audioDuration: audioDuration))
        }
        return results
    }

    static func recommendation(from results: [Result]) -> String {
        guard let best = results.max(by: { $0.realTimeFactor < $1.realTimeFactor }) else {
            return "No calibration results yet."
        }
        let baseline = String(format: "%.1f", whisperCppBaselineRealTimeFactor)
        let bestRTF = String(format: "%.1f", best.realTimeFactor)
        if best.realTimeFactor >= whisperCppBaselineRealTimeFactor {
            return "\(best.configName) clears the whisper.cpp baseline (\(baseline)x real-time) at \(bestRTF)x — ship WhisperKit with this config."
        } else {
            return "Best WhisperKit config (\(best.configName), \(bestRTF)x) does not clear the whisper.cpp baseline (\(baseline)x) on this machine — fall back to whisper.cpp + Core ML per plan."
        }
    }
}
