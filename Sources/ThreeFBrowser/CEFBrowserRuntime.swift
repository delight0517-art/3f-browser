import AppKit
import Foundation

@MainActor
enum CEFBrowserRuntime {
    static let hostBundleName = "3F Chromium Browser.app"

    static func open(_ url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host != nil, url.user == nil, url.password == nil else {
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
        var arguments = [
            "--url=\(url.absoluteString)",
            "--3f-profile-root=\(profileURL.path)",
            "--remote-debugging-port=0"
        ]
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let scheme = components.scheme, let host = components.host {
            let port = components.port.map { ":\($0)" } ?? ""
            arguments.append("--3f-site-origin=\(scheme.lowercased())://\(host.lowercased())\(port)")
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
            case .invalidURL: return "Google 인증 주소가 올바르지 않습니다."
            case .hostNotBundled: return "3F Chromium 브라우저 구성 요소를 찾지 못했습니다."
            case .launchFailed: return "3F Chromium 브라우저를 열지 못했습니다."
            }
        }
    }
}
