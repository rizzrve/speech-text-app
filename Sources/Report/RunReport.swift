import CoreML
import Foundation

/// Per-job run report, auto-generated after every transcription. Structurally
/// mirrors the manual audit performed by hand in the Mitra/PERKESO run reports
/// (run configuration, timing, generated files, and a verification section),
/// replacing the hand-written PDF with a machine-readable JSON sidecar.
struct RunReport: Codable {
    let schemaVersion: Int
    let generatedAt: Date
    let appVersion: String
    let input: Input
    let configuration: Configuration
    let timing: Timing
    let outputFiles: [OutputFile]
    let verification: VerificationReport
    let issues: [String]

    struct Input: Codable {
        let fileName: String
        let audioDurationSeconds: TimeInterval
    }

    struct Configuration: Codable {
        let requestedModel: String
        let modelUsed: String
        let modelFellBack: Bool
        let languageMode: String
        /// Whisper language code the run was forced to (e.g. "ms").
        let language: String
        let computeAssignment: [String: String]
    }

    struct Timing: Codable {
        let modelLoadSeconds: TimeInterval
        let transcriptionSeconds: TimeInterval
        let totalSeconds: TimeInterval
        let realTimeFactor: Double
    }

    struct OutputFile: Codable {
        let kind: String
        let path: String
        let sizeBytes: Int
    }
}

enum RunReportBuilder {
    static func build(
        sourceURL: URL,
        audioDurationSeconds: TimeInterval,
        requestedModel: TranscriptionModel,
        usedModel: TranscriptionModel,
        compute: ComputeAssignment,
        language: TranscriptionLanguage,
        modelLoadSeconds: TimeInterval,
        transcriptionSeconds: TimeInterval,
        outputFiles: [RunReport.OutputFile],
        verification: VerificationReport
    ) -> RunReport {
        let modelFellBack = usedModel != requestedModel

        return RunReport(
            schemaVersion: 2,
            generatedAt: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            input: .init(
                fileName: sourceURL.lastPathComponent,
                audioDurationSeconds: audioDurationSeconds
            ),
            configuration: .init(
                requestedModel: requestedModel.displayName,
                modelUsed: usedModel.displayName,
                modelFellBack: modelFellBack,
                languageMode: language.displayName,
                language: language.whisperCode,
                computeAssignment: compute.humanReadableAssignment
            ),
            timing: .init(
                modelLoadSeconds: modelLoadSeconds,
                transcriptionSeconds: transcriptionSeconds,
                totalSeconds: modelLoadSeconds + transcriptionSeconds,
                realTimeFactor: transcriptionSeconds > 0 ? audioDurationSeconds / transcriptionSeconds : 0
            ),
            outputFiles: outputFiles,
            verification: verification,
            issues: issues(modelFellBack: modelFellBack, requestedModel: requestedModel, usedModel: usedModel, verification: verification)
        )
    }

    private static func issues(
        modelFellBack: Bool,
        requestedModel: TranscriptionModel,
        usedModel: TranscriptionModel,
        verification: VerificationReport
    ) -> [String] {
        var notes: [String] = []

        if modelFellBack {
            notes.append("Requested \(requestedModel.displayName) failed to load; fell back to \(usedModel.displayName).")
        }
        if !verification.repetitionClusters.isEmpty {
            notes.append("\(verification.repetitionClusters.count) repetition cluster(s) detected — mirrors the whisper.cpp context-carryover repetition-loop failure mode; review recommended.")
        }
        if !verification.overlaps.isEmpty {
            notes.append("\(verification.overlaps.count) overlapping segment(s) detected.")
        }
        if !verification.largeGaps.isEmpty {
            notes.append("\(verification.largeGaps.count) gap(s) longer than the configured threshold detected.")
        }
        if !verification.lowConfidenceIndices.isEmpty {
            notes.append("\(verification.lowConfidenceIndices.count) segment(s) flagged as low-confidence — recommend manual review.")
        }
        if !verification.garbledSegmentIndices.isEmpty {
            notes.append("\(verification.garbledSegmentIndices.count) garbled/non-Latin-encoded segment(s) detected.")
        }
        if !verification.emptySegmentIndices.isEmpty {
            notes.append("\(verification.emptySegmentIndices.count) empty segment(s) detected.")
        }

        if notes.isEmpty {
            notes.append("No issues detected.")
        }
        return notes
    }
}

private extension ComputeAssignment {
    var humanReadableAssignment: [String: String] {
        [
            "mel": Self.describe(melCompute),
            "audioEncoder": Self.describe(audioEncoderCompute),
            "textDecoder": Self.describe(textDecoderCompute),
            "prefill": Self.describe(prefillCompute),
        ]
    }

    static func describe(_ unit: MLComputeUnits) -> String {
        switch unit {
        case .cpuOnly: return "CPU"
        case .cpuAndGPU: return "CPU+GPU"
        case .cpuAndNeuralEngine: return "CPU+ANE"
        case .all: return "CPU+GPU+ANE"
        @unknown default: return "unknown"
        }
    }
}
