import Foundation
import XCTest
@testable import ThreeFBrowser

final class MediaSiteSnoozeStoreTests: XCTestCase {
    func testSnoozePersistsAcrossStoreInstancesAndAppliesToSubdomains() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstLaunch = MediaSiteSnoozeStore(defaults: defaults, key: "snoozes")
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        firstLaunch.snooze(domain: "Twitch.TV", at: now)

        let nextLaunch = MediaSiteSnoozeStore(defaults: defaults, key: "snoozes")
        XCTAssertTrue(nextLaunch.suppresses(host: "clips.twitch.tv", at: now.addingTimeInterval(60)))
        XCTAssertFalse(nextLaunch.suppresses(host: "youtube.com", at: now.addingTimeInterval(60)))
    }

    func testSnoozeExpiresAtTwentyFourHoursAndRemovesExpiredEntry() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = MediaSiteSnoozeStore(defaults: defaults, key: "snoozes")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        store.snooze(domain: "twitch.tv", at: now)

        let expiry = now.addingTimeInterval(MediaSiteSnoozeStore.duration)
        XCTAssertFalse(store.suppresses(host: "twitch.tv", at: expiry))
        XCTAssertEqual(store.activeSnoozes(at: expiry), [:])
    }

    func testQAProfileUsesIsolatedSnoozeSuiteAndStandardLaunchUsesStandardDefaults() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let profile = temporaryRoot.appendingPathComponent("profile", isDirectory: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let qaDefaults = try XCTUnwrap(BrowserSessionStore.mediaSiteSnoozeDefaults(
            environment: ["THREEF_BROWSER_ENABLE_ISOLATED_QA_PROFILE": "1",
                         "THREEF_BROWSER_QA_PROFILE_DIRECTORY": profile.path],
            arguments: [], temporaryDirectory: temporaryRoot
        ))
        let productionDefaults = try XCTUnwrap(BrowserSessionStore.mediaSiteSnoozeDefaults(
            environment: [:], arguments: [], temporaryDirectory: temporaryRoot
        ))
        XCTAssertFalse(qaDefaults === UserDefaults.standard)
        XCTAssertTrue(productionDefaults === UserDefaults.standard)

        let key = "qa-snooze-\(UUID().uuidString)"
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        MediaSiteSnoozeStore(defaults: qaDefaults, key: key).snooze(domain: "example.test", at: date)
        XCTAssertNotNil(qaDefaults.object(forKey: key))
        XCTAssertNil(UserDefaults.standard.object(forKey: key))
    }

    func testUnavailableQAStoreFailsClosedWithoutFallingBackToStandardDefaults() throws {
        let key = "qa-snooze-unavailable-\(UUID().uuidString)"
        let store = MediaSiteSnoozeStore(defaults: nil, key: key)
        store.snooze(domain: "twitch.tv", at: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertEqual(store.activeSnoozes(at: Date(timeIntervalSince1970: 1_700_000_001)), [:])
        XCTAssertFalse(store.suppresses(host: "twitch.tv", at: Date(timeIntervalSince1970: 1_700_000_001)))
        XCTAssertNil(UserDefaults.standard.object(forKey: key), "a missing QA suite must never write to production defaults")
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "MediaSiteSnoozeStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
