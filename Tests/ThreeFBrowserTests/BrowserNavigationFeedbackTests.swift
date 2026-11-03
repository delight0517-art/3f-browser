import Foundation
import XCTest
@testable import ThreeFBrowser

@MainActor
final class BrowserNavigationFeedbackTests: XCTestCase {
    func testQuickLinksSubmitImmediateNavigationsForYouTubeGeminiAndDrive() throws {
        let model = BrowserModel()

        for title in ["YouTube", "Gemini", "Drive"] {
            let link = try XCTUnwrap(model.theme.quickLinks.first { $0.title == title })
            let destination = try XCTUnwrap(link.destination)
            let previousRequestID = model.navigationRequestID

            model.openQuickLink(link)

            XCTAssertEqual(model.currentURL, destination)
            XCTAssertEqual(model.addressText, destination.absoluteString)
            XCTAssertEqual(model.navigationRequestID, previousRequestID + 1)
            XCTAssertTrue(model.isLoading)

            model.pageDidNavigate(to: destination, title: title)
            XCTAssertFalse(model.isLoading)
        }
    }

    func testQuickLinkWaitsForFocusFenceApprovalBeforeSubmittingWebKitRequest() throws {
        let model = BrowserModel()
        let link = try XCTUnwrap(model.theme.quickLinks.first { $0.title == "Gemini" })
        var authorizedURL: URL?

        model.openQuickLink(link) { url, completion in
            authorizedURL = url
            completion(.allowed)
        }

        XCTAssertEqual(authorizedURL, link.destination)
        XCTAssertEqual(model.currentURL, link.destination)
        XCTAssertEqual(model.addressText, link.destination?.absoluteString)
        XCTAssertEqual(model.navigationRequestID, 1)
        XCTAssertTrue(model.isLoading)
        XCTAssertNil(model.addressBlockNotice)
    }

    func testExternalDeepLinkWaitsForFocusFenceApprovalBeforeSubmittingWebKitRequest() throws {
        let model = BrowserModel()
        let destination = try XCTUnwrap(URL(string: "https://gemini.google.com/app"))
        let deepLink = try XCTUnwrap(URL(string: "threef://open?url=https%3A%2F%2Fgemini.google.com%2Fapp"))
        var authorizedURL: URL?
        var pending: ((BrowserNavigationAuthorizationDecision) -> Void)?

        model.openExternalURL(deepLink) { url, completion in
            authorizedURL = url
            pending = completion
        }

        XCTAssertEqual(authorizedURL, destination)
        XCTAssertNil(model.currentURL)
        XCTAssertEqual(model.addressText, destination.absoluteString)
        XCTAssertEqual(model.navigationRequestID, 0)
        XCTAssertTrue(model.isLoading)

        pending?(.allowed)

        XCTAssertEqual(model.currentURL, destination)
        XCTAssertEqual(model.navigationRequestID, 1)
    }

