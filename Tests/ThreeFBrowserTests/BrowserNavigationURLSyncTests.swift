import XCTest
@testable import ThreeFBrowser

final class BrowserNavigationURLSyncTests: XCTestCase {
    func testReturnsChangedWebViewURLForClientSideNavigation() throws {
        let modelURL = try XCTUnwrap(URL(string: "https://www.youtube.com/watch?v=oldvideo123"))
        let webViewURL = try XCTUnwrap(URL(string: "https://www.youtube.com/watch?v=newvideo123"))

        XCTAssertEqual(BrowserNavigationURLSync.changedURL(modelURL: modelURL, webViewURL: webViewURL), webViewURL)
    }

    func testIgnoresUnchangedOrUnsafeWebViewURLs() throws {
        let modelURL = try XCTUnwrap(URL(string: "https://www.youtube.com/watch?v=oldvideo123"))
        let unsafeURL = try XCTUnwrap(URL(string: "javascript:alert(1)"))

        XCTAssertNil(BrowserNavigationURLSync.changedURL(modelURL: modelURL, webViewURL: modelURL))
        XCTAssertNil(BrowserNavigationURLSync.changedURL(modelURL: modelURL, webViewURL: unsafeURL))
        XCTAssertNil(BrowserNavigationURLSync.changedURL(modelURL: modelURL, webViewURL: nil))
    }
}
