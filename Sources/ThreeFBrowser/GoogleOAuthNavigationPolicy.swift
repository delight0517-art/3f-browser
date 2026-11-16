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

    static func verifiedAuthenticationBrowserBundleID(_ statusData: Data?) -> String? {
        guard let statusData,
              let root = try? JSONSerialization.jsonObject(with: statusData) as? [String: Any],
              let browsers = root["browsers"] as? [[String: Any]] else {
            return nil
        }

        // Prefer Safari when it has verified enforcement, then use Aside as a
        // protected fallback. Unknown browsers and mismatched bundle IDs never open.
        let approved = ["safari": "com.apple.Safari", "aside": "at.studio.AsideBrowser"]
        for browserName in ["safari", "aside"] {
            guard let browser = browsers.first(where: { $0["browser"] as? String == browserName }),
                  browser["bundleID"] as? String == approved[browserName],
                  browser["extensionReady"] as? Bool == true,
                  browser["blockedByFallback"] as? Bool == false,
                  browser["urlRulesStateKnown"] as? Bool == true,
                  browser["urlRulesProtected"] as? Bool == true,
                  browser["blockedForUnprotectedURLRules"] as? Bool == false,
                  browser["usageCollectionAvailable"] as? Bool == true else {
                continue
            }
            return approved[browserName]
        }
        return nil
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
