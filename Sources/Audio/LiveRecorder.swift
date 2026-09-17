import AVFoundation
import Foundation

/// Record-then-transcribe capture (not real-time streaming, per plan scope).
/// On stop, the caller feeds the resulting file into the same batch pipeline
/// used for imported files.
@MainActor
final class LiveRecorder: ObservableObject {
    enum RecorderError: Error, LocalizedError {
        case alreadyRecording
        case notRecording
        case microphonePermissionDenied

        var errorDescription: String? {
            switch self {
            case .alreadyRecording: return "Already recording."
            case .notRecording: return "Not currently recording."
            case .microphonePermissionDenied: return "Microphone access was denied. Enable it in System Settings > Privacy & Security > Microphone."
            }
        }
    }

    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0

    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var startDate: Date?
    private var timer: Timer?

    @discardableResult
    func start() async throws -> URL {
        guard !isRecording else { throw RecorderError.alreadyRecording }
        guard await Self.requestMicrophonePermission() else { throw RecorderError.microphonePermissionDenied }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-\(Int(Date().timeIntervalSince1970))")
            .appendingPathExtension("caf")

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let file = try AVAudioFile(forWriting: outputURL, settings: format.settings)

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            try? file.write(from: buffer)
        }

        engine.prepare()
        try engine.start()

        audioFile = file
        startDate = Date()
        isRecording = true
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let start = self.startDate else { return }
            Task { @MainActor in self.elapsed = Date().timeIntervalSince(start) }
        }

        return outputURL
    }

    @discardableResult
    func stop() throws -> URL {
        guard isRecording, let audioFile else { throw RecorderError.notRecording }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false
        let url = audioFile.url
        self.audioFile = nil
        return url
    }

    private static func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}
