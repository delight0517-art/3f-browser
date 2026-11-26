import Foundation
import CryptoKit

struct WildcardBlockRule: Codable, Equatable, Sendable {
    var pattern: String
    var hideTitle: Bool
    var blockUrl: Bool
    var updatedAtMs: Int64
}

final class WildcardBlockStore: @unchecked Sendable {
    static let shared = WildcardBlockStore()

    static func shouldSyncWithRemoteServices(isQASession: Bool) -> Bool {
        !isQASession
    }

    private static let apiBase = URL(string: "https://brainwire-f2gf.onrender.com")!
    private let fileManager = FileManager.default
    private let rulesFileURL: URL
    private let authFileURL: URL
    private let lock = NSLock()
    private var cachedRules: [WildcardBlockRule] = []

    init(directory: URL? = nil) {
        let baseDir = directory ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/BlueCloud", isDirectory: true)
        self.rulesFileURL = baseDir.appendingPathComponent("wildcard_blocks.json")
        self.authFileURL = baseDir.appendingPathComponent("auth.json")
        self.cachedRules = Self.readRulesFromDisk(url: self.rulesFileURL)
    }

    var isBlueCloudSignedIn: Bool {
        readAuth()?.token.isEmpty == false
    }

    var blueCloudUsername: String? {
        readAuth()?.username
    }

    func loadRules() -> [WildcardBlockRule] {
        lock.lock()
        defer { lock.unlock() }
        let diskRules = Self.readRulesFromDisk(url: rulesFileURL)
        if !diskRules.isEmpty || cachedRules.isEmpty {
            cachedRules = diskRules
        }
        return cachedRules
    }

    func hiddenTitleKeywords() -> [String] {
        loadRules().filter(\.hideTitle).map(\.pattern)
    }

    func blockedUrlPatterns() -> [String] {
        loadRules().filter(\.blockUrl).map(\.pattern)
    }

    func matchesBlockedUrl(_ url: URL) -> Bool {
        let patterns = blockedUrlPatterns()
        guard !patterns.isEmpty else { return false }
        let raw = url.absoluteString.lowercased()
        var decoded = raw
        for _ in 0..<2 {
            guard let next = decoded.removingPercentEncoding?.lowercased(), next != decoded else { break }
            decoded = next
        }
        return patterns.contains { pattern in
            !pattern.isEmpty && (raw.contains(pattern) || decoded.contains(pattern))
        }
    }

    @discardableResult
    func addRule(pattern rawPattern: String, hideTitle: Bool, blockUrl: Bool, updatedAtMs: Int64? = nil) -> Bool {
        let pattern = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard pattern.count >= 2, hideTitle || blockUrl else { return false }
        let nowMs = updatedAtMs ?? Int64(Date().timeIntervalSince1970 * 1000)

        lock.lock()
        var rules = Self.readRulesFromDisk(url: rulesFileURL)
        if let idx = rules.firstIndex(where: { $0.pattern == pattern }) {
            let prev = rules[idx]
            rules[idx] = WildcardBlockRule(
                pattern: pattern,
                hideTitle: prev.hideTitle || hideTitle,
                blockUrl: prev.blockUrl || blockUrl,
                updatedAtMs: max(prev.updatedAtMs, nowMs)
            )
        } else {
            rules.append(WildcardBlockRule(
                pattern: pattern,
                hideTitle: hideTitle,
                blockUrl: blockUrl,
                updatedAtMs: nowMs
            ))
        }
        rules.sort { $0.pattern < $1.pattern }
        cachedRules = rules
        Self.writeRulesToDisk(rules, url: rulesFileURL, fileManager: fileManager)
        lock.unlock()
        return true
    }

