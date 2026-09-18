import Foundation

/// Whisper's control tokens (`<|startoftranscript|>`, `<|ms|>`, `<|4.00|>`,
/// `<|endoftext|>`, …) are decoder bookkeeping, not speech. They leak into
/// segment text unless the decoder is told to skip them, and when they do they
/// also defeat text-based QA: timestamp tokens make otherwise identical lines
/// differ, and token-only lines look non-empty.
enum WhisperSpecialTokens {
    private static let pattern = /<\|[^|]*\|>/

    static func strip(_ text: String) -> String {
        text.replacing(pattern, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
