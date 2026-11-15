import Foundation

enum CloudflareLoginNavigationPolicy {
    enum Route: Equatable {
        case continueInThreeF
        case blockedByFocusFence
    }

    static func isLoginURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "dash.cloudflare.com",
              url.user == nil,
              url.password == nil else { return false }
        let path = url.path.lowercased()
        return path == "/" || ["/login", "/sign-up", "/signup"].contains {
            path == $0 || path.hasPrefix($0 + "/")
        }
    }

    static func loginURL(for url: URL) -> URL? {
        if isLoginURL(url) { return url }
        guard let host = url.host?.lowercased(),
              ["google.com", "www.google.com"].contains(host),
              url.path == "/url",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let target = components.queryItems?.first(where: { ["q", "url"].contains($0.name) })?.value,
              let destination = URL(string: target),
              isLoginURL(destination) else { return nil }
        return destination
    }

    static func route(for url: URL, rules: Data?) -> Route {
        guard let loginURL = loginURL(for: url) else { return .continueInThreeF }
        guard let rules,
              let allowed = ThreeFBrowserControlController.focusFenceAllows(loginURL, rules: rules) else {
            // Keep login in 3F when FF is offline. A valid explicit block wins.
            return .continueInThreeF
        }
        return allowed ? .continueInThreeF : .blockedByFocusFence
    }
}
