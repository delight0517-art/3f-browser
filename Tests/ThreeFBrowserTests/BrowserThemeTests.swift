import CryptoKit
import Foundation
import XCTest
@testable import ThreeFBrowser

final class BrowserThemeTests: XCTestCase {
    func testThemeAcceptsOnlySixDigitHexColor() {
        XCTAssertTrue(BrowserTheme(accentHex: "#22AAFF").isValid)
        XCTAssertFalse(BrowserTheme(accentHex: "blue").isValid)
        XCTAssertFalse(BrowserTheme(accentHex: "#22AAFG").isValid)
        XCTAssertFalse(BrowserTheme(accentHex: "#22AAFF00").isValid)
    }

    func testHotModuleStoreAppliesAndRollsBackThemeData() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("threef-hot-theme-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = HotModuleStore(root: root)
        let first = Data(##"{"accentHex":"#112233"}"##.utf8)
        let second = Data(##"{"accentHex":"#AABBCC"}"##.utf8)
        try await store.apply(revision: 1, files: ["theme.json": first], expectedHashes: ["theme.json": Self.sha256(first)])
        try await store.apply(revision: 2, files: ["theme.json": second], expectedHashes: ["theme.json": Self.sha256(second)])

        let activeManifest = try await store.currentManifest()
        let activeTheme = try await store.loadFile(named: "theme.json")
        XCTAssertEqual(activeManifest?.revision, 2)
        XCTAssertEqual(activeTheme, second)
        try await store.rollback()
        let restoredManifest = try await store.currentManifest()
        let restoredTheme = try await store.loadFile(named: "theme.json")
        XCTAssertEqual(restoredManifest?.revision, 1)
        XCTAssertEqual(restoredTheme, first)
    }

    func testHotModuleStoreRejectsIncorrectHashAndUnsafePath() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("threef-hot-theme-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HotModuleStore(root: root)
        let data = Data(##"{"accentHex":"#112233"}"##.utf8)

        do {
            try await store.apply(revision: 1, files: ["theme.json": data], expectedHashes: ["theme.json": "bad"])
            XCTFail("expected hash mismatch")
        } catch HotModuleError.invalidHash("theme.json") {
        }
        do {
            try await store.apply(revision: 1, files: ["../theme.json": data], expectedHashes: ["../theme.json": Self.sha256(data)])
            XCTFail("expected path rejection")
        } catch HotModuleError.invalidPath("../theme.json") {
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
