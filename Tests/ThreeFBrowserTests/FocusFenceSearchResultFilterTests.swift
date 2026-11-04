import Foundation
import JavaScriptCore
import XCTest
@testable import ThreeFBrowser

final class FocusFenceSearchResultFilterTests: XCTestCase {
    func testSearchResultHostsAndPathsAreRecognized() {
        XCTAssertTrue(FocusFenceSearchResultFilter.isSearchResultsURL(URL(string: "https://www.google.com/search?q=test")!))
        XCTAssertTrue(FocusFenceSearchResultFilter.isSearchResultsURL(URL(string: "https://www.google.co.kr/search?q=test")!))
        XCTAssertTrue(FocusFenceSearchResultFilter.isSearchResultsURL(URL(string: "https://www.bing.com/search?q=test")!))
        XCTAssertTrue(FocusFenceSearchResultFilter.isSearchResultsURL(URL(string: "https://duckduckgo.com/?q=test")!))
        XCTAssertFalse(FocusFenceSearchResultFilter.isSearchResultsURL(URL(string: "https://example.com/search?q=test")!))
        XCTAssertFalse(FocusFenceSearchResultFilter.isSearchResultsURL(URL(string: "https://www.google.com/maps")!))
    }

    func testGoogleImagesSearchURLsAreRecognizedAndUseImageResultHandling() throws {
        let imageSearch = try XCTUnwrap(URL(string: "https://www.google.co.kr/search?q=blocked.example&tbm=isch"))
        XCTAssertTrue(FocusFenceSearchResultFilter.isSearchResultsURL(imageSearch))
        XCTAssertTrue(FocusFenceSearchResultFilter.isGoogleImagesResultsURL(imageSearch))
        XCTAssertFalse(FocusFenceSearchResultFilter.isGoogleImagesResultsURL(
            URL(string: "https://www.google.co.kr/search?q=blocked.example")!
        ))
        XCTAssertFalse(FocusFenceSearchResultFilter.isGoogleImagesResultsURL(
            URL(string: "https://example.com/search?q=x&tbm=isch")!
        ))

        let rules = Data(#"{"blockedDomains":["blocked.example"],"blockedUrlParts":[],"keywords":[],"blockExceptions":[]}"#.utf8)
        let script = try XCTUnwrap(FocusFenceSearchResultFilter.script(for: imageSearch, rules: rules))
        XCTAssertTrue(script.contains("div.isv-r"))
        XCTAssertTrue(script.contains("imgrefurl"))
        XCTAssertTrue(script.contains("searchParams.get('tbm') === 'isch'"))
    }

    func testClassifierBlocksConfiguredDestinationsAndAdultDirectoriesButKeepsNeutralMentions() throws {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript(FocusFenceSearchResultFilter.classifierSource)

        XCTAssertTrue(classify(context, host: "sub.adult.example", path: "/page", title: "Ordinary page", snippet: ""))
        XCTAssertTrue(classify(context, host: "safe.example", path: "/forbidden-tag", title: "Ordinary page", snippet: ""))
        XCTAssertTrue(classify(context, host: "directory.example", path: "/", title: "Adult domains list", snippet: "A list of porn websites and .porn extensions"))
        XCTAssertTrue(classify(context, host: "list.example", path: "/ips", title: "Porn IP address list", snippet: "Adult site IP addresses"))
        XCTAssertFalse(classify(context, host: "neutral.example", path: "/article", title: "Understanding the .porn top-level domain", snippet: "A neutral technical explanation."))
        XCTAssertFalse(classify(context, host: "neutral.example", path: "/article", title: "How browsers handle adult content", snippet: "This article discusses safety controls."))

        let search = SearchProvider.google.searchURL(for: "porn websites")
        XCTAssertTrue(SearchProvider.google.ownsSearchURL(try XCTUnwrap(search)))
    }

    func testFilterScriptRequiresValidRulesAndSearchResultsPage() {
        let rules = Data(#"{"blockedDomains":["adult.example"],"blockedUrlParts":[],"keywords":[],"blockExceptions":[]}"#.utf8)
        let searchURL = URL(string: "https://www.google.com/search?q=adult.example")!
        XCTAssertNotNil(FocusFenceSearchResultFilter.script(for: searchURL, rules: rules))
        XCTAssertNil(FocusFenceSearchResultFilter.script(for: URL(string: "https://example.com/search")!, rules: rules))
        XCTAssertNil(FocusFenceSearchResultFilter.script(for: searchURL, rules: Data("{}".utf8)))
    }

    private func classify(_ context: JSContext, host: String, path: String, title: String, snippet: String) -> Bool {
        let rules = #"{"blockedDomains":["adult.example"],"blockedUrlParts":["forbidden-tag"],"keywords":["directory"],"blockExceptions":[]}"#
        let arguments = [host, path, title, snippet].map(Self.javascriptString).joined(separator: ",")
        let result = context.evaluateScript("(() => threefShouldHideResult(\(arguments), \(rules)) )()")
        return result?.toBool() ?? false
    }

    private static func javascriptString(_ value: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [value])) ?? Data("[\"\"]".utf8)
        let array = String(data: data, encoding: .utf8) ?? "[\"\"]"
        return String(array.dropFirst().dropLast())
    }
}
