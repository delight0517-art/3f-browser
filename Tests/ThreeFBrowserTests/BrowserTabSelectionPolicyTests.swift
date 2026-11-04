import XCTest
@testable import ThreeFBrowser

final class BrowserTabSelectionPolicyTests: XCTestCase {
    func testOpeningBackgroundTabKeepsCurrentSelection() {
        let current = UUID()
        let newTab = UUID()

        XCTAssertEqual(
            BrowserTabSelectionPolicy.selectedTabID(
                currentSelection: current,
                newlyOpenedTabID: newTab,
                opensInBackground: true
            ),
            current
        )
    }

    func testOpeningForegroundTabSelectsNewTab() {
        let current = UUID()
        let newTab = UUID()

        XCTAssertEqual(
            BrowserTabSelectionPolicy.selectedTabID(
                currentSelection: current,
                newlyOpenedTabID: newTab,
                opensInBackground: false
            ),
            newTab
        )
    }

    func testBackgroundOpenWithoutCurrentSelectionSelectsNewTab() {
        let newTab = UUID()

        XCTAssertEqual(
            BrowserTabSelectionPolicy.selectedTabID(
                currentSelection: nil,
                newlyOpenedTabID: newTab,
                opensInBackground: true
            ),
            newTab
        )
    }
}
