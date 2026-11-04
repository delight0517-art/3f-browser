import Foundation

struct ReaderArticle: Decodable, Identifiable {
    let title: String
    let byline: String
    let siteName: String
    let excerpt: String
    let text: String
    let sourceURL: String

    var id: String { sourceURL }
}
