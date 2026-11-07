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
        XCTAssertFalse(GoogleOAuthNavigationPolicy.requiresSystemBrowser(for: URL(string: "https://accounts.google.com/signin")!))
        XCTAssertFalse(GoogleOAuthNavigationPolicy.requiresSystemBrowser(for: URL(string: "https://accounts.google.com/o/oauth2evil")!))
    }

    func testRejectsOAuthTokenAPIEndpoint() {
        XCTAssertFalse(GoogleOAuthNavigationPolicy.requiresSystemBrowser(for: URL(string: "https://oauth2.googleapis.com/token")!))
    }
}
