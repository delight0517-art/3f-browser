import Foundation

enum AddressBarNavigationRequest {
    static func resolve(_ input: String, searchProvider: SearchProvider) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }

        if let components = URLComponents(string: text),
           let scheme = components.scheme?.lowercased(),
           ["http", "https"].contains(scheme),
           let host = components.host, !host.isEmpty,
           components.user == nil, components.password == nil {
            return components.url
        }

        if let url = URL(string: text), url.isFileURL, url.user == nil, url.password == nil {
            return url
        }

        if (text.hasPrefix("/") || text.hasPrefix("~/")),
           let path = (text as NSString).expandingTildeInPath as String?,
           FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        // Explicit web or file URLs must not silently become search queries when malformed
        // or when they contain credentials.
        if text.range(of: #"^(https?|file)://"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return nil
        }

        if !text.contains(where: \.isWhitespace), !text.contains("@"), !text.contains("://"),
           let candidate = URL(string: "https://\(text)"),
           let host = candidate.host,
           host == "localhost" || host.contains("."),
           candidate.user == nil, candidate.password == nil {
            return candidate
        }
        return searchProvider.searchURL(for: text)
    }
}
