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

    func testTwitchPromptsWhenYouTubeQuotaIsBlocked() {
        let candidate = MediaSiteCandidate.detect(
            host: "www.twitch.tv",
            blockedDomains: [],
            youtubeQuotaBlocked: true
        )

        XCTAssertEqual(candidate?.domain, "twitch.tv")
        XCTAssertEqual(candidate?.category, .liveVideo)
        XCTAssertEqual(candidate?.platformName, "Twitch")
    }

    func testNewWebtoonPlatformPromptsWhenAnotherWebtoonSiteIsBlocked() {
        let candidate = MediaSiteCandidate.detect(
            host: "page.kakao.com",
            blockedDomains: ["comic.naver.com"],
            youtubeQuotaBlocked: false
        )

        XCTAssertEqual(candidate?.domain, "page.kakao.com")
        XCTAssertEqual(candidate?.category, .webtoon)
        XCTAssertEqual(
            candidate?.scheduleRequestMessage(after: "매일 밤 10시부터 아침 7시까지"),
            "매일 밤 10시부터 아침 7시까지 page.kakao.com 차단"
        )
    }

    func testAlreadyBlockedSiteDoesNotPromptAgain() {
        XCTAssertNil(
            MediaSiteCandidate.detect(
                host: "www.twitch.tv",
                blockedDomains: ["twitch.tv"],
                youtubeQuotaBlocked: true
            )
        )
    }

    func testUnrelatedSiteDoesNotBecomeWebtoonCandidate() {
        XCTAssertNil(
            MediaSiteCandidate.detect(
                host: "book.naver.com",
                blockedDomains: ["comic.naver.com"],
                youtubeQuotaBlocked: false
            )
        )
    }
}
