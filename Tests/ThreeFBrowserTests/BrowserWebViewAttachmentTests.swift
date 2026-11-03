import AppKit
import WebKit
import XCTest
@testable import ThreeFBrowser

final class BrowserWebViewAttachmentTests: XCTestCase {
    @MainActor
    func testWebViewNotifiesControlWhenAttachedAfterItsInitialCreation() async throws {
        let webView = ThreeFWindowAwareWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
        let attached = expectation(description: "web view entered a browser window")
        var didAttach = false
        webView.onWindowAttachment = { view in
            guard !didAttach, view.window != nil else { return }
            didAttach = true
            attached.fulfill()
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = webView

        await fulfillment(of: [attached], timeout: 2)
        XCTAssertTrue(webView.window === window)
        window.orderOut(nil)
    }
}
