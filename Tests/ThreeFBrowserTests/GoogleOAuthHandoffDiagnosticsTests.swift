import Foundation
import XCTest
@testable import ThreeFBrowser

final class GoogleOAuthHandoffDiagnosticsTests: XCTestCase {
    func testDiagnosticContextDoesNotExposePathOrQuery() throws {
        let cloudflare = try XCTUnwrap(URL(string: "https://dash.cloudflare.com/account/private?next=/secret"))
        let ordinarySite = try XCTUnwrap(URL(string: "https://example.com/private?token=sample"))

        XCTAssertEqual(GoogleOAuthHandoffDiagnostics.contextLabel(for: cloudflare), "Cloudflare")
        XCTAssertEqual(GoogleOAuthHandoffDiagnostics.contextLabel(for: ordinarySite), "웹페이지")
    }

    func testCloudflareChallengeHostMustMatchExactly() throws {
        let challenge = try XCTUnwrap(URL(string: "https://challenges.cloudflare.com/cdn-cgi/challenge-platform/widget"))
        let lookalike = try XCTUnwrap(URL(string: "https://challenges.cloudflare.com.example.org/widget"))

        XCTAssertTrue(GoogleOAuthHandoffDiagnostics.isCloudflareChallengeURL(challenge))
        XCTAssertFalse(GoogleOAuthHandoffDiagnostics.isCloudflareChallengeURL(lookalike))
    }

    func testCloudflareDiagnosticCategoriesRejectUntrustedDetails() {
        let categories = ["script", "frame", "style", "image", "resource", "javascript", "promise"]

        XCTAssertEqual(GoogleOAuthHandoffDiagnostics.safeCloudflareDiagnosticCategory("SCRIPT", allowed: categories), "script")
        XCTAssertNil(GoogleOAuthHandoffDiagnostics.safeCloudflareDiagnosticCategory("https://dash.cloudflare.com/login?token=secret", allowed: categories))
        XCTAssertNil(GoogleOAuthHandoffDiagnostics.safeCloudflareDiagnosticCategory("password=private", allowed: categories))
    }
}
