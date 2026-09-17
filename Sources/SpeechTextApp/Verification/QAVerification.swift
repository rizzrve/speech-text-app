import Foundation

/// Automates the manual audit performed by hand in the Mitra transcription run
/// report (§7): segment overlap/gap/coverage checks, repetition-loop detection
/// (the §3 whisper.cpp context-carryover defect), and confidence flags.
enum QAVerification {
    static func verify(
        segments: [TranscriptSegment],
        sourceDuration: TimeInterval? = nil,
        gapThreshold: TimeInterval = 5.0,
        repetitionRunThreshold: Int = 3,
        lowLogProbThreshold: Double = -1.0,
        highNoSpeechThreshold: Double = 0.6
    ) -> VerificationReport {
        guard !segments.isEmpty else {
            return VerificationReport(
                segmentCount: 0,
                coverageStart: nil,
                coverageEnd: nil,
                leadingGap: 0,
                trailingGap: nil,
                overlaps: [],
                largeGaps: [],
                repetitionClusters: [],
                emptySegmentIndices: [],
                garbledSegmentIndices: [],
                lowConfidenceIndices: []
            )
        }

        var overlaps: [VerificationReport.Overlap] = []
        var largeGaps: [VerificationReport.Gap] = []

        for i in 0..<(segments.count - 1) {
            let current = segments[i]
            let next = segments[i + 1]
            let delta = next.start - current.end
            if delta < 0 {
                overlaps.append(.init(firstIndex: i, secondIndex: i + 1, overlapDuration: -delta))
            } else if delta > gapThreshold {
                largeGaps.append(.init(afterIndex: i, duration: delta))
            }
        }

        var repetitionClusters: [VerificationReport.RepetitionCluster] = []
        var runStart = 0
        for i in 1...segments.count {
            let sameAsRunStart = i < segments.count && normalized(segments[i].text) == normalized(segments[runStart].text)
            if !sameAsRunStart {
                let runLength = i - runStart
                if runLength >= repetitionRunThreshold, !normalized(segments[runStart].text).isEmpty {
                    repetitionClusters.append(.init(startIndex: runStart, endIndex: i - 1, text: segments[runStart].text))
                }
                runStart = i
            }
        }

        let emptySegmentIndices = segments.indices.filter { normalized(segments[$0].text).isEmpty }
        let garbledSegmentIndices = segments.indices.filter { isGarbled(segments[$0].text) }
        let lowConfidenceIndices = segments.indices.filter { idx in
            let s = segments[idx]
            if let logProb = s.avgLogProb, logProb < lowLogProbThreshold { return true }
            if let noSpeech = s.noSpeechProb, noSpeech > highNoSpeechThreshold { return true }
            return false
        }

        let leadingGap = segments[0].start
        let trailingGap = sourceDuration.map { max(0, $0 - segments[segments.count - 1].end) }

        return VerificationReport(
            segmentCount: segments.count,
            coverageStart: segments.first?.start,
            coverageEnd: segments.last?.end,
            leadingGap: leadingGap,
            trailingGap: trailingGap,
            overlaps: overlaps,
            largeGaps: largeGaps,
            repetitionClusters: repetitionClusters,
            emptySegmentIndices: emptySegmentIndices,
            garbledSegmentIndices: garbledSegmentIndices,
            lowConfidenceIndices: lowConfidenceIndices
        )
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isGarbled(_ text: String) -> Bool {
        if text.unicodeScalars.contains(where: { $0.value == 0xFFFD }) {
            return true
        }
        let hasDisallowedControlChars = text.unicodeScalars.contains { scalar in
            CharacterSet.controlCharacters.contains(scalar) && scalar != "\n" && scalar != "\t" && scalar != "\r"
        }
        return hasDisallowedControlChars
    }
}

struct VerificationReport: Equatable, Codable {
    struct Overlap: Equatable, Codable {
        let firstIndex: Int
        let secondIndex: Int
        let overlapDuration: TimeInterval
    }

    struct Gap: Equatable, Codable {
        let afterIndex: Int
        let duration: TimeInterval
    }

    struct RepetitionCluster: Equatable, Codable {
        let startIndex: Int
        let endIndex: Int
        let text: String
    }

    let segmentCount: Int
    let coverageStart: TimeInterval?
    let coverageEnd: TimeInterval?
    let leadingGap: TimeInterval
    let trailingGap: TimeInterval?
    let overlaps: [Overlap]
    let largeGaps: [Gap]
    let repetitionClusters: [RepetitionCluster]
    let emptySegmentIndices: [Int]
    let garbledSegmentIndices: [Int]
    let lowConfidenceIndices: [Int]

    var isClean: Bool {
        overlaps.isEmpty
            && repetitionClusters.isEmpty
            && emptySegmentIndices.isEmpty
            && garbledSegmentIndices.isEmpty
    }
}
