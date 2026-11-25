import AppKit
import Foundation
import WebKit
import XCTest
@testable import ThreeFBrowser

final class BrowserWebViewLoginCompatibilityTests: XCTestCase {
    private final class NavigationWaiter: NSObject, WKNavigationDelegate {
        private var continuation: CheckedContinuation<Void, Error>?

        func wait(for webView: WKWebView, loading html: String, baseURL: URL?) async throws {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                webView.navigationDelegate = self
                webView.loadHTMLString(html, baseURL: baseURL)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            continuation?.resume()
            continuation = nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    func testStandardWebKitApplicationNameIncludesSafariTokenAndSanitizesFallback() {
        XCTAssertEqual(
            BrowserWebView.standardWebKitApplicationNameForUserAgent(safariShortVersion: "27.3"),
            "Version/27.3 Safari/605.1.15"
        )
        XCTAssertEqual(
            BrowserWebView.standardWebKitApplicationNameForUserAgent(safariShortVersion: " 18.4.1 "),
            "Version/18.4.1 Safari/605.1.15"
        )
        for invalid in ["", "   ", "bad/1", ".18", "18.", "18.0-beta", "Version/18"] {
            XCTAssertEqual(
                BrowserWebView.standardWebKitApplicationNameForUserAgent(safariShortVersion: invalid),
                "Version/18.0 Safari/605.1.15",
                "Expected fallback for invalid version \(invalid)"
            )
        }
    }

    @MainActor
    func testConfiguredWebViewExposesSafariCompatibleUserAgentAndCleanPageWorld() async throws {
        let configuration = BrowserWebView.makeWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let waiter = NavigationWaiter()
        defer {
            webView.stopLoading()
            webView.navigationDelegate = nil
        }

        try await waiter.wait(
            for: webView,
            loading: "<!doctype html><meta charset=\"utf-8\"><body>login-check</body>",
            baseURL: URL(string: "https://dash.cloudflare.com/login")
        )

        let raw = try await webView.evaluateJavaScript("""
            JSON.stringify({
                ua: navigator.userAgent,
                webkitType: typeof window.webkit,
                reporterType: typeof window.__threefKeywordSelectionReporter
            })
        """) as? String
        let data = try XCTUnwrap(raw?.data(using: .utf8))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])

        let ua = try XCTUnwrap(payload["ua"])
        XCTAssertTrue(ua.contains("AppleWebKit/605.1.15"), "Unexpected UA: \(ua)")
        XCTAssertTrue(ua.contains("Version/"), "Missing Version token in UA: \(ua)")
        XCTAssertTrue(ua.contains("Safari/605.1.15"), "Missing Safari token in UA: \(ua)")
        XCTAssertEqual(payload["webkitType"], "undefined", "window.webkit must not leak into WKContentWorld.page")
        XCTAssertEqual(payload["reporterType"], "undefined", "internal script flags must not leak into WKContentWorld.page")
    }

    func testAllowsEmbeddedSubframeDocumentPermitsChallengeSchemesOnlyInSubframes() throws {
        let allowedSubframeURLs = [
            "about:blank",
            "about:srcdoc",
            "about:blank#turnstile",
            "about:blank?v=1",
            "blob:https://challenges.cloudflare.com/abc-123",
            "data:text/html,ok"
        ]
        for raw in allowedSubframeURLs {
            let url = try XCTUnwrap(URL(string: raw))
            XCTAssertTrue(
                BrowserWebView.Coordinator.allowsEmbeddedSubframeDocument(url, targetFrameIsMainFrame: false),
                "Expected subframe allowance for \(raw)"
            )
            XCTAssertFalse(
                BrowserWebView.Coordinator.allowsEmbeddedSubframeDocument(url, targetFrameIsMainFrame: true),
                "Main frame must not allow \(raw)"
            )
            XCTAssertFalse(
                BrowserWebView.Coordinator.allowsEmbeddedSubframeDocument(url, targetFrameIsMainFrame: nil),
                "Unknown targetFrame must not allow \(raw)"
            )
        }

        let rejectedSubframeURLs = [
            "blob:http://example.com/1",
            "blob:https://user:pass@example.com/1",
            "blob:not-a-valid-https-url",
            "about://evil/blank",
            "data://evil/text/html,ok",
            "javascript:alert(1)"
        ]
        for raw in rejectedSubframeURLs {
            let url = try XCTUnwrap(URL(string: raw))
            XCTAssertFalse(
                BrowserWebView.Coordinator.allowsEmbeddedSubframeDocument(url, targetFrameIsMainFrame: false),
                "Expected rejection for \(raw)"
            )
        }
    }

    func testCloudflareLoginPolicyRecognizesSignInAndSSOPaths() throws {
        for raw in [
            "https://dash.cloudflare.com/",
            "https://dash.cloudflare.com/login",
            "https://dash.cloudflare.com/sign-in",
            "https://dash.cloudflare.com/sign-up",
            "https://dash.cloudflare.com/signup",
            "https://dash.cloudflare.com/sso",
            "https://dash.cloudflare.com/sso/callback"
        ] {
            let url = try XCTUnwrap(URL(string: raw))
            XCTAssertTrue(CloudflareLoginNavigationPolicy.isLoginURL(url), "Expected Cloudflare login path recognition for \(raw)")
        }

        let unrelated = try XCTUnwrap(URL(string: "https://dash.cloudflare.com/profile"))
        XCTAssertFalse(CloudflareLoginNavigationPolicy.isLoginURL(unrelated))
    }

    func testManagedPopupRoutingDistinguishesScriptLoginPopupsFromTargetBlankLinks() throws {
        let httpsURL = try XCTUnwrap(URL(string: "https://auth.example.com/oauth"))
        let aboutBlank = try XCTUnwrap(URL(string: "about:blank"))

        XCTAssertTrue(BrowserWebView.Coordinator.shouldOpenManagedPopup(
            navigationType: .other,
            url: httpsURL,
            hasExplicitWindowSize: true
        ))
        XCTAssertTrue(BrowserWebView.Coordinator.shouldOpenManagedPopup(
            navigationType: .other,
            url: aboutBlank,
            hasExplicitWindowSize: false
        ))
        XCTAssertTrue(BrowserWebView.Coordinator.shouldOpenManagedPopup(
            navigationType: .other,
            url: nil,
            hasExplicitWindowSize: false
        ))
        XCTAssertFalse(BrowserWebView.Coordinator.shouldOpenManagedPopup(
            navigationType: .other,
            url: httpsURL,
            hasExplicitWindowSize: false
        ))
        XCTAssertFalse(BrowserWebView.Coordinator.shouldOpenManagedPopup(
            navigationType: .linkActivated,
            url: httpsURL,
            hasExplicitWindowSize: true
        ))
        XCTAssertFalse(BrowserWebView.Coordinator.shouldOpenManagedPopup(
            navigationType: .linkActivated,
            url: aboutBlank,
            hasExplicitWindowSize: false
        ))
    }
}
