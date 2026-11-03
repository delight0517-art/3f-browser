import AppKit
import Combine
import Foundation

@MainActor
final class DefaultBrowserService: ObservableObject {
    @Published private(set) var status = "기본 브라우저 상태를 확인하고 있습니다."
    @Published private(set) var isApplying = false

    private let schemes = ["http", "https"]

    func refresh() {
        let appID = Bundle.main.bundleIdentifier
        let isDefaultForEveryScheme = schemes.allSatisfy { scheme in
            guard let url = URL(string: "\(scheme)://example.com"),
                  let handlerURL = NSWorkspace.shared.urlForApplication(toOpen: url),
                  let handlerID = Bundle(url: handlerURL)?.bundleIdentifier else { return false }
            return handlerID == appID
        }

        status = isDefaultForEveryScheme
            ? "3F Browser가 HTTP와 HTTPS 기본 브라우저입니다."
            : "3F Browser가 아직 HTTP와 HTTPS 기본 브라우저가 아닙니다."
    }

    func setAsDefaultBrowser() {
        guard !isApplying else { return }
        isApplying = true

        Task {
            defer { isApplying = false }
            do {
                for scheme in schemes {
                    try await NSWorkspace.shared.setDefaultApplication(
                        at: Bundle.main.bundleURL,
                        toOpenURLsWithScheme: scheme
                    )
                }
                refresh()
            } catch {
                status = "기본 브라우저 변경을 완료하지 못했습니다: \(error.localizedDescription)"
                refreshIfNeededAfterFailure()
            }
        }
    }

    private func refreshIfNeededAfterFailure() {
        let failure = status
        refresh()
        if status.hasPrefix("3F Browser가 아직") {
            status = failure
        }
    }
}
