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

    static func allowsAuthenticationTransport(
        _ authenticationURL: URL,
        originatingPage: URL?,
        focusFenceRules: Data?
    ) -> Bool {
        guard requiresSystemBrowser(for: authenticationURL) else { return false }
        guard let originatingPage = safeHTTPSPageURL(originatingPage),
              let focusFenceRules,
              let sourceAllowed = ThreeFBrowserControlController.focusFenceAllows(originatingPage, rules: focusFenceRules) else {
            // Do not open an unrestricted browser when the source page cannot
            // be checked against Focus Fence's current policy.
            return false
        }
        return sourceAllowed
    }

    static func asideProtectionIsVerified(_ statusData: Data?) -> Bool {
        guard let statusData,
              let root = try? JSONSerialization.jsonObject(with: statusData) as? [String: Any],
              let browsers = root["browsers"] as? [[String: Any]],
              let aside = browsers.first(where: { $0["browser"] as? String == "aside" }) else {
            return false
        }
        return aside["extensionReady"] as? Bool == true
            && aside["blockedByFallback"] as? Bool == false
            && aside["urlRulesStateKnown"] as? Bool == true
            && aside["urlRulesProtected"] as? Bool == true
            && aside["blockedForUnprotectedURLRules"] as? Bool == false
            && aside["usageCollectionAvailable"] as? Bool == true
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
