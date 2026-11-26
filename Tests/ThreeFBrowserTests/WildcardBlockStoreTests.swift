import XCTest
@testable import ThreeFBrowser

final class WildcardBlockStoreTests: XCTestCase {
    func testRemoteSyncIsDisabledOnlyForQASessions() {
        XCTAssertTrue(WildcardBlockStore.shouldSyncWithRemoteServices(isQASession: false))
        XCTAssertFalse(WildcardBlockStore.shouldSyncWithRemoteServices(isQASession: true))
    }

    func testWildcardBlockStoreSavesAndMatchesUrlAndTitle() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("threef-wildcard-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = WildcardBlockStore(directory: dir)
        XCTAssertFalse(store.addRule(pattern: "a", hideTitle: true, blockUrl: true))
        XCTAssertFalse(store.addRule(pattern: "yandong", hideTitle: false, blockUrl: false))

        XCTAssertTrue(store.addRule(pattern: "yandong", hideTitle: true, blockUrl: true))
        XCTAssertTrue(store.addRule(pattern: "onlytitle", hideTitle: true, blockUrl: false))

        XCTAssertEqual(store.hiddenTitleKeywords(), ["onlytitle", "yandong"])
        XCTAssertEqual(store.blockedUrlPatterns(), ["yandong"])

        let matched = URL(string: "https://mirror99.example.com/path/yandong/list")!
        let encoded = URL(string: "https://google.com/search?q=%79%61%6e%64%6f%6e%67")!
        let titleOnly = URL(string: "https://example.com/onlytitle")!

        XCTAssertTrue(store.matchesBlockedUrl(matched))
        XCTAssertTrue(store.matchesBlockedUrl(encoded))
        XCTAssertFalse(store.matchesBlockedUrl(titleOnly))

        // Persistence round-trip
        let reloaded = WildcardBlockStore(directory: dir)
        XCTAssertTrue(reloaded.matchesBlockedUrl(matched))
        XCTAssertEqual(reloaded.hiddenTitleKeywords(), ["onlytitle", "yandong"])
    }
}
