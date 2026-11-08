import Foundation

struct MediaSiteSnoozeStore {
    static let duration: TimeInterval = 24 * 60 * 60

    private let defaults: UserDefaults?
    private let key: String

    init(defaults: UserDefaults? = BrowserSessionStore.mediaSiteSnoozeDefaults(), key: String = "threef.focusFence.mediaSiteSnoozes.v1") {
        guard let defaults else { self.defaults = .standard; self.key = key; return }
        self.defaults = defaults
        self.key = key
    }

    func snooze(domain rawDomain: String, at date: Date = Date()) {
        let domain = Self.normalize(rawDomain)
        guard !domain.isEmpty else { return }
        var active = activeSnoozes(at: date)
        active[domain] = date.timeIntervalSince1970 + Self.duration
        defaults?.set(active, forKey: key)
    }

    func activeSnoozes(at date: Date = Date()) -> [String: TimeInterval] {
        let stored = defaults?.dictionary(forKey: key) as? [String: TimeInterval] ?? [:]
        let now = date.timeIntervalSince1970
        let active = stored.filter { $0.value > now }
        if active.count != stored.count {
            defaults?.set(active, forKey: key)
        }
        return active
    }

    func suppresses(host rawHost: String, at date: Date = Date()) -> Bool {
        let host = Self.normalize(rawHost)
        return activeSnoozes(at: date).keys.contains {
            host == $0 || host.hasSuffix("." + $0)
        }
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
}
