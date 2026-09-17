import AVFoundation
import Foundation

enum JobStatus: Equatable {
    case queued
    case processing(stage: String)
    case done(VerificationReport)
    case failed(String)
}

@MainActor
final class TranscriptionJob: ObservableObject, Identifiable {
    let id = UUID()
    let sourceURL: URL
    private(set) var model: TranscriptionModel
    @Published var status: JobStatus = .queued
    @Published var segments: [TranscriptSegment] = []
    @Published var exportedFiles: Exporter.ExportedFiles?

    init(sourceURL: URL, model: TranscriptionModel) {
        self.sourceURL = sourceURL
        self.model = model
    }

    fileprivate func updateModel(_ model: TranscriptionModel) {
        self.model = model
    }
}

/// Tracks batch/live jobs and drives each one through
/// load model -> transcribe -> verify -> export, sequentially (WhisperKit
/// keeps one model resident at a time, so concurrent jobs would thrash reloads).
@MainActor
final class JobQueue: ObservableObject {
    @Published private(set) var jobs: [TranscriptionJob] = []

    private let engine = TranscriptionEngine()
    private let outputDirectory: URL
    private var isProcessing = false

    init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    @discardableResult
    func enqueue(url: URL, model: TranscriptionModel) -> TranscriptionJob {
        let job = TranscriptionJob(sourceURL: url, model: model)
        jobs.append(job)
        processNextIfNeeded()
        return job
    }

    private func processNextIfNeeded() {
        guard !isProcessing else { return }
        guard let next = jobs.first(where: { $0.status == .queued }) else { return }
        isProcessing = true
        Task {
            await process(next)
            isProcessing = false
            processNextIfNeeded()
        }
    }

    private func process(_ job: TranscriptionJob) async {
        job.status = .processing(stage: "Loading \(job.model.displayName)")
        do {
            let requestedModel = job.model
            let loadStart = Date()
            let loadedModel = try await engine.ensureLoaded(model: requestedModel) { [weak job] stage in
                Task { @MainActor in job?.status = .processing(stage: stage) }
            }
            let modelLoadSeconds = Date().timeIntervalSince(loadStart)
            job.updateModel(loadedModel)

            job.status = .processing(stage: "Transcribing")
            let transcribeStart = Date()
            let outcome = try await engine.transcribe(fileURL: job.sourceURL) { [weak job] partial in
                Task { @MainActor in job?.segments = partial }
            }
            let transcriptionSeconds = Date().timeIntervalSince(transcribeStart)
            job.segments = outcome.segments

            job.status = .processing(stage: "Verifying")
            let verification = QAVerification.verify(segments: outcome.segments)

            job.status = .processing(stage: "Exporting")
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            let baseName = job.sourceURL.deletingPathExtension().lastPathComponent + "-transcript"
            let baseURL = outputDirectory.appendingPathComponent(baseName)
            let exported = try Exporter.writeAll(outcome.segments, baseURL: baseURL)

            let audioDurationSeconds = (try? await AVURLAsset(url: job.sourceURL).load(.duration).seconds) ?? 0

            let outputFiles: [RunReport.OutputFile] = [
                ("txt", exported.txt), ("srt", exported.srt), ("json", exported.json),
            ].map { kind, url in
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                return RunReport.OutputFile(kind: kind, path: url.path, sizeBytes: size)
            }

            let runReport = RunReportBuilder.build(
                sourceURL: job.sourceURL,
                audioDurationSeconds: audioDurationSeconds,
                requestedModel: requestedModel,
                usedModel: loadedModel,
                compute: .libraryDefault,
                detectedLanguage: outcome.detectedLanguage,
                modelLoadSeconds: modelLoadSeconds,
                transcriptionSeconds: transcriptionSeconds,
                outputFiles: outputFiles,
                verification: verification
            )
            let reportURL = try Exporter.writeReport(runReport, baseURL: baseURL)
            job.exportedFiles = Exporter.ExportedFiles(txt: exported.txt, srt: exported.srt, json: exported.json, report: reportURL)

            job.status = .done(verification)
        } catch {
            job.status = .failed(error.localizedDescription)
        }
    }
}
