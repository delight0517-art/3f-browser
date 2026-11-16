import XCTest
@testable import ThreeFBrowser

@MainActor
final class AddressBarAutocompleteTests: XCTestCase {
    func testAutocompleteMatchesByHostAndTitleCaseInsensitively() {
        let preferences = BrowserPreferenceStore(
            environment: ["THREEF_BROWSER_QA_PROFILE_DIRECTORY": FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path],
            defaults: UserDefaults(suiteName: UUID().uuidString)!
        )
        let model = BrowserModel(preferences: preferences)

        model.pageDidNavigate(to: URL(string: "https://nid.naver.com/nidlogin.login")!, title: "네이버 로그인")
        model.pageDidNavigate(to: URL(string: "https://www.google.com/search?q=swift")!, title: "Google 검색")
        model.pageDidNavigate(to: URL(string: "https://github.com/apple/swift")!, title: "GitHub - apple/swift")

        // Search by korean title
        let naverMatches = model.autocompleteSuggestions(for: "네이버")
        XCTAssertEqual(naverMatches.count, 1)
        XCTAssertEqual(naverMatches.first?.url, "https://nid.naver.com/nidlogin.login")
        XCTAssertEqual(naverMatches.first?.title, "네이버 로그인")

        // Search by domain fragment case-insensitively
        let nidMatches = model.autocompleteSuggestions(for: "NID.NAVER")
        XCTAssertEqual(nidMatches.count, 1)
        XCTAssertEqual(nidMatches.first?.url, "https://nid.naver.com/nidlogin.login")

        // Search common keyword "swift"
        let swiftMatches = model.autocompleteSuggestions(for: "swift")
        XCTAssertEqual(swiftMatches.count, 2)

        // Empty query returns empty
        XCTAssertTrue(model.autocompleteSuggestions(for: "").isEmpty)
        XCTAssertTrue(model.autocompleteSuggestions(for: "   ").isEmpty)
    }

    func testAutocompleteLimitsToSixResults() {
        let preferences = BrowserPreferenceStore(
            environment: ["THREEF_BROWSER_QA_PROFILE_DIRECTORY": FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path],
            defaults: UserDefaults(suiteName: UUID().uuidString)!
        )
        let model = BrowserModel(preferences: preferences)

        for i in 1...10 {
            model.pageDidNavigate(to: URL(string: "https://example\(i).com")!, title: "Example \(i)")
        }

        let suggestions = model.autocompleteSuggestions(for: "example")
        XCTAssertEqual(suggestions.count, 6)
    }
}
