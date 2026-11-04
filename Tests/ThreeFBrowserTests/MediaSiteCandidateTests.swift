import Foundation
import XCTest
@testable import ThreeFBrowser

final class MediaSiteCandidateTests: XCTestCase {
    func testScheduleRequestIncludesCandidateDomain() {
        let candidate = MediaSiteCandidate(
            domain: "twitch.tv",
            category: .liveVideo,
            platformName: "Twitch"
        )

        XCTAssertEqual(
            candidate.scheduleRequestMessage(after: "매일 밤 10시부터 아침 7시까지"),
            "매일 밤 10시부터 아침 7시까지 twitch.tv 차단"
        )
    }

    func testScheduleRequestDoesNotAppendCandidateDomainTwice() {
        let candidate = MediaSiteCandidate(
            domain: "twitch.tv",
            category: .liveVideo,
            platformName: "Twitch"
        )

        XCTAssertEqual(
            candidate.scheduleRequestMessage(after: "밤 10시에 TWITCH.TV 차단"),
            "밤 10시에 TWITCH.TV 차단"
        )
        XCTAssertEqual(
            candidate.scheduleRequestMessage(after: "밤 10시에 www.twitch.tv 차단"),
            "밤 10시에 www.twitch.tv 차단"
        )
        XCTAssertEqual(
            candidate.scheduleRequestMessage(after: "밤 10시에 not-twitch.tv 차단"),
            "밤 10시에 not-twitch.tv 차단 twitch.tv 차단"
        )
    }

    func testScheduleRequestTrimsAndRejectsBlankTimeWindow() {
        let candidate = MediaSiteCandidate(
            domain: "twitch.tv",
            category: .liveVideo,
            platformName: "Twitch"
        )

        XCTAssertEqual(
            candidate.scheduleRequestMessage(after: "  매일 22시  "),
            "매일 22시 twitch.tv 차단"
        )
        XCTAssertEqual(candidate.scheduleRequestMessage(after: " \n "), "")
    }
}
