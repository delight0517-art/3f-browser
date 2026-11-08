import Foundation

struct BrowserSessionTab: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var url: URL? = nil
}

struct BrowserSessionSnapshot: Codable, Equatable {
    var tabs: [BrowserSessionTab]
    var selectedTabID: UUID?
}

struct BrowserSessionManifest: Codable, Equatable {
    static let currentVersion = 1

    let version: Int
    var windows: [String]
    var activeWindowID: String?

    init(windows: [String] = [], activeWindowID: String? = nil) {
        version = Self.currentVersion
        self.windows = windows
        self.activeWindowID = activeWindowID
    }
}

enum BrowserSessionStoreError: Error {
    case tooManyWindows
}

enum BrowserSessionStore {
    private static let productionBundleIdentifier = "com.rogan.threef.browser"
    private static let fileName = "browser-session.json"
    private static let legacyFileName = "browser-session.json"
    private static let manifestFileName = "browser-session-manifest.json"
    private static let sessionsDirectoryName = "browser-sessions"
    private static let maximumTabs = 50
    private static let maximumWindows = 20
    private static let maximumTitleUTF8Bytes = 120
    private static let maximumFileBytes = 512_000
    private static let isolatedQAProfileFlag = "THREEF_BROWSER_ENABLE_ISOLATED_QA_PROFILE"
    private static let isolatedQAProfilePath = "THREEF_BROWSER_QA_PROFILE_DIRECTORY"
    private static let qaMediaSiteSnoozeSuite = "com.rogan.threef.browser.qa.media-site-snoozes"

    static func mediaSiteSnoozeDefaults(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = CommandLine.arguments,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) -> UserDefaults? {
        guard isolatedQASessionDirectory(environment: environment, arguments: arguments,
                                         temporaryDirectory: temporaryDirectory) != nil else {
            return .standard
        }
        return UserDefaults(suiteName: qaMediaSiteSnoozeSuite)
    }

    static var defaultDirectory: URL {
        if let qaDirectory = isolatedQASessionDirectory(
            environment: ProcessInfo.processInfo.environment,
            arguments: CommandLine.arguments,
            temporaryDirectory: FileManager.default.temporaryDirectory
        ) {
            return qaDirectory
        }
        let applicationSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return directory(
            applicationSupportDirectory: applicationSupport,
            bundleIdentifier: Bundle.main.bundleIdentifier
        )
    }

    static var isolatedQAProfileEnabled: Bool {
        isolatedQASessionDirectory(
            environment: ProcessInfo.processInfo.environment,
            arguments: CommandLine.arguments,
            temporaryDirectory: FileManager.default.temporaryDirectory
        ) != nil
    }

    static func isolatedQASessionDirectory(
        environment: [String: String],
        arguments: [String] = [],
        temporaryDirectory: URL
    ) -> URL? {
        let argumentPath = arguments.first(where: { $0.hasPrefix("--threef-browser-qa-profile=") })
            .map { String($0.dropFirst("--threef-browser-qa-profile=".count)) }
        let enabled = environment[isolatedQAProfileFlag] == "1"
            || arguments.contains("--spaceo-agent-session")
        guard enabled,
              let path = argumentPath ?? environment[isolatedQAProfilePath], !path.isEmpty else { return nil }

        let temporaryRoot = temporaryDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        let prefix = temporaryRoot.path.hasSuffix("/") ? temporaryRoot.path : temporaryRoot.path + "/"
        var isDirectory: ObjCBool = false
        guard candidate.path.hasPrefix(prefix), candidate.path != temporaryRoot.path,
              FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return candidate
    }

