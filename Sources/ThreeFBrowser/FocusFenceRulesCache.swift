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
        guard let normalized = Self.normalizedRules(data) else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try normalized.write(to: rulesURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    func load() -> Data? {
        guard let data = try? Data(contentsOf: rulesURL) else { return nil }
        return Self.normalizedCachedRules(data)
    }

    private static func normalizedCachedRules(_ data: Data) -> Data? {
        normalizedRules(data)
    }

    static func normalizedRules(_ data: Data) -> Data? {
        if isUsable(data) { return data }
        guard var rules = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let adultKeys = ["adultProtectedDomains", "adultProtectedUrlParts", "adultProtectedKeywords"]
        // FF versions can still return the complete legacy policy without these
        // newer optional protection arrays. Normalize that payload before both
        // caching and enforcement, while rejecting partial/null/malformed fields.
        guard adultKeys.allSatisfy({ rules[$0] == nil }),
              rules["blockedDomains"] is [String],
              rules["blockedUrlParts"] is [String],
              rules["keywords"] is [String],
              rules["blockExceptions"] is [String] else { return nil }
        adultKeys.forEach { rules[$0] = [String]() }
        guard let normalized = try? JSONSerialization.data(withJSONObject: rules), isUsable(normalized) else { return nil }
        return normalized
    }

    private static func isUsable(_ data: Data) -> Bool {
        guard let rules = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              rules["blockedDomains"] is [String],
              rules["blockedUrlParts"] is [String],
              rules["adultProtectedDomains"] is [String],
              rules["adultProtectedUrlParts"] is [String],
              rules["adultProtectedKeywords"] is [String],
              rules["keywords"] is [String],
              rules["blockExceptions"] is [String] else { return false }
        return true
    }
}
