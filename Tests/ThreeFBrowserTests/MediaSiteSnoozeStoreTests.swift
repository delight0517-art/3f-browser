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

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "MediaSiteSnoozeStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
