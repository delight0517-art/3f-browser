import Foundation
import XCTest
@testable import ThreeFBrowser

final class CloudflareInAppNavigationTests: XCTestCase {
    func testCloudflareSignUpIsAllowedWhenFocusFenceIsOffline() throws {
        let signup = try XCTUnwrap(URL(string: "https://dash.cloudflare.com/sign-up"))

        XCTAssertEqual(
            ThreeFBrowserControlController.navigationAuthorizationDecision(for: signup, rules: nil),
            .allowed
        )
    }

    func testExplicitFocusFenceRuleStillBlocksCloudflareLogin() throws {
        let signup = try XCTUnwrap(URL(string: "https://dash.cloudflare.com/sign-up"))
        let blockedRules = Data(#"{"blockedDomains":["dash.cloudflare.com"],"blockedUrlParts":[],"adultProtectedDomains":[],"adultProtectedUrlParts":[],"adultProtectedKeywords":[],"keywords":[],"blockExceptions":[]}"#.utf8)

        XCTAssertEqual(
            ThreeFBrowserControlController.navigationAuthorizationDecision(for: signup, rules: blockedRules),
            .blocked
        )
    }

    @MainActor
    func testCloudflareSignupWithoutAuthorizerStaysInThreeF() throws {
        let model = makeModel()
        let signup = try XCTUnwrap(URL(string: "https://dash.cloudflare.com/sign-up"))

        model.navigate(to: signup)

        XCTAssertEqual(model.currentURL, signup)
        XCTAssertEqual(model.addressText, signup.absoluteString)
        XCTAssertEqual(model.navigationRequestID, 1)
        XCTAssertNil(model.addressBlockNotice)
    }

    @MainActor
    func testAuthorizedCloudflareLoginStaysInThreeF() throws {
        let model = makeModel()
        let login = try XCTUnwrap(URL(string: "https://dash.cloudflare.com/?to=/:account/home"))

        model.navigate(to: login) { _, complete in complete(.allowed) }

        XCTAssertEqual(model.currentURL, login)
        XCTAssertEqual(model.addressText, login.absoluteString)
        XCTAssertEqual(model.navigationRequestID, 1)
        XCTAssertNil(model.addressBlockNotice)
    }

    @MainActor
    func testExplicitlyRejectedCloudflareNavigationRemainsBlocked() throws {
        let model = makeModel()
        let login = try XCTUnwrap(URL(string: "https://dash.cloudflare.com/sign-up"))

        model.navigate(to: login) { _, complete in complete(.blocked) }

        XCTAssertNil(model.currentURL)
        XCTAssertEqual(model.rejectedNavigationURL, login)
    }

    @MainActor
    private func makeModel() -> BrowserModel {
        let suite = "threef-cloudflare-navigation-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return BrowserModel(preferences: BrowserPreferenceStore(
            environment: [:],
            arguments: [],
            defaults: defaults
        ))
    }
}
