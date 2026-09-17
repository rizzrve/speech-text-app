import Hub
import XCTest
@testable import SpeechTextApp

final class TranscriptionEngineModelCacheTests: XCTestCase {
    private let requiredComponents = ["MelSpectrogram", "AudioEncoder", "TextDecoder", "TextDecoderContextPrefill"]

    private func expectedFolder(tempDir: URL, model: TranscriptionModel) -> URL {
        let repo = Hub.Repo(id: "argmaxinc/whisperkit-coreml", type: .models)
        return HubApi(downloadBase: tempDir).localRepoLocation(repo).appending(component: model.whisperKitIdentifier)
    }

    private func writeWeightFile(in componentDir: URL, bytes: Data = Data([0x01, 0x02, 0x03])) throws {
        let weightsDir = componentDir.appendingPathComponent("weights")
        try FileManager.default.createDirectory(at: weightsDir, withIntermediateDirectories: true)
        try bytes.write(to: weightsDir.appendingPathComponent("weight.bin"))
    }

    private func makeTempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    func testMissingFolderReturnsNil() {
        let tempDir = makeTempDir()
        let result = TranscriptionEngine.completeLocalModelFolder(for: .turbo, downloadBase: tempDir)
        XCTAssertNil(result)
    }

    func testCompleteFolderIsRecognized() throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let folder = expectedFolder(tempDir: tempDir, model: .turbo)
        for component in requiredComponents {
            try writeWeightFile(in: folder.appendingPathComponent("\(component).mlmodelc"))
        }

        let result = TranscriptionEngine.completeLocalModelFolder(for: .turbo, downloadBase: tempDir)
        XCTAssertEqual(result, folder)
    }

    func testIncompleteFolderMissingOneComponentReturnsNil() throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let folder = expectedFolder(tempDir: tempDir, model: .turbo)
        for component in requiredComponents.dropLast() {
            try writeWeightFile(in: folder.appendingPathComponent("\(component).mlmodelc"))
        }

        let result = TranscriptionEngine.completeLocalModelFolder(for: .turbo, downloadBase: tempDir)
        XCTAssertNil(result)
    }

    func testEmptyWeightFileIsNotConsideredComplete() throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let folder = expectedFolder(tempDir: tempDir, model: .turbo)
        for component in requiredComponents {
            try writeWeightFile(in: folder.appendingPathComponent("\(component).mlmodelc"), bytes: Data())
        }

        let result = TranscriptionEngine.completeLocalModelFolder(for: .turbo, downloadBase: tempDir)
        XCTAssertNil(result)
    }
}
