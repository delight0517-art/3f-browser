import XCTest
@testable import ThreeFBrowser

@MainActor
final class DefaultBrowserServiceTests: XCTestCase {
    func testCurrentBundlePathMatches() {
        let bundle = URL(fileURLWithPath: "/Users/test/Applications/3F Browser.app")

        XCTAssertTrue(DefaultBrowserService.isCurrentApplication(bundle, bundleURL: bundle))
    }

    func testOtherCopyDoesNotMatchCurrentBundle() {
        let installed = URL(fileURLWithPath: "/Users/test/Applications/3F Browser.app")
        let staleCandidate = URL(fileURLWithPath: "/Users/test/project/.build/3F Browser.app")

        XCTAssertFalse(DefaultBrowserService.isCurrentApplication(staleCandidate, bundleURL: installed))
    }

    func testMissingHandlerDoesNotMatch() {
        XCTAssertFalse(DefaultBrowserService.isCurrentApplication(nil, bundleURL: URL(fileURLWithPath: "/Users/test/3F Browser.app")))
    }

    func testStatusExplainsHowToSelectCurrentCopyWhenAnotherCopyIsHandler() {
        let text = DefaultBrowserService.status(currentHandlers: [false, false], sameBundleCopy: true)
        XCTAssertTrue(text.contains("시스템 설정 > 데스크탑 및 Dock > 기본 웹 브라우저"))
        XCTAssertFalse(text.contains("기본 브라우저입니다"))
    }

    func testStatusReportsSuccessOnlyWhenBothSchemesSelectCurrentCopy() {
        XCTAssertEqual(
            DefaultBrowserService.status(currentHandlers: [true, true], sameBundleCopy: false),
            "3F Browser가 HTTP와 HTTPS 기본 브라우저입니다."
        )
        XCTAssertFalse(
            DefaultBrowserService.status(currentHandlers: [true, false], sameBundleCopy: false)
                .contains("기본 브라우저입니다")
        )
    }

    func testFailureStatusPreservesErrorAndRefreshedReadback() {
        let text = DefaultBrowserService.failureStatus(
            errorDescription: "permission denied",
            refreshedStatus: "3F Browser가 아직 HTTP와 HTTPS 기본 브라우저가 아닙니다."
        )

        XCTAssertTrue(text.contains("permission denied"))
        XCTAssertTrue(text.contains("3F Browser가 아직 HTTP와 HTTPS 기본 브라우저가 아닙니다."))
    }
}
