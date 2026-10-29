import CryptoKit
import Foundation
import XCTest
@testable import ThreeFBrowser

final class BrowserThemeTests: XCTestCase {
    func testCurrentEngineDoesNotClaimChromeExtensionSupport() {
        XCTAssertEqual(ExtensionCompatibility.currentEngine, .webKit)
        XCTAssertEqual(ExtensionCompatibility.supportLevel, .none)
        XCTAssertTrue(ExtensionCompatibility.limitation.contains("모든 확장"))
        XCTAssertTrue(ExtensionCompatibility.chromiumProfileRequirement.contains("전용"))
    }

    @MainActor
    func testThreeFRouterAcceptsHTTPSOnlyAndDrainsQueueOnce() throws {
        let router = ThreeFURLRouter()
        router.receive([
            try XCTUnwrap(URL(string: "threef://open?url=https%3A%2F%2Fexample.com%2Fpath")),
            try XCTUnwrap(URL(string: "threef://open?url=http%3A%2F%2Fexample.com")),
            try XCTUnwrap(URL(string: "threef://open?url=javascript%3Aalert(1)")),
            try XCTUnwrap(URL(string: "other://open?url=https%3A%2F%2Fexample.com")),
            try XCTUnwrap(URL(string: "threef://user:secret@open?url=https%3A%2F%2Fexample.com")),
            try XCTUnwrap(URL(string: "threef://open:8443?url=https%3A%2F%2Fexample.com"))
        ])

        let firstDrain = router.takePendingURLs()
        XCTAssertEqual(firstDrain.count, 1)
        XCTAssertEqual(URLComponents(url: firstDrain[0], resolvingAgainstBaseURL: false)?.queryItems?.first?.value,
                       "https://example.com/path")
        XCTAssertTrue(router.takePendingURLs().isEmpty)
    }

    func testThemeAcceptsOnlySixDigitHexColor() {
        XCTAssertTrue(BrowserTheme(accentHex: "#22AAFF").isValid)
        XCTAssertFalse(BrowserTheme(accentHex: "blue").isValid)
        XCTAssertFalse(BrowserTheme(accentHex: "#22AAFG").isValid)
        XCTAssertFalse(BrowserTheme(accentHex: "#22AAFF00").isValid)
    }

    func testQuickLinksAllowOnlyBoundedHTTPSDestinations() {
        let valid = BrowserTheme(accentHex: "#22AAFF", quickLinks: [
            BrowserQuickLink(title: "Docs", url: "https://example.com/docs")
        ])
        XCTAssertTrue(valid.isValid)
        XCTAssertEqual(valid.quickLinks.first?.destination?.host, "example.com")

        XCTAssertFalse(BrowserTheme(accentHex: "#22AAFF", quickLinks: [
            BrowserQuickLink(title: "Run code", url: "javascript:alert(1)")
        ]).isValid)
        XCTAssertFalse(BrowserTheme(accentHex: "#22AAFF", quickLinks: (0..<9).map {
            BrowserQuickLink(title: "Link \($0)", url: "https://example.com/\($0)")
        }).isValid)
    }

    func testLegacyThemeModuleWithoutQuickLinksStillLoads() throws {
        let legacy = Data(##"{"accentHex":"#22AAFF"}"##.utf8)
        let decoded = try JSONDecoder().decode(BrowserTheme.self, from: legacy)
        XCTAssertTrue(decoded.isValid)
        XCTAssertTrue(decoded.quickLinks.isEmpty)
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
