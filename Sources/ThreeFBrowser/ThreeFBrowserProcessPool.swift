import WebKit

enum ThreeFBrowserProcessPool {
    @MainActor static let shared = WKProcessPool()
}
