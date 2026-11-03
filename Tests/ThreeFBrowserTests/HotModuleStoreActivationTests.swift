import CryptoKit
import Foundation
import XCTest
@testable import ThreeFBrowser

final class HotModuleStoreActivationTests: XCTestCase {
    func testFailedActivationRestoresThePreviousRevision() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("threef-hot-activation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fileManager = FailingPendingActivationFileManager()
        let store = HotModuleStore(root: root, fileManager: fileManager)
        let first = Data(##"{"accentHex":"#112233"}"##.utf8)
        let second = Data(##"{"accentHex":"#AABBCC"}"##.utf8)
        try await store.apply(revision: 1, files: ["theme.json": first], expectedHashes: ["theme.json": Self.sha256(first)])

        fileManager.failNextPendingActivation = true
        do {
            try await store.apply(revision: 2, files: ["theme.json": second], expectedHashes: ["theme.json": Self.sha256(second)])
            XCTFail("expected pending activation failure")
        } catch is PendingActivationFailure {
        }

        let restoredManifest = try await store.currentManifest()
        let restoredTheme = try await store.loadFile(named: "theme.json")
        XCTAssertEqual(restoredManifest?.revision, 1)
        XCTAssertEqual(restoredTheme, first)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("pending").path))
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private struct PendingActivationFailure: Error {}

private final class FailingPendingActivationFileManager: FileManager {
    var failNextPendingActivation = false

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if failNextPendingActivation,
           srcURL.lastPathComponent == "pending",
           dstURL.lastPathComponent == "active" {
            failNextPendingActivation = false
            throw PendingActivationFailure()
        }
        try super.moveItem(at: srcURL, to: dstURL)
    }
}
