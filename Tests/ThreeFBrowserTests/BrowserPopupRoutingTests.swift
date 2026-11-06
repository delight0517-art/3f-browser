import XCTest
@testable import ThreeFBrowser

final class BrowserPopupRoutingTests: XCTestCase {
    func testLoginPopupHTTPSTargetCanBeRoutedToBrowserTab() throws {
        let loginURL = try XCTUnwrap(URL(string: "https://accounts.google.com/signin"))
        var openedTabURL: URL?

        let routed = BrowserWebView.Coordinator.routePopup(
            targetFrameIsAbsent: true,
            url: loginURL,
            openInNewTab: { openedTabURL = $0 }
        )

        XCTAssertTrue(routed)
        XCTAssertEqual(openedTabURL, loginURL)
    }

    func testPopupRoutingRejectsNonHTTPURLs() throws {
        let javascriptURL = try XCTUnwrap(URL(string: "javascript:alert(1)"))
        let credentialURL = try XCTUnwrap(URL(string: "https://user:password@example.com/"))

        XCTAssertFalse(BrowserWebView.Coordinator.routePopup(
            targetFrameIsAbsent: true,
            url: javascriptURL,
            openInNewTab: { _ in XCTFail("Non-HTTP popup must not open") }
        ))
        XCTAssertFalse(BrowserWebView.Coordinator.routePopup(
            targetFrameIsAbsent: true,
            url: credentialURL,
            openInNewTab: { _ in XCTFail("Credential-bearing popup must not open") }
        ))
    }

    func testNamedTargetNavigationIsNotMisroutedAsPopup() throws {
        let destination = try XCTUnwrap(URL(string: "https://example.com/"))

        XCTAssertFalse(BrowserWebView.Coordinator.routePopup(
            targetFrameIsAbsent: false,
            url: destination,
            openInNewTab: { _ in XCTFail("A named target is not a popup") }
        ))
    }
}