    func signInBlueCloud(username: String, password: String) async -> Bool {
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUser.isEmpty, !password.isEmpty else { return false }
        var req = URLRequest(url: Self.apiBase.appendingPathComponent("api/auth/login"))
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("isle", forHTTPHeaderField: "x-cloud-app")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "username": trimmedUser,
            "password": password
        ])
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["token"] as? String, !token.isEmpty else {
            return false
        }
        let user = json["user"] as? [String: Any]
        let name = (user?["username"] as? String) ?? trimmedUser
        saveAuth(token: token, username: name)
        await syncWithBlueCloud()
        return true
    }

    private static let focusFenceBaseURL = URL(string: "http://127.0.0.1:17361")!

    func checkFocusFenceConnection() async -> Bool {
        var req = URLRequest(url: Self.focusFenceBaseURL.appendingPathComponent("ping"))
        req.timeoutInterval = 2
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else {
            return false
        }
        return (200..<300).contains(http.statusCode)
    }

    @discardableResult
    func syncWithFocusFence() async -> Bool {
        guard Self.shouldSyncWithRemoteServices(isQASession: FocusFenceQARouting.isQARequested()) else {
            return false
        }
        let localRules = loadRules()
        guard !localRules.isEmpty else {
            return await checkFocusFenceConnection()
        }
        var anySucceeded = false
        let endpoint = Self.focusFenceBaseURL.appendingPathComponent("wildcard-blocks")
        for rule in localRules {
            var req = URLRequest(url: endpoint)
            req.httpMethod = "POST"
            req.timeoutInterval = 3
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: [
                "pattern": rule.pattern,
                "hideTitle": rule.hideTitle,
                "blockUrl": rule.blockUrl
            ])
            if let (_, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse,
               (200..<300).contains(http.statusCode) {
                anySucceeded = true
            }
        }
        return anySucceeded
    }

    func syncWithBlueCloud() async {
        guard Self.shouldSyncWithRemoteServices(isQASession: FocusFenceQARouting.isQARequested()) else {
            return
        }
        _ = await syncWithFocusFence()
        guard let auth = readAuth(), !auth.token.isEmpty else { return }
        let endpoint = Self.apiBase.appendingPathComponent("api/cloud-state/focus-fense")
        var getReq = URLRequest(url: endpoint)
        getReq.httpMethod = "GET"
        getReq.timeoutInterval = 20
        getReq.setValue("Bearer \(auth.token)", forHTTPHeaderField: "Authorization")
        getReq.setValue("isle", forHTTPHeaderField: "x-cloud-app")

        guard let (data, response) = try? await URLSession.shared.data(for: getReq),
              let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 {
            clearAuth()
            return
        }
        guard (200..<300).contains(http.statusCode) || http.statusCode == 404 else { return }

        var state: [String: Any] = [:]
        if http.statusCode != 404,
           let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let rawState = body["state"] as? [String: Any] {
            state = rawState
        }

        let rev = (state["_rev"] as? NSNumber)?.intValue ?? 0
        var collection = (state["focusFenseSyncV1"] as? [String: Any]) ?? ["schemaVersion": 1]
        var tables = (collection["tables"] as? [String: Any]) ?? [:]
        var remoteRows = (tables["wildcard_blocks"] as? [String: Any]) ?? [:]

        // Pull remote wildcard_blocks into local store
        for (_, rawEnv) in remoteRows {
            guard let env = rawEnv as? [String: Any],
                  (env["deleted"] as? Bool) != true,
                  let row = env["row"] as? [String: Any],
                  let pattern = (row["pattern"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  pattern.count >= 2 else { continue }
            let hideTitle = (row["hide_title"] as? Bool) == true || (row["hideTitle"] as? Bool) == true
            let blockUrl = (row["block_url"] as? Bool) == true || (row["blockUrl"] as? Bool) == true
            let updatedAt = (row["updated_at"] as? NSNumber)?.int64Value ?? (env["updatedAt"] as? NSNumber)?.int64Value ?? 0
            _ = addRule(pattern: pattern, hideTitle: hideTitle, blockUrl: blockUrl, updatedAtMs: updatedAt)
        }

        // Push local rules missing or newer into remote wildcard_blocks
        let localRules = loadRules()
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        var changed = false
        for rule in localRules {
            let rowId = "wildcard_" + Self.shortHash(rule.pattern)
            let existingEnv = remoteRows[rowId] as? [String: Any]
            let existingRow = existingEnv?["row"] as? [String: Any]
            let existingHide = (existingRow?["hide_title"] as? Bool) == true
            let existingBlock = (existingRow?["block_url"] as? Bool) == true
            let effectiveHide = existingHide || rule.hideTitle
            let effectiveBlock = existingBlock || rule.blockUrl
            if existingEnv == nil || effectiveHide != existingHide || effectiveBlock != existingBlock {
                let row: [String: Any] = [
                    "id": rowId,
                    "pattern": rule.pattern,
                    "hide_title": effectiveHide,
                    "block_url": effectiveBlock,
                    "updated_at": max(rule.updatedAtMs, nowMs),
                    "created_at": rule.updatedAtMs > 0 ? rule.updatedAtMs : nowMs
                ]
                remoteRows[rowId] = [
                    "row": row,
                    "updatedAt": max(rule.updatedAtMs, nowMs)
                ]
                changed = true
            }
        }
        guard changed else { return }
        tables["wildcard_blocks"] = remoteRows
        collection["schemaVersion"] = 1
        collection["tables"] = tables
        state["focusFenseSyncV1"] = collection

        var putReq = URLRequest(url: endpoint)
        putReq.httpMethod = "PUT"
        putReq.timeoutInterval = 20
        putReq.setValue("Bearer \(auth.token)", forHTTPHeaderField: "Authorization")
        putReq.setValue("isle", forHTTPHeaderField: "x-cloud-app")
        putReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload = state
        payload["_expectedRev"] = rev
        putReq.httpBody = try? JSONSerialization.data(withJSONObject: ["state": payload])
        _ = try? await URLSession.shared.data(for: putReq)
    }

    private struct AuthRecord: Codable {
        var token: String
        var username: String
    }

    private func readAuth() -> AuthRecord? {
        guard let data = try? Data(contentsOf: authFileURL) else { return nil }
        return try? JSONDecoder().decode(AuthRecord.self, from: data)
    }

    private func saveAuth(token: String, username: String) {
        let dir = authFileURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(AuthRecord(token: token, username: username)) {
            try? data.write(to: authFileURL, options: .atomic)
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authFileURL.path)
        }
    }

    private func clearAuth() {
        try? fileManager.removeItem(at: authFileURL)
    }

    private static func shortHash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(24).description
    }

    private static func readRulesFromDisk(url: URL) -> [WildcardBlockRule] {
        guard let data = try? Data(contentsOf: url),
              let rules = try? JSONDecoder().decode([WildcardBlockRule].self, from: data) else {
            return []
        }
        return rules.filter { $0.pattern.count >= 2 && ($0.hideTitle || $0.blockUrl) }
    }

    private static func writeRulesToDisk(_ rules: [WildcardBlockRule], url: URL, fileManager: FileManager) {
        let dir = url.deletingLastPathComponent()
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(rules) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
