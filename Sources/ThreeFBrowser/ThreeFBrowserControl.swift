import Foundation
import Network
import WebKit
import Darwin

enum ThreeFBrowserControlPageState {
    static func isReady(modelURL: URL?, webViewURL: URL?) -> Bool {
        guard let modelURL else { return false }
        return modelURL == webViewURL
    }
}

private enum ThreeFBrowserTerminationProbe {
    static func installIfRequested() {
        guard ProcessInfo.processInfo.environment["THREEF_BROWSER_TRACE_SIGTERM"] == "1" else { return }
        var action = sigaction()
        action.sa_flags = SA_SIGINFO
        action.__sigaction_u.__sa_sigaction = threefBrowserSigtermHandler
        sigemptyset(&action.sa_mask)
        _ = sigaction(SIGTERM, &action, nil)
    }
}

private let threefBrowserSigtermHandler: @convention(c) (Int32, UnsafeMutablePointer<siginfo_t>?, UnsafeMutableRawPointer?) -> Void = { signalNumber, info, _ in
    // Fixed-size binary record: magic, signal, sender PID, sender UID. Keep the
    // handler limited to stack data and async-signal-safe POSIX calls.
    var record: (UInt32, Int32, Int32, Int32) = (
        0x33465347,
        signalNumber,
        info?.pointee.si_pid ?? -1,
        Int32(bitPattern: info?.pointee.si_uid ?? UInt32.max)
    )
    withUnsafeBytes(of: &record) { bytes in
        _ = Darwin.write(STDERR_FILENO, bytes.baseAddress, bytes.count)
    }
    _ = Darwin.signal(signalNumber, SIG_DFL)
    _ = Darwin.kill(Darwin.getpid(), signalNumber)
}

struct ThreeFControlRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
}

enum ThreeFControlRequestParser {
    static let maximumBodyBytes = 16_384

    enum ParseResult {
        case incomplete
        case request(ThreeFControlRequest)
        case invalid(Int, String)
    }

    static func parse(_ data: Data) -> ParseResult {
        let delimiter = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: delimiter) else {
            return data.count > 8_192 ? .invalid(431, "headers too large") : .incomplete
        }
        guard let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else {
            return .invalid(400, "invalid headers")
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return .invalid(400, "missing request line") }
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3, parts[2] == "HTTP/1.1" else { return .invalid(400, "invalid request line") }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return .invalid(400, "invalid header") }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, headers[name] == nil else { return .invalid(400, "duplicate header") }
            headers[name] = value
        }
        guard headers["transfer-encoding"] == nil else { return .invalid(400, "transfer encoding unsupported") }
        let contentLength: Int
        if let rawLength = headers["content-length"] {
            guard let parsed = Int(rawLength), parsed >= 0, parsed <= maximumBodyBytes else {
                return .invalid(413, "body too large")
            }
            contentLength = parsed
        } else {
            contentLength = 0
        }
        let bodyStart = headerRange.upperBound
        let available = data.count - bodyStart
        guard available >= contentLength else { return .incomplete }
        guard available == contentLength else { return .invalid(400, "unexpected trailing data") }
        return .request(ThreeFControlRequest(
            method: String(parts[0]),
            path: String(parts[1]),
            headers: headers,
            body: data[bodyStart...]
        ))
    }
}

@MainActor
final class ThreeFBrowserControlController {
    static let shared = ThreeFBrowserControlController()
    private weak var model: BrowserModel?
    private weak var webView: WKWebView?
    private let authorizeNavigation: ((URL) async -> Bool?)?
    private var navigationCompletion: CheckedContinuation<Bool, Never>?
    private var navigationTimeout: Task<Void, Never>?
    private var navigationTargetID: ObjectIdentifier?

    init(navigationAuthorizer: ((URL) async -> Bool?)? = ThreeFBrowserControlController.focusFencePolicyDecision) {
        authorizeNavigation = navigationAuthorizer
    }

    nonisolated static func focusFencePolicyDecision(for url: URL) async -> Bool? {
        guard OptionalFeatureAvailability.focusFenceEnforcement else { return true }
        guard let data = await fetchFocusFenceRules() else { return nil }
        return focusFenceAllows(url, rules: data)
    }

