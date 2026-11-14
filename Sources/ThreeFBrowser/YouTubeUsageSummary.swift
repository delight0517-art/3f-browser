import Foundation

private final class FocusFenceQARedirectRejector: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum FocusFenceQARouting {
    static func baseURL(qaRequested: Bool, profileValid: Bool, fixture: String?) -> URL? {
        guard qaRequested else { return URL(string: "http://127.0.0.1:17361") }
        guard profileValid, let fixture, let components = URLComponents(string: fixture),
              components.scheme == "http",
              components.host == "127.0.0.1",
              let port = components.port, (1...65535).contains(port), port != 17361,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/" else { return nil }
        return components.url
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.connectionProxyDictionary = [:]
        return URLSession(configuration: configuration, delegate: FocusFenceQARedirectRejector(), delegateQueue: nil)
    }

    static func currentQARequestBaseURL() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        let arguments = ProcessInfo.processInfo.arguments
        let fixture = arguments.first(where: { $0.hasPrefix("--threef-browser-qa-fixture=") })
            .map { String($0.dropFirst("--threef-browser-qa-fixture=".count)) }
            ?? environment["THREEF_BROWSER_FOCUS_FENCE_QA_URL"]
        return baseURL(
            qaRequested: isQARequested(),
            profileValid: BrowserSessionStore.isolatedQAProfileEnabled,
            fixture: fixture
        )
    }

    static func isQARequested() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        let arguments = ProcessInfo.processInfo.arguments
        return environment["THREEF_BROWSER_ENABLE_ISOLATED_QA_PROFILE"] == "1"
            || arguments.contains("--spaceo-agent-session")
            || arguments.contains(where: { $0.hasPrefix("--threef-browser-qa-profile=") })
            || arguments.contains(where: { $0.hasPrefix("--threef-browser-qa-fixture=") })
    }
}

struct FocusFenceYouTubePlaybackPolicy: Decodable, Equatable, Sendable {
    let youtubeQuotaBlocked: Bool
    let youtubeBlockedByActiveSchedule: Bool?
    let youtubeQuotaResetAfterSeconds: Int?
    let blockShorts: Bool?

    static func decode(_ data: Data) -> Self? {
        guard let value = try? JSONDecoder().decode(Self.self, from: data),
              value.youtubeQuotaResetAfterSeconds.map({ $0 >= 0 && $0 <= 172_800 }) ?? true else { return nil }
        return value
    }
}

private struct FocusFenceAccountBudgetStatus: Decodable, Equatable, Sendable {
    let available: Bool?
    let fresh: Bool?
    let enabled: Bool?
}

struct FocusFenceYouTubeUsageSummary: Decodable, Equatable, Sendable {
    let todaySeconds: Int
    let dailyCapMinutes: Int
    let hourlyCapMinutes: Int?
    let hourlyUsedSeconds: Int?
    let hourlyRemainingSeconds: Int?
    let blocked: Bool
    private let cloudSignedIn: Bool?
    private let accountBudget: FocusFenceAccountBudgetStatus?
    private let localOnly: Bool?
    private(set) var playbackPolicy: FocusFenceYouTubePlaybackPolicy? = nil
    private(set) var policyReadAt: Date? = nil

    private enum CodingKeys: String, CodingKey {
        case todaySeconds, dailyCapMinutes, hourlyCapMinutes, hourlyUsedSeconds, hourlyRemainingSeconds
        case blocked, cloudSignedIn, accountBudget, localOnly
    }

    func withPolicy(_ policy: FocusFenceYouTubePlaybackPolicy?, observedAt: Date = Date()) -> Self {
        var result = self
        result.playbackPolicy = policy
        result.policyReadAt = policy == nil ? nil : observedAt
        return result
    }

    func restrictionReason(isShorts: Bool) -> String? {
        if isShorts && playbackPolicy?.blockShorts == true { return "FF의 Shorts 차단 규칙이 적용 중입니다." }
        if playbackPolicy?.youtubeBlockedByActiveSchedule == true { return "활성 스케줄로 YouTube 영상 재생이 제한됩니다." }
        guard blocked || playbackPolicy?.youtubeQuotaBlocked == true else { return nil }
        if dailyCapMinutes > 0 && todaySeconds >= dailyCapMinutes * 60 { return "오늘 YouTube 시청 한도 \(dailyCapMinutes)분을 모두 사용했습니다." }
        if let hourlyCapMinutes, let hourlyUsedSeconds,
           hourlyCapMinutes > 0, hourlyUsedSeconds >= hourlyCapMinutes * 60 {
            return "최근 1시간 YouTube 시청 한도 \(hourlyCapMinutes)분을 모두 사용했습니다."
        }
        return "FF의 YouTube 재생 정책으로 제한 중입니다."
    }

    func resumeStatus(at now: Date = Date(), isShorts: Bool = false) -> String? {
        if isShorts && playbackPolicy?.blockShorts == true { return "다시 시청할 시간은 Shorts 차단 규칙·스케줄에 따라 달라집니다." }
        if playbackPolicy?.youtubeBlockedByActiveSchedule == true { return "스케줄 종료 후 다시 확인합니다. 종료 시간은 아직 전달되지 않았습니다." }
        guard blocked || playbackPolicy?.youtubeQuotaBlocked == true else { return nil }
        guard let seconds = playbackPolicy?.youtubeQuotaResetAfterSeconds, let policyReadAt else {
            return "다시 시청할 시간을 FF에서 확인하고 있습니다."
        }
        let wait = max(0, Int(ceil(policyReadAt.addingTimeInterval(Double(seconds)).timeIntervalSince(now))))
        return wait == 0 ? "한도 갱신을 확인하고 있습니다." : "다시 시청까지 약 \(Self.duration(wait))"
    }

