import Foundation

enum ThreeFContextMenuAction: String, Equatable {
    case openInNewTab = "threef.openLink.newTab"
    case openInNewWindow = "threef.openLink.newWindow"
}

enum ThreeFContextMenuIntent: Equatable {
    case newTab(URL)
    case newWindow(URL)
}

enum ThreeFContextMenuPolicy {
    static let webKitOpenLinkInNewWindowIdentifier = "WKMenuItemIdentifierOpenLinkInNewWindow"

    static func action(for menuItemIdentifier: String?) -> ThreeFContextMenuAction? {
        guard let menuItemIdentifier else { return nil }
        return ThreeFContextMenuAction(rawValue: menuItemIdentifier)
    }

    static func safeHTTPURL(_ url: URL?) -> URL? {
        guard let url,
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }

    static func intent(action: ThreeFContextMenuAction?, url: URL?, isAllowed: Bool) -> ThreeFContextMenuIntent? {
        guard isAllowed, let action, let url = safeHTTPURL(url) else { return nil }
        switch action {
        case .openInNewTab: return .newTab(url)
        case .openInNewWindow: return .newWindow(url)
        }
    }
}

@MainActor
enum ThreeFContextMenuWindowRoute {
    private static var pending: [(url: URL, expiresAt: Date)] = []

    @discardableResult
    static func enqueue(_ url: URL, now: Date = Date()) -> Bool {
        guard let safeURL = ThreeFContextMenuPolicy.safeHTTPURL(url) else { return false }
        pending.removeAll { $0.expiresAt <= now }
        guard pending.count < 10 else { return false }
        pending.append((safeURL, now.addingTimeInterval(10)))
        return true
    }

    static func takeNext(now: Date = Date()) -> URL? {
        pending.removeAll { $0.expiresAt <= now }
        guard !pending.isEmpty else { return nil }
        return pending.removeFirst().url
    }
}
