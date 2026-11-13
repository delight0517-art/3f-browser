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

    func scheduleRequestMessage(
        after timeWindow: String,
        includeRelatedCategory: Bool = false
    ) -> String {
        let timeWindow = timeWindow.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !timeWindow.isEmpty else { return "" }
        if includeRelatedCategory, category == .liveVideo {
            return "\(timeWindow) 스트리밍 전체 차단"
        }
        let escapedDomain = NSRegularExpression.escapedPattern(for: domain)
        let domainPattern = #"(?<![a-zA-Z0-9.-])(?:[a-zA-Z0-9-]+\.)*\#(escapedDomain)(?![a-zA-Z0-9.-])"#
        if timeWindow.range(of: domainPattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return timeWindow
        }
        return "\(timeWindow) \(domain) 차단"
    }

    static func detect(
        host rawHost: String,
        path rawPath: String = "/",
        blockedDomains: [String],
        blockedUrlParts: [String] = [],
        youtubeQuotaBlocked: Bool
    ) -> MediaSiteCandidate? {
        let host = normalize(rawHost)
        let path = rawPath.lowercased()
        let address = host + path
        guard let candidate = platforms.first(where: {
                  isWithin(host, $0.domain) && routeMatches(path, allowed: $0.webtoonPaths)
              }),
              !blockedDomains.contains(where: { hostIsBlocked(host, by: normalize($0)) }),
              !blockedUrlParts.contains(where: { !normalize($0).isEmpty && address.contains(normalize($0)) }) else {
            return nil
        }

        let relatedDomainIsBlocked = blockedDomains.contains { rule in
            let rule = normalize(rule)
            return platforms.contains {
                $0.category == candidate.category && isWithin(rule, $0.domain)
            }
        }
        let relatedWebtoonRouteIsBlocked = blockedUrlParts.contains { rawRule in
            let rule = normalize(rawRule)
            return platforms.contains { platform in
                platform.category == .webtoon && platform.webtoonPaths.contains { route in
                    rule.contains(platform.domain + route)
                }
            }
        }
        let relatedYoutubeIsBlocked = candidate.category == .liveVideo && youtubeQuotaBlocked
        guard relatedDomainIsBlocked || relatedWebtoonRouteIsBlocked || relatedYoutubeIsBlocked else { return nil }
        return MediaSiteCandidate(
            domain: candidate.domain,
            category: candidate.category,
            platformName: candidate.name
        )
    }

    private static let platforms: [(domain: String, name: String, category: Category, webtoonPaths: [String])] = [
        ("youtube.com", "YouTube", .liveVideo, []),
        ("twitch.tv", "Twitch", .liveVideo, []),
        ("chzzk.naver.com", "치지직", .liveVideo, []),
        ("sooplive.com", "SOOP", .liveVideo, []),
        ("comic.naver.com", "네이버 웹툰", .webtoon, []),
        ("series.naver.com", "네이버 시리즈", .webtoon, ["/comic"]),
        ("page.kakao.com", "카카오페이지", .webtoon, []),
        ("webtoon.kakao.com", "카카오웹툰", .webtoon, []),
        ("lezhin.com", "레진코믹스", .webtoon, ["/ko/comic", "/ko/bookshome"]),
        ("toomics.kr", "투믹스", .webtoon, []),
        ("toomics.com", "투믹스", .webtoon, []),
        ("ridibooks.com", "리디", .webtoon, [])
    ]

    private static func routeMatches(_ path: String, allowed: [String]) -> Bool {
        allowed.isEmpty || allowed.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

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
