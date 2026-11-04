import Foundation

enum BrowserNavigationURLSync {
    static func changedURL(modelURL: URL?, webViewURL: URL?) -> URL? {
        guard let webViewURL,
              ["http", "https"].contains(webViewURL.scheme?.lowercased() ?? ""),
              webViewURL.host != nil,
              webViewURL.user == nil,
              webViewURL.password == nil,
              webViewURL != modelURL else { return nil }
        return webViewURL
    }
}
