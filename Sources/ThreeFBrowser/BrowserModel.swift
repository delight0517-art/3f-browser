import Combine
import Foundation

enum SearchProvider: String, CaseIterable, Identifiable {
    case google
    case bing
    case duckduckgo

    static let preferenceKey = "appearance.v1.searchProvider"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .google: "Google"
        case .bing: "Bing"
        case .duckduckgo: "DuckDuckGo"
        }
    }

    func searchURL(for query: String) -> URL? {
        var components: URLComponents
        switch self {
        case .google:
            components = URLComponents(string: "https://www.google.com/search")!
        case .bing:
            components = URLComponents(string: "https://www.bing.com/search")!
        case .duckduckgo:
            components = URLComponents(string: "https://duckduckgo.com/")!
        }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url
    }
}

@MainActor
final class BrowserModel: ObservableObject {
    @Published var searchProvider: SearchProvider {
        didSet {
            UserDefaults.standard.set(searchProvider.rawValue, forKey: SearchProvider.preferenceKey)
        }
    }
    @Published var addressText = ""
    @Published var currentURL: URL?
    @Published var navigationRequestID = 0
    @Published var isShowingSettings = false

    init() {
        let savedProvider = UserDefaults.standard.string(forKey: SearchProvider.preferenceKey)
        searchProvider = SearchProvider(rawValue: savedProvider ?? "") ?? .google
    }

    func submit(_ text: String) {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        let destination = Self.webAddress(from: input) ?? searchProvider.searchURL(for: input)
        guard let destination else { return }

        currentURL = destination
        addressText = input
        navigationRequestID += 1
    }

    func openExternalURL(_ deepLink: URL) {
        guard deepLink.scheme?.lowercased() == "threef",
              deepLink.host?.lowercased() == "open",
              let components = URLComponents(url: deepLink, resolvingAgainstBaseURL: false),
              let value = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let destination = URLComponents(string: value)?.url,
              let scheme = destination.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              destination.host != nil,
              destination.user == nil,
              destination.password == nil else { return }

        currentURL = destination
        addressText = destination.absoluteString
        navigationRequestID += 1
    }

    func showNewTab() {
        currentURL = nil
        addressText = ""
    }

    func pageDidNavigate(to url: URL?) {
        guard let url else { return }
        currentURL = url
        addressText = url.absoluteString
    }

    private static func webAddress(from input: String) -> URL? {
        if let components = URLComponents(string: input),
           let scheme = components.scheme?.lowercased(),
           ["http", "https"].contains(scheme),
           components.host != nil {
            return components.url
        }

        guard !input.contains(where: \.isWhitespace),
              let candidate = URL(string: "https://\(input)"),
              let host = candidate.host,
              host == "localhost" || host.contains(".") else {
            return nil
        }
        return candidate
    }
}