    func testDeniedExternalYouTubeDeepLinkDoesNotSubmitWebKitRequest() throws {
        let model = BrowserModel()
        let deepLink = try XCTUnwrap(URL(string: "threef://open?url=https%3A%2F%2Fyoutube.com%2F"))

        model.openExternalURL(deepLink) { _, completion in completion(.youtubeBlocked) }

        XCTAssertNil(model.currentURL)
        XCTAssertEqual(model.navigationRequestID, 0)
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.addressBlockNotice,
                       "YouTube가 Focus Fence에서 제한 중입니다. 한도·스케줄 설정을 확인해 주세요.")
    }

    func testPendingAuthorizationShowsTypedDestinationWithoutReplacingCurrentPage() throws {
        let model = BrowserModel()
        let previous = try XCTUnwrap(URL(string: "https://example.org/"))
        let link = try XCTUnwrap(model.theme.quickLinks.first { $0.title == "Gemini" })
        model.currentURL = previous
        var pending: ((BrowserNavigationAuthorizationDecision) -> Void)?

        model.openQuickLink(link) { _, completion in pending = completion }

        XCTAssertEqual(model.currentURL, previous)
        XCTAssertEqual(model.addressText, link.destination?.absoluteString)
        XCTAssertTrue(model.isLoading)
        XCTAssertEqual(model.navigationRequestID, 0)

        pending?(.allowed)

        XCTAssertEqual(model.currentURL, link.destination)
        XCTAssertEqual(model.addressText, link.destination?.absoluteString)
        XCTAssertEqual(model.navigationRequestID, 1)
    }

    func testQuickLinkQuotaDenialDoesNotSubmitWebKitRequestAndExplainsWhy() throws {
        let model = BrowserModel()
        let link = try XCTUnwrap(model.theme.quickLinks.first { $0.title == "YouTube" })

        model.openQuickLink(link) { _, completion in completion(.youtubeBlocked) }

        XCTAssertNil(model.currentURL)
        XCTAssertEqual(model.addressText, link.destination?.absoluteString)
        XCTAssertEqual(model.navigationRequestID, 0)
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.addressBlockNotice,
                       "YouTube가 Focus Fence에서 제한 중입니다. 한도·스케줄 설정을 확인해 주세요.")
    }

    func testStaleAuthorizationCannotNavigateAfterUserChoosesANewDestination() throws {
        let model = BrowserModel()
        let gemini = try XCTUnwrap(model.theme.quickLinks.first { $0.title == "Gemini" })
        let drive = try XCTUnwrap(model.theme.quickLinks.first { $0.title == "Drive" })
        var pending: ((BrowserNavigationAuthorizationDecision) -> Void)?

        model.openQuickLink(gemini) { _, completion in pending = completion }
        model.openQuickLink(drive) { _, completion in completion(.allowed) }
        pending?(.allowed)

        XCTAssertEqual(model.currentURL, drive.destination)
        XCTAssertEqual(model.navigationRequestID, 1)
    }

    func testStaleAuthorizationForSameURLCannotOverrideNewerDenial() throws {
        let model = BrowserModel()
        let youtube = try XCTUnwrap(model.theme.quickLinks.first { $0.title == "YouTube" })
        var first: ((BrowserNavigationAuthorizationDecision) -> Void)?

        model.openQuickLink(youtube) { _, completion in first = completion }
        model.openQuickLink(youtube) { _, completion in completion(.youtubeBlocked) }
        first?(.allowed)

        XCTAssertNil(model.currentURL)
        XCTAssertEqual(model.navigationRequestID, 0)
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.addressBlockNotice,
                       "YouTube가 Focus Fence에서 제한 중입니다. 한도·스케줄 설정을 확인해 주세요.")
    }

    func testPendingAddressAuthorizationCannotOverrideAnInternalPageNavigation() throws {
        let model = BrowserModel()
        let current = try XCTUnwrap(URL(string: "https://example.com/"))
        let internalLink = try XCTUnwrap(URL(string: "https://example.org/article"))
        let gemini = try XCTUnwrap(model.theme.quickLinks.first { $0.title == "Gemini" })
        model.currentURL = current
        var pending: ((BrowserNavigationAuthorizationDecision) -> Void)?

        model.openQuickLink(gemini) { _, completion in pending = completion }
        model.pageDidStartNavigation(to: internalLink)
        pending?(.allowed)

        XCTAssertEqual(model.currentURL, internalLink)
        XCTAssertEqual(model.addressText, internalLink.absoluteString)
        XCTAssertTrue(model.isLoading)
        XCTAssertEqual(model.navigationRequestID, 0)
    }

    func testNavigationFailureStopsLoadingAndShowsAnExplanation() {
        let model = BrowserModel()
        model.isLoading = true

        model.pageDidFailToNavigate(NSError(domain: "Navigation", code: 1))

        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.addressBlockNotice, "페이지 연결에 실패했습니다. 네트워크나 Focus Fence 제한을 확인해 주세요.")
    }

    func testStartingALinkNavigationImmediatelyShowsTheDestination() throws {
        let model = BrowserModel()
        model.addressBlockNotice = "이전 안내"
        let destination = try XCTUnwrap(URL(string: "https://drive.google.com/drive/my-drive"))

        model.pageDidStartNavigation(to: destination)

        XCTAssertEqual(model.currentURL, destination)
        XCTAssertEqual(model.addressText, destination.absoluteString)
        XCTAssertTrue(model.isLoading)
        XCTAssertNil(model.addressBlockNotice)
    }

    func testCanceledPreviousNavigationDoesNotClearCurrentLoadingState() {
        let model = BrowserModel()
        model.isLoading = true
        model.addressBlockNotice = "기존 안내"

        model.pageDidFailToNavigate(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))

        XCTAssertTrue(model.isLoading)
        XCTAssertEqual(model.addressBlockNotice, "기존 안내")
    }

    func testNavigationFeedbackSeparatesPolicyBlockFromFocusFenceUnavailable() {
        let model = BrowserModel()
        model.isLoading = true

        model.pageDidRejectNavigation(.blocked)

        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.addressBlockNotice,
                       "Focus Fence 규칙에 따라 이 페이지를 차단했습니다.")

        model.isLoading = true
        model.pageDidRejectNavigation(.unavailable)

        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.addressBlockNotice,
                       "Focus Fence에 연결할 수 없어 열지 못했습니다. 연결을 확인한 뒤 다시 시도해 주세요.")
    }

    func testNavigationFeedbackIdentifiesTheYouTubeQuotaBlock() {
        let model = BrowserModel()
        model.isLoading = true

        model.pageDidRejectNavigation(.youtubeBlocked)

        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.addressBlockNotice,
                       "YouTube가 Focus Fence에서 제한 중입니다. 한도·스케줄 설정을 확인해 주세요.")
    }

    func testFocusFenceNavigationDecisionUsesQuotaReasonOnlyForBlockedYouTube() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "blockedDomains": ["youtube.com"],
            "blockedUrlParts": [String](),
            "keywords": [String](),
            "blockExceptions": [String](),
            "youtubeQuotaBlocked": true,
        ])
        let youtube = try XCTUnwrap(URL(string: "https://www.youtube.com/"))
        let gemini = try XCTUnwrap(URL(string: "https://gemini.google.com/"))
        let drive = try XCTUnwrap(URL(string: "https://drive.google.com/"))

        XCTAssertEqual(ThreeFBrowserControlController.navigationAuthorizationDecision(for: youtube, rules: data), .youtubeBlocked)
        XCTAssertEqual(ThreeFBrowserControlController.navigationAuthorizationDecision(for: gemini, rules: data), .allowed)
        XCTAssertEqual(ThreeFBrowserControlController.navigationAuthorizationDecision(for: drive, rules: data), .allowed)
    }

    func testYouTubePageCanOpenInThreeFWhenOnlyPlaybackQuotaIsBlocked() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "blockedDomains": [String](),
            "blockedUrlParts": [String](),
            "keywords": [String](),
            "blockExceptions": [String](),
            "youtubeQuotaBlocked": true,
        ])
        let youtube = try XCTUnwrap(URL(string: "https://www.youtube.com/"))

        XCTAssertEqual(ThreeFBrowserControlController.navigationAuthorizationDecision(for: youtube, rules: data), .allowed)
    }

    func testWindowsWebtoonRouteRulesBlockOnlyTheConfiguredComicPaths() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "blockedDomains": ["toomics.kr"],
            "blockedUrlParts": ["series.naver.com/comic/", "lezhin.com/ko/comic/", "lezhin.com/ko/bookshome"],
            "keywords": [String](),
            "blockExceptions": [String](),
            "youtubeQuotaBlocked": false,
        ])
        let blocked = [
            "https://series.naver.com/comic/detail.series?productNo=1",
            "https://www.lezhin.com/ko/comic/123",
            "https://www.lezhin.com/ko/bookshome",
            "https://toomics.kr/webtoon/list",
        ]
        let allowed = [
            "https://series.naver.com/novel/detail.series?productNo=1",
            "https://www.lezhin.com/ko/novel/123",
        ]

        for value in blocked {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertEqual(ThreeFBrowserControlController.navigationAuthorizationDecision(for: url, rules: data), .blocked,
                           "Expected configured Windows parity route to be denied: \(url.host ?? "")\(url.path)")
        }
        for value in allowed {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertEqual(ThreeFBrowserControlController.navigationAuthorizationDecision(for: url, rules: data), .allowed,
                           "Novel routes must remain outside the webtoon catalog: \(url.host ?? "")\(url.path)")
        }
    }
}
