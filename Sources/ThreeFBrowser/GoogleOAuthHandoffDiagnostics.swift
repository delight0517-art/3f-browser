import Foundation
import AppKit
import Combine

struct GoogleOAuthHandoffEvent: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let outcome: Outcome

    enum Outcome: String {
        case opened = "Aside로 열음"
        case duplicateSuppressed = "중복 전달 억제"
        case asideUnavailable = "Aside를 찾지 못함"
        case openFailed = "Aside 열기 실패"
    }
}

@MainActor
final class GoogleOAuthHandoffDiagnostics: ObservableObject {
    static let shared = GoogleOAuthHandoffDiagnostics()
    static let asideBundleIdentifier = "at.studio.AsideBrowser"

    @Published private(set) var events: [GoogleOAuthHandoffEvent] = []
    private var recentKeys: [String: Date] = [:]
    // A login flow can emit the same handoff repeatedly while it redirects.
    // A short debounce still opens another browser window every few seconds.
    private let duplicateWindow: TimeInterval = 120
    private let capacity = 30

    private init() {}

    func handoff(_ url: URL, sourceURL: URL?) {
        let now = Date()
        recentKeys = recentKeys.filter { now.timeIntervalSince($0.value) < duplicateWindow }
        let key = Self.deduplicationKey(for: url, sourceHost: sourceURL?.host)
        guard recentKeys[key] == nil else {
            record(.duplicateSuppressed)
            return
        }
        recentKeys[key] = now

        guard let aside = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: Self.asideBundleIdentifier).first else {
            record(.asideUnavailable)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: aside, configuration: configuration) { [weak self] _, error in
            Task { @MainActor in
                if error == nil { self?.record(.opened) }
                else { self?.record(.openFailed) }
            }
        }
    }

    func clear() {
        events.removeAll()
    }

    nonisolated static func deduplicationKey(for url: URL, sourceHost: String?) -> String {
        // Google changes paths and query values throughout one sign-in flow.
        // Treat those redirects as the same handoff to prevent window storms.
        "\(sourceHost?.lowercased() ?? "unknown")|\(url.host?.lowercased() ?? "unknown")"
    }

    private func record(_ outcome: GoogleOAuthHandoffEvent.Outcome) {
        events.insert(GoogleOAuthHandoffEvent(id: UUID(), date: Date(), outcome: outcome), at: 0)
        if events.count > capacity { events.removeLast(events.count - capacity) }
    }
}
