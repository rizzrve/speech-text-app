import Foundation

/// Engine-agnostic transcript segment. Kept decoupled from WhisperKit's own
/// `TranscriptionSegment` so QAVerification/Exporter work unchanged if the
/// engine ever falls back to whisper.cpp (see plan's engine gate).
struct TranscriptSegment: Identifiable, Codable, Equatable, Sendable {
    let id: Int
    let start: TimeInterval
    let end: TimeInterval
    let text: String
    /// Average log-probability over sampled tokens, if the engine reports one.
    let avgLogProb: Double?
    /// Ratio of encoded text length to compressed length; high values indicate repetition.
    let compressionRatio: Double?
    /// Probability the segment contains no speech.
    let noSpeechProb: Double?

    init(
        id: Int,
        start: TimeInterval,
        end: TimeInterval,
        text: String,
        avgLogProb: Double? = nil,
        compressionRatio: Double? = nil,
        noSpeechProb: Double? = nil
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.avgLogProb = avgLogProb
        self.compressionRatio = compressionRatio
        self.noSpeechProb = noSpeechProb
    }
}
