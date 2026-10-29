import Combine
import Foundation

@MainActor
final class ThreeFURLRouter: ObservableObject {
    static let shared = ThreeFURLRouter()

    @Published private(set) var pendingURLs: [URL] = []

    func receive(_ urls: [URL]) {
        let supported = urls.filter(Self.isSupportedNavigationURL)
        guard !supported.isEmpty else { return }
        pendingURLs.append(contentsOf: supported)
    }

    func takePendingURLs() -> [URL] {
        let urls = pendingURLs
        pendingURLs.removeAll()
        return urls
    }

    private static func isSupportedNavigationURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "threef",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.host == "open" else {
            return false
        }
        return components.queryItems?.contains(where: {
            $0.name == "url" && $0.value.flatMap(URL.init(string:))?.scheme?.lowercased() == "https"
        }) == true
    }
}
