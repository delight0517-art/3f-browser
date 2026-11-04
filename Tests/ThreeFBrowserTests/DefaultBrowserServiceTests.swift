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
}
