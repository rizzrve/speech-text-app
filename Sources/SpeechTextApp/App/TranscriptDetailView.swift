import AppKit
import SwiftUI

struct TranscriptDetailView: View {
    @ObservedObject var job: TranscriptionJob

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            transcriptList
        }
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(job.sourceURL.lastPathComponent).font(.headline)
                    Text(job.model.displayName).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let files = job.exportedFiles {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([files.txt, files.srt, files.json])
                    }
                }
            }

            switch job.status {
            case .processing(let stage):
                HStack {
                    ProgressView().controlSize(.small)
                    Text(stage)
                }
            case .failed(let message):
                Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
            case .done(let report):
                VerificationSummaryView(report: report)
            case .queued:
                Text("Queued").foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var transcriptList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(job.segments) { segment in
                    SegmentRow(segment: segment, isFlagged: flaggedIndices.contains(segment.id))
                }
            }
            .padding()
        }
    }

    private var flaggedIndices: Set<Int> {
        guard case .done(let report) = job.status else { return [] }
        var set = Set<Int>()
        for overlap in report.overlaps {
            set.insert(overlap.firstIndex)
            set.insert(overlap.secondIndex)
        }
        for cluster in report.repetitionClusters where cluster.startIndex <= cluster.endIndex {
            set.formUnion(cluster.startIndex...cluster.endIndex)
        }
        set.formUnion(report.emptySegmentIndices)
        set.formUnion(report.garbledSegmentIndices)
        set.formUnion(report.lowConfidenceIndices)
        return set
    }
}

private struct SegmentRow: View {
    let segment: TranscriptSegment
    let isFlagged: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(timestamp(segment.start))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(segment.text)
                .textSelection(.enabled)
            if isFlagged {
                Image(systemName: "flag.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
            }
        }
    }

    private func timestamp(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private struct VerificationSummaryView: View {
    let report: VerificationReport

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(
                report.isClean ? "No issues found" : "Flagged for review",
                systemImage: report.isClean ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(report.isClean ? .green : .yellow)

            Text("\(report.segmentCount) segments\(gapSummary)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !report.repetitionClusters.isEmpty {
                Text("\(report.repetitionClusters.count) repetition cluster(s) — possible runaway-loop artifact, review flagged lines")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if !report.overlaps.isEmpty {
                Text("\(report.overlaps.count) overlapping segment(s)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if !report.lowConfidenceIndices.isEmpty {
                Text("\(report.lowConfidenceIndices.count) low-confidence segment(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var gapSummary: String {
        guard !report.largeGaps.isEmpty else { return "" }
        return ", \(report.largeGaps.count) gap(s) > threshold"
    }
}
