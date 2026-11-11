import Foundation

enum GoogleOAuthNavigationPolicy {
    static func requiresSystemBrowser(for url: URL) -> Bool {
        guard url.scheme?.caseInsensitiveCompare("https") == .orderedSame,
              url.host?.caseInsensitiveCompare("accounts.google.com") == .orderedSame else {
            return false
        }

        // Google Identity Services uses several sign-in paths beyond the
        // OAuth endpoints (for example /gsi/select and /signin/v2/*).
        // Keep the entire Google Accounts host out of the embedded WebView.
        return true
    }
}
