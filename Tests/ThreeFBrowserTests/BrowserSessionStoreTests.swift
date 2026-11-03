import Foundation
import XCTest
@testable import ThreeFBrowser

final class BrowserSessionStoreTests: XCTestCase {
    func testProductionBundleKeepsExistingSessionDirectory() {
        let support = URL(fileURLWithPath: "/qa/application-support", isDirectory: true)
        XCTAssertEqual(
            BrowserSessionStore.directory(
                applicationSupportDirectory: support,
                bundleIdentifier: "com.rogan.threef.browser"
            ),
            support.appendingPathComponent("3F Browser", isDirectory: true)
        )
    }

    func testNonProductionBundleUsesAValidatedIsolatedSessionDirectory() {
        let support = URL(fileURLWithPath: "/qa/application-support", isDirectory: true)
        let first = BrowserSessionStore.directory(
            applicationSupportDirectory: support,
            bundleIdentifier: "com.rogan.threef.browser.qa.first"
        )
        let second = BrowserSessionStore.directory(
            applicationSupportDirectory: support,
            bundleIdentifier: "com.rogan.threef.browser.qa.second"
        )
        let invalid = BrowserSessionStore.directory(
            applicationSupportDirectory: support,
            bundleIdentifier: "../../outside"
        )

        XCTAssertNotEqual(first, support.appendingPathComponent("3F Browser", isDirectory: true))
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.path.hasSuffix("3F Browser/QA Profiles/com.rogan.threef.browser.qa.first"))
        XCTAssertTrue(invalid.path.hasSuffix("3F Browser/QA Profiles/unknown-app"))
    }

    func testSaveAndLoadRestoresTabsAndSelectedTab() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = BrowserSessionTab(title: "Example", url: URL(string: "https://example.com/path"))
        let second = BrowserSessionTab(title: "새 탭")
        let expected = BrowserSessionSnapshot(tabs: [first, second], selectedTabID: second.id)

        try BrowserSessionStore.save(expected, to: directory)

        XCTAssertEqual(BrowserSessionStore.load(from: directory), expected)
        let directoryMode = try XCTUnwrap((try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber)?.intValue)
        let file = directory.appendingPathComponent("browser-session.json")
        let fileMode = try XCTUnwrap((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue)
        XCTAssertEqual(directoryMode & 0o777, 0o700)
        XCTAssertEqual(fileMode & 0o777, 0o600)
    }

    func testLoadRejectsInvalidSchemeAndFallsBackForCorruptData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let invalid = BrowserSessionTab(title: "Unsafe", url: URL(string: "file:///etc/passwd"))
        try BrowserSessionStore.save(BrowserSessionSnapshot(tabs: [invalid], selectedTabID: invalid.id), to: directory)

        let restored = try XCTUnwrap(BrowserSessionStore.load(from: directory))
        XCTAssertNil(restored.tabs.first?.url)

        try Data("not json".utf8).write(to: directory.appendingPathComponent("browser-session.json"))
        XCTAssertNil(BrowserSessionStore.load(from: directory))
    }

    func testEmptySnapshotRestoresOneSelectedNewTab() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        try BrowserSessionStore.save(BrowserSessionSnapshot(tabs: [], selectedTabID: nil), to: directory)

        let restored = try XCTUnwrap(BrowserSessionStore.load(from: directory))
        XCTAssertEqual(restored.tabs.count, 1)
        XCTAssertEqual(restored.tabs[0].title, "새 탭")
        XCTAssertEqual(restored.selectedTabID, restored.tabs[0].id)
    }

    func testSessionNearMaximumTabAndURLSizesCanBeRestored() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let prefix = "https://example.com/"
        let longURL = try XCTUnwrap(URL(string: prefix + String(repeating: "a", count: 4_096 - prefix.utf8.count)))
        let tabs = (0..<50).map { _ in BrowserSessionTab(title: "Example", url: longURL) }
        let snapshot = BrowserSessionSnapshot(tabs: tabs, selectedTabID: tabs[0].id)

        try BrowserSessionStore.save(snapshot, to: directory)

        XCTAssertEqual(BrowserSessionStore.load(from: directory)?.tabs.count, 50)
    }

    func testByteHeavySessionTitlesAndURLsRemainRestorable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let longURL = try XCTUnwrap(URL(string: "https://example.com/" + String(repeating: "/", count: 4_000)))
        let controlHeavyTitle = String(repeating: "\u{0001}", count: 160)
        let tabs = (0..<50).map { _ in BrowserSessionTab(title: controlHeavyTitle, url: longURL) }
        let snapshot = BrowserSessionSnapshot(tabs: tabs, selectedTabID: tabs[0].id)

        try BrowserSessionStore.save(snapshot, to: directory, windowID: UUID().uuidString)

        let sessionFile = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("browser-sessions"), includingPropertiesForKeys: nil).first)
        let fileSize = try XCTUnwrap(sessionFile.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        XCTAssertLessThanOrEqual(fileSize, 512_000)
        let restored = try XCTUnwrap(BrowserSessionStore.load(
            windowID: sessionFile.deletingPathExtension().lastPathComponent,
            from: directory
        ))
        XCTAssertEqual(restored.tabs.count, 50)
        XCTAssertEqual(restored.tabs[0].title.utf8.count, 120)
    }

    func testOversizedMultibyteURLIsDroppedByUTF8ByteLimit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let oversizedURL = try XCTUnwrap(URL(string: "https://example.com/" + String(repeating: "é", count: 1_000)))
        XCTAssertGreaterThan(oversizedURL.absoluteString.utf8.count, 4_096)
        let tab = BrowserSessionTab(title: "Large URL", url: oversizedURL)

        try BrowserSessionStore.save(
            BrowserSessionSnapshot(tabs: [tab], selectedTabID: tab.id),
            to: directory,
            windowID: UUID().uuidString
        )

        let windowID = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("browser-sessions"), includingPropertiesForKeys: nil).first?.deletingPathExtension().lastPathComponent)
        XCTAssertNil(BrowserSessionStore.load(windowID: windowID, from: directory)?.tabs.first?.url)
    }

    func testWindowSessionsDoNotOverwriteEachOther() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstWindowID = UUID().uuidString
        let secondWindowID = UUID().uuidString
        let firstTab = BrowserSessionTab(title: "First", url: URL(string: "https://first.example"))
        let secondTab = BrowserSessionTab(title: "Second", url: URL(string: "https://second.example"))
        let first = BrowserSessionSnapshot(tabs: [firstTab], selectedTabID: firstTab.id)
        let second = BrowserSessionSnapshot(tabs: [secondTab], selectedTabID: secondTab.id)

        try BrowserSessionStore.save(first, to: directory, windowID: firstWindowID)
        try BrowserSessionStore.save(second, to: directory, windowID: secondWindowID)

        XCTAssertEqual(BrowserSessionStore.load(windowID: firstWindowID, from: directory), first)
        XCTAssertEqual(BrowserSessionStore.load(windowID: secondWindowID, from: directory), second)
        let sessionsDirectory = directory.appendingPathComponent("browser-sessions")
        let directoryMode = try XCTUnwrap((try FileManager.default.attributesOfItem(atPath: sessionsDirectory.path)[.posixPermissions] as? NSNumber)?.intValue)
        XCTAssertEqual(directoryMode & 0o777, 0o700)
    }

    func testRemovingClosedWindowSessionPreservesOtherWindows() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let closedWindowID = UUID().uuidString
        let openWindowID = UUID().uuidString
        let closedTab = BrowserSessionTab(title: "Closed", url: URL(string: "https://closed.example"))
        let openTab = BrowserSessionTab(title: "Open", url: URL(string: "https://open.example"))
        try BrowserSessionStore.save(
            BrowserSessionSnapshot(tabs: [closedTab], selectedTabID: closedTab.id),
            to: directory,
            windowID: closedWindowID
        )
        try BrowserSessionStore.save(
            BrowserSessionSnapshot(tabs: [openTab], selectedTabID: openTab.id),
            to: directory,
            windowID: openWindowID
        )
        try BrowserSessionStore.saveManifest(
            BrowserSessionManifest(windows: [closedWindowID, openWindowID], activeWindowID: closedWindowID),
            to: directory
        )

        try BrowserSessionStore.remove(windowID: closedWindowID, from: directory)

        XCTAssertNil(BrowserSessionStore.load(windowID: closedWindowID, from: directory))
        XCTAssertEqual(
            BrowserSessionStore.load(windowID: openWindowID, from: directory),
            BrowserSessionSnapshot(tabs: [openTab], selectedTabID: openTab.id)
        )
        XCTAssertEqual(
            BrowserSessionStore.loadManifest(from: directory),
            BrowserSessionManifest(windows: [openWindowID.lowercased()], activeWindowID: openWindowID.lowercased())
        )
    }

    func testManifestPreservesWindowOrderAndTracksActiveWindow() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = UUID().uuidString
        let second = UUID().uuidString
        let third = UUID().uuidString

        try BrowserSessionStore.registerWindow(first, activate: true, in: directory)
        try BrowserSessionStore.registerWindow(second, activate: false, in: directory)
        try BrowserSessionStore.registerWindow(third, activate: true, in: directory)
        try BrowserSessionStore.markWindowActive(second, in: directory)

        XCTAssertEqual(
            BrowserSessionStore.loadManifest(from: directory),
            BrowserSessionManifest(windows: [first, second, third].map { UUID(uuidString: $0)!.uuidString.lowercased() },
                                   activeWindowID: UUID(uuidString: second)!.uuidString.lowercased())
        )
        let file = directory.appendingPathComponent("browser-session-manifest.json")
        let mode = try XCTUnwrap((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue)
        XCTAssertEqual(mode & 0o777, 0o600)
    }

    func testRestoringWindowRegistersItAndMarksItActiveWithoutChangingOrder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = UUID().uuidString
        let restored = UUID().uuidString
        let firstTab = BrowserSessionTab(title: "First", url: URL(string: "https://first.example"))
        let restoredTab = BrowserSessionTab(title: "Restored", url: URL(string: "https://restored.example"))
        try BrowserSessionStore.save(
            BrowserSessionSnapshot(tabs: [firstTab], selectedTabID: firstTab.id), to: directory, windowID: first
        )
        try BrowserSessionStore.save(
            BrowserSessionSnapshot(tabs: [restoredTab], selectedTabID: restoredTab.id), to: directory, windowID: restored
        )
        try BrowserSessionStore.saveManifest(BrowserSessionManifest(windows: [first], activeWindowID: first), to: directory)

        let snapshot = try BrowserSessionStore.restoreWindow(restored, in: directory)

        XCTAssertEqual(snapshot, BrowserSessionSnapshot(tabs: [restoredTab], selectedTabID: restoredTab.id))
        XCTAssertEqual(
            BrowserSessionStore.loadManifest(from: directory),
            BrowserSessionManifest(
                windows: [first, restored].map { UUID(uuidString: $0)!.uuidString.lowercased() },
                activeWindowID: UUID(uuidString: restored)!.uuidString.lowercased()
            )
        )
    }

    func testRestoringNewWindowRegistersAnEmptyWindow() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let windowID = UUID().uuidString

        XCTAssertNil(try BrowserSessionStore.restoreWindow(windowID, in: directory))

        XCTAssertEqual(
            BrowserSessionStore.loadManifest(from: directory),
            BrowserSessionManifest(windows: [UUID(uuidString: windowID)!.uuidString.lowercased()],
                                   activeWindowID: UUID(uuidString: windowID)!.uuidString.lowercased())
        )
    }

    func testManifestRejectsDuplicateWindowIDsAndUnknownVersions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID().uuidString.lowercased()
        let file = directory.appendingPathComponent("browser-session-manifest.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try JSONEncoder().encode(BrowserSessionManifest(windows: [id, id], activeWindowID: id)).write(to: file)
        XCTAssertNil(BrowserSessionStore.loadManifest(from: directory))

        try Data("{\"version\":99,\"windows\":[\"\(id)\"],\"activeWindowID\":\"\(id)\"}".utf8).write(to: file)
        XCTAssertNil(BrowserSessionStore.loadManifest(from: directory))
    }

    func testRemovingSessionRejectsInvalidWindowIdentifier() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertThrowsError(try BrowserSessionStore.remove(windowID: "../../unsafe", from: directory))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testLegacySessionMigratesToOnlyFirstWindowAndRemainsRecoverable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let tab = BrowserSessionTab(title: "Legacy", url: URL(string: "https://legacy.example"))
        let legacy = BrowserSessionSnapshot(tabs: [tab], selectedTabID: tab.id)
        let firstWindowID = UUID().uuidString

        try BrowserSessionStore.save(legacy, to: directory)

        XCTAssertEqual(BrowserSessionStore.load(windowID: firstWindowID, from: directory), legacy)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("browser-session.migrated.json").path))
        XCTAssertNil(BrowserSessionStore.load(windowID: UUID().uuidString, from: directory))

        let restoredLegacy = BrowserSessionTab(title: "Restored old copy")
        try BrowserSessionStore.save(
            BrowserSessionSnapshot(tabs: [restoredLegacy], selectedTabID: restoredLegacy.id),
            to: directory
        )
        XCTAssertNil(BrowserSessionStore.load(windowID: UUID().uuidString, from: directory))
        XCTAssertEqual(BrowserSessionStore.load(windowID: firstWindowID, from: directory), legacy)
    }

    func testWindowSessionRejectsInvalidWindowIdentifier() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let tab = BrowserSessionTab(title: "Safe")

        XCTAssertNil(BrowserSessionStore.load(windowID: "../../unsafe", from: directory))
        XCTAssertThrowsError(try BrowserSessionStore.save(
            BrowserSessionSnapshot(tabs: [tab], selectedTabID: tab.id),
            to: directory,
            windowID: "../../unsafe"
        ))
    }
}
