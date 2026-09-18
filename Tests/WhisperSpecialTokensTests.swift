import XCTest
@testable import SpeechTextApp

final class WhisperSpecialTokensTests: XCTestCase {
    func testWindowHeaderAndTimestampTokensAreStripped() {
        let raw = "<|startoftranscript|><|ms|><|transcribe|><|0.00|> saya pilihkan<|2.00|>"
        XCTAssertEqual(WhisperSpecialTokens.strip(raw), "saya pilihkan")
    }

    func testTokenOnlyTextBecomesEmpty() {
        let raw = "<|startoftranscript|><|en|><|transcribe|><|0.00|><|endoftext|>"
        XCTAssertEqual(WhisperSpecialTokens.strip(raw), "")
    }

    func testPlainTextIsOnlyTrimmed() {
        XCTAssertEqual(WhisperSpecialTokens.strip("  Kalau saya tak perlu "), "Kalau saya tak perlu")
    }

    func testAngleBracketsThatAreNotTokensAreKept() {
        XCTAssertEqual(WhisperSpecialTokens.strip("a < b > c"), "a < b > c")
    }
}
