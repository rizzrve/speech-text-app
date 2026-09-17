import Foundation

/// Writes txt/srt/json outputs, matching the format of the existing
/// whisper.cpp workflow (see run reports) so downstream tooling is unaffected.
enum Exporter {
    struct ExportedFiles {
        let txt: URL
        let srt: URL
        let json: URL
        /// Populated once `writeReport` has run; nil in the moment right after
        /// `writeAll` since the report depends on the sizes of these files.
        let report: URL?
    }

    static func txt(_ segments: [TranscriptSegment]) -> String {
        segments.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: "\n")
    }

    static func srt(_ segments: [TranscriptSegment]) -> String {
        segments.enumerated().map { index, segment in
            """
            \(index + 1)
            \(srtTimestamp(segment.start)) --> \(srtTimestamp(segment.end))
            \(segment.text.trimmingCharacters(in: .whitespacesAndNewlines))
            """
        }.joined(separator: "\n\n")
    }

    static func json(_ segments: [TranscriptSegment]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(segments)
    }

    @discardableResult
    static func writeAll(_ segments: [TranscriptSegment], baseURL: URL) throws -> ExportedFiles {
        let txtURL = baseURL.appendingPathExtension("txt")
        let srtURL = baseURL.appendingPathExtension("srt")
        let jsonURL = baseURL.appendingPathExtension("json")

        try txt(segments).write(to: txtURL, atomically: true, encoding: .utf8)
        try srt(segments).write(to: srtURL, atomically: true, encoding: .utf8)
        try json(segments).write(to: jsonURL)

        return ExportedFiles(txt: txtURL, srt: srtURL, json: jsonURL, report: nil)
    }

    /// Encodes and writes a `RunReport` to `<baseURL>-report.json`, a sibling
    /// of the txt/srt/json outputs written by `writeAll`.
    @discardableResult
    static func writeReport(_ report: RunReport, baseURL: URL) throws -> URL {
        let reportURL = baseURL.deletingLastPathComponent()
            .appendingPathComponent(baseURL.lastPathComponent + "-report.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(to: reportURL)

        return reportURL
    }

    private static func srtTimestamp(_ time: TimeInterval) -> String {
        let totalMilliseconds = Int((time * 1000).rounded())
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds / 60_000) % 60
        let seconds = (totalMilliseconds / 1_000) % 60
        let milliseconds = totalMilliseconds % 1_000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }
}
