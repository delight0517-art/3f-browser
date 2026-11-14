import Foundation

struct FocusFenceRulesCache {
    let directory: URL

    static var production: FocusFenceRulesCache {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return FocusFenceRulesCache(directory: support.appendingPathComponent("3F Browser/FocusFence", isDirectory: true))
    }

    var rulesURL: URL { directory.appendingPathComponent("rules-v1.json") }

    func save(_ data: Data) -> Bool {
        guard Self.isUsable(data) else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: rulesURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    func load() -> Data? {
        guard let data = try? Data(contentsOf: rulesURL), Self.isUsable(data) else { return nil }
        return data
    }

    private static func isUsable(_ data: Data) -> Bool {
        guard let rules = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              rules["blockedDomains"] is [String],
              rules["blockedUrlParts"] is [String],
              rules["keywords"] is [String],
              rules["blockExceptions"] is [String] else { return false }
        return true
    }
}
