import Foundation

enum AIModeNavigationPolicy {
    static let onlyChatURL = URL(string: "http://127.0.0.1:8899/")!

    static func isOnlyChatLocalOrigin(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "http"
            && url.host == "127.0.0.1"
            && url.port == 8899
    }
}
