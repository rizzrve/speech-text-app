import WhisperKit
import XCTest
@testable import SpeechTextApp

final class TranscriptionLanguageTests: XCTestCase {
    func testMalayUsesWhisperCodeMsNotMy() {
        // "my" is Whisper's code for Burmese, not Malay.
        XCTAssertEqual(TranscriptionLanguage.malay.whisperCode, "ms")
        XCTAssertEqual(TranscriptionLanguage.english.whisperCode, "en")
    }

    func testDecodingOptionsForceTheSelectedLanguage() {
        let options = TranscriptionEngine.decodingOptions(for: .malay)
        XCTAssertEqual(options.language, "ms")
        XCTAssertFalse(options.detectLanguage)
        XCTAssertTrue(options.skipSpecialTokens)
    }
}
