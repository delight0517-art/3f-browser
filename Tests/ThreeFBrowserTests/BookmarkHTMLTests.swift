import Foundation
import XCTest
@testable import ThreeFBrowser

final class BookmarkHTMLTests: XCTestCase {
    func testImportsSafeHTTPSBookmarksAndDecodesHTML() throws {
        let html = #"""
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <DL><p>
        <DT><A HREF="https://example.com/?a=1&amp;b=2">A &amp; B</A>
        <DT><A href='http://insecure.example/'>Insecure</A>
        <DT><A HREF="javascript:alert(1)">Script</A>
        <DT><A HREF="https://user:pass@example.com/">Credential URL</A>
        </DL>
        """#

        let bookmarks = BookmarkHTML.import(Data(html.utf8))

        XCTAssertEqual(bookmarks, [BrowserQuickLink(title: "A & B", url: "https://example.com/?a=1&b=2")])
    }

    func testExportEscapesValuesAndRoundTrips() {
        let input = [BrowserQuickLink(title: "Research & Notes", url: "https://example.com/?a=1&b=2")]

        let html = String(decoding: BookmarkHTML.export(input), as: UTF8.self)
        let imported = BookmarkHTML.import(Data(html.utf8))

        XCTAssertTrue(html.contains("Research &amp; Notes"))
        XCTAssertTrue(html.contains("a=1&amp;b=2"))
        XCTAssertEqual(imported, input)
    }

    func testRejectsOversizedFilesAndDeduplicatesURLs() {
        let oversized = Data(repeating: 0x20, count: BookmarkHTML.maximumFileSize + 1)
        XCTAssertTrue(BookmarkHTML.import(oversized).isEmpty)

        let duplicateHTML = #"<a href="https://example.com">One</a><a href="https://example.com">Two</a>"#
        XCTAssertEqual(BookmarkHTML.import(Data(duplicateHTML.utf8)).map(\.title), ["One"])
    }
}
