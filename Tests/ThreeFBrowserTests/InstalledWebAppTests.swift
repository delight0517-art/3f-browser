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

    func testQuickLinkAppResolutionAndActionAvailability() throws {
        let model = BrowserModel()
        let quickLinkURL = try XCTUnwrap(URL(string: "https://gemini.google.com/app?test-ql=\(UUID().uuidString)"))
        let quickLink = BrowserQuickLink(title: "Gemini", url: quickLinkURL.absoluteString)

        // 미설치 상태 확인: 대상 destination을 매칭하는 설치 웹앱이 없어야 함
        let uninstalledApp = model.installedWebApps.first { $0.destination == quickLink.destination }
        XCTAssertNil(uninstalledApp, "미설치 상태인 퀵링크는 matching 설치 앱이 없어야 함")

        // 웹앱 설치 수행
        let installedApp = try XCTUnwrap(model.installCurrentWebsiteAsApp(title: quickLink.title, url: quickLink.destination))
        defer { model.removeInstalledWebApp(installedApp) }

        // 설치 완료 상태 확인: destination 기반으로 설치 앱 창 열기가 가능한 매칭 앱이 식별되어야 함
        let resolvedApp = model.installedWebApps.first { $0.destination == quickLink.destination }
        XCTAssertNotNil(resolvedApp, "설치 후에는 퀵링크의 destination과 매치되는 웹앱이 존재해야 함")
        XCTAssertEqual(resolvedApp?.id, installedApp.id)
        XCTAssertEqual(resolvedApp?.destination, quickLinkURL)
    }
}
