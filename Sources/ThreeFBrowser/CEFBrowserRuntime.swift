import AppKit
import Foundation

@MainActor
enum CEFBrowserRuntime {
    static let hostBundleName = "3F Chromium Browser.app"

    static func open(
        _ authenticationURL: URL,
        originatingPage: URL?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard GoogleOAuthNavigationPolicy.requiresSystemBrowser(for: authenticationURL) else {
            completion(.failure(LaunchError.invalidURL))
            return
        }

        let hostURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent(hostBundleName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: hostURL.path) else {
            completion(.failure(LaunchError.hostNotBundled))
            return
        }

        let profileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("3F Browser/CEF/cefclient", isDirectory: true)
        let safeOriginatingPage = GoogleOAuthNavigationPolicy.safeHTTPSPageURL(originatingPage)
        let initialURL = safeOriginatingPage ?? authenticationURL
        var arguments = [
            "--url=\(initialURL.absoluteString)",
            "--3f-profile-root=\(profileURL.path)",
            "--3f-auth-only"
        ]
        if let safeOriginatingPage,
           let origin = GoogleOAuthNavigationPolicy.exactOrigin(for: safeOriginatingPage) {
            arguments.append("--3f-site-origin=\(origin.absoluteString)")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        NSWorkspace.shared.openApplication(at: hostURL, configuration: configuration) { app, error in
            DispatchQueue.main.async {
                if let error {
                    completion(.failure(error))
                } else if app != nil {
                    completion(.success(()))
                } else {
                    completion(.failure(LaunchError.launchFailed))
                }
            }
        }
    }

    private enum LaunchError: LocalizedError {
        case invalidURL
        case hostNotBundled
        case launchFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "HTTPS Google 인증 주소가 올바르지 않습니다."
            case .hostNotBundled: return "3F Chromium 브라우저 구성 요소를 찾지 못했습니다."
            case .launchFailed: return "3F Chromium 브라우저를 열지 못했습니다."
            }
        }
    }
}
