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
