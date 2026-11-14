import Combine
import Foundation

@MainActor
final class FocusFenceConnectionService: ObservableObject {
    @Published private(set) var recognitionStatus = "확인 전"
    @Published private(set) var rulesStatus = "확인 전"
    @Published private(set) var filterStatus = "확인 전"
    @Published private(set) var detail = "3F Browser는 Focus Fence의 브라우저 자동 검색 대상으로 등록되어 있습니다."

    private let expectedFilterBundleID = "com.rogan.VeliMac.NetworkFilter"

    struct QuickAddOutcome {
        let ok: Bool
        let duplicate: Bool
        let message: String
        let scheduleName: String?
    }

    struct ScheduleOutcome {
        let ok: Bool
        let requiresConfirm: Bool
        let message: String
        let scheduleName: String?
        let rulesAdded: Int?
    }

    private var pendingScheduleConfirmation: String?

    /// Uses Focus Fence's existing local confirmation path; the returned schedule
    /// name tells the caller where Focus Fence actually placed the rule.
    func quickAddDomain(_ rawHost: String) async throws -> QuickAddOutcome {
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !host.isEmpty,
              !host.contains("/"), !host.contains(":"), !host.contains("@"),
              let components = URLComponents(string: "https://\(host)"),
              components.host?.lowercased() == host,
              host.contains(".") else {
            throw URLError(.badURL)
        }

        guard let baseURL = FocusFenceQARouting.currentQARequestBaseURL() else {
            throw URLError(.badURL)
        }
        let endpoint = baseURL.appendingPathComponent("quick-add")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 4
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["input": host])
        let session = FocusFenceQARouting.isQARequested() ? FocusFenceQARouting.makeSession() : URLSession.shared
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              let payload = try? JSONDecoder().decode(QuickAddResponse.self, from: data) else {
            throw URLError(.badServerResponse)
        }
        guard (200...409).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return QuickAddOutcome(
            ok: payload.ok,
            duplicate: payload.duplicate ?? false,
            message: payload.message ?? "Focus Fence가 규칙 적용 결과를 알려주지 않았습니다.",
            scheduleName: payload.scheduleName
        )
    }

    /// The first POST previews only. A second POST applies only the exact message
    /// that returned a successful, explicit confirmation requirement.
    func previewSchedule(_ rawMessage: String) async throws -> ScheduleOutcome {
        let message = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, message.count <= 1000 else {
            throw URLError(.badURL)
        }
        pendingScheduleConfirmation = nil
        let result = try await postSchedule(message, confirm: false)
        if result.ok && result.requiresConfirm {
            pendingScheduleConfirmation = message
        }
        return result
    }

    func confirmSchedule(_ rawMessage: String) async throws -> ScheduleOutcome {
        let message = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pendingScheduleConfirmation == message else {
            throw URLError(.userAuthenticationRequired)
        }
        let result = try await postSchedule(message, confirm: true)
        if result.ok { pendingScheduleConfirmation = nil }
        return result
    }

    private func postSchedule(_ message: String, confirm: Bool) async throws -> ScheduleOutcome {
        guard let baseURL = FocusFenceQARouting.currentQARequestBaseURL() else {
            throw URLError(.badURL)
        }
        let endpoint = baseURL.appendingPathComponent("chat/schedule")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["message": message]
        if confirm { body["confirm"] = true }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let session = FocusFenceQARouting.isQARequested() ? FocusFenceQARouting.makeSession() : URLSession.shared
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              let payload = try? JSONDecoder().decode(ChatScheduleResponse.self, from: data),
              (200...403).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return ScheduleOutcome(
            ok: payload.ok,
            requiresConfirm: payload.requiresConfirm ?? false,
            message: payload.message ?? "Focus Fence가 일정 적용 결과를 알려주지 않았습니다.",
            scheduleName: payload.scheduleName,
            rulesAdded: payload.rulesAdded
        )
    }

    func refresh() async {
        guard OptionalFeatureAvailability.focusFenceEnforcement
                || OptionalFeatureAvailability.youtubeUsageReporting
                || OptionalFeatureAvailability.youtubePreviewBlocking else {
            recognitionStatus = "연동 기능 비활성 · TODO"
            rulesStatus = "비활성 · 일반 페이지 이동 허용"
            filterStatus = "확인하지 않음 · 연동 비활성"
            detail = "Focus Fence 연동은 검증 전까지 꺼져 있습니다. 일반 웹 탐색은 사용할 수 있으며, 사이트 차단과 YouTube 연동은 완료 후 앱 업데이트로 켭니다."
            return
        }

        recognitionStatus = "확인 중…"
        rulesStatus = "확인 중…"
        filterStatus = "확인 중…"

        do {
            guard let snapshot = await ThreeFBrowserControlController.fetchFocusFenceRulesSnapshot() else {
                throw URLError(.cannotConnectToHost)
            }
            let payload = snapshot.data
            guard ThreeFBrowserControlController.usableFocusFenceRules(payload),
                  let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
                  let blockedDomains = object["blockedDomains"] as? [String] else {
                throw URLError(.cannotDecodeContentData)
            }
            rulesStatus = snapshot.isCached
                ? "저장된 차단 규칙 사용 중 · 도메인 \(blockedDomains.count)개"
                : "차단 규칙 연결됨 · 도메인 \(blockedDomains.count)개"
        } catch {
            rulesStatus = "규칙 연결 안 됨 · 페이지 이동 차단됨"
        }

        do {
            let discovery = try await fetch(DiscoveryStatus.self, path: "/maintenance/browser-discovery/status")
            if discovery.scanState == "scanning" {
                recognitionStatus = "Focus Fence에서 검색 중"
            } else if discovery.discovered.contains(where: { $0.bundleID == "com.rogan.threef.browser" && $0.identity == "browser" }) {
                recognitionStatus = "Focus Fence에서 자동 인식됨"
            } else if discovery.ambiguousHandlers.contains(where: { $0.bundleID == "com.rogan.threef.browser" }) {
                recognitionStatus = "브라우저 분류 확인 필요"
            } else {
                recognitionStatus = "아직 검색 결과에 없음"
            }
        } catch {
            recognitionStatus = "Focus Fence 상태 서비스 응답 없음"
            filterStatus = "확인 불가"
            detail = "3F Browser 실행은 Focus Fence 준비 상태와 별개입니다. Focus Fence 상태를 확인할 수 없어 웹페이지 이동은 규칙 연결 전까지 차단됩니다."
            return
        }

        do {
            let filter = try await fetch(NetworkFilterStatus.self, path: "/maintenance/network-filter/status")
            if filter.filterEnabled && filter.providerBundleIdentifier == expectedFilterBundleID {
                filterStatus = "Focus Fence 시스템 필터 활성"
            } else if filter.filterEnabled {
                filterStatus = "다른 네트워크 필터 활성"
            } else {
                filterStatus = "Focus Fence 시스템 필터 비활성"
            }
            if rulesStatus.hasPrefix("규칙 연결 안 됨") {
                detail = "3F Browser 실행은 허용됩니다. Focus Fence 규칙을 확인할 수 없어 웹페이지 이동만 차단하고 있습니다."
            } else {
                detail = "3F Browser 실행은 Focus Fence 브라우저 준비 상태와 별개입니다. 페이지 이동은 Focus Fence 규칙과 일정에 따라 검사합니다."
            }
        } catch {
            filterStatus = "시스템 필터 상태 확인 불가"
            detail = "3F Browser 실행은 Focus Fence 브라우저 준비 상태와 별개입니다. 3F 인식은 확인했지만 네트워크 필터 상태는 읽지 못했습니다. 페이지 이동은 Focus Fence 규칙에 따라 검사합니다."
        }
    }

    private func fetch<Value: Decodable>(_ type: Value.Type, path: String) async throws -> Value {
        guard let baseURL = FocusFenceQARouting.currentQARequestBaseURL() else {
            throw URLError(.badURL)
        }
        let endpoint = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 1.5
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let session = FocusFenceQARouting.isQARequested() ? FocusFenceQARouting.makeSession() : URLSession.shared
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(type, from: data)
    }

    private struct DiscoveryStatus: Decodable {
        let scanState: String
        let discovered: [BrowserRow]
        let ambiguousHandlers: [BrowserRow]
    }

    private struct BrowserRow: Decodable {
        let bundleID: String
        let identity: String
    }

    private struct NetworkFilterStatus: Decodable {
        let filterEnabled: Bool
        let providerBundleIdentifier: String?
    }

    private struct QuickAddResponse: Decodable {
        let ok: Bool
        let message: String?
        let duplicate: Bool?
        let scheduleName: String?
    }

    private struct ChatScheduleResponse: Decodable {
        let ok: Bool
        let message: String?
        let scheduleName: String?
        let requiresConfirm: Bool?
        let rulesAdded: Int?
    }

}