    var synchronizationExplanation: String? {
        if localOnly == true { return "FF 연결 끊김 · 3F에 저장된 최신 한도 적용 · 재연결 시 사용량 동기화" }
        guard cloudSignedIn == true, accountBudget?.available != true else { return accountSyncStatusLine }
        return "FF 계정 로그인됨 · 계정 공통 한도 확인 불가 · 현재는 이 Mac의 한도로 제한합니다."
    }

    var accountSyncStatusLine: String? {
        guard cloudSignedIn != nil || accountBudget != nil else { return nil }
        guard cloudSignedIn == true else { return "계정 연결 필요" }
        guard let accountBudget, accountBudget.available == true else { return "계정 사용량 동기화 불가" }
        guard accountBudget.fresh == true else { return "계정 한도 갱신 지연" }
        return accountBudget.enabled == true ? "계정 한도 최신" : "계정 예산 비활성"
    }

    private var compactAccountSyncStatus: String? {
        if localOnly == true { return "3F 로컬 · 동기화 대기" }
        guard cloudSignedIn != nil || accountBudget != nil else { return nil }
        guard cloudSignedIn == true else { return "연결 필요" }
        guard let accountBudget, accountBudget.available == true else { return "사용량 불가" }
        guard accountBudget.fresh == true else { return "갱신 지연" }
        return accountBudget.enabled == true ? "계정 최신" : "예산 중지"
    }

    static func decode(_ data: Data) -> Self? {
        guard let summary = try? JSONDecoder().decode(Self.self, from: data),
              summary.todaySeconds >= 0,
              summary.dailyCapMinutes >= 0,
              summary.hourlyCapMinutes.map({ $0 >= 0 }) ?? true,
              summary.hourlyUsedSeconds.map({ $0 >= 0 }) ?? true,
              summary.hourlyRemainingSeconds.map({ $0 >= 0 }) ?? true else { return nil }
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
        let hourly: String
        if let hourlyCapMinutes, let hourlyUsedSeconds, let hourlyRemainingSeconds {
            hourly = hourlyCapMinutes > 0
                ? "최근 1시간 시청 \(Self.duration(hourlyUsedSeconds)) · 시간 한도 \(hourlyCapMinutes)분 · 남은 한도 \(Self.duration(hourlyRemainingSeconds))"
                : "시간 한도 없음"
        } else {
            hourly = "최근 1시간 사용량 확인 불가"
        }
        return ([daily, hourly, accountSyncStatusLine].compactMap { $0 }).joined(separator: " · ")
    }

    var compactStatusLine: String {
        let daily = dailyCapMinutes > 0
            ? "오늘 \(Self.duration(todaySeconds)) / 일 \(dailyCapMinutes)분 · 남은 \(Self.duration(max(0, dailyCapMinutes * 60 - todaySeconds)))"
            : "오늘 \(Self.duration(todaySeconds)) · 일 한도 없음"
        let hourly: String?
        if let hourlyCapMinutes, let hourlyUsedSeconds, let hourlyRemainingSeconds, hourlyCapMinutes > 0 {
            hourly = "최근 1시간 \(Self.duration(hourlyUsedSeconds)) / \(hourlyCapMinutes)분 · 남은 \(Self.duration(hourlyRemainingSeconds))"
        } else {
            hourly = nil
        }
        return ([compactAccountSyncStatus, daily, hourly, blocked ? "재생 제한 중" : nil].compactMap { $0 }).joined(separator: " · ")
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
    // Focus Fence keeps local requests open for up to 12 seconds while servicing its main-actor route.
    static let requestTimeoutInterval: TimeInterval = 10
    static let policyRequestTimeoutInterval: TimeInterval = 5

    static func makeRequest() -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeoutInterval
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        return request
    }

    static func fetch(session: URLSession = .shared) async -> FocusFenceYouTubeUsageSummary? {
        let qaRequested = FocusFenceQARouting.isQARequested()
        guard let baseURL = FocusFenceQARouting.currentQARequestBaseURL() else { return await offlineFallback() }
        let requestSession = qaRequested ? FocusFenceQARouting.makeSession() : session
        async let policy = fetchPolicy(session: requestSession)
        var request = URLRequest(url: baseURL.appendingPathComponent("usage/youtube"))
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeoutInterval
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        guard let (data, response) = try? await requestSession.data(for: request),
              let response = response as? HTTPURLResponse,
              response.statusCode == 200 else { return await offlineFallback() }
        guard let summary = FocusFenceYouTubeUsageSummary.decode(data) else { return await offlineFallback() }
        guard let resolvedPolicy = await policy else { return await offlineFallback() }
        return summary.withPolicy(resolvedPolicy)
    }

    private static func offlineFallback() async -> FocusFenceYouTubeUsageSummary? {
        await MainActor.run { YouTubeOfflineQuotaStore.shared.offlineSummary() }
    }

    static func fetchPolicy(session: URLSession = .shared) async -> FocusFenceYouTubePlaybackPolicy? {
        let qaRequested = FocusFenceQARouting.isQARequested()
        guard let baseURL = FocusFenceQARouting.currentQARequestBaseURL() else { return nil }
        let requestSession = qaRequested ? FocusFenceQARouting.makeSession() : session
        var components = URLComponents(url: baseURL.appendingPathComponent("rules"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "browser", value: "3f")]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = policyRequestTimeoutInterval
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        guard let (data, response) = try? await requestSession.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return FocusFenceYouTubePlaybackPolicy.decode(data)
    }
}
