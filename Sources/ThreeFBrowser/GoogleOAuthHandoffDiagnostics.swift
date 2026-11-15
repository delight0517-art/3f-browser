import AppKit
import Combine
import Foundation
import WebKit

struct GoogleOAuthHandoffEvent: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let outcome: Outcome
    let detail: String?

    enum Outcome: String {
        case navigationStarted = "페이지 이동 시작"
        case navigationCommitted = "페이지 응답 표시 시작"
        case navigationFinished = "페이지 이동 완료"
        case navigationFailed = "페이지 이동 실패"
        case httpResponse = "HTTP 응답"
        case cloudflareChallengeAllowed = "Cloudflare 검증 프레임 허용"
        case cloudflareChallengeRejected = "Cloudflare 검증 프레임 거부"
        case cloudflareLoginState = "Cloudflare 로그인 폼 상태"
        case cloudflareLoginSubmitted = "Cloudflare 로그인 제출"
        case cloudflareExternalBrowserOpened = "Cloudflare 로그인 외부 브라우저에서 열림"
        case cloudflareExternalBrowserUnavailable = "Cloudflare 비교 브라우저를 찾지 못함"
        case cloudflareExternalBrowserFailed = "Cloudflare 외부 브라우저 열기 실패"
        case opened = "Google 로그인 페이지 열림 · 3F 내부"
        case cefBrowserHandoff = "Google 인증을 3F Chromium 창으로 전달"
        case cefBrowserUnavailable = "3F Chromium 창 열기 실패"
        case popupOpened = "팝업을 3F 탭으로 열음"
        case popupStormBlocked = "팝업 폭주 차단"
        case duplicateSuppressed = "반복 팝업 억제"
        case asideUnavailable = "로그인 화면을 3F에서 유지"
        case focusFenceBlocked = "Focus Fence 정책이 인증 사이트를 차단"
        case authenticationPolicyUnavailable = "Focus Fence 연결 없이 Google 인증 허용"
        case openFailed = "브라우저 진단 이벤트"
        case unsupportedMedia = "지원되지 않는 미디어 형식"
    }
}

