import AppKit
import Foundation
import WebKit

@MainActor
final class YouTubePreviewUsageMonitor {
    static let shared = YouTubePreviewUsageMonitor()

    private weak var webView: WKWebView?
    private var timer: Timer?
    private var sampling = false
    private var pendingPlaybackMilliseconds: [String: Int] = [:]
    private var shortsProgressMilliseconds: [String: Int] = [:]
    private var countedShorts = Set<String>()

    private init() {}

    func attach(_ webView: WKWebView) {
        guard self.webView !== webView else { return }
        timer?.invalidate()
        self.webView = webView
        pendingPlaybackMilliseconds.removeAll()
        shortsProgressMilliseconds.removeAll()
        countedShorts.removeAll()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.sampleAndReport() }
        }
    }

    private func sampleAndReport() async {
        guard !sampling, NSApp.isActive, let webView, webView.window != nil else { return }
        sampling = true
        defer { sampling = false }

        guard let sample = await readSample(from: webView), sample.progressMilliseconds > 0,
              let pageURL = webView.url, isYouTube(pageURL.host) else { return }

        let accumulated = (pendingPlaybackMilliseconds[sample.videoID] ?? 0) + sample.progressMilliseconds
        let creditedSeconds = accumulated / 1_000
        pendingPlaybackMilliseconds[sample.videoID] = accumulated % 1_000

        var shortsEventID: String?
        if sample.isShorts {
            let pageKey = sample.videoID
            let total = (shortsProgressMilliseconds[pageKey] ?? 0) + sample.progressMilliseconds
            shortsProgressMilliseconds[pageKey] = total
            if total >= 1_000, !countedShorts.contains(pageKey) {
                countedShorts.insert(pageKey)
                shortsEventID = UUID().uuidString.lowercased()
            }
        }
        guard creditedSeconds > 0 else { return }

        var payload: [String: Any] = [
            "host": "www.youtube.com",
            "browser": "3f",
            "seconds": creditedSeconds,
            "watchSeconds": creditedSeconds,
            "playing": true,
            "url": sample.isShorts
                ? "https://www.youtube.com/shorts/\(sample.videoID)"
                : pageURL.absoluteString,
            "videoId": sample.videoID,
            "title": sample.title,
            "channelId": sample.channelID,
            "reportId": UUID().uuidString.lowercased()
        ]
        if let shortsEventID { payload["shortsEventId"] = shortsEventID }
        await post(payload)
    }

    private func readSample(from webView: WKWebView) async -> Sample? {
        guard NSApp.isActive, webView.window != nil,
              let raw = try? await webView.evaluateJavaScript(Self.sampleScript) else { return nil }
        let value: Any?
        if let encoded = raw as? String, let data = encoded.data(using: .utf8) {
            value = try? JSONSerialization.jsonObject(with: data)
        } else {
            value = raw
        }
        guard let object = value as? [String: Any],
              let videoID = object["videoID"] as? String,
              videoID.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil,
              let progress = object["progressMilliseconds"] as? Int else { return nil }
        return Sample(
            videoID: videoID,
            isShorts: object["isShorts"] as? Bool == true,
            title: String((object["title"] as? String ?? "").prefix(200)),
            channelID: String((object["channelID"] as? String ?? "").prefix(100)),
            progressMilliseconds: min(5_000, max(0, progress))
        )
    }

    private func post(_ payload: [String: Any]) async {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let url = URL(string: "http://127.0.0.1:17361/ingest") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 2
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        _ = try? await URLSession.shared.data(for: request)
    }

    private func isYouTube(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "youtube.com" || host == "www.youtube.com" || host == "m.youtube.com"
    }

    private struct Sample {
        let videoID: String
        let isShorts: Bool
        let title: String
        let channelID: String
        let progressMilliseconds: Int
    }

    private static let sampleScript = #"""
    (() => {
      try {
        if (document.visibilityState !== 'visible' ||
            !/^(?:(?:www|m)\.)?youtube\.com$/i.test(location.hostname)) return null;
        const videos = [...document.querySelectorAll('video')];
        for (const video of videos) {
          if (video.paused || video.ended || video.seeking || video.readyState < 2 || video.currentTime <= 0) continue;
          const rect = video.getBoundingClientRect();
          if (rect.width < 40 || rect.height < 40 || rect.bottom <= 0 || rect.right <= 0 || rect.top >= innerHeight || rect.left >= innerWidth) continue;
          if (video.closest('ytd-ad-slot-renderer, ytd-promoted-sparkles-web-renderer, #player-ads')) continue;

          const shortsMatch = location.pathname.match(/^\/shorts\/([A-Za-z0-9_-]{11})\/?$/);
          let videoID = shortsMatch?.[1] || new URL(location.href).searchParams.get('v') || '';
          let isShorts = !!shortsMatch;
          let card = null;
          if (!videoID) {
            card = video.closest('ytd-reel-item-renderer, ytd-rich-item-renderer, ytd-reel-video-renderer, ytd-video-preview, ytd-compact-video-renderer, ytm-shorts-lockup-view-model, ytm-reel-item-renderer, ytd-rich-grid-media');
            if (!card) {
              for (let node = video.parentElement, depth = 0; node && depth < 7; node = node.parentElement, depth++) {
                if (node.querySelector('a[href*="/shorts/"], a[href*="watch?v="]')) { card = node; break; }
              }
            }
            if (!card) continue;
            const identities = [...new Map([...card.querySelectorAll('a[href*="/shorts/"], a[href*="watch?v="]')].map(link => {
              const url = new URL(link.href, location.href);
              const shorts = url.pathname.match(/^\/shorts\/([A-Za-z0-9_-]{11})\/?$/)?.[1];
              const id = shorts || url.searchParams.get('v') || '';
              return /^[A-Za-z0-9_-]{11}$/.test(id) ? [id, !!shorts] : ['', false];
            }).filter(([id]) => id))];
            if (identities.length !== 1) continue;
            videoID = identities[0][0]; isShorts = identities[0][1];
          }
          const old = window.__threefPreviewSample;
          const now = performance.now();
          const source = video.currentSrc || video.src;
          const delta = old ? video.currentTime - old.position : 0;
          const elapsed = old ? (now - old.at) / 1000 : 0;
          const verified = !!old && old.video === video && old.videoID === videoID && old.source === source && old.rate > 0 && elapsed > 0 && elapsed <= 5 && delta > 0 && delta <= elapsed * video.playbackRate + 0.5;
          window.__threefPreviewSample = {video, videoID, source, position: video.currentTime, rate: video.playbackRate, at: now};
          const title = card?.querySelector('#video-title, h3, [title]')?.getAttribute('title') || card?.querySelector('#video-title, h3, [title]')?.textContent || document.title || '';
          const channelHref = card?.querySelector('a[href*="/channel/"], a[href*="/@"]')?.href || '';
          const channelID = channelHref.match(/\/channel\/(UC[A-Za-z0-9_-]{22})/)?.[1] || channelHref.match(/\/@([A-Za-z0-9._-]{3,30})/)?.[1] || '';
          return JSON.stringify({videoID, isShorts, title: String(title).trim().slice(0, 200), channelID, progressMilliseconds: verified ? Math.floor(delta * 1000) : 0});
        }
        window.__threefPreviewSample = null;
      } catch (_) { window.__threefPreviewSample = null; }
      return null;
    })()
    """#
}
