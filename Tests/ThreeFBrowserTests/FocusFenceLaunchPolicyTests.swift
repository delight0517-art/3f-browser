import Foundation
import XCTest
@testable import ThreeFBrowser

final class FocusFenceLaunchPolicyTests: XCTestCase {
    func testRunningRollbackCopyPreventsLaunchingADuplicate() {
        let canonical = URL(fileURLWithPath: "/Applications/Focus Fence.app")

        XCTAssertFalse(FocusFenceLaunchPolicy.shouldLaunch(canonicalURL: canonical, runningInstanceCount: 1))
    }

    func testRunningCanonicalAppDoesNotLaunchAnotherInstance() {
        let canonical = URL(fileURLWithPath: "/Applications/Focus Fence.app")

        XCTAssertFalse(FocusFenceLaunchPolicy.shouldLaunch(canonicalURL: canonical, runningInstanceCount: 1))
    }

    func testRunningInstanceBlocksLaunchEvenWhenItsBundleURLCannotBeRead() {
        let canonical = URL(fileURLWithPath: "/Applications/Focus Fence.app")

        XCTAssertFalse(FocusFenceLaunchPolicy.shouldLaunch(canonicalURL: canonical, runningInstanceCount: 1))
    }

    func testSpaceOAgentSessionNeverLaunchesFocusFenceOnTheUserDesktop() {
        let canonical = URL(fileURLWithPath: "/Applications/Focus Fence.app")

        XCTAssertFalse(FocusFenceLaunchPolicy.shouldLaunch(
            canonicalURL: canonical,
            runningInstanceCount: 0,
            isSpaceOAgentSession: true
        ))
    }

    func testNormalBrowserLaunchCanStartFocusFenceWhenNoInstanceIsRunning() {
        let canonical = URL(fileURLWithPath: "/Applications/Focus Fence.app")

        XCTAssertTrue(FocusFenceLaunchPolicy.shouldLaunch(canonicalURL: canonical, runningInstanceCount: 0))
    }
}
