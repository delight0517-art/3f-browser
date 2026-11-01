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

enum BrowserSessionStore {
    private static let productionBundleIdentifier = "com.rogan.threef.browser"
    private static let fileName = "browser-session.json"
    private static let legacyFileName = "browser-session.json"
    private static let sessionsDirectoryName = "browser-sessions"
    private static let maximumTabs = 50
    private static let maximumTitleUTF8Bytes = 120
    private static let maximumFileBytes = 512_000

    static var defaultDirectory: URL {
        let applicationSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return directory(
            applicationSupportDirectory: applicationSupport,
            bundleIdentifier: Bundle.main.bundleIdentifier
        )
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

    private static func read(from file: URL) -> BrowserSessionSnapshot? {
        guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= maximumFileBytes,
              let data = try? Data(contentsOf: file),
              let snapshot = try? JSONDecoder().decode(BrowserSessionSnapshot.self, from: data) else { return nil }
        return normalized(snapshot)
    }

    static func save(_ snapshot: BrowserSessionSnapshot, to directory: URL = defaultDirectory) throws {
        try write(snapshot, to: directory.appendingPathComponent(fileName))
    }

    static func save(_ snapshot: BrowserSessionSnapshot, to directory: URL = defaultDirectory, windowID: String) throws {
        guard let identifier = UUID(uuidString: windowID)?.uuidString.lowercased() else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let sessionsDirectory = directory.appendingPathComponent(sessionsDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: sessionsDirectory.path)
        try write(snapshot, to: sessionsDirectory.appendingPathComponent("\(identifier).json"))
    }

    private static func write(_ snapshot: BrowserSessionSnapshot, to file: URL) throws {
        let manager = FileManager.default
        let directory = file.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let data = try JSONEncoder().encode(normalized(snapshot))
        try data.write(to: file, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
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
