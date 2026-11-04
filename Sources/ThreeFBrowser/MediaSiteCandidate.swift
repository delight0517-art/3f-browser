import Foundation

struct MediaSiteCandidate: Identifiable, Equatable {
    enum Category: Equatable {
        case liveVideo
        case webtoon

        var label: String {
            switch self {
            case .liveVideo: "영상·방송"
            case .webtoon: "웹툰"
            }
        }
    }

    let domain: String
    let category: Category
    let platformName: String

    var id: String { domain }

    func scheduleRequestMessage(after timeWindow: String) -> String {
        let timeWindow = timeWindow.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !timeWindow.isEmpty else { return "" }
        let escapedDomain = NSRegularExpression.escapedPattern(for: domain)
        let domainPattern = #"(?<![a-zA-Z0-9.-])(?:[a-zA-Z0-9-]+\.)*\#(escapedDomain)(?![a-zA-Z0-9.-])"#
        if timeWindow.range(of: domainPattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return timeWindow
        }
        return "\(timeWindow) \(domain) 차단"
    }

    static func detect(
        host rawHost: String,
        blockedDomains: [String],
        youtubeQuotaBlocked: Bool
    ) -> MediaSiteCandidate? {
        let host = normalize(rawHost)
        guard let candidate = platforms.first(where: { isWithin(host, $0.domain) }),
              !blockedDomains.contains(where: { hostIsBlocked(host, by: normalize($0)) }) else {
            return nil
        }

        let relatedDomainIsBlocked = blockedDomains.contains { rule in
            let rule = normalize(rule)
            return platforms.contains {
                $0.category == candidate.category && isWithin(rule, $0.domain)
            }
        }
        let relatedYoutubeIsBlocked = candidate.category == .liveVideo && youtubeQuotaBlocked
        guard relatedDomainIsBlocked || relatedYoutubeIsBlocked else { return nil }
        return MediaSiteCandidate(
            domain: candidate.domain,
            category: candidate.category,
            platformName: candidate.name
        )
    }

    private static let platforms: [(domain: String, name: String, category: Category)] = [
        ("youtube.com", "YouTube", .liveVideo),
        ("twitch.tv", "Twitch", .liveVideo),
        ("chzzk.naver.com", "치지직", .liveVideo),
        ("sooplive.com", "SOOP", .liveVideo),
        ("comic.naver.com", "네이버 웹툰", .webtoon),
        ("series.naver.com", "네이버 시리즈", .webtoon),
        ("page.kakao.com", "카카오페이지", .webtoon),
        ("webtoon.kakao.com", "카카오웹툰", .webtoon),
        ("lezhin.com", "레진코믹스", .webtoon),
        ("toomics.com", "투믹스", .webtoon),
        ("ridibooks.com", "리디", .webtoon)
    ]

    private static func normalize(_ value: String) -> String {
        value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private static func isWithin(_ host: String, _ domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }

    private static func hostIsBlocked(_ host: String, by rule: String) -> Bool {
        !rule.isEmpty && isWithin(host, rule)
    }
}
