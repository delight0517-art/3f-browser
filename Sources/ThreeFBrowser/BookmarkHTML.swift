import Foundation

/// Interchanges the flat HTTPS bookmark set using Firefox/Chromium-compatible Netscape Bookmark HTML.
enum BookmarkHTML {
    static let maximumFileSize = 5 * 1024 * 1024
    static let maximumBookmarks = 100

    static func export(_ bookmarks: [BrowserQuickLink]) -> Data {
        let entries = bookmarks.filter(\.isValid).prefix(maximumBookmarks).map { bookmark in
            "<DT><A HREF=\"\(escape(bookmark.url))\">\(escape(bookmark.title))</A>"
        }.joined(separator: "\n")
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
        <TITLE>3F Browser Bookmarks</TITLE>
        <H1>3F Browser Bookmarks</H1>
        <DL><p>
        \(entries)
        </DL><p>
        """
        return Data(html.utf8)
    }

    static func `import`(_ data: Data) -> [BrowserQuickLink] {
        guard data.count <= maximumFileSize,
              let html = String(data: data, encoding: .utf8) else { return [] }
        let anchorPattern = #"(?is)<a\b([^>]*)>(.*?)</a\s*>"#
        guard let anchorRegex = try? NSRegularExpression(pattern: anchorPattern) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var result: [BrowserQuickLink] = []
        var seen = Set<String>()

        for match in anchorRegex.matches(in: html, range: range) {
            guard result.count < maximumBookmarks,
                  let attributesRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html),
                  let url = href(in: String(html[attributesRange])),
                  let rawTitle = String(html[titleRange]).replacingOccurrences(
                    of: #"(?is)<[^>]*>"#, with: "", options: .regularExpression
                  ).nilIfEmpty,
                  let title = decodeEntities(rawTitle).nilIfEmpty else { continue }

            let link = BrowserQuickLink(title: String(title.prefix(40)), url: decodeEntities(url))
            guard link.isValid, seen.insert(link.url).inserted else { continue }
            result.append(link)
        }
        return result
    }

    private static func href(in attributes: String) -> String? {
        let pattern = #"(?is)\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: attributes, range: NSRange(attributes.startIndex..., in: attributes)) else { return nil }
        for index in 1...3 {
            if let range = Range(match.range(at: index), in: attributes) { return String(attributes[range]) }
        }
        return nil
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func decodeEntities(_ value: String) -> String {
        let pattern = #"&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos|nbsp);"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        let matches = regex.matches(in: value, range: NSRange(value.startIndex..., in: value))
        var decoded = value
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: decoded),
                  let entityRange = Range(match.range(at: 1), in: decoded) else { continue }
            let entity = String(decoded[entityRange])
            let replacement: String
            switch entity {
            case "amp": replacement = "&"
            case "lt": replacement = "<"
            case "gt": replacement = ">"
            case "quot": replacement = "\""
            case "apos": replacement = "'"
            case "nbsp": replacement = " "
            default:
                let scalarValue: UInt32?
                if entity.hasPrefix("#x") { scalarValue = UInt32(entity.dropFirst(2), radix: 16) }
                else { scalarValue = UInt32(entity.dropFirst()) }
                replacement = scalarValue.flatMap(Unicode.Scalar.init).map(String.init) ?? String(decoded[fullRange])
            }
            decoded.replaceSubrange(fullRange, with: replacement)
        }
        return decoded.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
