import Foundation

enum GoogleOAuthNavigationPolicy {
    static func requiresSystemBrowser(for url: URL) -> Bool {
        // The user explicitly wants sign-in to remain inside 3F. Google may
        // reject OAuth in WKWebView; do not silently hand the page to another app.
        false
    }
}
