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

    static func verifiedAuthenticationBrowserBundleID(
        _ statusData: Data?,
        safariRulesData: Data?,
        asideRulesData: Data?
    ) -> String? {
        guard let statusData,
              let root = try? JSONSerialization.jsonObject(with: statusData) as? [String: Any],
              let browsers = root["browsers"] as? [[String: Any]] else {
            return nil
        }

        // Prefer Safari when it has verified enforcement, then use Aside as a
        // protected fallback. Unknown browsers and mismatched bundle IDs never open.
        let approved = ["safari": "com.apple.Safari", "aside": "at.studio.AsideBrowser"]
        let rulesByBrowser = ["safari": safariRulesData, "aside": asideRulesData]
        for browserName in ["safari", "aside"] {
            guard let browser = browsers.first(where: { $0["browser"] as? String == browserName }),
                  browser["bundleID"] as? String == approved[browserName],
                  browser["extensionReady"] as? Bool == true,
                  browser["blockedByFallback"] as? Bool == false,
                  browser["urlRulesStateKnown"] as? Bool == true,
                  browser["urlRulesProtected"] as? Bool == true,
                  browser["blockedForUnprotectedURLRules"] as? Bool == false,
                  browser["usageCollectionAvailable"] as? Bool == true,
                  rulesProtectRequiredSites(rulesByBrowser[browserName] ?? nil) else {
                continue
            }
            return approved[browserName]
        }
        return nil
    }

    private static func rulesProtectRequiredSites(_ rulesData: Data?) -> Bool {
        guard let rulesData,
              let rules = try? JSONSerialization.jsonObject(with: rulesData) as? [String: Any],
              let rawDomains = rules["blockedDomains"] as? [String],
              let rawParts = rules["blockedUrlParts"] as? [String],
              let exceptions = rules["blockExceptions"] as? [String] else { return false }

        let domains = rawDomains.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        let parts = rawParts.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        let requiredWebtoonTargets = [
            "webtoon.naver.com",
            "comic.naver.com",
            "series.naver.com/webtoon",
            "lezhin.com",
            "toomics.com",
            "webtoons.com",
            "ridibooks.com/webtoon"
        ]
        let youtubeBlocked = domains.contains { $0 == "youtube.com" || $0 == "youtu.be" }
            || rules["youtubeQuotaBlocked"] as? Bool == true
            || rules["youtubeBlockedByActiveSchedule"] as? Bool == true
        let googleSearchBlocked = parts.contains { $0.contains("google.com/search") }
        let webtoonsBlocked = requiredWebtoonTargets.allSatisfy { target in
            domains.contains { $0 == target || $0.hasSuffix(".\(target)") }
                || parts.contains { $0.contains(target) }
        }
        let sensitiveTargets = ["youtube.com", "youtu.be", "google.com/search"] + requiredWebtoonTargets
        let hasTargetException = exceptions.contains { exception in
            let normalized = exception.lowercased()
            return sensitiveTargets.contains { normalized.contains($0) }
        }
        return youtubeBlocked && googleSearchBlocked && webtoonsBlocked && !hasTargetException
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
