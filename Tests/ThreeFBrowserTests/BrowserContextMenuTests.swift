import AppKit
import WebKit
import XCTest
@testable import ThreeFBrowser

final class BrowserContextMenuTests: XCTestCase {
    func testOnlyKnownThreeFLinkMenuActionsAreAccepted() {
        XCTAssertEqual(ThreeFContextMenuPolicy.action(for: ThreeFContextMenuAction.openInNewTab.rawValue), .openInNewTab)
        XCTAssertEqual(ThreeFContextMenuPolicy.action(for: ThreeFContextMenuAction.openInNewWindow.rawValue), .openInNewWindow)
        XCTAssertNil(ThreeFContextMenuPolicy.action(for: ThreeFContextMenuPolicy.webKitOpenLinkInNewWindowIdentifier))
        XCTAssertNil(ThreeFContextMenuPolicy.action(for: "threef.openLink.runScript"))
        XCTAssertNil(ThreeFContextMenuPolicy.action(for: nil))
    }

    func testOnlyCredentialFreeHTTPAndHTTPSLinksCanBeOpened() {
        XCTAssertEqual(ThreeFContextMenuPolicy.safeHTTPURL(URL(string: "https://example.com/path")), URL(string: "https://example.com/path"))
        XCTAssertEqual(ThreeFContextMenuPolicy.safeHTTPURL(URL(string: "http://example.com")), URL(string: "http://example.com"))
        XCTAssertNil(ThreeFContextMenuPolicy.safeHTTPURL(URL(string: "file:///etc/passwd")))
        XCTAssertNil(ThreeFContextMenuPolicy.safeHTTPURL(URL(string: "javascript:alert(1)")))
        XCTAssertNil(ThreeFContextMenuPolicy.safeHTTPURL(URL(string: "https://user:secret@example.com")))
        XCTAssertNil(ThreeFContextMenuPolicy.safeHTTPURL(URL(string: "https:///missing-host")))
    }

    func testFocusFenceDenialNeverProducesAnOpenIntent() {
        let url = URL(string: "https://blocked.example/path")
        XCTAssertNil(ThreeFContextMenuPolicy.intent(action: .openInNewTab, url: url, isAllowed: false))
        XCTAssertNil(ThreeFContextMenuPolicy.intent(action: .openInNewWindow, url: url, isAllowed: false))
    }

    func testApprovedLinksRouteToTheRequestedThreeFContainer() {
        let url = URL(string: "https://example.com/path")!
        XCTAssertEqual(ThreeFContextMenuPolicy.intent(action: .openInNewTab, url: url, isAllowed: true), .newTab(url))
        XCTAssertEqual(ThreeFContextMenuPolicy.intent(action: .openInNewWindow, url: url, isAllowed: true), .newWindow(url))
        XCTAssertNil(ThreeFContextMenuPolicy.intent(action: .openInNewTab, url: URL(string: "file:///tmp/x"), isAllowed: true))
    }

    func testBackgroundLinkMessageRequiresMainFrameAndSafeHTTPURLs() {
        let pageURL = URL(string: "https://source.example/page")!
        let destination = URL(string: "https://target.example/path")!

        XCTAssertEqual(
            ThreeFBackgroundLinkPolicy.destination(from: destination.absoluteString, isMainFrame: true, pageURL: pageURL),
            destination
        )
        XCTAssertNil(ThreeFBackgroundLinkPolicy.destination(from: destination.absoluteString, isMainFrame: false, pageURL: pageURL))
        XCTAssertNil(ThreeFBackgroundLinkPolicy.destination(from: "javascript:alert(1)", isMainFrame: true, pageURL: pageURL))
        XCTAssertNil(ThreeFBackgroundLinkPolicy.destination(from: "https://user:secret@target.example", isMainFrame: true, pageURL: pageURL))
        XCTAssertNil(ThreeFBackgroundLinkPolicy.destination(from: destination.absoluteString, isMainFrame: true, pageURL: URL(string: "file:///tmp/test")))
        XCTAssertNil(ThreeFBackgroundLinkPolicy.destination(from: 42, isMainFrame: true, pageURL: pageURL))
    }

