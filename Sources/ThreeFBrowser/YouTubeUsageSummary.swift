import Foundation

struct FocusFenceYouTubeUsageSummary: Decodable, Equatable, Sendable {
    let todaySeconds: Int
    let dailyCapMinutes: Int
    let hourlyCapMinutes: Int
    let hourlyUsedSeconds: Int
    let hourlyRemainingSeconds: Int
    let blocked: Bool

    static func decode(_ data: Data) -> Self? {
        guard let summary = try? JSONDecoder().decode(Self.self, from: data),
              summary.todaySeconds >= 0,
              summary.dailyCapMinutes >= 0,
              summary.hourlyCapMinutes >= 0,
              summary.hourlyUsedSeconds >= 0,
              summary.hourlyRemainingSeconds >= 0 else { return nil }
        return summary
    }

    var statusLine: String {
        let daily: String
        if dailyCapMinutes > 0 {
            let capSeconds = dailyCapMinutes * 60
            let remaining = max(0, capSeconds - todaySeconds)
            let state = blocked ? "· YouTube 영상 재생 제한 중" : "· 남은 한도 \(Self.duration(remaining))"
            daily = "오늘 시청 \(Self.duration(todaySeconds)) · 일 한도 \(dailyCapMinutes)분 \(state)"
        } else {
            daily = "오늘 시청 \(Self.duration(todaySeconds)) · 일 한도 없음\(blocked ? " · YouTube 영상 재생 제한 중" : "")"
        }
        let hourly = hourlyCapMinutes > 0
            ? "최근 1시간 시청 \(Self.duration(hourlyUsedSeconds)) · 시간 한도 \(hourlyCapMinutes)분 · 남은 한도 \(Self.duration(hourlyRemainingSeconds))"
            : "시간 한도 없음"
        return "\(daily) · \(hourly)"
    }

    var compactStatusLine: String {
        let watched = "오늘 시청 \(Self.duration(todaySeconds))"
        guard dailyCapMinutes > 0 else {
            return "\(watched) · \(blocked ? "재생 제한 중" : "일 한도 없음")"
        }
        if blocked {
            return "\(watched) · 한도 \(dailyCapMinutes)분 · 재생 제한 중"
        }
        let remaining = max(0, dailyCapMinutes * 60 - todaySeconds)
        return "\(watched) · 남은 \(Self.duration(remaining))"
    }

    static func duration(_ seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let hours = safeSeconds / 3_600
        let minutes = (safeSeconds % 3_600) / 60
        let remainder = safeSeconds % 60
        if hours > 0 {
            return remainder == 0 ? "\(hours)시간 \(minutes)분" : "\(hours)시간 \(minutes)분 \(remainder)초"
        }
        return remainder == 0 ? "\(minutes)분" : "\(minutes)분 \(remainder)초"
    }
}

enum FocusFenceYouTubeUsageClient {
    static let endpoint = URL(string: "http://127.0.0.1:17361/usage/youtube")!

    static func fetch(session: URLSession = .shared) async -> FocusFenceYouTubeUsageSummary? {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 2
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        guard let (data, response) = try? await session.data(for: request),
              let response = response as? HTTPURLResponse,
              response.statusCode == 200 else { return nil }
        return FocusFenceYouTubeUsageSummary.decode(data)
    }
}
