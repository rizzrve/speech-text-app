import XCTest
@testable import SpeechTextApp

final class RunReportTests: XCTestCase {
    private let cleanVerification = VerificationReport(
        segmentCount: 2,
        coverageStart: 0,
        coverageEnd: 10,
        leadingGap: 0,
        trailingGap: 0,
        overlaps: [],
        largeGaps: [],
        repetitionClusters: [],
        emptySegmentIndices: [],
        garbledSegmentIndices: [],
        lowConfidenceIndices: []
    )

    // MARK: - VerificationReport Codable round-trip

    func testVerificationReportRoundTripsThroughJSON() throws {
        let report = VerificationReport(
            segmentCount: 3,
            coverageStart: 0,
            coverageEnd: 12.5,
            leadingGap: 0.5,
            trailingGap: 1.2,
            overlaps: [.init(firstIndex: 0, secondIndex: 1, overlapDuration: 0.3)],
            largeGaps: [.init(afterIndex: 1, duration: 6.0)],
            repetitionClusters: [.init(startIndex: 4, endIndex: 6, text: "loop")],
            emptySegmentIndices: [7],
            garbledSegmentIndices: [8],
            lowConfidenceIndices: [9]
        )

        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(VerificationReport.self, from: data)
        XCTAssertEqual(decoded, report)
    }

    // MARK: - RunReportBuilder

    func testBuildWithCleanRunHasNoIssuesNote() {
        let report = RunReportBuilder.build(
            sourceURL: URL(fileURLWithPath: "/tmp/sample.wav"),
            audioDurationSeconds: 100,
            requestedModel: .turbo,
            usedModel: .turbo,
            compute: .libraryDefault,
            detectedLanguage: "en",
            modelLoadSeconds: 2,
            transcriptionSeconds: 10,
            outputFiles: [],
            verification: cleanVerification
        )

        XCTAssertEqual(report.issues, ["No issues detected."])
        XCTAssertFalse(report.configuration.modelFellBack)
        XCTAssertEqual(report.configuration.requestedModel, TranscriptionModel.turbo.displayName)
        XCTAssertEqual(report.configuration.modelUsed, TranscriptionModel.turbo.displayName)
        XCTAssertEqual(report.configuration.detectedLanguage, "en")
        XCTAssertEqual(report.timing.modelLoadSeconds, 2)
        XCTAssertEqual(report.timing.transcriptionSeconds, 10)
        XCTAssertEqual(report.timing.totalSeconds, 12)
        XCTAssertEqual(report.timing.realTimeFactor, 10, accuracy: 0.0001)
        XCTAssertEqual(report.input.fileName, "sample.wav")
    }

    func testBuildWithModelFallbackAddsFallbackNote() {
        let report = RunReportBuilder.build(
            sourceURL: URL(fileURLWithPath: "/tmp/sample.wav"),
            audioDurationSeconds: 100,
            requestedModel: .largeV3,
            usedModel: .turbo,
            compute: .libraryDefault,
            detectedLanguage: nil,
            modelLoadSeconds: 2,
            transcriptionSeconds: 10,
            outputFiles: [],
            verification: cleanVerification
        )

        XCTAssertTrue(report.configuration.modelFellBack)
        XCTAssertTrue(report.issues.contains {
            $0.contains(TranscriptionModel.largeV3.displayName) && $0.contains(TranscriptionModel.turbo.displayName)
        })
    }

    func testBuildWithRepetitionClusterAddsMatchingNote() {
        let verification = VerificationReport(
            segmentCount: 5,
            coverageStart: 0,
            coverageEnd: 10,
            leadingGap: 0,
            trailingGap: 0,
            overlaps: [],
            largeGaps: [],
            repetitionClusters: [.init(startIndex: 1, endIndex: 3, text: "repeat")],
            emptySegmentIndices: [],
            garbledSegmentIndices: [],
            lowConfidenceIndices: []
        )

        let report = RunReportBuilder.build(
            sourceURL: URL(fileURLWithPath: "/tmp/sample.wav"),
            audioDurationSeconds: 100,
            requestedModel: .turbo,
            usedModel: .turbo,
            compute: .libraryDefault,
            detectedLanguage: nil,
            modelLoadSeconds: 2,
            transcriptionSeconds: 10,
            outputFiles: [],
            verification: verification
        )

        XCTAssertTrue(report.issues.contains { $0.contains("1 repetition cluster") })
    }

    // MARK: - Exporter.writeReport

    func testWriteReportWritesDecodableJSONAtExpectedPath() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let baseURL = tempDir.appendingPathComponent("sample-transcript")
        let report = RunReportBuilder.build(
            sourceURL: URL(fileURLWithPath: "/tmp/sample.wav"),
            audioDurationSeconds: 100,
            requestedModel: .turbo,
            usedModel: .turbo,
            compute: .libraryDefault,
            detectedLanguage: "en",
            modelLoadSeconds: 2,
            transcriptionSeconds: 10,
            outputFiles: [.init(kind: "txt", path: "/tmp/sample-transcript.txt", sizeBytes: 123)],
            verification: cleanVerification
        )

        let reportURL = try Exporter.writeReport(report, baseURL: baseURL)

        XCTAssertEqual(reportURL.lastPathComponent, "sample-transcript-report.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportURL.path))

        let data = try Data(contentsOf: reportURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RunReport.self, from: data)

        XCTAssertEqual(decoded.configuration.requestedModel, report.configuration.requestedModel)
        XCTAssertEqual(decoded.verification, report.verification)
        XCTAssertEqual(decoded.outputFiles.first?.sizeBytes, 123)
    }
}