    nonisolated static func navigationAuthorizationDecision(
        for url: URL,
        rules data: Data
    ) -> BrowserNavigationAuthorizationDecision {
        guard let allowed = focusFenceAllows(url, rules: data) else { return .unavailable }
        if allowed { return .allowed }

        guard let rules = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              rules["youtubeQuotaBlocked"] as? Bool == true,
              let host = url.host?.lowercased(),
              (host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")),
              host != "music.youtube.com" else { return .blocked }
        return .youtubeBlocked
    }

    nonisolated static func refreshFocusFencePolicyContact() async -> Bool {
        await fetchFocusFenceRules() != nil
    }

    nonisolated static func fetchFocusFenceRules() async -> Data? {
        var components = URLComponents(string: "http://127.0.0.1:17361/rules")!
        components.queryItems = [URLQueryItem(name: "browser", value: "3f")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 2
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = response as? HTTPURLResponse, status.statusCode == 200,
              usableFocusFenceRules(data) else { return nil }
        return data
    }

    nonisolated static func usableFocusFenceRules(_ data: Data) -> Bool {
        guard let rules = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              rules["blockedDomains"] is [String],
              rules["blockedUrlParts"] is [String],
              rules["keywords"] is [String],
              rules["blockExceptions"] is [String] else { return false }
        return true
    }

    nonisolated static func focusFenceAllows(_ url: URL, rules data: Data) -> Bool? {
        guard let rules = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let host = url.host?.lowercased(), !host.isEmpty,
              let blockedDomains = rules["blockedDomains"] as? [String],
              let blockedURLParts = rules["blockedUrlParts"] as? [String],
              let keywords = rules["keywords"] as? [String],
              let blockExceptions = rules["blockExceptions"] as? [String] else { return nil }
        func normalizedDomain(_ value: String) -> String {
            let domain = value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return domain.hasPrefix("www.") ? String(domain.dropFirst(4)) : domain
        }
        let normalizedHost = normalizedDomain(host)
        let exceptions = blockExceptions.map(normalizedDomain)
        if exceptions.contains(where: { normalizedHost == $0 || normalizedHost.hasSuffix("." + $0) }) { return true }
        func isBlockedHost(_ candidate: String) -> Bool {
            let candidate = normalizedDomain(candidate)
            return blockedDomains.contains { entry in
                let domain = normalizedDomain(entry)
                return !domain.isEmpty && (candidate == domain || candidate.hasSuffix("." + domain))
            }
        }
        let hostBlocked = isBlockedHost(host)
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let nestedHostBlocked = queryItems.contains { item in
            var candidate = item.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            for layer in 0...2 {
                let target: URL?
                if candidate.hasPrefix("//") {
                    target = URL(string: "https:" + candidate)
                } else if candidate.range(of: #"^https?://"#, options: .regularExpression) != nil {
                    target = URL(string: candidate)
                } else if candidate.range(of: #"^[^\s/?#@]+(?:\.[^\s/?#@]+)+(?:[/?#].*)?$"#, options: .regularExpression) != nil {
                    target = URL(string: "https://" + candidate)
                } else {
                    target = nil
                }
                if let nestedHost = target?.host, !exceptions.contains(where: {
                    let domain = normalizedDomain($0)
                    return normalizedDomain(nestedHost) == domain || normalizedDomain(nestedHost).hasSuffix("." + domain)
                }), isBlockedHost(nestedHost) { return true }
                guard layer < 2, let decoded = candidate.removingPercentEncoding, decoded != candidate else { break }
                candidate = decoded
            }
            return false
        }
        let urlSuffix = "\(url.path)\(url.query.map { "?\($0)" } ?? "")\(url.fragment.map { "#\($0)" } ?? "")".lowercased()
        let hostVariants = Array(Set([host, normalizedHost]))
        var addresses = hostVariants.map { "\($0)\(urlSuffix)" }
        addresses.append(contentsOf: queryItems.flatMap { ["\($0.name)=\($0.value ?? "")", $0.value ?? ""] }.map { $0.lowercased() })
        for address in addresses {
            var decoded = address
            for _ in 0..<2 {
                guard let next = decoded.removingPercentEncoding?.lowercased(), next != decoded else { break }
                addresses.append(next)
                decoded = next
            }
        }
        let partBlocked = blockedURLParts.contains { part in
            !part.isEmpty && addresses.contains { $0.contains(part.lowercased()) }
        }
        let keywordBlocked = keywords.contains { keyword in
            keyword.count >= 2 && addresses.contains { $0.contains(keyword.lowercased()) }
        }
        let firstLabel = normalizedHost.split(separator: ".").first.map(String.init) ?? ""
        let stem = String(firstLabel.reversed().drop(while: \.isNumber).reversed())
        let digitCount = firstLabel.count - stem.count
        let numericEvasionBlocked = stem.count >= 5 && (1...4).contains(digitCount)
            && blockedURLParts.contains(stem)
        return !(hostBlocked || nestedHostBlocked || partBlocked || keywordBlocked || numericEvasionBlocked)
    }

    func attach(model: BrowserModel, webView: WKWebView) {
        self.model = model
        self.webView = webView
    }

    func performNavigation(for target: AnyObject, _ start: () -> Void) async -> Bool {
        guard navigationCompletion == nil else { return false }
        let targetID = ObjectIdentifier(target)
        return await withCheckedContinuation { continuation in
            navigationCompletion = continuation
            navigationTargetID = targetID
            navigationTimeout = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled else { return }
                self?.finishNavigation(success: false, targetID: targetID)
            }
            start()
        }
    }

    func navigationDidFinish(for target: AnyObject) {
        finishNavigation(success: true, targetID: ObjectIdentifier(target))
    }

    func navigationDidFail(for target: AnyObject) {
        finishNavigation(success: false, targetID: ObjectIdentifier(target))
    }

    private func finishNavigation(success: Bool, targetID: ObjectIdentifier) {
        guard let continuation = navigationCompletion,
              navigationTargetID == targetID else { return }
        navigationCompletion = nil
        navigationTargetID = nil
        navigationTimeout?.cancel()
        navigationTimeout = nil
        continuation.resume(returning: success)
    }

    func handle(_ request: ThreeFControlRequest) async -> (Int, [String: Any]) {
        switch (request.method, request.path) {
        case ("GET", "/v1/status"):
            guard let model, let webView else { return (503, ["ok": false, "error": "browser view not ready"]) }
            let pageReady = ThreeFBrowserControlPageState.isReady(modelURL: model.currentURL, webViewURL: webView.url)
            return (200, ["ok": true, "url": model.currentURL?.absoluteString ?? "about:blank",
                          "title": pageReady ? (webView.title ?? "") : "", "ready": pageReady,
                          "backURL": pageReady ? (webView.backForwardList.backItem?.url.absoluteString ?? "") : "",
                          "forwardURL": pageReady ? (webView.backForwardList.forwardItem?.url.absoluteString ?? "") : ""])
        case ("GET", "/v1/read"):
            guard let webView else { return (503, ["ok": false, "error": "browser view not ready"]) }
            guard let pageURL = model?.currentURL,
                  ThreeFBrowserControlPageState.isReady(modelURL: pageURL, webViewURL: webView.url) else {
                return (409, ["ok": false, "error": "selected browser page is not ready"])
            }
            do {
                let value = try await evaluate("document.body?.innerText?.slice(0, 12000) || ''", in: webView)
                return (200, ["ok": true, "url": pageURL.absoluteString, "text": value as? String ?? ""])
            } catch { return (502, ["ok": false, "error": "page text could not be read"]) }
        case ("GET", "/v1/aria"):
            guard let webView else { return (503, ["ok": false, "error": "browser view not ready"]) }
            guard let pageURL = model?.currentURL,
                  ThreeFBrowserControlPageState.isReady(modelURL: pageURL, webViewURL: webView.url) else {
                return (409, ["ok": false, "error": "selected browser page is not ready"])
            }
            let script = """
            (() => {
              const els = [...document.querySelectorAll('a[href],button,input,textarea,select,[role="button"],[role="link"],[role="textbox"]')];
              return els.slice(0, 100).map((el, i) => {
                const id = 'oc-agent-' + (i + 1); el.dataset.threefAgentId = id;
                const label = el.getAttribute('aria-label') || el.innerText || el.value || el.placeholder || el.title || '';
                return '[' + id + '] ' + (el.getAttribute('role') || el.tagName.toLowerCase()) + ' ' + String(label).trim().replace(/\\s+/g, ' ').slice(0, 160);
              }).filter(line => !line.endsWith(' ')).join('\\n') + '\\n' + (document.body?.innerText || '').slice(0, 6000);
            })()
            """
            do {
                let value = try await evaluate(script, in: webView)
                return (200, ["ok": true, "url": pageURL.absoluteString, "ariaTree": value as? String ?? ""])
            } catch { return (502, ["ok": false, "error": "page accessibility tree could not be read"]) }
        case ("POST", "/v1/navigate"):
            guard let payload = try? JSONSerialization.jsonObject(with: request.body) as? [String: String],
                  let rawURL = payload["url"], let components = URLComponents(string: rawURL),
                  let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  let host = components.host, !host.isEmpty,
                  components.user == nil, components.password == nil,
                  let url = components.url else {
                return (400, ["ok": false, "error": "valid HTTP or HTTPS URL required"])
            }
            let targetModel = model
            let targetWebView = webView
            guard let authorizeNavigation else {
                return (503, ["ok": false, "error": "Focus Fence navigation policy is unavailable"])
            }
            guard let allowed = await authorizeNavigation(url) else {
                return (503, ["ok": false, "error": "Focus Fence navigation policy is unavailable"])
            }
            guard allowed else {
                return (403, ["ok": false, "error": "navigation blocked by Focus Fence"])
            }
            guard let targetModel, let targetWebView else { return (503, ["ok": false, "error": "browser view not ready"]) }
            let completed = await performNavigation(for: targetWebView) { targetModel.navigate(to: url) }
            guard completed, let currentURL = targetWebView.url else {
                return (504, ["ok": false, "error": "browser page load could not be confirmed"])
            }
            return (200, ["ok": true, "url": currentURL.absoluteString])
        case ("POST", "/v1/history"):
            guard let payload = try? JSONSerialization.jsonObject(with: request.body) as? [String: String],
                  let action = payload["action"], let webView else {
                return (400, ["ok": false, "error": "history action required"])
            }
            guard ThreeFBrowserControlPageState.isReady(modelURL: model?.currentURL, webViewURL: webView.url) else {
                return (409, ["ok": false, "error": "selected browser page is not ready"])
            }
            let target: URL?
            switch action {
            case "back": target = webView.backForwardList.backItem?.url
            case "forward": target = webView.backForwardList.forwardItem?.url
            case "reload": target = webView.url
            default: return (400, ["ok": false, "error": "supported actions: back, forward, reload"])
            }
            guard let target, let scheme = target.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  target.user == nil, target.password == nil else {
                return (409, ["ok": false, "error": "there is no safe page for this history action"])
            }
            let completed = await performNavigation(for: webView) {
                switch action {
                case "back": webView.goBack()
                case "forward": webView.goForward()
                default: webView.reload()
                }
            }
            guard completed, let currentURL = webView.url else {
                return (504, ["ok": false, "error": "browser history navigation could not be confirmed"])
            }
            return (200, ["ok": true, "url": currentURL.absoluteString])
        case ("POST", "/v1/act"):
            guard let payload = try? JSONSerialization.jsonObject(with: request.body) as? [String: String],
                  let action = payload["action"], let webView else {
                return (400, ["ok": false, "error": "action required"])
            }
            guard ThreeFBrowserControlPageState.isReady(modelURL: model?.currentURL, webViewURL: webView.url) else {
                return (409, ["ok": false, "error": "selected browser page is not ready"])
            }
            let pattern = try! NSRegularExpression(pattern: #"^(click|type|fill)\s+\[?(oc-agent-\d+)\]?\s*(.*)$"#, options: [.caseInsensitive, .dotMatchesLineSeparators])
            let range = NSRange(action.startIndex..., in: action)
            guard let match = pattern.firstMatch(in: action, range: range),
                  let operationRange = Range(match.range(at: 1), in: action),
                  let idRange = Range(match.range(at: 2), in: action),
                  let valueRange = Range(match.range(at: 3), in: action) else {
                return (400, ["ok": false, "error": "supported actions: click, type, or fill an oc-agent element from the current accessibility tree"])
            }
            let operation = String(action[operationRange]).lowercased()
            let elementID = String(action[idRange])
            let value = String(action[valueRange])
            let script: String
            if operation == "click" {
                script = """
                (() => { const el = document.querySelector('[data-threef-agent-id=' + JSON.stringify(\(jsString(elementID))) + ']'); if (!el) return 'element not found'; el.click(); return 'clicked'; })()
                """
            } else {
                script = """
                (() => {
                  const el = document.querySelector('[data-threef-agent-id=' + JSON.stringify(\(jsString(elementID))) + ']');
                  if (!el) return 'element not found';
                  if (!('value' in el)) return 'element is not editable';
                  const value = \(jsString(value));
                  const setter = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(el), 'value')?.set;
                  setter ? setter.call(el, value) : (el.value = value);
                  el.dispatchEvent(new Event('input', { bubbles: true }));
                  el.dispatchEvent(new Event('change', { bubbles: true }));
                  return 'typed';
                })()
                """
            }
            do {
                let result = try await evaluate(script, in: webView) as? String ?? "action failed"
                let ok = ["clicked", "typed"].contains(result)
                return (ok ? 200 : 404, ["ok": ok, "result": result])
            } catch { return (502, ["ok": false, "error": "browser action failed"]) }
        default:
            return (404, ["ok": false, "error": "unknown control endpoint"])
        }
    }

    private func evaluate(_ script: String, in webView: WKWebView) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { value, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: value) }
            }
        }
    }

    private func jsString(_ value: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [value])) ?? Data("[\"\"]".utf8)
        let array = String(data: data, encoding: .utf8) ?? "[\"\"]"
        return String(array.dropFirst().dropLast())
    }
}

