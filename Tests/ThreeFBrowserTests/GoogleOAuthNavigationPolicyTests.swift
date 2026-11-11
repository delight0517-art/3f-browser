import Foundation
import XCTest
@testable import ThreeFBrowser

final class GoogleOAuthNavigationPolicyTests: XCTestCase {
    func testRequiresSystemBrowserForOAuth2AuthorizationPaths() {
        XCTAssertTrue(GoogleOAuthNavigationPolicy.requiresSystemBrowser(for: URL(string: "https://accounts.google.com/o/oauth2")!))
        XCTAssertTrue(GoogleOAuthNavigationPolicy.requiresSystemBrowser(for: URL(string: "https://accounts.google.com/o/oauth2/auth")!))
        XCTAssertTrue(GoogleOAuthNavigationPolicy.requiresSystemBrowser(for: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!))
    }

    func testRequiresSystemBrowserForSignInOAuthPaths() {
        XCTAssertTrue(GoogleOAuthNavigationPolicy.requiresSystemBrowser(for: URL(string: "https://accounts.google.com/signin/oauth")!))
        XCTAssertTrue(GoogleOAuthNavigationPolicy.requiresSystemBrowser(for: URL(string: "https://accounts.google.com/signin/oauth/consent")!))
        XCTAssertTrue(GoogleOAuthNavigationPolicy.requiresSystemBrowser(for: URL(string: "https://accounts.google.com/signin/v2/identifier")!))
        XCTAssertTrue(GoogleOAuthNavigationPolicy.requiresSystemBrowser(for: URL(string: "https://accounts.google.com/gsi/select")!))
    }

    func testHostMatchingIsCaseInsensitive() {
        XCTAssertTrue(GoogleOAuthNavigationPolicy.requiresSystemBrowser(for: URL(string: "https://ACCOUNTS.GOOGLE.COM/o/oauth2/auth")!))
    }

    func testRejectsNonHTTPSScheme() {
        XCTAssertFalse(GoogleOAuthNavigationPolicy.requiresSystemBrowser(for: URL(string: "http://accounts.google.com/o/oauth2/auth")!))
    }

    func testRejectsSubdomainAndHostSpoof() {
        XCTAssertFalse(GoogleOAuthNavigationPolicy.requiresSystemBrowser(for: URL(string: "https://sub.accounts.google.com/o/oauth2/auth")!))
        XCTAssertFalse(GoogleOAuthNavigationPolicy.requiresSystemBrowser(for: URL(string: "https://accounts.google.com.example.com/o/oauth2/auth")!))
        XCTAssertFalse(GoogleOAuthNavigationPolicy.requiresSystemBrowser(for: URL(string: "https://accounts.google.com@evil.example/o/oauth2/auth")!))
    }

    func testRejectsUnrelatedGoogleAccountPaths() {
        XCTAssertTrue(GoogleOAuthNavigationPolicy.requiresSystemBrowser(for: URL(string: "https://accounts.google.com/signin")!))
        XCTAssertTrue(GoogleOAuthNavigationPolicy.requiresSystemBrowser(for: URL(string: "https://accounts.google.com/o/oauth2evil")!))
    }

    func testRejectsOAuthTokenAPIEndpoint() {
        XCTAssertFalse(GoogleOAuthNavigationPolicy.requiresSystemBrowser(for: URL(string: "https://oauth2.googleapis.com/token")!))
    }

    func testExactOriginRemovesPathQueryAndFragment() {
        let page = URL(string: "https://Example.com:8443/login/start?next=%2Fhome#step")!

        XCTAssertEqual(
            GoogleOAuthNavigationPolicy.exactOrigin(for: page)?.absoluteString,
            "https://example.com:8443"
        )
    }

    func testRejectsNonHTTPSOrCredentialBearingOrigin() {
        XCTAssertNil(GoogleOAuthNavigationPolicy.exactOrigin(for: URL(string: "http://example.com/login")!))
        XCTAssertNil(GoogleOAuthNavigationPolicy.exactOrigin(for: URL(string: "https://user:pass@example.com/login")!))
    }

    func testOnlyHTTPSAccountsHostIsGoogleAuthURL() {
        XCTAssertTrue(GoogleOAuthNavigationPolicy.isGoogleAuthURL(URL(string: "https://accounts.google.com/o/oauth2/auth")!))
        XCTAssertFalse(GoogleOAuthNavigationPolicy.isGoogleAuthURL(URL(string: "http://accounts.google.com/o/oauth2/auth")!))
        XCTAssertFalse(GoogleOAuthNavigationPolicy.isGoogleAuthURL(URL(string: "https://accounts.google.com.evil.example/")!))
        XCTAssertFalse(GoogleOAuthNavigationPolicy.isGoogleAuthURL(URL(string: "https://oauth2.googleapis.com/token")!))
    }

    func testHandoffStartsAtGoogleAuthAndKeepsExactSourceOrigin() {
        let page = URL(string: "https://Example.com:8443/path?state=private#fragment")!
        let auth = URL(string: "https://accounts.google.com/signin/v2/identifier")!

        XCTAssertEqual(GoogleOAuthNavigationPolicy.safeHTTPSPageURL(page), page)
        XCTAssertEqual(GoogleOAuthNavigationPolicy.exactOrigin(for: page)?.absoluteString, "https://example.com:8443")
        XCTAssertEqual(GoogleOAuthNavigationPolicy.safeHTTPSPageURL(URL(string: "http://example.com/path")), nil)
        XCTAssertEqual(GoogleOAuthNavigationPolicy.authenticationStartURL(for: auth), auth)
        XCTAssertNil(GoogleOAuthNavigationPolicy.authenticationStartURL(for: page))
    }

    func testOnlyExactHTTPSOriginMayReceiveOAuthCallbackRedirect() {
        let source = URL(string: "https://Example.com:8443/login/start")!

        XCTAssertTrue(GoogleOAuthNavigationPolicy.isAllowedCallbackRedirect(
            URL(string: "https://example.com:8443/oauth/callback?code=secret")!, from: source))
        XCTAssertFalse(GoogleOAuthNavigationPolicy.isAllowedCallbackRedirect(
            URL(string: "https://example.com/oauth/callback")!, from: source))
        XCTAssertFalse(GoogleOAuthNavigationPolicy.isAllowedCallbackRedirect(
            URL(string: "https://example.com.evil.test/oauth/callback")!, from: source))
        XCTAssertFalse(GoogleOAuthNavigationPolicy.isAllowedCallbackRedirect(
            URL(string: "http://example.com:8443/oauth/callback")!, from: source))
    }

    func testHandoffDeduplicationKeyExcludesOAuthQueryAndFragment() {
        let first = URL(string: "https://accounts.google.com/o/oauth2/auth?state=secret&code=private#fragment")!
        let second = URL(string: "https://accounts.google.com/signin/v2/identifier?state=other&code=different#another")!

        XCTAssertEqual(
            GoogleOAuthHandoffDiagnostics.deduplicationKey(for: first, sourceHost: "Example.com"),
            GoogleOAuthHandoffDiagnostics.deduplicationKey(for: second, sourceHost: "example.com")
        )
        XCTAssertFalse(GoogleOAuthHandoffDiagnostics.deduplicationKey(for: first, sourceHost: "example.com").contains("secret"))
        XCTAssertFalse(GoogleOAuthHandoffDiagnostics.deduplicationKey(for: first, sourceHost: "example.com").contains("private"))
    }
}
