import Foundation

enum GoogleOAuthNavigationPolicy {
    static func requiresSystemBrowser(for url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else { return false }
        return host == "accounts.google.com"
    }
}
