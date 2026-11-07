import Foundation

enum GoogleOAuthNavigationPolicy {
    static func requiresSystemBrowser(for url: URL) -> Bool {
        guard url.scheme?.caseInsensitiveCompare("https") == .orderedSame,
              url.host?.caseInsensitiveCompare("accounts.google.com") == .orderedSame else {
            return false
        }

        let path = url.path
        return path == "/o/oauth2"
            || path.hasPrefix("/o/oauth2/")
            || path == "/signin/oauth"
            || path.hasPrefix("/signin/oauth/")
    }
}