    static func directory(applicationSupportDirectory: URL, bundleIdentifier: String?) -> URL {
        let browserDirectory = applicationSupportDirectory.appendingPathComponent("3F Browser", isDirectory: true)
        guard bundleIdentifier != productionBundleIdentifier else { return browserDirectory }

        let namespace: String
        if let bundleIdentifier,
           !bundleIdentifier.isEmpty,
           bundleIdentifier.utf8.count <= 255,
           bundleIdentifier.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ segment in
               !segment.isEmpty && segment != "." && segment != ".."
                   && segment.unicodeScalars.allSatisfy { scalar in
                       let value = scalar.value
                       return (48...57).contains(value) || (65...90).contains(value)
                           || (97...122).contains(value) || value == 45
                   }
           }) {
            namespace = bundleIdentifier
        } else {
            namespace = "unknown-app"
        }

        return browserDirectory
            .appendingPathComponent("QA Profiles", isDirectory: true)
            .appendingPathComponent(namespace, isDirectory: true)
    }

    static func load(from directory: URL = defaultDirectory) -> BrowserSessionSnapshot? {
        read(from: directory.appendingPathComponent(fileName))
    }

    static func load(windowID: String, from directory: URL = defaultDirectory) -> BrowserSessionSnapshot? {
        guard let identifier = UUID(uuidString: windowID)?.uuidString.lowercased() else { return nil }
        let sessionsDirectory = directory.appendingPathComponent(sessionsDirectoryName, isDirectory: true)
        let sessionFile = sessionsDirectory.appendingPathComponent("\(identifier).json")
        if let snapshot = read(from: sessionFile) { return snapshot }

        // Migrate the pre-window session once. Moving the legacy file after the
        // atomic per-window write keeps the original recoverable if migration fails.
        let migratedFile = directory.appendingPathComponent("browser-session.migrated.json")
        guard !FileManager.default.fileExists(atPath: migratedFile.path) else { return nil }
        let legacyFile = directory.appendingPathComponent(legacyFileName)
        guard let legacy = read(from: legacyFile) else { return nil }
        do {
            try save(legacy, to: directory, windowID: identifier)
            try FileManager.default.moveItem(at: legacyFile, to: migratedFile)
            return legacy
        } catch {
            return nil
        }
    }

    @discardableResult
    static func restoreWindow(
        _ windowID: String,
        in directory: URL = defaultDirectory
    ) throws -> BrowserSessionSnapshot? {
        guard let identifier = normalizedWindowID(windowID) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let snapshot = load(windowID: identifier, from: directory)
        try registerWindow(identifier, activate: true, in: directory)
        return snapshot
    }

    static func loadManifest(from directory: URL = defaultDirectory) -> BrowserSessionManifest? {
        let file = directory.appendingPathComponent(manifestFileName)
        guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= 16_384,
              let data = try? Data(contentsOf: file),
              let manifest = try? JSONDecoder().decode(BrowserSessionManifest.self, from: data),
              manifest.version == BrowserSessionManifest.currentVersion,
              manifest.windows.count <= maximumWindows else { return nil }
        let ids = manifest.windows.compactMap(normalizedWindowID)
        guard ids.count == manifest.windows.count, Set(ids).count == ids.count else { return nil }
        let active = manifest.activeWindowID.flatMap(normalizedWindowID)
        guard manifest.activeWindowID == nil || active != nil,
              active.map(ids.contains) ?? true else { return nil }
        return BrowserSessionManifest(windows: ids, activeWindowID: active)
    }

    static func saveManifest(_ manifest: BrowserSessionManifest, to directory: URL = defaultDirectory) throws {
        guard manifest.version == BrowserSessionManifest.currentVersion,
              manifest.windows.count <= maximumWindows else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let ids = manifest.windows.compactMap(normalizedWindowID)
        guard ids.count == manifest.windows.count, Set(ids).count == ids.count else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let active = manifest.activeWindowID.flatMap(normalizedWindowID)
        guard manifest.activeWindowID == nil || active != nil,
              active.map(ids.contains) ?? true else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try write(
            BrowserSessionManifest(windows: ids, activeWindowID: active),
            to: directory.appendingPathComponent(manifestFileName)
        )
    }

    static func registerWindow(
        _ windowID: String,
        activate: Bool,
        in directory: URL = defaultDirectory
    ) throws {
        guard let id = normalizedWindowID(windowID) else { throw CocoaError(.fileWriteInvalidFileName) }
        let manifestURL = directory.appendingPathComponent(manifestFileName)
        var manifest: BrowserSessionManifest
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            guard let stored = loadManifest(from: directory) else { throw CocoaError(.fileReadCorruptFile) }
            manifest = stored
        } else {
            manifest = BrowserSessionManifest()
        }
        if !manifest.windows.contains(id) {
            guard manifest.windows.count < maximumWindows else { throw BrowserSessionStoreError.tooManyWindows }
            manifest.windows.append(id)
        }
        if activate || manifest.activeWindowID == nil { manifest.activeWindowID = id }
        try saveManifest(manifest, to: directory)
    }

    static func markWindowActive(_ windowID: String, in directory: URL = defaultDirectory) throws {
        guard let id = normalizedWindowID(windowID),
              var manifest = loadManifest(from: directory),
              manifest.windows.contains(id) else { throw CocoaError(.fileWriteInvalidFileName) }
        manifest.activeWindowID = id
        try saveManifest(manifest, to: directory)
    }

    static func remove(windowID: String, from directory: URL = defaultDirectory) throws {
        guard let identifier = normalizedWindowID(windowID) else { throw CocoaError(.fileWriteInvalidFileName) }
        if var manifest = loadManifest(from: directory), manifest.windows.contains(identifier) {
            manifest.windows.removeAll { $0 == identifier }
            if manifest.activeWindowID == identifier { manifest.activeWindowID = manifest.windows.last }
            try saveManifest(manifest, to: directory)
        }
        let sessionFile = directory
            .appendingPathComponent(sessionsDirectoryName, isDirectory: true)
            .appendingPathComponent("\(identifier).json")
        guard FileManager.default.fileExists(atPath: sessionFile.path) else { return }
        try FileManager.default.removeItem(at: sessionFile)
    }

    private static func read(from file: URL) -> BrowserSessionSnapshot? {
        guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= maximumFileBytes,
              let data = try? Data(contentsOf: file),
              let snapshot = try? JSONDecoder().decode(BrowserSessionSnapshot.self, from: data) else { return nil }
        return normalized(snapshot)
    }

    static func save(_ snapshot: BrowserSessionSnapshot, to directory: URL = defaultDirectory) throws {
        try write(normalized(snapshot), to: directory.appendingPathComponent(fileName))
    }

    static func save(_ snapshot: BrowserSessionSnapshot, to directory: URL = defaultDirectory, windowID: String) throws {
        guard let identifier = UUID(uuidString: windowID)?.uuidString.lowercased() else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let sessionsDirectory = directory.appendingPathComponent(sessionsDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: sessionsDirectory.path)
        try write(normalized(snapshot), to: sessionsDirectory.appendingPathComponent("\(identifier).json"))
    }

    private static func write<Value: Encodable>(_ value: Value, to file: URL) throws {
        let manager = FileManager.default
        let directory = file.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let data = try JSONEncoder().encode(value)
        try data.write(to: file, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    private static func normalizedWindowID(_ value: String) -> String? {
        UUID(uuidString: value)?.uuidString.lowercased()
    }

    private static func normalized(_ snapshot: BrowserSessionSnapshot) -> BrowserSessionSnapshot {
        let savedTabs = Array(snapshot.tabs.prefix(maximumTabs)).map { tab in
            let safeURL = tab.url.flatMap { url in
                ["http", "https"].contains(url.scheme?.lowercased() ?? "")
                    && url.user == nil && url.password == nil && url.absoluteString.utf8.count <= 4_096
                    ? url : nil
            }
            return BrowserSessionTab(id: tab.id, title: boundedTitle(tab.title), url: safeURL)
        }
        let tabs = savedTabs.isEmpty ? [BrowserSessionTab(title: "새 탭")] : savedTabs
        let selected = snapshot.selectedTabID.flatMap { id in tabs.contains { $0.id == id } ? id : nil }
        return BrowserSessionSnapshot(tabs: tabs, selectedTabID: selected ?? tabs.first?.id)
    }

    private static func boundedTitle(_ title: String) -> String {
        var scalars = String.UnicodeScalarView()
        var byteCount = 0
        for scalar in title.unicodeScalars {
            let scalarBytes = scalar.utf8.count
            guard byteCount + scalarBytes <= maximumTitleUTF8Bytes else { break }
            scalars.append(scalar)
            byteCount += scalarBytes
        }
        return String(scalars)
    }
}
