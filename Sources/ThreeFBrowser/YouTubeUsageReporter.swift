import Foundation
import WebKit

enum YouTubeUsageReporter {
    static let script = #"""
    (() => {
      if (window.__threefFFUsageReporter) return;
      window.__threefFFUsageReporter = true;
      const bridge = window.webkit?.messageHandlers?.threefYouTubeUsage;
      const request = payload => {
        if (!bridge?.postMessage) return Promise.reject(new Error('usage bridge unavailable'));
        return bridge.postMessage(payload);
      };
      let lastAt = performance.now(), samples = new Map();
      let watchMs = 0, blocked = true, remainingSeconds = 0;
      let lastPolicyAt = -Infinity, pendingReport = null, sending = false;
      let leaseMode = 'unknown', leaseRequestPending = false, accountLease = null;
      let accountIntervals = [], accountReportPending = null, accountReportSending = false;
      const leaseRetryIntervalMs = 30000;
      let lastLeaseAttemptAt = -Infinity;
      const isYouTubeHost = value => {
        const host = value.toLowerCase().replace(/^\.+|\.+$/g, '');
        return host === 'youtu.be' || ((host === 'youtube.com' || host.endsWith('.youtube.com')) && host !== 'music.youtube.com');
      };
      const snapshot = () => new Map([...document.querySelectorAll('video')].map(v => [v, {
        t: v.currentTime, src: v.currentSrc, playing: !v.paused && !v.ended && !v.seeking && v.readyState >= 2, rate: v.playbackRate
      }]));
      samples = snapshot();
      const stop = () => { if (isYouTubeHost(location.hostname)) document.querySelectorAll('video').forEach(v => { if (!v.paused) v.pause(); }); };
      const refreshQuota = async (force = false) => {
        const now = performance.now();
        if (!force && now - lastPolicyAt < 30000) return;
        lastPolicyAt = now;
        try {
          const policy = await request({type:'policy'});
          remainingSeconds = Number.isSafeInteger(policy?.remainingSeconds) ? policy.remainingSeconds : 0;
          blocked = !policy || policy.youtubeQuotaBlocked !== false;
          blocked = blocked || remainingSeconds === 0;
          if (blocked) { watchMs = 0; stop(); }
        } catch (_) { remainingSeconds = 0; blocked = true; watchMs = 0; stop(); }
      };
      const requestAccountLease = async (renew = false) => {
        if (leaseRequestPending || blocked || !isYouTubeHost(location.hostname)) return;
        leaseRequestPending = true;
        lastLeaseAttemptAt = performance.now();
        document.querySelectorAll('video').forEach(v => { if (!v.paused) v.pause(); });
        const requestedAt = performance.now();
        try {
          const requestId = crypto.randomUUID();
          const receipt = await request({type:'lease',requestId,qualificationMs:5000});
          if (receipt?.status === 400 && receipt?.error === 'invalid_youtube_lease_request') {
            leaseMode = 'local';
            accountLease = null;
            return;
          }
          if (receipt?.ok !== true || receipt.allowed !== true) {
            if (receipt?.allowed === false && receipt?.status !== 400) { blocked = true; stop(); }
            else leaseMode = 'local';
            return;
          }
          if (receipt.schemaVersion !== 3 || receipt.requestId !== requestId ||
              receipt.billingMode !== 'minimum_5s_qualified_30s_account_lease_v1' ||
              receipt.qualificationMs !== 5000 || receipt.quantumMs !== 30000 ||
              typeof receipt.grantId !== 'string' || !Number.isSafeInteger(receipt.startMs) ||
              !Number.isSafeInteger(receipt.endMs) || !Number.isSafeInteger(receipt.serverNowMs) ||
              receipt.endMs - receipt.startMs !== 30000) { leaseMode = 'local'; return; }
          const roundTrip = Math.max(0, performance.now() - requestedAt);
          const remaining = receipt.endMs - receipt.serverNowMs - roundTrip;
          if (remaining <= 0) { leaseMode = 'local'; return; }
          leaseMode = 'account';
          accountLease = {
            grantId: receipt.grantId, startMs: receipt.startMs, endMs: receipt.endMs,
            serverOffsetMs: receipt.serverNowMs - Date.now() + roundTrip / 2,
            deadline: performance.now() + remaining
          };
          watchMs = 0;
          await refreshQuota(true);
        } catch (_) {
          leaseMode = 'local';
        } finally {
          leaseRequestPending = false;
          if (!blocked && (leaseMode === 'local' || accountLease)) {
            document.querySelectorAll('video').forEach(v => { if (v.paused) v.play().catch(() => {}); });
          }
        }
      };
      const sendAccountReport = async () => {
        if (!accountLease || !accountIntervals.length || accountReportSending) return;
        if (!accountReportPending) accountReportPending = {
          type:'leaseReport', report:{grantId:accountLease.grantId,reportId:crypto.randomUUID(),intervals:accountIntervals.slice(0,20).map(x => x.slice())}
        };
        accountReportSending = true;
        try {
          const result = await request(accountReportPending);
          if (result?.queued === true) {
            accountIntervals.splice(0, accountReportPending.report.intervals.length);
            accountReportPending = null;
            await refreshQuota(true);
          }
        } catch (_) { /* retain intervals and report ID for a deduplicated retry */ }
        finally { accountReportSending = false; }
      };
      const tick = async (flush = false) => {
        await refreshQuota();
        const host = location.hostname.toLowerCase();
        const onYouTube = isYouTubeHost(host);
        const now = performance.now(), elapsed = now - lastAt, current = snapshot();
        let watchedMs = 0;
        // WebKit can coalesce background timers; count only a bounded gap with matching media progress.
        const maxElapsedMs = document.visibilityState === 'hidden' ? 120000 : 15000;
        if (!blocked && onYouTube && elapsed > 0 && elapsed <= maxElapsedMs) {
          for (const [video, next] of current) {
            const prev = samples.get(video);
            if (!prev?.playing || prev.src !== next.src || !(prev.rate > 0)) continue;
            const progress = next.t - prev.t;
            if (progress > 0 && progress <= elapsed / 1000 * prev.rate + 0.5) {
              watchedMs = Math.max(watchedMs, Math.min(elapsed, progress / prev.rate * 1000));
            }
          }
          if (leaseMode === 'account' && accountLease && performance.now() <= accountLease.deadline) {
            const end = Math.min(accountLease.endMs, Math.round(Date.now() + accountLease.serverOffsetMs));
            const start = Math.max(accountLease.startMs, end - Math.round(watchedMs));
            const previous = accountIntervals[accountIntervals.length - 1];
            if (end > start) {
              if (previous && start <= previous[1]) previous[1] = Math.max(previous[1], end);
              else accountIntervals.push([start, end]);
            }
          } else {
            watchMs += watchedMs;
          }
        } else if (!onYouTube || blocked) {
          watchMs = 0;
        }
        lastAt = now; samples = current;
        if (blocked) stop();
        if (!onYouTube) return;
        if (leaseMode === 'account' && accountLease) {
          if (flush || accountIntervals.reduce((sum, range) => sum + range[1] - range[0], 0) >= 5000) await sendAccountReport();
          if (performance.now() >= accountLease.deadline && !leaseRequestPending && !blocked) {
            await sendAccountReport();
            if (!accountReportPending && accountIntervals.length === 0) await requestAccountLease(true);
            else { blocked = true; stop(); }
          }
          return;
        }
        if (leaseMode === 'unknown' && !leaseRequestPending && watchMs >= 5000) {
          await requestAccountLease();
          if (leaseMode === 'account' || leaseRequestPending) return;
        }
        const reportThresholdMs = remainingSeconds < 0 ? 5000 : Math.min(5, remainingSeconds) * 1000;
        if (!pendingReport && (flush || watchMs >= reportThresholdMs)) {
          const watched = Math.floor(watchMs / 1000);
          const reportSeconds = remainingSeconds < 0 ? watched : Math.min(watched, remainingSeconds);
          if (!reportSeconds) return;
          pendingReport = {host, reportId:crypto.randomUUID(), seconds:reportSeconds, watchSeconds:reportSeconds,
            playing:true,browser:'3f'};
          watchMs = remainingSeconds < 0 ? watchMs - reportSeconds * 1000 : Math.max(0, watchMs - reportSeconds * 1000);
          if (remainingSeconds >= 0) {
            remainingSeconds -= reportSeconds;
            if (remainingSeconds === 0) { blocked = true; watchMs = 0; stop(); }
          }
        }
        if (!pendingReport || sending) return;
        sending = true;
        try {
          const result = await request({type:'report', report:pendingReport});
          if (result?.ok === true) {
            pendingReport = null;
            await refreshQuota(true);
            if (leaseMode === 'local' && watchMs < 1000 &&
                performance.now() - lastLeaseAttemptAt >= leaseRetryIntervalMs) {
              await requestAccountLease(true);
            }
          }
        } catch (_) { /* retain the batch and report ID for a deduplicated retry */ }
        finally { sending = false; }
      };
      document.addEventListener('play', () => { if (blocked) stop(); }, true);
      document.addEventListener('playing', event => {
        if (!event.target || event.target.tagName !== 'VIDEO') return;
        lastAt = performance.now();
        samples = snapshot();
      }, true);
      for (const eventName of ['pause', 'ended']) {
        document.addEventListener(eventName, () => tick(true), true);
      }
      document.addEventListener('visibilitychange', () => tick(true), true);
      refreshQuota(true);
      setInterval(tick, 1000);
      addEventListener('yt-navigate-finish', () => tick(true), true);
    })();
    """#
}

enum YouTubeUsageBridgePayload {
    static let playbackQualificationMilliseconds = 5_000
    static let accountLeaseQuantumMilliseconds = 30_000

    static func leaseRequest(from value: Any, pageHost: String) -> [String: Any]? {
        guard isYouTubeHost(pageHost),
              let input = value as? [String: Any],
              let requestID = input["requestId"] as? String,
              (1...96).contains(requestID.utf8.count),
              requestID.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-").contains($0)
              }),
              let qualification = input["qualificationMs"] as? Int,
              qualification == playbackQualificationMilliseconds else { return nil }
        return ["requestId": requestID, "qualificationMs": qualification]
    }

    static func leaseReport(from value: Any, pageHost: String) -> [String: Any]? {
        guard isYouTubeHost(pageHost),
              let input = value as? [String: Any],
              let grantID = input["grantId"] as? String,
              (1...96).contains(grantID.utf8.count),
              grantID.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-").contains($0)
              }),
              let reportID = input["reportId"] as? String,
              (1...96).contains(reportID.utf8.count),
              reportID.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-").contains($0)
              }),
              let rawIntervals = input["intervals"] as? [[NSNumber]],
              rawIntervals.count <= 20 else { return nil }

        let intervals = rawIntervals.map { $0.map(\.int64Value) }
        guard intervals.allSatisfy({ $0.count == 2 && $0[0] >= 0 && $0[1] > $0[0] }) else { return nil }
        return ["grantId": grantID, "reportId": reportID, "intervals": intervals, "browser": "3f"]
    }

    static func report(from value: Any, pageHost: String) -> [String: Any]? {
        guard isYouTubeHost(pageHost),
              let input = value as? [String: Any],
              let reportID = input["reportId"] as? String,
              (1...80).contains(reportID.utf8.count),
              reportID.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-").contains($0)
              }),
              let seconds = input["seconds"] as? Int, (1...120).contains(seconds),
              let watchSeconds = input["watchSeconds"] as? Int, (1...seconds).contains(watchSeconds) else {
            return nil
        }
        return [
            "host": pageHost.lowercased(),
            "reportId": reportID,
            "seconds": seconds,
            "watchSeconds": watchSeconds,
            "playing": true,
            "browser": "3f"
        ]
    }

    static func isYouTubeHost(_ host: String) -> Bool {
        let value = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return value == "youtu.be" ||
            ((value == "youtube.com" || value.hasSuffix(".youtube.com")) && value != "music.youtube.com")
    }
}

@MainActor
final class YouTubeUsageScriptMessageHandler: NSObject, WKScriptMessageHandlerWithReply {
    static let name = "threefYouTubeUsage"
    private let endpoint = URL(string: "http://127.0.0.1:17361")!

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        guard message.frameInfo.isMainFrame,
              YouTubeUsageBridgePayload.isYouTubeHost(message.frameInfo.securityOrigin.host),
              let webView = message.webView,
              YouTubeUsageBridgePayload.isYouTubeHost(webView.url?.host ?? ""),
              let body = message.body as? [String: Any],
              let type = body["type"] as? String else {
            replyHandler(nil, "untrusted usage message")
            return
        }

        Task { @MainActor in
            switch type {
            case "policy":
                replyHandler(await fetchPolicy(), nil)
            case "lease":
                guard let requestBody = YouTubeUsageBridgePayload.leaseRequest(from: body, pageHost: webView.url?.host ?? "") else {
                    replyHandler(["ok": false, "error": "invalid_request"], nil)
                    return
                }
                replyHandler(await requestLease(requestBody), nil)
            case "leaseReport":
                guard let reportBody = body["report"],
                      let report = YouTubeUsageBridgePayload.leaseReport(from: reportBody, pageHost: webView.url?.host ?? "") else {
                    replyHandler(["queued": false], nil)
                    return
                }
                replyHandler(await sendLeaseReport(report), nil)
            case "report":
                guard let reportBody = body["report"],
                      let report = YouTubeUsageBridgePayload.report(from: reportBody, pageHost: webView.url?.host ?? "") else {
                    replyHandler(["ok": false], nil)
                    return
                }
                replyHandler(["ok": await sendReport(report)], nil)
            default:
                replyHandler(nil, "unsupported usage message")
            }
        }
    }

    private func fetchPolicy() async -> [String: Any] {
        var components = URLComponents(url: endpoint.appendingPathComponent("rules"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "browser", value: "3f")]
        var request = URLRequest(url: components.url!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 5
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let response = response as? HTTPURLResponse,
              response.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocked = object["youtubeQuotaBlocked"] as? Bool else {
            return ["youtubeQuotaBlocked": true]
        }
        guard let usage = await FocusFenceYouTubeUsageClient.fetch() else {
            return ["youtubeQuotaBlocked": true, "remainingSeconds": 0]
        }
        var remaining = [Int]()
        if usage.dailyCapMinutes > 0 {
            remaining.append(max(0, usage.dailyCapMinutes * 60 - usage.todaySeconds))
        }
        if usage.hourlyCapMinutes > 0 { remaining.append(usage.hourlyRemainingSeconds) }
        let remainingSeconds = remaining.min() ?? -1
        return ["youtubeQuotaBlocked": blocked || usage.blocked || remainingSeconds == 0,
                "remainingSeconds": remainingSeconds]
    }

    private func sendReport(_ payload: [String: Any]) async -> Bool {
        var request = URLRequest(url: endpoint.appendingPathComponent("ingest"))
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return false }
        request.httpBody = data
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let response = response as? HTTPURLResponse else { return false }
        return response.statusCode == 200
    }

    private func requestLease(_ payload: [String: Any]) async -> [String: Any] {
        var components = URLComponents(url: endpoint.appendingPathComponent("youtube/budget/grant"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "browser", value: "3f")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            return ["ok": false, "error": "invalid_request"]
        }
        request.httpBody = data
        guard let (responseData, response) = try? await URLSession.shared.data(for: request),
              let response = response as? HTTPURLResponse,
              let body = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            return ["ok": false, "error": "unavailable"]
        }
        guard response.statusCode == 200 else {
            return ["ok": false, "status": response.statusCode, "error": body["error"] ?? "unavailable"]
        }
        return ["ok": true].merging(body) { _, new in new }
    }

    private func sendLeaseReport(_ payload: [String: Any]) async -> [String: Any] {
        var components = URLComponents(url: endpoint.appendingPathComponent("youtube/budget/report"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "browser", value: "3f")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return ["queued": false] }
        request.httpBody = data
        guard let (responseData, response) = try? await URLSession.shared.data(for: request),
              let response = response as? HTTPURLResponse,
              response.statusCode == 200,
              let body = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              body["ok"] as? Bool == true else { return ["queued": false] }
        return ["queued": true, "summary": body["summary"] ?? [:]]
    }
}