    @MainActor
    func testNewWindowRouteIsSingleUseBoundedAndExpires() throws {
        let now = Date(timeIntervalSince1970: 100)
        let url = try XCTUnwrap(URL(string: "https://example.com/new-window"))
        XCTAssertTrue(ThreeFContextMenuWindowRoute.enqueue(url, now: now))
        XCTAssertEqual(ThreeFContextMenuWindowRoute.takeNext(now: now), url)
        XCTAssertNil(ThreeFContextMenuWindowRoute.takeNext(now: now))

        XCTAssertTrue(ThreeFContextMenuWindowRoute.enqueue(url, now: now))
        XCTAssertNil(ThreeFContextMenuWindowRoute.takeNext(now: now.addingTimeInterval(11)))
        XCTAssertFalse(ThreeFContextMenuWindowRoute.enqueue(try XCTUnwrap(URL(string: "file:///tmp/x")), now: now))
    }

    @MainActor
    func testNewWindowRoutePreservesFIFOAndRejectsOverflow() throws {
        while ThreeFContextMenuWindowRoute.takeNext() != nil {}
        let now = Date(timeIntervalSince1970: 200)
        let urls = try (0..<10).map { index in
            try XCTUnwrap(URL(string: "https://example.com/window-\(index)"))
        }

        for url in urls {
            XCTAssertTrue(ThreeFContextMenuWindowRoute.enqueue(url, now: now))
        }
        XCTAssertFalse(ThreeFContextMenuWindowRoute.enqueue(
            try XCTUnwrap(URL(string: "https://example.com/overflow")), now: now
        ))
        XCTAssertEqual((0..<10).compactMap { _ in ThreeFContextMenuWindowRoute.takeNext(now: now) }, urls)
        XCTAssertNil(ThreeFContextMenuWindowRoute.takeNext(now: now))
    }

    @MainActor
    func testNativeWebKitLinkMenuOffersOnly3FTabAndWindowRoutes() throws {
        let webView = ThreeFWindowAwareWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let menu = NSMenu()
        let original = NSMenuItem(title: "Open Link in New Window", action: #selector(MenuActionRecorder.open(_:)), keyEquivalent: "")
        original.identifier = NSUserInterfaceItemIdentifier(ThreeFContextMenuPolicy.webKitOpenLinkInNewWindowIdentifier)
        original.target = MenuActionRecorder.shared
        menu.addItem(original)
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: NSPoint(x: 1, y: 1),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))

        webView.willOpenMenu(menu, with: event)

        XCTAssertEqual(menu.items.map { $0.identifier?.rawValue }, [
            ThreeFContextMenuAction.openInNewTab.rawValue,
            ThreeFContextMenuAction.openInNewWindow.rawValue
        ])
        XCTAssertTrue(menu.items.allSatisfy { $0.representedObject as? NSMenuItem === original })
        XCTAssertTrue(menu.items.allSatisfy { $0.action != nil })
    }

    @MainActor
    func testSelectingNativeTabRouteForwardsWebKitContextAction() throws {
        let webView = ThreeFWindowAwareWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let menu = NSMenu()
        let original = NSMenuItem(title: "Open Link in New Window", action: #selector(MenuActionRecorder.open(_:)), keyEquivalent: "")
        original.identifier = NSUserInterfaceItemIdentifier(ThreeFContextMenuPolicy.webKitOpenLinkInNewWindowIdentifier)
        original.target = MenuActionRecorder.shared
        menu.addItem(original)
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: NSPoint(x: 1, y: 1),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
        webView.willOpenMenu(menu, with: event)

        NSApp.sendAction(menu.items[0].action!, to: menu.items[0].target, from: menu.items[0])

        XCTAssertEqual(webView.contextMenuAction, .openInNewTab)
        XCTAssertTrue(MenuActionRecorder.shared.didOpen)
        MenuActionRecorder.shared.didOpen = false
    }

    @MainActor
    private final class MenuActionRecorder: NSObject {
        static let shared = MenuActionRecorder()
        var didOpen = false

        @objc func open(_ sender: Any?) {
            didOpen = true
        }
    }

}
