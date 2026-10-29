import Combine
import Foundation

@MainActor
final class ThreeFURLRouter: ObservableObject {
    static let shared = ThreeFURLRouter()

    @Published private(set) var pendingURLs: [URL] = []

    func receive(_ urls: [URL]) {
        pendingURLs.append(contentsOf: urls)
    }

    func takePendingURLs() -> [URL] {
        let urls = pendingURLs
        pendingURLs.removeAll()
        return urls
    }
}
