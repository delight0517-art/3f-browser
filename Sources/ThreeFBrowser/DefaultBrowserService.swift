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
        let handlers = schemes.map { scheme -> (URL?, String?) in
            guard let url = URL(string: "\(scheme)://example.com"),
                  let handlerURL = NSWorkspace.shared.urlForApplication(toOpen: url) else { return (nil, nil) }
            return (handlerURL, Bundle(url: handlerURL)?.bundleIdentifier)
        }

        let currentHandlers = handlers.map { Self.isCurrentApplication($0.0, bundleURL: Bundle.main.bundleURL) }
        let sameBundleCopy = appID != nil && handlers.allSatisfy { $0.1 == appID }
        status = Self.status(currentHandlers: currentHandlers, sameBundleCopy: sameBundleCopy)
    }

    static func isCurrentApplication(_ handlerURL: URL?, bundleURL: URL) -> Bool {
        guard let handlerURL else { return false }
        return handlerURL.standardizedFileURL.resolvingSymlinksInPath() ==
            bundleURL.standardizedFileURL.resolvingSymlinksInPath()
    }

    static func status(currentHandlers: [Bool], sameBundleCopy: Bool) -> String {
        guard currentHandlers.count == 2, currentHandlers.allSatisfy({ $0 }) else {
            return sameBundleCopy
                ? "macOS가 다른 3F Browser 복사본을 선택했습니다. 시스템 설정 > 데스크탑 및 Dock > 기본 웹 브라우저에서 현재 복사본을 선택하세요."
                : "3F Browser가 아직 HTTP와 HTTPS 기본 브라우저가 아닙니다."
        }
        return "3F Browser가 HTTP와 HTTPS 기본 브라우저입니다."
    }

    static func failureStatus(errorDescription: String, refreshedStatus: String) -> String {
        "기본 브라우저 변경을 완료하지 못했습니다: \(errorDescription)\n\(refreshedStatus)"
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
                let handlers = schemes.map { scheme -> (URL?, String?) in
                    guard let url = URL(string: "\(scheme)://example.com"),
                          let handlerURL = NSWorkspace.shared.urlForApplication(toOpen: url) else { return (nil, nil) }
                    return (handlerURL, Bundle(url: handlerURL)?.bundleIdentifier)
                }
                let currentHandlers = handlers.map { Self.isCurrentApplication($0.0, bundleURL: Bundle.main.bundleURL) }
                let sameBundleCopy = Bundle.main.bundleIdentifier != nil && handlers.allSatisfy { $0.1 == Bundle.main.bundleIdentifier }
                status = Self.status(currentHandlers: currentHandlers, sameBundleCopy: sameBundleCopy)
            } catch {
                refresh()
                status = Self.failureStatus(errorDescription: error.localizedDescription, refreshedStatus: status)
            }
        }
    }
}