final class BrowserDiagnosticsScriptMessageHandler: NSObject, WKScriptMessageHandler {
    static let name = "threeFDiagnostics"
    static let script = #"""
    (() => {
      const isCloudflareLogin = () => location.protocol === 'https:'
        && location.hostname.toLowerCase() === 'dash.cloudflare.com'
        && /^\/(login|sign-in|signup|sign-up)(\/|$)/i.test(location.pathname);
      let lastLoginState = '';
      let scheduledLoginState = false;
      const visible = element => {
        if (!(element instanceof Element)) return false;
        const style = getComputedStyle(element);
        const rect = element.getBoundingClientRect();
        return style.display !== 'none' && style.visibility !== 'hidden' && rect.width > 0 && rect.height > 0;
      };
      const post = payload => window.webkit?.messageHandlers?.threeFDiagnostics?.postMessage(payload);
      const loginState = () => {
        if (!isCloudflareLogin()) return;
        const passwordFields = [...document.querySelectorAll('input[type="password"]')].filter(visible);
        const loginForm = passwordFields[0]?.form || null;
        const identityFields = loginForm
          ? [...loginForm.querySelectorAll('input[type="email"], input[autocomplete="username"], input[type="text"][name="email"], input[type="text"][name="username"]')].filter(visible)
          : [];
        const submitButtons = loginForm
          ? [...loginForm.querySelectorAll('button[type="submit"], button:not([type]), input[type="submit"]')].filter(visible)
          : [];
        const challengeFramePresent = [...document.querySelectorAll('iframe[src]')].filter(visible).some(frame => {
          try { return new URL(frame.src, location.href).hostname.toLowerCase() === 'challenges.cloudflare.com'; }
          catch (_) { return false; }
        });
        const invalidFieldPresent = !!loginForm
          && [...loginForm.querySelectorAll('input[aria-invalid="true"], [role="alert"]')].some(visible);
        const pageText = document.body?.innerText || '';
        const challengeErrorPresent = /there was a problem with verification|verification failed|please reload and try again|인증에 문제가|검증에 실패|다시 로드.*다시 시도/i.test(pageText);
        const values = {
          formPresent: String(passwordFields.length > 0),
          identityFieldPresent: String(identityFields.length > 0),
          identityFilled: String(identityFields.some(field => field.value.length > 0)),
          passwordFieldPresent: String(passwordFields.length > 0),
          passwordFilled: String(passwordFields.some(field => field.value.length > 0)),
          submitPresent: String(submitButtons.length > 0),
          submitEnabled: String(submitButtons.some(button => !button.disabled && button.getAttribute('aria-disabled') !== 'true')),
          challengeFramePresent: String(challengeFramePresent),
          validationMessagePresent: String(invalidFieldPresent),
          challengeErrorPresent: String(challengeErrorPresent)
        };
        const signature = Object.values(values).join('|');
        if (signature === lastLoginState) return;
        lastLoginState = signature;
        post({kind: 'cloudflareLoginState', ...values});
      };
      const scheduleLoginState = () => {
        if (scheduledLoginState) return;
        scheduledLoginState = true;
        setTimeout(() => { scheduledLoginState = false; loginState(); }, 150);
      };
      document.addEventListener('error', event => {
        const media = event.target;
        if (!(media instanceof HTMLMediaElement)) return;
        const source = media.currentSrc || media.querySelector('source')?.src || '';
        const mime = media.querySelector('source')?.type || media.type || '';
        const ext = source.split(/[?#]/, 1)[0].split('.').pop()?.toLowerCase() || '';
        if (media.error?.code === 4 || (mime && !media.canPlayType(mime))) {
          window.webkit?.messageHandlers?.threeFDiagnostics?.postMessage({kind:'unsupportedMedia', mime:mime.slice(0,80), ext:ext.slice(0,12)});
        }
      }, true);
      document.addEventListener('input', scheduleLoginState, true);
      document.addEventListener('change', scheduleLoginState, true);
      document.addEventListener('submit', event => {
        if (!isCloudflareLogin() || !(event.target instanceof HTMLFormElement)
          || !event.target.querySelector('input[type="password"]')) return;
        post({kind: 'cloudflareLoginSubmitted'});
      }, true);
      document.addEventListener('DOMContentLoaded', scheduleLoginState, {once: true});
      window.addEventListener('pageshow', scheduleLoginState);
      if (document.documentElement) {
        new MutationObserver(scheduleLoginState).observe(document.documentElement, {
          subtree: true, childList: true, attributes: true,
          attributeFilter: ['disabled', 'aria-disabled', 'aria-invalid', 'src', 'style', 'class']
        });
      } else {
        document.addEventListener('DOMContentLoaded', () => {
          if (document.documentElement) new MutationObserver(scheduleLoginState).observe(document.documentElement, {
            subtree: true, childList: true, attributes: true,
            attributeFilter: ['disabled', 'aria-disabled', 'aria-invalid', 'src', 'style', 'class']
          });
        }, {once: true});
      }
      scheduleLoginState();
    })();
    """#

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.name, let body = message.body as? [String: String] else { return }
        if body["kind"] == "cloudflareLoginState" || body["kind"] == "cloudflareLoginSubmitted" {
            let origin = message.frameInfo.securityOrigin
            guard message.frameInfo.isMainFrame,
                  origin.protocol.lowercased() == "https",
                  origin.host.lowercased() == "dash.cloudflare.com" else { return }
            Task { @MainActor in
                let diagnostics = GoogleOAuthHandoffDiagnostics.shared
                if body["kind"] == "cloudflareLoginSubmitted" {
                    diagnostics.record(.cloudflareLoginSubmitted, detail: "제출 이벤트 감지 · 입력값은 저장하지 않음", key: "cloudflare-login-submitted")
                } else {
                    diagnostics.recordCloudflareLoginState(body)
                }
            }
            return
        }
        guard body["kind"] == "unsupportedMedia" else { return }
        let mime = body["mime"]?.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber || "/-+._".contains($0)) } ?? ""
        let ext = body["ext"]?.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) } ?? ""
        let suffix = mime.isEmpty ? ext : mime
        Task { @MainActor in
            GoogleOAuthHandoffDiagnostics.shared.record(.unsupportedMedia, detail: suffix.isEmpty ? nil : suffix, key: "media-\(suffix)")
        }
    }
}

@MainActor
final class GoogleOAuthHandoffDiagnostics: ObservableObject {
    static let shared = GoogleOAuthHandoffDiagnostics()
    @Published private(set) var events: [GoogleOAuthHandoffEvent] = []
    @Published private(set) var saveStatus = "로컬 로그 저장 대기"
    private let capacity = 100
    private let maxFileBytes = 1_048_576
    private var recentKeys: [String: Date] = [:]
    private var recentHandoffKeys: [String: Date] = [:]
    private var pendingHandoffKeys: Set<String> = []
    private var popupRequestDates: [Date] = []

    private var logURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("3F Browser", isDirectory: true)
            .appendingPathComponent("diagnostics.jsonl")
    }

    private init() { load() }

    func record(_ outcome: GoogleOAuthHandoffEvent.Outcome, detail: String? = nil, key: String = "event") {
        let now = Date()
        recentKeys = recentKeys.filter { now.timeIntervalSince($0.value) < 10 }
        guard recentKeys[key] == nil else { return }
        recentKeys[key] = now
        let event = GoogleOAuthHandoffEvent(id: UUID(), date: now, outcome: outcome, detail: detail)
        events.insert(event, at: 0)
        if events.count > capacity { events.removeLast(events.count - capacity) }
        persist(event)
    }

    func recordNavigation(_ outcome: GoogleOAuthHandoffEvent.Outcome, url: URL?) {
        guard [.navigationStarted, .navigationCommitted, .navigationFinished].contains(outcome) else { return }
        let context = Self.contextLabel(for: url)
        let scheme = url?.scheme?.uppercased() ?? "알 수 없음"
        record(outcome, detail: "\(context) · \(scheme)", key: "\(outcome.rawValue)-\(UUID().uuidString)")
    }

    func recordNavigationFailure(_ error: Error, url: URL?) {
        let webError = error as NSError
        guard webError.code != NSURLErrorCancelled else { return }
        let context = Self.contextLabel(for: url)
        let domain: String
        switch webError.domain {
        case NSURLErrorDomain: domain = "URL"
        case "WebKitErrorDomain": domain = "WebKit"
        default: domain = "앱"
        }
        record(.navigationFailed, detail: "\(context) · \(domain) 오류 코드 \(webError.code)", key: "navigation-failed-\(UUID().uuidString)")
    }

    func recordHTTPResponse(_ response: URLResponse, isMainFrame: Bool) {
        guard let http = response as? HTTPURLResponse else { return }
        let context = Self.contextLabel(for: response.url)
        guard http.statusCode >= 400 || context == "Cloudflare" else { return }
        let frame = isMainFrame ? "기본 프레임" : "하위 프레임"
        record(.httpResponse, detail: "\(context) · \(frame) · HTTP \(http.statusCode)", key: "http-\(context)-\(frame)-\(http.statusCode)")
    }

    func recordCloudflareChallenge(allowed: Bool) {
        record(
            allowed ? .cloudflareChallengeAllowed : .cloudflareChallengeRejected,
            detail: "Cloudflare 비기본 프레임",
            key: allowed ? "cloudflare-challenge-allowed" : "cloudflare-challenge-rejected"
        )
    }

    func recordCloudflareLoginState(_ body: [String: String]) {
        func state(_ key: String, yes: String, no: String) -> String? {
            guard let value = body[key], value == "true" || value == "false" else { return nil }
            return value == "true" ? yes : no
        }
        guard let identity = state("identityFilled", yes: "계정 칸 입력됨", no: "계정 칸 비어 있음"),
              let password = state("passwordFilled", yes: "암호 칸 입력됨", no: "암호 칸 비어 있음"),
              let submit = state("submitEnabled", yes: "로그인 버튼 활성", no: "로그인 버튼 비활성") else { return }
        let form = state("formPresent", yes: "폼 감지", no: "폼 미감지") ?? "폼 상태 미상"
        let challenge = state("challengeFramePresent", yes: "검증 프레임 있음", no: "검증 프레임 없음") ?? "검증 프레임 미상"
        let invalid = state("validationMessagePresent", yes: "검증 오류 표시", no: "검증 오류 표시 없음") ?? "검증 오류 미상"
        let challengeError = state("challengeErrorPresent", yes: "Cloudflare 검증 실패 표시", no: "Cloudflare 검증 실패 표시 없음") ?? "Cloudflare 오류 상태 미상"
        let detail = [form, identity, password, submit, challenge, invalid, challengeError].joined(separator: " · ")
        record(.cloudflareLoginState, detail: detail, key: "cloudflare-login-state-\(detail)")
    }

    nonisolated static func isCloudflareChallengeURL(_ url: URL?) -> Bool {
        url?.host?.lowercased() == "challenges.cloudflare.com"
    }

    nonisolated static func contextLabel(for url: URL?) -> String {
        guard let host = url?.host?.lowercased() else { return "웹페이지" }
        if host == "dash.cloudflare.com" || host == "cloudflare.com" || host.hasSuffix(".cloudflare.com") {
            return "Cloudflare"
        }
        if host == "accounts.google.com" || host == "consent.google.com" {
            return "Google 인증"
        }
        return "웹페이지"
    }

    func handoff(_ url: URL, sourceURL: URL?) {
        // Restart the sign-in from its HTTPS origin in the restricted Chromium
        // sidecar so the site's state and callback stay in that isolated session.
        guard GoogleOAuthNavigationPolicy.requiresSystemBrowser(for: url) else {
            record(.openFailed, detail: "인증 주소 검증 실패", key: "google-auth-url-invalid")
            return
        }
        let originatingPage = GoogleOAuthNavigationPolicy.safeHTTPSPageURL(sourceURL)
        let now = Date()
        recentHandoffKeys = recentHandoffKeys.filter { now.timeIntervalSince($0.value) < 120 }
        let handoffKey = Self.deduplicationKey(for: url, sourceHost: originatingPage?.host)
        guard recentHandoffKeys[handoffKey] == nil else {
            record(.duplicateSuppressed, key: "handoff-\(handoffKey)")
            return
        }
        guard pendingHandoffKeys.insert(handoffKey).inserted else {
            record(.duplicateSuppressed, key: "handoff-pending-\(handoffKey)")
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let rules = OptionalFeatureAvailability.focusFenceEnforcement
                ? await ThreeFBrowserControlController.fetchFocusFenceRules()
                : nil
            guard GoogleOAuthNavigationPolicy.allowsAuthenticationTransport(
                url,
                originatingPage: originatingPage,
                focusFenceRules: rules
            ) else {
                self.pendingHandoffKeys.remove(handoffKey)
                self.record(.focusFenceBlocked, detail: "인증을 시작한 사이트가 차단됨", key: "google-cef-focus-fence-blocked")
                return
            }
            if OptionalFeatureAvailability.focusFenceEnforcement,
               rules == nil,
               originatingPage != nil {
                self.record(.authenticationPolicyUnavailable, key: "google-auth-policy-unavailable")
            }
            CEFBrowserRuntime.open(url, originatingPage: originatingPage) { [weak self] result in
                switch result {
                case .success:
                    self?.pendingHandoffKeys.remove(handoffKey)
                    self?.recentHandoffKeys[handoffKey] = Date()
                    self?.record(.cefBrowserHandoff, key: "google-cef-\(originatingPage?.host ?? "auth-only")")
                case .failure:
                    self?.pendingHandoffKeys.remove(handoffKey)
                    self?.record(.cefBrowserUnavailable, key: "google-cef-unavailable")
                }
            }
        }
    }

    func allowPopup() -> Bool {
        let now = Date()
        popupRequestDates = popupRequestDates.filter { now.timeIntervalSince($0) < 10 }
        let burstKey = "popup-storm-\(Int(now.timeIntervalSince1970 / 10))"
        guard popupRequestDates.count < 5 else {
            record(.popupStormBlocked, detail: "10초 내 팝업 6건째부터 차단", key: burstKey)
            return false
        }
        popupRequestDates.append(now)
        if popupRequestDates.count == 1 {
            record(.popupOpened, key: "popup-opened")
        }
        return true
    }

    func clear() {
        events.removeAll()
        do {
            if FileManager.default.fileExists(atPath: logURL.path) { try FileManager.default.removeItem(at: logURL) }
            let rotated = logURL.appendingPathExtension("1")
            if FileManager.default.fileExists(atPath: rotated.path) { try FileManager.default.removeItem(at: rotated) }
            saveStatus = "로컬 로그 삭제됨"
        } catch { saveStatus = "로그 삭제 실패: \(error.localizedDescription)" }
    }

    func openLogFolder() { NSWorkspace.shared.open(logURL.deletingLastPathComponent()) }

    nonisolated static func deduplicationKey(for url: URL, sourceHost: String?) -> String {
        "\(sourceHost?.lowercased() ?? "unknown")|\(url.host?.lowercased() ?? "unknown")"
    }

    private func load() {
        do {
            let data = try Data(contentsOf: logURL)
            let lines = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline)
            events = lines.suffix(capacity).compactMap { line in
                guard let row = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: String],
                      let stamp = row["date"], let date = ISO8601DateFormatter().date(from: stamp),
                      let label = row["event"], let outcome = GoogleOAuthHandoffEvent.Outcome(rawValue: label) else { return nil }
                return GoogleOAuthHandoffEvent(id: UUID(), date: date, outcome: outcome, detail: row["detail"])
            }.reversed()
            saveStatus = "로컬 로그 읽음 · \(events.count)건"
        } catch where (error as NSError).code == NSFileReadNoSuchFileError {
            saveStatus = "로컬 로그 저장 대기"
        } catch { saveStatus = "로그 읽기 실패" }
    }

    private func persist(_ event: GoogleOAuthHandoffEvent) {
        do {
            let manager = FileManager.default
            try manager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var row: [String: String] = ["date": ISO8601DateFormatter().string(from: event.date), "event": event.outcome.rawValue]
            if let detail = event.detail { row["detail"] = detail }
            var data = try JSONSerialization.data(withJSONObject: row)
            data.append(0x0A)
            if let size = try? manager.attributesOfItem(atPath: logURL.path)[.size] as? NSNumber,
               size.intValue + data.count > maxFileBytes {
                let rotated = logURL.appendingPathExtension("1")
                try? manager.removeItem(at: rotated)
                if manager.fileExists(atPath: logURL.path) { try manager.moveItem(at: logURL, to: rotated) }
            }
            if !manager.fileExists(atPath: logURL.path) { manager.createFile(atPath: logURL.path, contents: nil) }
            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
            saveStatus = "로컬 저장됨 · diagnostics.jsonl"
        } catch { saveStatus = "로컬 로그 저장 실패" }
    }
}
