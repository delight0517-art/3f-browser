import Foundation
import XCTest
@testable import ThreeFBrowser

final class ThreeFURLRouterTests: XCTestCase {
    @MainActor
    func testApplicationDelegateCanBeConstructedWithoutInjectedRouter() {
        let delegate = ThreeFBrowserAppDelegate()
        XCTAssertNotNil(delegate)
    }

    @MainActor
    func testApplicationDelegateQueuesNormalizedExternalHTTPSURL() throws {
        let router = ThreeFURLRouter()
        var presentationRequests = 0
        router.setBrowserWindowPresenter {
            presentationRequests += 1
            return true
        }
        defer {
            _ = router.takePendingURLs()
        }

        let url = try XCTUnwrap(URL(string: "https://example.com/path"))
        let delegate = ThreeFBrowserAppDelegate(externalURLRouter: router)
        delegate.application(NSApplication.shared, open: [url])

        let pending = router.takePendingURLs()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.scheme, "threef")
        XCTAssertEqual(pending.first?.host, "open")
        XCTAssertEqual(
            URLComponents(url: try XCTUnwrap(pending.first), resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "url" })?.value,
            url.absoluteString
        )
        XCTAssertEqual(presentationRequests, 1)
    }

    @MainActor
    func testDirectHTTPAndHTTPSURLsBecomeExistingBrowserDeepLinks() throws {
        let router = ThreeFURLRouter()
        let http = try XCTUnwrap(URL(string: "http://example.com/path?q=hello%20world"))
        let https = try XCTUnwrap(URL(string: "https://example.org/"))

        router.receive([http, https])

        let links = router.takePendingURLs()
        XCTAssertEqual(links.count, 2)
        let targets = links.map { link -> String? in
            guard link.scheme == "threef", link.host == "open" else { return nil }
            return URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value
        }
        XCTAssertEqual(targets, [http.absoluteString, https.absoluteString])
        XCTAssertTrue(router.takePendingURLs().isEmpty)
    }

    @MainActor
    func testUnsafeAndUnsupportedDirectURLsAreIgnored() throws {
        let router = ThreeFURLRouter()
        router.receive([
            try XCTUnwrap(URL(string: "javascript:alert(1)")),
            try XCTUnwrap(URL(string: "mailto:test@example.com")),
            try XCTUnwrap(URL(string: "https://user:secret@example.com/")),
            try XCTUnwrap(URL(string: "http://user:secret@example.com/")),
            try XCTUnwrap(URL(string: "https:///missing-host"))
        ])
        XCTAssertTrue(router.takePendingURLs().isEmpty)
    }

    @MainActor
    func testAcceptedExternalURLRequestsStandaloneWindowPresentation() throws {
        let router = ThreeFURLRouter()
        var presentationRequests = 0
        router.setBrowserWindowPresenter {
            presentationRequests += 1
            return true
        }

        router.receive([
            try XCTUnwrap(URL(string: "javascript:alert(1)")),
            try XCTUnwrap(URL(string: "https://example.com/"))
        ])

        XCTAssertEqual(presentationRequests, 1)
        XCTAssertEqual(router.takePendingURLs().count, 1)
    }

    @MainActor
    func testExistingThreeFHTTPSDeepLinkRemainsSupportedButHTTPDeepLinkIsRejected() throws {
        let router = ThreeFURLRouter()
        router.receive([
            try XCTUnwrap(URL(string: "threef://open?url=https%3A%2F%2Fexample.com%2F")),
            try XCTUnwrap(URL(string: "threef://open?url=http%3A%2F%2Fexample.com%2F"))
        ])
        XCTAssertEqual(router.takePendingURLs(), [try XCTUnwrap(URL(string: "threef://open?url=https%3A%2F%2Fexample.com%2F"))])
    }

    @MainActor
    func testDirectFileURLBecomesBrowserDeepLink() throws {
        let router = ThreeFURLRouter()
        let fileURL = URL(fileURLWithPath: "/Users/rogan/Desktop/test.html")
        router.receive([fileURL])

        let pending = router.takePendingURLs()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.scheme, "threef")
        XCTAssertEqual(pending.first?.host, "open")
        let target = URLComponents(url: try XCTUnwrap(pending.first), resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "url" })?.value
        XCTAssertEqual(target, fileURL.absoluteString)
    }

    @MainActor
    func testThreeFFileDeepLinkIsSupported() throws {
        let router = ThreeFURLRouter()
        let fileDeepLink = try XCTUnwrap(URL(string: "threef://open?url=file%3A%2F%2F%2FUsers%2Frogan%2FDesktop%2Ftest.html"))
        router.receive([fileDeepLink])
        XCTAssertEqual(router.takePendingURLs(), [fileDeepLink])
    }
}
