import XCTest
@testable import SpeechTextApp

final class ExporterTests: XCTestCase {
    private let segments = [
        TranscriptSegment(id: 0, start: 0.0, end: 2.5, text: "Hello there"),
        TranscriptSegment(id: 1, start: 2.5, end: 3661.234, text: "A much later line"),
    ]

    func testTxtExportIsOneLinePerSegment() {
        let txt = Exporter.txt(segments)
        XCTAssertEqual(txt, "Hello there\nA much later line")
    }

    func testSrtExportFormatsTimestampsAsHHMMSSmmm() {
        let srt = Exporter.srt(segments)
        XCTAssertTrue(srt.contains("00:00:00,000 --> 00:00:02,500"))
        XCTAssertTrue(srt.contains("00:00:02,500 --> 01:01:01,234"))
    }

    func testSrtExportNumbersEntriesStartingAtOne() {
        let srt = Exporter.srt(segments)
        let lines = srt.components(separatedBy: "\n")
        XCTAssertEqual(lines.first, "1")
        XCTAssertTrue(lines.contains("2"))
    }

    func testJsonExportRoundTripsSegments() throws {
        let data = try Exporter.json(segments)
        let decoded = try JSONDecoder().decode([TranscriptSegment].self, from: data)
        XCTAssertEqual(decoded, segments)
    }

    func testWriteAllCreatesThreeFilesWithExpectedExtensions() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let baseURL = tempDir.appendingPathComponent("sample-transcript")
        let result = try Exporter.writeAll(segments, baseURL: baseURL)

        XCTAssertEqual(result.txt.pathExtension, "txt")
        XCTAssertEqual(result.srt.pathExtension, "srt")
        XCTAssertEqual(result.json.pathExtension, "json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.txt.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.srt.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.json.path))
    }
}
