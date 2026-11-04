import Foundation
import WebKit

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

enum ThreeFBackgroundLinkPolicy {
    static let messageName = "threefBackgroundLink"
    static let contentWorld = WKContentWorld.world(name: "com.rogan.threef.browser.background-link")
    static func isBackgroundLink(navigationType: WKNavigationType, buttonNumber: Int, isMainFrame: Bool) -> Bool {
        isMainFrame && navigationType == .linkActivated && buttonNumber == 2
    }

    static let script = #"""
    (() => {
      document.addEventListener('auxclick', event => {
        if (!event.isTrusted || event.button !== 1) return;
        const target = event.target instanceof Element ? event.target : event.target?.parentElement;
        const href = target?.closest?.('a[href]')?.href;
        const bridge = window.webkit?.messageHandlers?.threefBackgroundLink;
        if (!href || !bridge?.postMessage) return;
        event.preventDefault();
        bridge.postMessage(href);
      }, true);
    })();
    """#

    static func destination(from body: Any, isMainFrame: Bool, pageURL: URL?) -> URL? {
        guard isMainFrame,
              ThreeFContextMenuPolicy.safeHTTPURL(pageURL) != nil,
              let href = body as? String else { return nil }
        return ThreeFContextMenuPolicy.safeHTTPURL(URL(string: href))
    }
}

@MainActor
protocol ThreeFBackgroundLinkDelegate: AnyObject {
    func openBackgroundLink(_ url: URL)
}

@MainActor
final class ThreeFBackgroundLinkScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: ThreeFBackgroundLinkDelegate?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let destination = ThreeFBackgroundLinkPolicy.destination(
            from: message.body,
            isMainFrame: message.frameInfo.isMainFrame,
            pageURL: message.webView?.url
        ) else { return }
        delegate?.openBackgroundLink(destination)
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
