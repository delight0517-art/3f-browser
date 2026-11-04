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

    func ownsSearchURL(_ url: URL) -> Bool {
        guard let expected = searchURL(for: ""),
              url.host?.lowercased() == expected.host?.lowercased() else { return false }
        return url.path == expected.path
    }
}

struct BrowserTheme: Codable, Equatable, Sendable {
    let accentHex: String
    var quickLinks: [BrowserQuickLink] = []

    private enum CodingKeys: String, CodingKey { case accentHex, quickLinks }

    init(accentHex: String, quickLinks: [BrowserQuickLink] = []) {
        self.accentHex = accentHex
        self.quickLinks = quickLinks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accentHex = try container.decode(String.self, forKey: .accentHex)
        quickLinks = try container.decodeIfPresent([BrowserQuickLink].self, forKey: .quickLinks) ?? []
    }

    static let standard = BrowserTheme(
        accentHex: "#7950D9",
        quickLinks: [
            BrowserQuickLink(title: "YouTube", url: "https://www.youtube.com/"),
            BrowserQuickLink(title: "ChatGPT", url: "https://chatgpt.com"),
            BrowserQuickLink(title: "Gemini", url: "https://gemini.google.com"),
            BrowserQuickLink(title: "Drive", url: "https://drive.google.com"),
            BrowserQuickLink(title: "Docs", url: "https://docs.google.com")
        ]
    )

    var isValid: Bool {
        let value = accentHex
        guard value.count == 7, value.first == "#" else { return false }
        guard value.dropFirst().allSatisfy({ $0.isHexDigit }), quickLinks.count <= 8 else { return false }
        return quickLinks.allSatisfy(\.isValid)
    }

    var color: Color {
        let value = UInt64(accentHex.dropFirst(), radix: 16) ?? 0x7950D9
        return Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

struct BrowserQuickLink: Codable, Equatable, Sendable, Identifiable {
    let title: String
    let url: String
    var id: String { url }

    var destination: URL? {
        guard isValid else { return nil }
        return URL(string: url)
    }

    var isValid: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.count <= 40,
              let components = URLComponents(string: url),
              components.scheme?.lowercased() == "https",
              components.host != nil,
              components.user == nil, components.password == nil else { return false }
        return true
    }
}

struct BrowserHistoryEntry: Codable, Equatable, Identifiable {
    let url: String
    let title: String
    let visitedAt: Date
    var id: String { "\(url)|\(visitedAt.timeIntervalSince1970)" }
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
    @Published var isLoading = false
    @Published var isShowingSettings = false
    @Published var downloadStatus: String?
    @Published var addressBlockNotice: String?
    @Published private(set) var youtubeUsageSummary: FocusFenceYouTubeUsageSummary?
    @Published private(set) var youtubeUsageUnavailable = false
    @Published private(set) var theme = BrowserTheme.standard
    @Published private(set) var themeModuleStatus = "기본 테마"
    @Published private(set) var bookmarks: [BrowserQuickLink] = []
    @Published private(set) var history: [BrowserHistoryEntry] = []
    @Published var pendingMediaSiteCandidate: MediaSiteCandidate?
    private var navigationAuthorizationID: UUID?
    private var mediaCandidateCheck: Task<Void, Never>?
    private let hotModuleStore = HotModuleStore()
    private let bookmarksKey = "browser.v1.bookmarks"
    private let historyKey = "browser.v1.history"

    var isYouTubePage: Bool {
        guard let host = currentURL?.host?.lowercased() else { return false }
        return host == "youtu.be" || ((host == "youtube.com" || host.hasSuffix(".youtube.com")) && host != "music.youtube.com")
    }

    var youtubeUsagePollKey: String? {
        isYouTubePage ? currentURL?.host?.lowercased() : nil
    }

    var youtubeUsageStatusLabel: String {
        guard isYouTubePage else { return "" }
        if let youtubeUsageSummary { return youtubeUsageSummary.compactStatusLine }
        return youtubeUsageUnavailable ? "Focus Fence 사용량 확인 불가" : "Focus Fence 사용량 확인 중"
    }

    var youtubeUsageDetail: String {
        youtubeUsageSummary?.statusLine ?? youtubeUsageStatusLabel
    }

