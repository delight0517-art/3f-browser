import XCTest
@testable import ThreeFBrowser

final class BrowserKeyboardCommandsTests: XCTestCase {
    func testF5AndCommandRReload() {
        XCTAssertEqual(ThreeFBrowserKeyboardAction.resolve(keyCode: 96, command: false, shift: false, isFullScreen: false), .reload)
        XCTAssertEqual(ThreeFBrowserKeyboardAction.resolve(keyCode: 15, command: true, shift: false, isFullScreen: false), .reload)
    }

    func testCommandShiftRHardReloads() {
        XCTAssertEqual(ThreeFBrowserKeyboardAction.resolve(keyCode: 15, command: true, shift: true, isFullScreen: false), .hardReload)
    }

    func testCommandWClosesSelectedTab() {
        XCTAssertEqual(ThreeFBrowserKeyboardAction.resolve(keyCode: 13, command: true, shift: false, isFullScreen: false), .closeTab)
        XCTAssertNil(ThreeFBrowserKeyboardAction.resolve(keyCode: 13, command: true, shift: true, isFullScreen: false))
    }

    func testF11TogglesFullscreenAndEscapeExitsOnlyWhenFullscreen() {
        XCTAssertEqual(ThreeFBrowserKeyboardAction.resolve(keyCode: 103, command: false, shift: false, isFullScreen: false), .toggleFullScreen)
        XCTAssertEqual(ThreeFBrowserKeyboardAction.resolve(keyCode: 53, command: false, shift: false, isFullScreen: true), .exitFullScreen)
        XCTAssertNil(ThreeFBrowserKeyboardAction.resolve(keyCode: 53, command: false, shift: false, isFullScreen: false))
    }

    func testCommandZoomControls() {
        XCTAssertEqual(ThreeFBrowserKeyboardAction.resolve(keyCode: 24, command: true, shift: false, isFullScreen: false), .zoomIn)
        XCTAssertEqual(ThreeFBrowserKeyboardAction.resolve(keyCode: 69, command: true, shift: false, isFullScreen: false), .zoomIn)
        XCTAssertEqual(ThreeFBrowserKeyboardAction.resolve(keyCode: 27, command: true, shift: false, isFullScreen: false), .zoomOut)
        XCTAssertEqual(ThreeFBrowserKeyboardAction.resolve(keyCode: 78, command: true, shift: false, isFullScreen: false), .zoomOut)
        XCTAssertEqual(ThreeFBrowserKeyboardAction.resolve(keyCode: 29, command: true, shift: false, isFullScreen: false), .resetZoom)
        XCTAssertEqual(ThreeFBrowserKeyboardAction.resolve(keyCode: 82, command: true, shift: false, isFullScreen: false), .resetZoom)
    }

    func testUnrelatedKeysAreLeftForThePage() {
        XCTAssertNil(ThreeFBrowserKeyboardAction.resolve(keyCode: 0, command: false, shift: false, isFullScreen: false))
        XCTAssertNil(ThreeFBrowserKeyboardAction.resolve(keyCode: 96, command: false, shift: true, isFullScreen: false))
    }

    func testWindowEventsRouteOnlyToTheMatchingWindow() {
        let activeWindow = NSObject()
        let inactiveWindow = NSObject()

        XCTAssertTrue(ThreeFBrowserWindowRouting.targets(activeWindow, window: activeWindow))
        XCTAssertFalse(ThreeFBrowserWindowRouting.targets(activeWindow, window: inactiveWindow))
        XCTAssertFalse(ThreeFBrowserWindowRouting.targets(activeWindow, window: nil))
    }
}
