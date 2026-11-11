import Foundation

enum GoogleOAuthNavigationPolicy {
    static func isGoogleAuthURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else { return false }
        return host == "accounts.google.com"
    }

    static func requiresSystemBrowser(for url: URL) -> Bool {
        isGoogleAuthURL(url)
    }

    static func authenticationStartURL(for url: URL) -> URL? {
        requiresSystemBrowser(for: url) ? url : nil
    }

    static func safeHTTPSPageURL(_ url: URL?) -> URL? {
        guard let url,
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    static func exactOrigin(for url: URL) -> URL? {
        guard safeHTTPSPageURL(url) != nil,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.host = components.host?.lowercased()
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }

    static func isAllowedCallbackRedirect(_ destination: URL, from sourcePage: URL?) -> Bool {
        guard safeHTTPSPageURL(destination) != nil,
              let sourcePage,
              let destinationOrigin = exactOrigin(for: destination),
              let sourceOrigin = exactOrigin(for: sourcePage) else { return false }
        return destinationOrigin == sourceOrigin
    }
}
