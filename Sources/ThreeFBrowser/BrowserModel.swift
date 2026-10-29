import Combine
import CryptoKit
import Foundation
import SwiftUI

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

struct BrowserTheme: Codable, Equatable, Sendable {
    let accentHex: String

    static let standard = BrowserTheme(accentHex: "#0A84FF")

    var isValid: Bool {
        let value = accentHex
        guard value.count == 7, value.first == "#" else { return false }
        return value.dropFirst().allSatisfy { $0.isHexDigit }
    }

    var color: Color {
        let value = UInt64(accentHex.dropFirst(), radix: 16) ?? 0x0A84FF
        return Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
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
    @Published private(set) var theme = BrowserTheme.standard
    @Published private(set) var themeModuleStatus = "기본 테마"
    private let hotModuleStore = HotModuleStore()

    init() {
        let savedProvider = UserDefaults.standard.string(forKey: SearchProvider.preferenceKey)
        searchProvider = SearchProvider(rawValue: savedProvider ?? "") ?? .google
        reloadThemeModule()
    }

    func importThemeModule(from url: URL) {
        Task {
            do {
                let data = try Data(contentsOf: url)
                let newTheme = try JSONDecoder().decode(BrowserTheme.self, from: data)
                guard newTheme.isValid else { throw ThemeModuleError.invalidTheme }
                let currentRevision = try await hotModuleStore.currentManifest()?.revision ?? 0
                let nextRevision = currentRevision + 1
                try await hotModuleStore.apply(
                    revision: nextRevision,
                    files: ["theme.json": data],
                    expectedHashes: ["theme.json": Self.sha256(data)]
                )
                theme = newTheme
                themeModuleStatus = "적용됨 · revision \(nextRevision)"
            } catch {
                themeModuleStatus = "적용 실패 · \(error.localizedDescription)"
            }
        }
    }

    func reloadThemeModule() {
        Task {
            do {
                guard let manifest = try await hotModuleStore.currentManifest() else { return }
                let data = try await hotModuleStore.loadFile(named: "theme.json")
                let loadedTheme = try JSONDecoder().decode(BrowserTheme.self, from: data)
                guard loadedTheme.isValid,
                      manifest.files["theme.json"] == Self.sha256(data) else {
                    throw ThemeModuleError.invalidTheme
                }
                theme = loadedTheme
                themeModuleStatus = "적용됨 · revision \(manifest.revision)"
            } catch {
                themeModuleStatus = "불러오기 실패 · \(error.localizedDescription)"
            }
        }
    }

    func rollbackThemeModule() {
        Task {
            do {
                try await hotModuleStore.rollback()
                reloadThemeModule()
            } catch {
                themeModuleStatus = "복원 실패 · \(error.localizedDescription)"
            }
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private enum ThemeModuleError: LocalizedError {
        case invalidTheme
        var errorDescription: String? { "테마 JSON은 #RRGGBB 형식의 accentHex 값만 허용합니다." }
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
