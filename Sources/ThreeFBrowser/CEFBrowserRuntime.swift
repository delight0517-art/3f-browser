import AppKit
import Foundation

@MainActor
enum CEFBrowserRuntime {
    static let hostBundleName = "3F Chromium Browser.app"
    private static var activeProcesses: [Int32: Process] = [:]

    static func open(
        _ authenticationURL: URL,
        originatingPage: URL?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let initialURL = GoogleOAuthNavigationPolicy.authenticationStartURL(for: authenticationURL) else {
            completion(.failure(LaunchError.invalidURL))
            return
        }

        let hostURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent(hostBundleName, isDirectory: true)
        let executableURL = hostURL.appendingPathComponent("Contents/MacOS/cefclient")
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            completion(.failure(LaunchError.hostNotBundled))
            return
        }

        let profileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("3F Browser/CEF/cefclient", isDirectory: true)
        let safeOriginatingPage = GoogleOAuthNavigationPolicy.safeHTTPSPageURL(originatingPage)
        var arguments = [
            // Open the restricted surface on Google itself. The originating
            // 3F site is passed only for the post-auth redirect.
            "--url=\(initialURL.absoluteString)",
            "--3f-profile-root=\(profileURL.path)",
            "--3f-auth-only"
        ]
        if let safeOriginatingPage,
           let origin = GoogleOAuthNavigationPolicy.exactOrigin(for: safeOriginatingPage) {
            arguments.append("--3f-site-origin=\(origin.absoluteString)")
        }
        let process = Process()
        process.executableURL = executableURL
        process.currentDirectoryURL = hostURL
        process.arguments = arguments
        do {
            try process.run()
            let processID = process.processIdentifier
            activeProcesses[processID] = process
            process.terminationHandler = { _ in
                DispatchQueue.main.async {
                    activeProcesses.removeValue(forKey: processID)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard process.isRunning else {
                    completion(.failure(LaunchError.launchFailed))
                    return
                }
                completion(.success(()))
            }
        } catch {
            completion(.failure(error))
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
