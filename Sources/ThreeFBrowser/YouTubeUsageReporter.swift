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
      let watchMs = 0, blocked = true, wasVisible = document.visibilityState === 'visible';
      let lastPolicyAt = -Infinity, pendingReport = null, sending = false;
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
          blocked = !policy || policy.youtubeQuotaBlocked !== false;
          if (blocked) stop();
        } catch (_) { blocked = true; stop(); }
      };
      const tick = async (flush = false) => {
        await refreshQuota();
        const now = performance.now(), elapsed = now - lastAt, current = snapshot();
        if (wasVisible && elapsed > 0 && elapsed <= 15000) {
          let watchedMs = 0;
          for (const [video, next] of current) {
            const prev = samples.get(video);
            if (!prev?.playing || prev.src !== next.src || !(prev.rate > 0)) continue;
            const progress = next.t - prev.t;
            if (progress > 0 && progress <= elapsed / 1000 * prev.rate + 0.5) {
              watchedMs = Math.max(watchedMs, Math.min(elapsed, progress / prev.rate * 1000));
            }
          }
          watchMs += watchedMs;
        }
        lastAt = now; samples = current;
        wasVisible = document.visibilityState === 'visible';
        if (blocked) stop();
        const host = location.hostname.toLowerCase();
        if (!isYouTubeHost(host)) return;
        if (!pendingReport && (flush || watchMs >= 5000)) {
          const watched = Math.floor(watchMs / 1000);
          if (!watched) return;
          pendingReport = {host, reportId:crypto.randomUUID(), seconds:watched, watchSeconds:watched,
            playing:true,browser:'3f'};
          watchMs -= watched * 1000;
        }
        if (!pendingReport || sending) return;
        sending = true;
        try {
          const result = await request({type:'report', report:pendingReport});
          if (result?.ok === true) {
            pendingReport = null;
            await refreshQuota(true);
          }
        } catch (_) { /* retain the batch and report ID for a deduplicated retry */ }
        finally { sending = false; }
      };
      document.addEventListener('play', () => { if (blocked) stop(); }, true);
      document.addEventListener('playing', event => {
        if (!event.target || event.target.tagName !== 'VIDEO') return;
        lastAt = performance.now();
        samples = snapshot(); wasVisible = document.visibilityState === 'visible';
      }, true);
      for (const eventName of ['pause', 'ended']) {
        document.addEventListener(eventName, () => tick(true), true);
      }
      document.addEventListener('visibilitychange', () => tick(true), true);
      refreshQuota(true);
      setInterval(tick, 5000);
      addEventListener('yt-navigate-finish', () => tick(true), true);
    })();
    """#
}

enum YouTubeUsageBridgePayload {
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
        return ["youtubeQuotaBlocked": blocked]
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
}
