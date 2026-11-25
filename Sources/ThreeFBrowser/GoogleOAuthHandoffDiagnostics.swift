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
        case cloudflareLoginAfterSubmitState = "Cloudflare 제출 후 폼 상태"
        case cloudflareLoginRuntimeIssue = "Cloudflare 로그인 스크립트/리소스 오류"
        case cloudflareLoginSecurityPolicy = "Cloudflare 페이지 보안 정책 차단"
        case cloudflareLoginNavigationAttempted = "Cloudflare 제출 후 페이지 이동 시도"
        case cloudflareExternalBrowserOpened = "Cloudflare 로그인 외부 브라우저에서 열림"
        case cloudflareExternalBrowserUnavailable = "Cloudflare 비교 브라우저를 찾지 못함"
        case cloudflareExternalBrowserFailed = "Cloudflare 외부 브라우저 열기 실패"
        case opened = "Google 로그인 페이지 열림 · 3F 내부"
        case protectedBrowserHandoff = "Google 인증을 보호 확인된 브라우저로 전달"
        case protectedBrowserUnavailable = "보호 확인된 브라우저 열기 실패"
        case browserProtectionUnverified = "Focus Fence 브라우저 보호 미검증 · 인증 전달 보류"
        case popupOpened = "팝업을 3F 탭으로 열음"
        case popupStormBlocked = "팝업 폭주 차단"
        case mediaFallbackOpened = "미지원 미디어를 보호 브라우저에서 열음"
        case mediaFallbackHeld = "미디어 대체 브라우저 보호 미검증 · 열기 보류"
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
      const isCloudflareChallengeFrame = () => location.protocol === 'https:'
        && location.hostname.toLowerCase() === 'challenges.cloudflare.com';
      const isCloudflareDiagnosticContext = () => isCloudflareLogin() || isCloudflareChallengeFrame();
      let lastLoginState = '';
      let scheduledLoginState = false;
      let loginAttemptPending = false;
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
        const signature = [...Object.values(values), String(loginAttemptPending)].join('|');
        if (signature === lastLoginState) return;
        lastLoginState = signature;
        post({kind: loginAttemptPending ? 'cloudflareLoginAfterSubmitState' : 'cloudflareLoginState', ...values});
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
      window.addEventListener('error', event => {
        if (!isCloudflareDiagnosticContext()) return;
        const target = event.target;
        const resourceType = target instanceof Element
          ? ({SCRIPT:'script', IFRAME:'frame', LINK:'style', IMG:'image'}[target.tagName] || 'resource')
          : 'javascript';
        post({kind: 'cloudflareLoginRuntimeIssue', resourceType});
      }, true);
      window.addEventListener('unhandledrejection', () => {
        if (isCloudflareDiagnosticContext()) post({kind: 'cloudflareLoginRuntimeIssue', resourceType: 'promise'});
      });
      document.addEventListener('securitypolicyviolation', event => {
        if (!isCloudflareDiagnosticContext()) return;
        const directive = String(event.violatedDirective || '').split('-')[0];
        post({kind: 'cloudflareLoginSecurityPolicy', directive});
      });
      if (isCloudflareLogin()) {
        document.addEventListener('input', scheduleLoginState, true);
        document.addEventListener('change', scheduleLoginState, true);
        document.addEventListener('submit', event => {
          if (!(event.target instanceof HTMLFormElement)
            || !event.target.querySelector('input[type="password"]')) return;
          loginAttemptPending = true;
          post({kind: 'cloudflareLoginSubmitted'});
          setTimeout(scheduleLoginState, 500);
          setTimeout(scheduleLoginState, 2000);
        }, true);
        window.addEventListener('beforeunload', () => {
          if (loginAttemptPending) post({kind: 'cloudflareLoginNavigationAttempted'});
        });
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
      }
    })();
    """#

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.name, let body = message.body as? [String: String] else { return }
        let cloudflareKinds: Set<String> = [
            "cloudflareLoginState", "cloudflareLoginSubmitted", "cloudflareLoginAfterSubmitState",
            "cloudflareLoginRuntimeIssue", "cloudflareLoginSecurityPolicy", "cloudflareLoginNavigationAttempted"
        ]
        if let kind = body["kind"], cloudflareKinds.contains(kind) {
            let origin = message.frameInfo.securityOrigin
            let isHTTPS = origin.protocol.lowercased() == "https"
            let isMainCloudflareLogin = message.frameInfo.isMainFrame
                && isHTTPS
                && origin.host.lowercased() == "dash.cloudflare.com"
            let mainDocumentURL = message.frameInfo.request.mainDocumentURL
            let isCloudflareChallengeSubframe = !message.frameInfo.isMainFrame
                && isHTTPS
                && origin.host.lowercased() == "challenges.cloudflare.com"
                && mainDocumentURL?.scheme?.lowercased() == "https"
                && mainDocumentURL?.host?.lowercased() == "dash.cloudflare.com"
            let challengeFrameKinds: Set<String> = ["cloudflareLoginRuntimeIssue", "cloudflareLoginSecurityPolicy"]
            guard isMainCloudflareLogin || (isCloudflareChallengeSubframe && challengeFrameKinds.contains(kind)) else { return }
            Task { @MainActor in
                let diagnostics = GoogleOAuthHandoffDiagnostics.shared
                if body["kind"] == "cloudflareLoginSubmitted" {
                    diagnostics.record(.cloudflareLoginSubmitted, detail: "제출 이벤트 감지 · 입력값은 저장하지 않음", key: "cloudflare-login-submitted")
                } else if body["kind"] == "cloudflareLoginRuntimeIssue" {
                    let type = GoogleOAuthHandoffDiagnostics.safeCloudflareDiagnosticCategory(body["resourceType"], allowed: ["script", "frame", "style", "image", "resource", "javascript", "promise"])
                    diagnostics.record(.cloudflareLoginRuntimeIssue, detail: type.map { "오류 종류 · \($0) · 원문 미수집" } ?? "스크립트/리소스 오류 감지 · 원문 미수집", key: "cloudflare-login-runtime-issue-\(type ?? "unknown")")
                } else if body["kind"] == "cloudflareLoginSecurityPolicy" {
                    let directive = GoogleOAuthHandoffDiagnostics.safeCloudflareDiagnosticCategory(body["directive"], allowed: ["script", "frame", "style", "image", "connect", "font", "default", "object", "base", "form"])
                    diagnostics.record(.cloudflareLoginSecurityPolicy, detail: directive.map { "차단 지시문 · \($0) · URL 미수집" } ?? "보안 정책 위반 감지 · URL 미수집", key: "cloudflare-login-csp-\(directive ?? "unknown")")
                } else if body["kind"] == "cloudflareLoginNavigationAttempted" {
                    diagnostics.record(.cloudflareLoginNavigationAttempted, detail: "제출 후 페이지 이동 이벤트 · 성공 여부 아님", key: "cloudflare-login-navigation-attempted")
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
        let pageURL = message.frameInfo.request.mainDocumentURL
        Task { @MainActor in
            GoogleOAuthHandoffDiagnostics.shared.handleUnsupportedMedia(format: suffix, pageURL: pageURL)
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
    private var recentMediaFallbackKeys: [String: Date] = [:]
    private var pendingMediaFallbackKeys: Set<String> = []
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
        let outcome: GoogleOAuthHandoffEvent.Outcome = body["kind"] == "cloudflareLoginAfterSubmitState" ? .cloudflareLoginAfterSubmitState : .cloudflareLoginState
        let label = body["kind"] == "cloudflareLoginAfterSubmitState" ? "cloudflare-login-after-submit" : "cloudflare-login-state"
        record(outcome, detail: detail, key: "\(label)-\(detail)")
    }

    nonisolated static func isCloudflareChallengeURL(_ url: URL?) -> Bool {
        url?.host?.lowercased() == "challenges.cloudflare.com"
    }

    nonisolated static func safeCloudflareDiagnosticCategory(_ value: String?, allowed: [String]) -> String? {
        guard let value else { return nil }
        let normalized = value.lowercased()
        return allowed.contains(normalized) ? normalized : nil
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
        // Google rejects embedded CEF user agents. Route the original HTTPS
        // authorization URL to Aside instead of launching the CEF sidecar.
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
                self.record(.focusFenceBlocked, detail: "인증을 시작한 사이트가 차단됨", key: "google-aside-focus-fence-blocked")
                return
            }
            async let statusData = Self.fetchBrowserProtectionStatus()
            async let safariRulesData = Self.fetchBrowserRules(browser: "safari")
            async let asideRulesData = Self.fetchBrowserRules(browser: "aside")
            guard let status = await statusData,
                  let safariRules = await safariRulesData,
                  let asideRules = await asideRulesData,
                  let browserBundleID = GoogleOAuthNavigationPolicy.verifiedAuthenticationBrowserBundleID(
                    status,
                    safariRulesData: safariRules,
                    asideRulesData: asideRules
                  ) else {
                self.pendingHandoffKeys.remove(handoffKey)
                self.record(
                    .browserProtectionUnverified,
                    detail: "Focus Fence가 Safari와 Aside의 YouTube·Google 검색·웹툰 차단을 모두 확인하지 못함",
                    key: "google-aside-protection-unverified"
                )
                return
            }
            guard let protectedBrowserURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browserBundleID) else {
                self.pendingHandoffKeys.remove(handoffKey)
                self.record(.protectedBrowserUnavailable, detail: "Focus Fence 보호 브라우저 앱을 찾지 못함", key: "google-protected-browser-unavailable")
                return
            }
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: protectedBrowserURL, configuration: configuration) { [weak self] _, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.pendingHandoffKeys.remove(handoffKey)
                    if let error {
                        let failure = error as NSError
                        self.record(.protectedBrowserUnavailable,
                                    detail: "보호 브라우저 열기 실패 · \(failure.domain) \(failure.code)",
                                    key: "google-protected-browser-unavailable")
                    } else {
                        self.recentHandoffKeys[handoffKey] = Date()
                        let browserLabel = browserBundleID == "com.apple.Safari" ? "safari" : "aside"
                        self.record(.protectedBrowserHandoff, key: "google-\(browserLabel)-\(originatingPage?.host ?? "auth-only")")
                    }
                }
            }
        }
    }

    func handleUnsupportedMedia(format: String, pageURL: URL?) {
        let safeFormat = format.filter { $0.isASCII && ($0.isLetter || $0.isNumber || "/-+._".contains($0)) }
        let safePageURL = GoogleOAuthNavigationPolicy.safeHTTPSPageURL(pageURL)
        let host = safePageURL?.host?.lowercased() ?? "unknown"
        let key = "media-fallback-\(host)-\(safeFormat)"
        record(.unsupportedMedia, detail: safeFormat.isEmpty ? nil : safeFormat, key: "media-\(safeFormat)")

        guard let safePageURL else {
            record(.mediaFallbackHeld, detail: "안전한 HTTPS 페이지를 확인할 수 없음", key: key)
            return
        }
        let now = Date()
        recentMediaFallbackKeys = recentMediaFallbackKeys.filter { now.timeIntervalSince($0.value) < 600 }
        guard recentMediaFallbackKeys[key] == nil,
              pendingMediaFallbackKeys.insert(key).inserted else {
            record(.duplicateSuppressed, detail: "같은 미디어 대체 요청 중복 억제", key: key)
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let snapshot = await ThreeFBrowserControlController.fetchFocusFenceRulesSnapshot()
            guard let snapshot, !snapshot.isCached,
                  GoogleOAuthNavigationPolicy.allowsProtectedCompatibilityFallback(
                    from: safePageURL,
                    focusFenceRules: snapshot.data
                  ) else {
                self.pendingMediaFallbackKeys.remove(key)
                self.record(
                    .mediaFallbackHeld,
                    detail: "현재 Focus Fence 정책이 원본 페이지를 허용하는지 확인되지 않음",
                    key: key
                )
                return
            }

            async let statusData = Self.fetchBrowserProtectionStatus()
            async let safariRulesData = Self.fetchBrowserRules(browser: "safari")
            async let asideRulesData = Self.fetchBrowserRules(browser: "aside")
            guard let status = await statusData,
                  let safariRules = await safariRulesData,
                  let asideRules = await asideRulesData,
                  let browserBundleID = GoogleOAuthNavigationPolicy.verifiedAuthenticationBrowserBundleID(
                    status,
                    safariRulesData: safariRules,
                    asideRulesData: asideRules
                  ),
                  let browserURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browserBundleID) else {
                self.pendingMediaFallbackKeys.remove(key)
                self.record(
                    .mediaFallbackHeld,
                    detail: "Focus Fence가 YouTube·Google 검색·웹툰 차단을 확인한 Safari 또는 Aside가 없음",
                    key: key
                )
                return
            }

            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([safePageURL], withApplicationAt: browserURL, configuration: configuration) { [weak self] _, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.pendingMediaFallbackKeys.remove(key)
                    if let error {
                        let failure = error as NSError
                        self.record(
                            .mediaFallbackHeld,
                            detail: "보호 브라우저 열기 실패 · \(failure.domain) \(failure.code)",
                            key: key
                        )
                    } else {
                        self.recentMediaFallbackKeys[key] = Date()
                        let browserLabel = browserBundleID == "com.apple.Safari" ? "safari" : "aside"
                        self.record(.mediaFallbackOpened, detail: "\(browserLabel) · \(safeFormat)", key: key)
                    }
                }
            }
        }
    }

    private static func fetchBrowserProtectionStatus() async -> Data? {
        await fetchFocusFenceData(path: "/usage/browser-protection")
    }

    private static func fetchBrowserRules(browser: String) async -> Data? {
        guard ["safari", "aside"].contains(browser),
              var components = URLComponents(string: "http://127.0.0.1:17361/rules") else { return nil }
        components.queryItems = [URLQueryItem(name: "browser", value: browser)]
        guard let url = components.url else { return nil }
        return await fetchFocusFenceData(url: url)
    }

    private static func fetchFocusFenceData(path: String) async -> Data? {
        guard let url = URL(string: "http://127.0.0.1:17361\(path)") else { return nil }
        return await fetchFocusFenceData(url: url)
    }

    private static func fetchFocusFenceData(url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200 else { return nil }
        return data
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
