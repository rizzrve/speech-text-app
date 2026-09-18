import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var jobQueue = JobQueue(outputDirectory: ContentView.defaultOutputDirectory())
    @StateObject private var recorder = LiveRecorder()
    @State private var selectedJobID: TranscriptionJob.ID?
    @State private var selectedModel: TranscriptionModel = .turbo
    @State private var selectedLanguage: TranscriptionLanguage = .malay
    @State private var isDropTargeted = false
    @State private var calibrationResults: [ModelCalibration.Result] = []
    @State private var calibrationRecommendation: String?
    @State private var isCalibrating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(minWidth: 760, minHeight: 480)
        .alert("Error", isPresented: errorAlertBinding) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(jobQueue.jobs, selection: $selectedJobID) { job in
                JobRow(job: job).tag(job.id)
            }
            .listStyle(.sidebar)
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers)
                return true
            }
            .overlay {
                if jobQueue.jobs.isEmpty {
                    ContentUnavailableView("Drop audio files here", systemImage: "waveform", description: Text("or use Add Files below"))
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Picker("Model", selection: $selectedModel) {
                    ForEach(TranscriptionModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                Picker("Language", selection: $selectedLanguage) {
                    ForEach(TranscriptionLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                HStack {
                    Button {
                        addFiles()
                    } label: {
                        Label("Add Files", systemImage: "plus")
                    }

                    Spacer()

                    recordButton
                }
            }
            .padding(12)
        }
    }

    private var recordButton: some View {
        Button {
            Task { await toggleRecording() }
        } label: {
            if recorder.isRecording {
                Label(String(format: "Stop (%.0fs)", recorder.elapsed), systemImage: "stop.circle.fill")
            } else {
                Label("Record", systemImage: "record.circle")
            }
        }
        .tint(recorder.isRecording ? .red : nil)
    }

    @ViewBuilder
    private var detail: some View {
        if let job = jobQueue.jobs.first(where: { $0.id == selectedJobID }) {
            TranscriptDetailView(job: job)
        } else {
            calibrationView
        }
    }

    private var calibrationView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Engine Calibration")
                .font(.title2.bold())
            Text("Benchmarks WhisperKit's ANE vs. GPU compute assignment on this machine against the whisper.cpp baseline (\(baselineText)x real-time) from the existing run reports.")
                .foregroundStyle(.secondary)

            Button {
                Task { await runCalibration() }
            } label: {
                if isCalibrating {
                    ProgressView()
                } else {
                    Text("Run Calibration on a File…")
                }
            }
            .disabled(isCalibrating)

            ForEach(calibrationResults) { result in
                HStack {
                    Text(result.configName)
                    Spacer()
                    Text(String(format: "%.1fx real-time", result.realTimeFactor))
                        .monospacedDigit()
                }
            }

            if let calibrationRecommendation {
                Text(calibrationRecommendation)
                    .padding(.top, 8)
                    .font(.callout.weight(.medium))
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var baselineText: String {
        String(format: "%.1f", ModelCalibration.whisperCppBaselineRealTimeFactor)
    }

    private func addFiles() {
        let urls = AudioIngestion.presentFilePicker()
        for url in urls {
            jobQueue.enqueue(url: url, model: selectedModel, language: selectedLanguage)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        Task {
            let urls = await AudioIngestion.extractDroppedFileURLs(from: providers)
            for url in urls {
                jobQueue.enqueue(url: url, model: selectedModel, language: selectedLanguage)
            }
        }
    }

    private func toggleRecording() async {
        do {
            if recorder.isRecording {
                let url = try recorder.stop()
                jobQueue.enqueue(url: url, model: selectedModel, language: selectedLanguage)
            } else {
                try await recorder.start()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runCalibration() async {
        guard let url = AudioIngestion.presentFilePicker().first else { return }
        isCalibrating = true
        defer { isCalibrating = false }
        do {
            let results = try await ModelCalibration.run(fileURL: url)
            calibrationResults = results
            calibrationRecommendation = ModelCalibration.recommendation(from: results)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func defaultOutputDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SpeechTextApp Transcripts", isDirectory: true)
    }
}

private struct JobRow: View {
    @ObservedObject var job: TranscriptionJob

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(job.sourceURL.lastPathComponent).lineLimit(1)
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            statusIcon
        }
    }

    private var statusText: String {
        switch job.status {
        case .queued: return "Queued"
        case .processing(let stage): return stage
        case .done(let report): return report.isClean ? "Done" : "Done — \(flagCount(report)) flag(s)"
        case .failed(let message): return "Failed: \(message)"
        }
    }

    private func flagCount(_ report: VerificationReport) -> Int {
        report.overlaps.count + report.repetitionClusters.count + report.emptySegmentIndices.count + report.garbledSegmentIndices.count
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch job.status {
        case .queued:
            Image(systemName: "clock")
        case .processing:
            ProgressView().controlSize(.small)
        case .done(let report):
            Image(systemName: report.isClean ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(report.isClean ? .green : .yellow)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}

#Preview {
    ContentView()
}