@MainActor
final class ThreeFBrowserControlServer {
    private struct Descriptor: Encodable {
        let schemaVersion = 1
        let host = "127.0.0.1"
        let port: UInt16
        let token: String
    }

    private struct ExistingDescriptor: Decodable {
        let token: String
    }

    private let controller: ThreeFBrowserControlController
    private let queue = DispatchQueue(label: "com.rogan.threef.control-server")
    private let descriptorURL: URL
    private let token: String
    private var listener: NWListener?

    init(controller: ThreeFBrowserControlController? = nil, descriptorURL customDescriptorURL: URL? = nil) {
        self.controller = controller ?? .shared
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        descriptorURL = customDescriptorURL ?? support.appendingPathComponent("3F Browser/only-chat-control.json")
        token = UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    func start() {
        guard listener == nil else { return }
        ThreeFBrowserTerminationProbe.installIfRequested()
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host("127.0.0.1"), port: .any)
            let listener = try NWListener(using: parameters)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    guard let self else { connection.cancel(); return }
                    connection.start(queue: self.queue)
                    self.receive(connection, accumulated: Data())
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                guard case .ready = state, let port = listener.port?.rawValue else { return }
                Task { @MainActor in self?.writeDescriptor(port: port) }
            }
            listener.start(queue: queue)
        } catch {
            listener = nil
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        // Multiple app/candidate processes can coexist during QA. Only remove
        // the descriptor if it still belongs to this listener; otherwise a
        // retiring process can silently disconnect the surviving browser.
        guard let data = try? Data(contentsOf: descriptorURL),
              let descriptor = try? JSONDecoder().decode(ExistingDescriptor.self, from: data),
              descriptor.token == token else { return }
        try? FileManager.default.removeItem(at: descriptorURL)
    }

    /// Reclaim the shared descriptor when this browser becomes the foreground
    /// instance. Another QA/candidate process may have overwritten it and exited
    /// before its termination callback could remove the file.
    func publishForActiveInstance() {
        guard let port = listener?.port?.rawValue else { return }
        writeDescriptor(port: port)
    }

    private func writeDescriptor(port: UInt16) {
        do {
            let directory = descriptorURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let data = try JSONEncoder().encode(Descriptor(port: port, token: token))
            try data.write(to: descriptorURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: descriptorURL.path)
        } catch {
            listener?.cancel()
            listener = nil
        }
    }

    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                var combined = accumulated
                if let data { combined.append(data) }
                switch ThreeFControlRequestParser.parse(combined) {
                case .request(let request):
                    await self.respond(request, connection: connection)
                case .invalid(let status, let reason):
                    self.send(status: status, payload: ["ok": false, "error": reason], on: connection)
                case .incomplete where !isComplete && error == nil:
                    self.receive(connection, accumulated: combined)
                case .incomplete:
                    connection.cancel()
                }
            }
        }
    }

    private func respond(_ request: ThreeFControlRequest, connection: NWConnection) async {
        guard request.headers["host"] == "127.0.0.1:\(listener?.port?.rawValue ?? 0)",
              request.headers["origin"] == nil,
              let authorization = request.headers["authorization"],
              constantTimeEqual(authorization, "Bearer \(token)") else {
            send(status: 401, payload: ["ok": false, "error": "unauthorized"], on: connection)
            return
        }
        let (status, payload) = await controller.handle(request)
        send(status: status, payload: payload, on: connection)
    }

    private func send(status: Int, payload: [String: Any], on connection: NWConnection) {
        let body = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data("{}".utf8)
        let reason = status == 200 ? "OK" : status == 400 ? "Bad Request" : status == 401 ? "Unauthorized" : status == 403 ? "Forbidden" : status == 404 ? "Not Found" : status == 413 ? "Payload Too Large" : status == 431 ? "Request Header Fields Too Large" : status == 504 ? "Gateway Timeout" : "Service Unavailable"
        var response = Data("HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8), b = Array(rhs.utf8)
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
