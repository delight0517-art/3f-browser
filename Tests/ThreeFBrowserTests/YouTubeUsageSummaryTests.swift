import Foundation
import XCTest
@testable import ThreeFBrowser

final class YouTubeUsageSummaryTests: XCTestCase {
    func testDecodesOnlyAggregateUsageFieldsAndFormatsDailyAndRollingHourClearly() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "todaySeconds": 1339,
            "browserSeconds": ["3f": 480, "firefox": 859],
            "dailyCapMinutes": 20,
            "hourlyCapMinutes": 10,
            "hourlyUsedSeconds": 615,
            "hourlyRemainingSeconds": 900,
            "blocked": true,
            "cloudAccount": "ignored@example.com",
        ])

        let summary = try XCTUnwrap(FocusFenceYouTubeUsageSummary.decode(data))

        XCTAssertEqual(summary.statusLine, "오늘 시청 22분 19초 · 일 한도 20분 · YouTube 영상 재생 제한 중 · 최근 1시간 시청 10분 15초 · 시간 한도 10분 · 남은 한도 15분")
        XCTAssertEqual(summary.compactStatusLine, "오늘 22분 19초 / 일 20분 · 남은 0분 · 최근 1시간 10분 15초 / 10분 · 남은 15분 · 재생 제한 중")
        XCTAssertEqual(summary.todaySeconds, 1339)
        XCTAssertTrue(summary.blocked)
    }

    func testAvailableQuotaLabelsConsumedAndRemainingTimeSeparately() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "todaySeconds": 1080,
            "dailyCapMinutes": 20,
            "hourlyCapMinutes": 10,
            "hourlyUsedSeconds": 120,
            "hourlyRemainingSeconds": 480,
            "blocked": false,
        ])

        let summary = try XCTUnwrap(FocusFenceYouTubeUsageSummary.decode(data))

        XCTAssertEqual(summary.statusLine, "오늘 시청 18분 · 일 한도 20분 · 남은 한도 2분 · 최근 1시간 시청 2분 · 시간 한도 10분 · 남은 한도 8분")
        XCTAssertEqual(summary.compactStatusLine, "오늘 18분 / 일 20분 · 남은 2분 · 최근 1시간 2분 / 10분 · 남은 8분")
    }

    func testMalformedOrNegativeUsageIsUnavailableInsteadOfShowingZero() throws {
        let negative = try JSONSerialization.data(withJSONObject: [
            "todaySeconds": -1,
            "dailyCapMinutes": 20,
            "hourlyCapMinutes": 10,
            "hourlyUsedSeconds": 0,
            "hourlyRemainingSeconds": 600,
            "blocked": false,
        ])
        let incomplete = try JSONSerialization.data(withJSONObject: ["todaySeconds": 0])

        XCTAssertNil(FocusFenceYouTubeUsageSummary.decode(negative))
        XCTAssertNil(FocusFenceYouTubeUsageSummary.decode(incomplete))
    }

    func testUsageDurationKeepsSecondsVisibleForAmbiguousMinutes() {
        XCTAssertEqual(FocusFenceYouTubeUsageSummary.duration(0), "0분")
        XCTAssertEqual(FocusFenceYouTubeUsageSummary.duration(60), "1분")
        XCTAssertEqual(FocusFenceYouTubeUsageSummary.duration(1339), "22분 19초")
        XCTAssertEqual(FocusFenceYouTubeUsageSummary.duration(3661), "1시간 1분 1초")
    }
}
