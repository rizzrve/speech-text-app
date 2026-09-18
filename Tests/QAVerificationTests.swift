import XCTest
@testable import SpeechTextApp

final class QAVerificationTests: XCTestCase {
    private func segment(
        _ id: Int,
        _ start: TimeInterval,
        _ end: TimeInterval,
        _ text: String,
        avgLogProb: Double? = nil,
        compressionRatio: Double? = nil,
        noSpeechProb: Double? = nil
    ) -> TranscriptSegment {
        TranscriptSegment(id: id, start: start, end: end, text: text, avgLogProb: avgLogProb, compressionRatio: compressionRatio, noSpeechProb: noSpeechProb)
    }

    func testCleanTranscriptHasNoFlags() {
        let segments = [
            segment(0, 0.0, 2.0, "Hello there"),
            segment(1, 2.0, 4.0, "How are you"),
            segment(2, 4.0, 6.0, "Doing well thanks"),
        ]
        let report = QAVerification.verify(segments: segments, sourceDuration: 6.0)
        XCTAssertTrue(report.isClean)
        XCTAssertEqual(report.segmentCount, 3)
        XCTAssertEqual(report.leadingGap, 0.0)
        XCTAssertEqual(report.trailingGap, 0.0)
    }

    func testOverlappingSegmentsAreDetected() {
        let segments = [
            segment(0, 0.0, 3.0, "First"),
            segment(1, 2.0, 5.0, "Second overlaps first"),
        ]
        let report = QAVerification.verify(segments: segments)
        XCTAssertEqual(report.overlaps.count, 1)
        XCTAssertEqual(report.overlaps.first?.firstIndex, 0)
        XCTAssertEqual(report.overlaps.first?.secondIndex, 1)
        XCTAssertEqual(report.overlaps.first?.overlapDuration ?? -1, 1.0, accuracy: 0.0001)
    }

    func testLargeGapIsDetectedAboveThreshold() {
        let segments = [
            segment(0, 0.0, 2.0, "Before the gap"),
            segment(1, 30.0, 32.0, "After a 28s gap"),
        ]
        let report = QAVerification.verify(segments: segments, gapThreshold: 5.0)
        XCTAssertEqual(report.largeGaps.count, 1)
        XCTAssertEqual(report.largeGaps.first?.afterIndex, 0)
        XCTAssertEqual(report.largeGaps.first?.duration ?? -1, 28.0, accuracy: 0.0001)
    }

    func testGapBelowThresholdIsNotFlagged() {
        let segments = [
            segment(0, 0.0, 2.0, "Before"),
            segment(1, 4.0, 6.0, "After a 2s gap"),
        ]
        let report = QAVerification.verify(segments: segments, gapThreshold: 5.0)
        XCTAssertTrue(report.largeGaps.isEmpty)
    }

    func testRunawayRepetitionClusterIsDetected() {
        // Mirrors the Mitra report §3 failure mode: identical line repeated back to back.
        let segments = [
            segment(0, 0.0, 2.0, "Kami ingin mempunyai jenis JPI Citi."),
            segment(1, 2.0, 4.0, "Kami ingin mempunyai jenis JPI Citi."),
            segment(2, 4.0, 6.0, "Kami ingin mempunyai jenis JPI Citi."),
            segment(3, 6.0, 8.0, "Something different now"),
        ]
        let report = QAVerification.verify(segments: segments, repetitionRunThreshold: 3)
        XCTAssertEqual(report.repetitionClusters.count, 1)
        XCTAssertEqual(report.repetitionClusters.first?.startIndex, 0)
        XCTAssertEqual(report.repetitionClusters.first?.endIndex, 2)
        XCTAssertFalse(report.isClean)
    }

    func testRepetitionBelowThresholdIsNotFlagged() {
        let segments = [
            segment(0, 0.0, 2.0, "Pol itu"),
            segment(1, 2.0, 4.0, "Pol itu"),
            segment(2, 4.0, 6.0, "Different output"),
        ]
        let report = QAVerification.verify(segments: segments, repetitionRunThreshold: 3)
        XCTAssertTrue(report.repetitionClusters.isEmpty)
    }

    func testEmptySegmentIsDetected() {
        let segments = [
            segment(0, 0.0, 2.0, "Real text"),
            segment(1, 2.0, 4.0, "   "),
        ]
        let report = QAVerification.verify(segments: segments)
        XCTAssertEqual(report.emptySegmentIndices, [1])
        XCTAssertFalse(report.isClean)
    }

    func testTokenOnlySegmentIsDetectedAsEmpty() {
        let segments = [
            segment(0, 0.0, 2.0, "<|0.00|> Real text<|2.00|>"),
            segment(1, 2.0, 4.0, "<|startoftranscript|><|en|><|transcribe|><|0.00|><|endoftext|>"),
        ]
        let report = QAVerification.verify(segments: segments)
        XCTAssertEqual(report.emptySegmentIndices, [1])
    }

    func testRepetitionIsDetectedDespiteDifferingTimestampTokens() {
        let segments = [
            segment(0, 0.0, 2.0, "<|0.00|> Kedalam<|2.00|>"),
            segment(1, 2.0, 4.0, "<|2.00|> Kedalam<|4.00|>"),
            segment(2, 4.0, 6.0, "<|4.00|> Kedalam<|6.00|>"),
            segment(3, 6.0, 8.0, "<|6.00|> Something else<|8.00|>"),
        ]
        let report = QAVerification.verify(segments: segments, repetitionRunThreshold: 3)
        XCTAssertEqual(report.repetitionClusters.count, 1)
        XCTAssertEqual(report.repetitionClusters.first?.endIndex, 2)
    }

    func testGarbledSegmentIsDetected() {
        let segments = [
            segment(0, 0.0, 2.0, "Normal text"),
            segment(1, 2.0, 4.0, "Broken \u{FFFD}\u{FFFD} text"),
        ]
        let report = QAVerification.verify(segments: segments)
        XCTAssertEqual(report.garbledSegmentIndices, [1])
    }

    func testLowConfidenceViaLogProbIsDetected() {
        let segments = [
            segment(0, 0.0, 2.0, "Confident", avgLogProb: -0.2),
            segment(1, 2.0, 4.0, "Uncertain", avgLogProb: -1.4),
        ]
        let report = QAVerification.verify(segments: segments)
        XCTAssertEqual(report.lowConfidenceIndices, [1])
    }

    func testLowConfidenceViaNoSpeechProbIsDetected() {
        let segments = [
            segment(0, 0.0, 2.0, "Confident", noSpeechProb: 0.1),
            segment(1, 2.0, 4.0, "Probably silence", noSpeechProb: 0.9),
        ]
        let report = QAVerification.verify(segments: segments)
        XCTAssertEqual(report.lowConfidenceIndices, [1])
    }

    func testCoverageGapsAgainstSourceDuration() {
        let segments = [
            segment(0, 1.5, 3.0, "Starts late"),
            segment(1, 3.0, 4.0, "Ends before source ends"),
        ]
        let report = QAVerification.verify(segments: segments, sourceDuration: 6.0)
        XCTAssertEqual(report.leadingGap, 1.5, accuracy: 0.0001)
        XCTAssertEqual(report.trailingGap ?? -1, 2.0, accuracy: 0.0001)
    }

    func testEmptySegmentsArrayProducesEmptyReport() {
        let report = QAVerification.verify(segments: [])
        XCTAssertEqual(report.segmentCount, 0)
        XCTAssertTrue(report.isClean)
        XCTAssertNil(report.trailingGap)
    }
}