    init() {
        let savedProvider = UserDefaults.standard.string(forKey: SearchProvider.preferenceKey)
        searchProvider = SearchProvider(rawValue: savedProvider ?? "") ?? .google
        bookmarks = Self.load([BrowserQuickLink].self, forKey: bookmarksKey) ?? BrowserTheme.standard.quickLinks
        history = Self.load([BrowserHistoryEntry].self, forKey: historyKey) ?? []
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
                themeModuleStatus = "새 탭 설정 적용됨 · revision \(nextRevision) · 빠른 링크 \(newTheme.quickLinks.count)개"
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
                themeModuleStatus = "새 탭 설정 적용됨 · revision \(manifest.revision) · 빠른 링크 \(loadedTheme.quickLinks.count)개"
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

    func submit(
        _ text: String,
        authorize: (((URL, @escaping (BrowserNavigationAuthorizationDecision) -> Void) -> Void))? = nil
    ) {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        addressBlockNotice = nil
        isLoading = true
        guard let destination = AddressBarNavigationRequest.resolve(input, searchProvider: searchProvider) else {
            isLoading = false
            addressBlockNotice = "주소나 검색어를 확인해 주세요."
            return
        }
        authorizeAndNavigate(destination, authorize: authorize)
    }

    func openExternalURL(
        _ deepLink: URL,
        authorize: (((URL, @escaping (BrowserNavigationAuthorizationDecision) -> Void) -> Void))? = nil
    ) {
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

        authorizeAndNavigate(destination, authorize: authorize)
    }

    func navigate(
        to destination: URL,
        authorize: (((URL, @escaping (BrowserNavigationAuthorizationDecision) -> Void) -> Void))? = nil
    ) {
        guard let scheme = destination.scheme?.lowercased(), ["http", "https"].contains(scheme),
              destination.host != nil, destination.user == nil, destination.password == nil else { return }
        authorizeAndNavigate(destination, authorize: authorize)
    }

    func showNewTab() {
        currentURL = nil
        addressText = ""
        isLoading = false
        navigationAuthorizationID = nil
    }

    func pageDidStartNavigation(to url: URL?) {
        navigationAuthorizationID = nil
        if let url,
           let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
           url.host != nil, url.user == nil, url.password == nil {
            currentURL = url
            addressText = url.absoluteString
        }
        addressBlockNotice = nil
        isLoading = true
    }

    func openQuickLink(
        _ link: BrowserQuickLink,
        authorize: (((URL, @escaping (BrowserNavigationAuthorizationDecision) -> Void) -> Void))? = nil
    ) {
        guard let destination = link.destination else { return }
        authorizeAndNavigate(destination, authorize: authorize)
    }

    private func authorizeAndNavigate(
        _ destination: URL,
        authorize: (((URL, @escaping (BrowserNavigationAuthorizationDecision) -> Void) -> Void))?
    ) {
        let destination = Self.canonicalNavigationDestination(destination)
        addressBlockNotice = nil
        addressText = destination.absoluteString
        isLoading = true
        guard let authorize else {
            navigationAuthorizationID = nil
            currentURL = destination
            navigationRequestID += 1
            return
        }
        let authorizationID = UUID()
        navigationAuthorizationID = authorizationID
        authorize(destination) { [weak self] decision in
            guard let self, self.navigationAuthorizationID == authorizationID else { return }
            self.navigationAuthorizationID = nil
            guard decision.isAllowed else {
                self.pageDidRejectNavigation(decision)
                return
            }
            self.currentURL = destination
            self.navigationRequestID += 1
        }
    }

    private static func canonicalNavigationDestination(_ destination: URL) -> URL {
        guard let scheme = destination.scheme?.lowercased(), ["http", "https"].contains(scheme),
              destination.host?.lowercased() == "youtube.com", destination.port == nil,
              var components = URLComponents(url: destination, resolvingAgainstBaseURL: false) else {
            return destination
        }
        components.host = "www.youtube.com"
        return components.url ?? destination
    }

    func pageDidNavigate(to url: URL?, title: String? = nil) {
        guard let url else { return }
        navigationAuthorizationID = nil
        currentURL = url
        addressText = url.absoluteString
        isLoading = false
        if !isYouTubePage { clearYouTubeUsage() }
        recordVisit(to: url, title: title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? url.host ?? url.absoluteString)
        mediaCandidateCheck?.cancel()
        mediaCandidateCheck = Task { [weak self] in
            await self?.considerMediaSiteCandidate(at: url)
        }
    }

    func ignoreMediaSiteCandidate(_ candidate: MediaSiteCandidate) {
        rememberMediaSiteDecision(candidate.domain)
        pendingMediaSiteCandidate = nil
    }

    func resolveMediaSiteCandidate(_ candidate: MediaSiteCandidate) {
        rememberMediaSiteDecision(candidate.domain)
        pendingMediaSiteCandidate = nil
    }

    func deferMediaSiteCandidate(_ candidate: MediaSiteCandidate) {
        var deferred = Self.deferredMediaSiteDomains()
        deferred[candidate.domain] = Date().timeIntervalSince1970 + Self.mediaSiteSnoozeDuration
        UserDefaults.standard.set(deferred, forKey: Self.mediaSiteSnoozeKey)
        pendingMediaSiteCandidate = nil
    }

    private func considerMediaSiteCandidate(at url: URL) async {
        guard let host = url.host?.lowercased(),
              !Self.isMediaSitePromptSuppressed(host),
              let data = await ThreeFBrowserControlController.fetchFocusFenceRules(),
              currentURL == url,
              let rules = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blockedDomains = rules["blockedDomains"] as? [String] else { return }

        let candidate = MediaSiteCandidate.detect(
            host: host,
            blockedDomains: blockedDomains,
            youtubeQuotaBlocked: rules["youtubeQuotaBlocked"] as? Bool == true
        )
        guard let candidate,
              !Self.isMediaSitePromptSuppressed(candidate.domain),
              currentURL == url else { return }
        pendingMediaSiteCandidate = candidate
    }

    private func rememberMediaSiteDecision(_ domain: String) {
        var resolved = Self.resolvedMediaSiteDomains()
        resolved.insert(domain)
        UserDefaults.standard.set(resolved.sorted(), forKey: Self.mediaSiteDecisionsKey)
    }

    private static let mediaSiteDecisionsKey = "threef.focusFence.mediaSiteDecisions.v1"
    private static let mediaSiteSnoozeKey = "threef.focusFence.mediaSiteSnoozes.v1"
    private static let mediaSiteSnoozeDuration: TimeInterval = 24 * 60 * 60

    private static func resolvedMediaSiteDomains() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: mediaSiteDecisionsKey) ?? [])
    }

    private static func deferredMediaSiteDomains() -> [String: TimeInterval] {
        let now = Date().timeIntervalSince1970
        let stored = UserDefaults.standard.dictionary(forKey: mediaSiteSnoozeKey) as? [String: TimeInterval] ?? [:]
        let active = stored.filter { $0.value > now }
        if active.count != stored.count {
            UserDefaults.standard.set(active, forKey: mediaSiteSnoozeKey)
        }
        return active
    }

    private static func isMediaSitePromptSuppressed(_ rawHost: String) -> Bool {
        let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let resolved = resolvedMediaSiteDomains().union(deferredMediaSiteDomains().keys)
        return resolved.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    func refreshYouTubeUsage() async {
        guard isYouTubePage, let requestedURL = currentURL else {
            clearYouTubeUsage()
            return
        }
        guard let summary = await FocusFenceYouTubeUsageClient.fetch(),
              currentURL == requestedURL, isYouTubePage else {
            guard currentURL == requestedURL, isYouTubePage else { return }
            youtubeUsageSummary = nil
            youtubeUsageUnavailable = true
            return
        }
        youtubeUsageSummary = summary
        youtubeUsageUnavailable = false
    }

    func clearYouTubeUsage() {
        youtubeUsageSummary = nil
        youtubeUsageUnavailable = false
    }

    func pageDidFailToNavigate(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        isLoading = false
        addressBlockNotice = "페이지 연결에 실패했습니다. 네트워크나 Focus Fence 제한을 확인해 주세요."
    }

    func pageDidRejectNavigation(_ decision: BrowserNavigationAuthorizationDecision) {
        isLoading = false
        switch decision {
        case .allowed:
            addressBlockNotice = nil
        case .blocked:
            addressBlockNotice = "Focus Fence 규칙에 따라 이 페이지를 차단했습니다."
        case .youtubeBlocked:
            addressBlockNotice = "YouTube가 Focus Fence에서 제한 중입니다. 한도·스케줄 설정을 확인해 주세요."
        case .unavailable:
            addressBlockNotice = "Focus Fence에 연결할 수 없어 열지 못했습니다. 연결을 확인한 뒤 다시 시도해 주세요."
        }
    }

    func addBookmarkForCurrentPage() {
        guard let url = currentURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil else { return }
        let value = BrowserQuickLink(title: url.host ?? url.absoluteString, url: url.absoluteString)
        guard value.isValid, !bookmarks.contains(where: { $0.url == value.url }) else { return }
        bookmarks.insert(value, at: 0)
        if bookmarks.count > 100 { bookmarks = Array(bookmarks.prefix(100)) }
        Self.save(bookmarks, forKey: bookmarksKey)
    }

    func removeBookmark(_ bookmark: BrowserQuickLink) {
        bookmarks.removeAll { $0.id == bookmark.id }
        Self.save(bookmarks, forKey: bookmarksKey)
    }

    func clearHistory() {
        history = []
        Self.save(history, forKey: historyKey)
    }

    private func recordVisit(to url: URL, title: String) {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil else { return }
        let entry = BrowserHistoryEntry(url: url.absoluteString, title: title, visitedAt: Date())
        history.removeAll { $0.url == entry.url }
        history.insert(entry, at: 0)
        if history.count > 100 { history = Array(history.prefix(100)) }
        Self.save(history, forKey: historyKey)
    }

    private static func load<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func save<Value: Encodable>(_ value: Value, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
