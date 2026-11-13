import CryptoKit
import Foundation
import XCTest
@testable import ThreeFBrowser

final class BrowserThemeTests: XCTestCase {
    func testThreeFYouTubeReporterWaitsForFocusFenceQuotaBeforePlayback() {
        XCTAssertTrue(OptionalFeatureAvailability.youtubeUsageReporting)
        XCTAssertTrue(YouTubeUsageReporter.script.contains("blocked = true;"))
        XCTAssertTrue(YouTubeUsageReporter.script.contains("threefYouTubeUsage"))
        // Quota and Shorts policy behavior is executed by test-youtube-usage-reporter.js.
        XCTAssertTrue(YouTubeUsageReporter.script.contains("qualificationMs:5000"))
        XCTAssertTrue(YouTubeUsageReporter.script.contains("minimum_5s_qualified_30s_account_lease_v1"))
        XCTAssertTrue(YouTubeUsageReporter.script.contains("type:'leaseReport'"))
        XCTAssertTrue(YouTubeUsageReporter.script.contains("quotaBlocked = true"))
        XCTAssertTrue(YouTubeUsageReporter.script.contains("if (blocked) stop();"))
        XCTAssertTrue(YouTubeUsageReporter.script.contains("['ArrowLeft', 'ArrowRight'].includes(event.key)"))
        XCTAssertTrue(YouTubeUsageReporter.script.contains("event.stopImmediatePropagation()"))
        XCTAssertTrue(YouTubeUsageReporter.script.contains("const policyRefreshIntervalMs = 2000"))
        XCTAssertTrue(YouTubeUsageReporter.script.contains("let policyRefreshInFlight = null"))
        XCTAssertFalse(YouTubeUsageReporter.script.contains("fetch("), "The YouTube page must not call the local HTTP API directly")
    }

    func testThreeFLeaseBridgeValidatesQualificationAndYouTubeOrigin() throws {
        let payload = try XCTUnwrap(YouTubeUsageBridgePayload.leaseRequest(from: [
            "requestId": "lease-123", "qualificationMs": 5_000
        ], pageHost: "www.youtube.com"))
        XCTAssertEqual(payload["requestId"] as? String, "lease-123")
        XCTAssertEqual(payload["qualificationMs"] as? Int, 5_000)
        XCTAssertNil(YouTubeUsageBridgePayload.leaseRequest(from: [
            "requestId": "lease-123", "qualificationMs": 4_999
        ], pageHost: "www.youtube.com"))
        XCTAssertNil(YouTubeUsageBridgePayload.leaseRequest(from: [
            "requestId": "lease-123", "qualificationMs": 5_000
        ], pageHost: "example.com"))
        XCTAssertNil(YouTubeUsageBridgePayload.leaseRequest(from: [
            "requestId": "bad id", "qualificationMs": 5_000
        ], pageHost: "www.youtube.com"))
    }

    func testThreeFLeaseBridgeAcceptsOnlyBoundedMeasuredIntervals() throws {
        let payload = try XCTUnwrap(YouTubeUsageBridgePayload.leaseReport(from: [
            "grantId": "grant-123",
            "reportId": "report-456",
            "intervals": [[NSNumber(value: 1_000), NSNumber(value: 2_500)]]
        ], pageHost: "youtube.com"))
        XCTAssertEqual(payload["browser"] as? String, "3f")
        XCTAssertEqual(payload["grantId"] as? String, "grant-123")
        XCTAssertEqual(payload["reportId"] as? String, "report-456")
        XCTAssertNil(YouTubeUsageBridgePayload.leaseReport(from: [
            "grantId": "grant-123", "reportId": "report-456",
            "intervals": [[NSNumber(value: 2_500), NSNumber(value: 1_000)]]
        ], pageHost: "youtube.com"))
        XCTAssertNil(YouTubeUsageBridgePayload.leaseReport(from: [
            "grantId": "grant-123", "reportId": "report-456",
            "intervals": Array(repeating: [NSNumber(value: 1), NSNumber(value: 2)], count: 21)
        ], pageHost: "youtube.com"))
    }

    func testThreeFYouTubeBridgeSendsOnlyValidatedAggregatePlayback() throws {
        let report = try XCTUnwrap(YouTubeUsageBridgePayload.report(from: [
            "reportId": "abc-123",
            "seconds": 5,
            "watchSeconds": 4,
            "title": "private page title",
            "url": "https://www.youtube.com/watch?v=private"
        ], pageHost: "www.youtube.com"))

        XCTAssertEqual(report["host"] as? String, "www.youtube.com")
        XCTAssertEqual(report["browser"] as? String, "3f")
        XCTAssertEqual(report["seconds"] as? Int, 5)
        XCTAssertEqual(report["watchSeconds"] as? Int, 4)
        XCTAssertEqual(Set(report.keys), Set(["host", "reportId", "seconds", "watchSeconds", "playing", "browser"]))
        XCTAssertNil(YouTubeUsageBridgePayload.report(from: [
            "reportId": "abc-123", "seconds": 5, "watchSeconds": 6
        ], pageHost: "www.youtube.com"))
        XCTAssertNil(YouTubeUsageBridgePayload.report(from: [
            "reportId": "abc-123", "seconds": 5, "watchSeconds": 4
        ], pageHost: "example.com"))
    }

    func testAddressBarUsesSelectedSearchProviderAndRejectsURLCredentials() throws {
        let google = try XCTUnwrap(AddressBarNavigationRequest.resolve("cats", searchProvider: .google))
        XCTAssertEqual(google.host, "www.google.com")
        XCTAssertEqual(URLComponents(url: google, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "cats")

        let bing = try XCTUnwrap(AddressBarNavigationRequest.resolve("cats", searchProvider: .bing))
        XCTAssertEqual(bing.host, "www.bing.com")
        let duckDuckGo = try XCTUnwrap(AddressBarNavigationRequest.resolve("cats", searchProvider: .duckduckgo))
        XCTAssertEqual(duckDuckGo.host, "duckduckgo.com")

        XCTAssertNil(AddressBarNavigationRequest.resolve("https://user:secret@example.com", searchProvider: .google))
        XCTAssertEqual(AddressBarNavigationRequest.resolve("example.com", searchProvider: .google)?.absoluteString,
                       "https://example.com")
        XCTAssertEqual(AddressBarNavigationRequest.resolve("https://example.com/path", searchProvider: .google)?.host,
                       "example.com")
    }

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
            try XCTUnwrap(URL(string: "threef://open?url=https%3A%2F%2Fexample.com%2Fpath%3Fq%3Dhello%2520world")),
            try XCTUnwrap(URL(string: "threef://open?url=http%3A%2F%2Fexample.com")),
            try XCTUnwrap(URL(string: "threef://open?url=javascript%3Aalert(1)")),
            try XCTUnwrap(URL(string: "other://open?url=https%3A%2F%2Fexample.com")),
            try XCTUnwrap(URL(string: "threef://user:secret@open?url=https%3A%2F%2Fexample.com")),
            try XCTUnwrap(URL(string: "threef://open:8443?url=https%3A%2F%2Fexample.com"))
        ])

        let firstDrain = router.takePendingURLs()
        XCTAssertEqual(firstDrain.count, 2)
        XCTAssertEqual(URLComponents(url: firstDrain[0], resolvingAgainstBaseURL: false)?.queryItems?.first?.value,
                       "https://example.com/path")
        XCTAssertEqual(URLComponents(url: firstDrain[1], resolvingAgainstBaseURL: false)?.queryItems?.first?.value,
                       "https://example.com/path?q=hello%20world")
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
