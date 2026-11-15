import Foundation

enum CloudflareLoginNavigationPolicy {
    enum Route: Equatable {
        case continueInThreeF
        case openInDefaultBrowser
        case blockedByFocusFence
    }

    static func isLoginURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "dash.cloudflare.com",
              url.user == nil,
              url.password == nil else { return false }
        let path = url.path.lowercased()
        return ["/login", "/sign-up"].contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    static func route(for url: URL, rules: Data?) -> Route {
        guard isLoginURL(url) else { return .continueInThreeF }
        guard let rules,
              let allowed = ThreeFBrowserControlController.focusFenceAllows(url, rules: rules) else {
            // A missing/offline policy must not make an explicit user sign-in
            // action silently fail. A valid explicit block still wins.
            return .openInDefaultBrowser
        }
        return allowed ? .openInDefaultBrowser : .blockedByFocusFence
    }
}
