import SwiftUI
import WebKit
import XCTest
@testable import ThreeFBrowser

final class BrowserFileUploadTests: XCTestCase {
    @MainActor
    func testWebKitRecognizesFileUploadDelegate() {
        let parent = BrowserWebView(
            url: .constant(nil), requestID: .constant(0), webView: .constant(nil),
            onNavigation: { _, _ in }, onNavigationState: { _, _ in }
        )
        let delegate = parent.makeCoordinator()
        XCTAssertTrue(delegate.responds(to: #selector(WKUIDelegate.webView(
            _:runOpenPanelWith:initiatedByFrame:completionHandler:
        ))), "WebKit must find the optional upload callback instead of silently dropping file selection")
    }
}
