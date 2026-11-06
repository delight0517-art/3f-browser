import Combine
import Foundation

@MainActor
final class ThreeFURLRouter: ObservableObject {
    static let shared = ThreeFURLRouter()

    @Published private(set) var pendingURLs: [URL] = []
    private var browserWindowPresenter: (() -> Bool)?

    func setBrowserWindowPresenter(_ presenter: (() -> Bool)?) {
        browserWindowPresenter = presenter
    }

    func receive(_ urls: [URL]) {
        let supported = urls.compactMap(Self.normalizedNavigationURL)
        guard !supported.isEmpty else { return }
        pendingURLs.append(contentsOf: supported)
        _ = browserWindowPresenter?()
    }

    func takePendingURLs() -> [URL] {
        let urls = pendingURLs
        pendingURLs.removeAll()
        return urls
    }

    private static func normalizedNavigationURL(_ url: URL) -> URL? {
        if isSafeWebURL(url) {
            var deepLink = URLComponents()
            deepLink.scheme = "threef"
            deepLink.host = "open"
            deepLink.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
            return deepLink.url
        }

        guard url.scheme?.lowercased() == "threef",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.host == "open",
              let target = components.queryItems?.first(where: { $0.name == "url" })?.value.flatMap(URL.init(string:)),
              target.scheme?.lowercased() == "https",
              target.host != nil,
              target.user == nil,
              target.password == nil else { return nil }
        return url
    }

    private static func isSafeWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host != nil, url.user == nil, url.password == nil else { return false }
        return true
    }
}
