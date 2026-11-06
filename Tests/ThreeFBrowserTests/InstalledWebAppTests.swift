import Foundation
import XCTest
@testable import ThreeFBrowser

@MainActor
final class InstalledWebAppTests: XCTestCase {
    func testWebsiteCanBeInstalledAndRemovedAsStandaloneApp() throws {
        let model = BrowserModel()
        let url = try XCTUnwrap(URL(string: "https://gemini.google.com/app?3f-install-test=\(UUID().uuidString)"))
        let app = try XCTUnwrap(model.installCurrentWebsiteAsApp(title: "Gemini", url: url))
        defer { model.removeInstalledWebApp(app) }

        XCTAssertTrue(app.isValid)
        XCTAssertEqual(app.destination, url)
        XCTAssertTrue(model.installedWebApps.contains(app))
        XCTAssertTrue(BrowserModel().installedWebApps.contains(app), "installed web apps should survive BrowserModel recreation")
        XCTAssertEqual(model.installCurrentWebsiteAsApp(title: "Duplicate", url: url), app)
        XCTAssertEqual(model.installedWebApps.filter { $0.id == app.id }.count, 1)

        model.removeInstalledWebApp(app)
        XCTAssertFalse(model.installedWebApps.contains(app))
        XCTAssertFalse(BrowserModel().installedWebApps.contains(app), "removal should persist")
    }

    func testInstalledWebAppRejectsNonHTTPSAndCredentialBearingURLs() {
        XCTAssertFalse(InstalledWebApp(title: "Gemini", url: "http://gemini.google.com").isValid)
        XCTAssertFalse(InstalledWebApp(title: "Gemini", url: "https://user:pass@gemini.google.com").isValid)
        XCTAssertFalse(InstalledWebApp(title: " ", url: "https://gemini.google.com").isValid)
    }
}
