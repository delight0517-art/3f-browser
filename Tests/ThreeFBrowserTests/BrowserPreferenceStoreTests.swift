import Foundation
import XCTest
@testable import ThreeFBrowser

final class BrowserPreferenceStoreTests: XCTestCase {
    func testIsolatedQAProfileStoresBrowserPreferencesInsideTemporaryProfile() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("threef-browser-preferences-\(UUID().uuidString)", isDirectory: true)
        let profile = temporaryRoot.appendingPathComponent("profile", isDirectory: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let suiteName = "threef-browser-preference-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("user-search", forKey: "appearance.v1.searchProvider")

        let store = BrowserPreferenceStore(
            environment: [
                "THREEF_BROWSER_ENABLE_ISOLATED_QA_PROFILE": "1",
                "THREEF_BROWSER_QA_PROFILE_DIRECTORY": profile.path
            ],
            temporaryDirectory: temporaryRoot,
            defaults: defaults
        )
        XCTAssertTrue(store.isIsolated)

        store.set("qa-search", forKey: "appearance.v1.searchProvider")
        store.set(["qa.example"], forKey: "threef.focusFence.mediaSiteDecisions.v1")
        let bookmarks = try JSONEncoder().encode(["https://qa.example/"])
        store.set(bookmarks, forKey: "browser.v1.bookmarks")

        XCTAssertEqual(store.string(forKey: "appearance.v1.searchProvider"), "qa-search")
        XCTAssertEqual(store.stringArray(forKey: "threef.focusFence.mediaSiteDecisions.v1"), ["qa.example"])
        XCTAssertEqual(store.data(forKey: "browser.v1.bookmarks"), bookmarks)
        XCTAssertEqual(defaults.string(forKey: "appearance.v1.searchProvider"), "user-search")
        XCTAssertNil(defaults.data(forKey: "browser.v1.bookmarks"))

        let file = profile.appendingPathComponent("browser-preferences.plist")
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual(((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o777, 0o600)
    }

    func testRejectedQAPathUsesTheProvidedUserDefaults() throws {
        let suiteName = "threef-browser-preference-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = BrowserPreferenceStore(
            environment: [
                "THREEF_BROWSER_ENABLE_ISOLATED_QA_PROFILE": "1",
                "THREEF_BROWSER_QA_PROFILE_DIRECTORY": FileManager.default.homeDirectoryForCurrentUser.path
            ],
            temporaryDirectory: FileManager.default.temporaryDirectory,
            defaults: defaults
        )
        XCTAssertFalse(store.isIsolated)
        XCTAssertNil(store.string(forKey: "appearance.v1.searchProvider"))
        store.set("user-search", forKey: "appearance.v1.searchProvider")
        XCTAssertNil(defaults.string(forKey: "appearance.v1.searchProvider"))
    }
}
