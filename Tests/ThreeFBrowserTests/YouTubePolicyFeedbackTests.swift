import Foundation
import XCTest
@testable import ThreeFBrowser

final class YouTubePolicyFeedbackTests: XCTestCase {
    private func summary(_ changes: [String: Any] = [:]) throws -> FocusFenceYouTubeUsageSummary {
        let body: [String: Any] = ["todaySeconds": 1206, "dailyCapMinutes": 20,
            "hourlyCapMinutes": 10, "hourlyUsedSeconds": 0, "hourlyRemainingSeconds": 600,
            "blocked": true, "cloudSignedIn": true, "accountBudget": ["available": false]]
        let data = try JSONSerialization.data(withJSONObject: body.merging(changes, uniquingKeysWith: { _, value in value }))
        return try XCTUnwrap(FocusFenceYouTubeUsageSummary.decode(data))
    }

    private func policy(_ changes: [String: Any] = [:]) throws -> FocusFenceYouTubePlaybackPolicy {
        let body: [String: Any] = ["youtubeQuotaBlocked": true, "youtubeQuotaResetAfterSeconds": 3661,
            "youtubeBlockedByActiveSchedule": false, "blockShorts": false]
        let data = try JSONSerialization.data(withJSONObject: body.merging(changes, uniquingKeysWith: { _, value in value }))
        return try XCTUnwrap(FocusFenceYouTubePlaybackPolicy.decode(data))
    }

    func testDailyLimitShowsReasonAndServerCountdownWithoutClaimingRecoveryOnExpiry() throws {
        let observed = Date(timeIntervalSince1970: 1000)
        let value = try summary().withPolicy(policy(), observedAt: observed)
        XCTAssertEqual(value.restrictionReason(isShorts: false), "오늘 YouTube 시청 한도 20분을 모두 사용했습니다.")
        XCTAssertEqual(value.resumeStatus(at: observed), "다시 시청까지 약 1시간 1분 1초")
        XCTAssertEqual(value.resumeStatus(at: observed.addingTimeInterval(61)), "다시 시청까지 약 1시간 0분")
        XCTAssertEqual(value.resumeStatus(at: observed.addingTimeInterval(4000)), "한도 갱신을 확인하고 있습니다.")
        XCTAssertTrue(value.synchronizationExplanation?.contains("로그인됨") == true)
        XCTAssertTrue(value.synchronizationExplanation?.contains("계정 공통 한도 확인 불가") == true)
    }

    func testHourlyAndShortsLimitsAreDistinctAndNeverPromiseAnUnknownReset() throws {
        let hourly = try summary(["todaySeconds": 600, "hourlyUsedSeconds": 600, "hourlyRemainingSeconds": 0])
        XCTAssertTrue(hourly.restrictionReason(isShorts: false)?.contains("최근 1시간") == true)
        XCTAssertEqual(hourly.resumeStatus(), "다시 시청할 시간을 FF에서 확인하고 있습니다.")
        let shorts = try summary(["todaySeconds": 60, "blocked": false]).withPolicy(policy(["youtubeQuotaBlocked": false, "blockShorts": true]))
        XCTAssertEqual(shorts.restrictionReason(isShorts: true), "FF의 Shorts 차단 규칙이 적용 중입니다.")
        XCTAssertNil(shorts.restrictionReason(isShorts: false))
        XCTAssertNil(shorts.resumeStatus(isShorts: false))
        XCTAssertTrue(shorts.resumeStatus(isShorts: true)?.contains("규칙·스케줄") == true)
        let schedule = try summary().withPolicy(policy(["youtubeBlockedByActiveSchedule": true]))
        XCTAssertTrue(schedule.resumeStatus()?.contains("종료 시간은 아직 전달되지 않았습니다") == true)
    }

