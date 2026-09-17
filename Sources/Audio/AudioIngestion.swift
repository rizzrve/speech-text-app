import AppKit
import UniformTypeIdentifiers

/// File import for batch mode. WhisperKit decodes/resamples via AVFoundation
/// internally, so this only needs to gather candidate file URLs — no manual
/// ffmpeg conversion step, unlike the existing whisper.cpp workflow.
enum AudioIngestion {
    static let supportedExtensions: Set<String> = ["wav", "m4a", "mp3", "mp4", "mov", "aac", "flac", "caf"]

    static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    @MainActor
    static func presentFilePicker() -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.audio, .movie, .mpeg4Movie]
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.filter(isSupported)
    }

    static func extractDroppedFileURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            if let url = await loadFileURL(provider) {
                urls.append(url)
            }
        }
        return urls.filter(isSupported)
    }

    private static func loadFileURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