    func testMalformedResetMetadataIsRejectedAndMissingMetadataStaysUnknown() throws {
        XCTAssertNil(FocusFenceYouTubePlaybackPolicy.decode(Data(#"{"youtubeQuotaBlocked":true,"youtubeQuotaResetAfterSeconds":-1}"#.utf8)))
        XCTAssertNil(FocusFenceYouTubePlaybackPolicy.decode(Data(#"{"youtubeQuotaBlocked":true,"youtubeQuotaResetAfterSeconds":999999999}"#.utf8)))
        XCTAssertNotNil(FocusFenceYouTubePlaybackPolicy.decode(Data(#"{"youtubeQuotaBlocked":true,"youtubeQuotaResetAfterSeconds":null}"#.utf8)))
    }

    @MainActor
    func testFFRefreshFailureRetainsLastConfirmedYouTubeUsage() throws {
        let model = BrowserModel()
        let lastKnown = try summary(["todaySeconds": 480, "blocked": false])
            .withPolicy(policy(["youtubeQuotaBlocked": false]))

        model.applyYouTubeUsageRefresh(lastKnown)
        model.applyYouTubeUsageRefresh(nil)

        XCTAssertEqual(model.youtubeUsageSummary, lastKnown)
        XCTAssertTrue(model.youtubeUsageUnavailable,
                      "the dashboard must keep the last known values and report the FF disconnect")
    }

    @MainActor
    func testRejectedYouTubeNavigationStillHasAUsageContextAndNoLoadingSpinner() {
        let model = BrowserModel()
        let url = URL(string: "https://www.youtube.com/shorts/abcdefghijk")!
        model.submit(url.absoluteString) { _, completion in completion(.youtubeBlocked) }
        XCTAssertFalse(model.isLoading)
        XCTAssertTrue(model.shouldShowYouTubeUsage)
        XCTAssertTrue(model.youtubeUsageStatusLabel.isEmpty, "Usage amounts should be shown by the graphical dashboard, not repeated as status text.")
        XCTAssertTrue(model.isYouTubeShortsContext)
        XCTAssertEqual(model.youtubeUsagePollKey, url.absoluteString)
        XCTAssertEqual(model.rejectedNavigationURL, url)
        model.showNewTab()
        XCTAssertFalse(model.shouldShowYouTubeUsage)
    }

    @MainActor
    func testNetworkFailureExplanationDoesNotMislabelItAsAQuotaFailure() {
        let model = BrowserModel()
        model.pageDidFailToNavigate(URLError(.timedOut))
        XCTAssertTrue(model.addressBlockNotice?.contains("응답 시간") == true)
        model.pageDidFailToNavigate(URLError(.cannotFindHost))
        XCTAssertTrue(model.addressBlockNotice?.contains("DNS") == true)
    }

    func testUsageClientCombinesLivePolicyMetadataWithUsageThroughItsActualFetchBoundary() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [YouTubePolicyURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let fetched = await FocusFenceYouTubeUsageClient.fetch(session: session)
        let value = try XCTUnwrap(fetched)
        XCTAssertEqual(value.todaySeconds, 1206)
        XCTAssertEqual(value.playbackPolicy?.youtubeQuotaResetAfterSeconds, 3661)
        XCTAssertEqual(value.playbackPolicy?.blockShorts, true)
    }

    func testUsageClientAcceptsSummaryDelayedBeyondPreviousFiveSecondTimeout() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DelayedYouTubePolicyURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let fetched = await FocusFenceYouTubeUsageClient.fetch(session: session)

        XCTAssertEqual(fetched?.todaySeconds, 1206)
        XCTAssertEqual(fetched?.playbackPolicy?.youtubeQuotaResetAfterSeconds, 3661)
    }
}

private final class YouTubePolicyURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = request.url?.path == "/rules"
            ? #"{"youtubeQuotaBlocked":true,"blockShorts":true,"youtubeQuotaResetAfterSeconds":3661}"#
            : #"{"todaySeconds":1206,"dailyCapMinutes":20,"hourlyCapMinutes":10,"hourlyUsedSeconds":0,"hourlyRemainingSeconds":600,"blocked":true}"#
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class DelayedYouTubePolicyURLProtocol: URLProtocol {
    private let stateLock = NSLock()
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let delay = request.url?.path == "/usage/youtube" ? 5.5 : 0
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            let shouldSend = !self.stopped
            self.stateLock.unlock()
            guard shouldSend else { return }

            self.sendResponse()
        }
    }

    private func sendResponse() {
        let body = request.url?.path == "/rules"
            ? #"{"youtubeQuotaBlocked":true,"blockShorts":true,"youtubeQuotaResetAfterSeconds":3661}"#
            : #"{"todaySeconds":1206,"dailyCapMinutes":20,"hourlyCapMinutes":10,"hourlyUsedSeconds":0,"hourlyRemainingSeconds":600,"blocked":true}"#
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        stateLock.lock()
        stopped = true
        stateLock.unlock()
    }
}
