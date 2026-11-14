import Foundation
import WebKit

enum YouTubeUsageReporter {
    static let iframeKeyboardBlockerScript = #"""
    (() => {
      try {
        const host = location.hostname.toLowerCase().replace(/^\.+|\.+$/g, '');
        const isYouTubeHost = host === 'youtu.be' ||
          ((host === 'youtube.com' || host.endsWith('.youtube.com')) && host !== 'music.youtube.com');
        if (!isYouTubeHost || window.top === window || window.__threefQuotaKeyboardBlocker) return;
        window.__threefQuotaKeyboardBlocker = true;
        const bridge = window.webkit?.messageHandlers?.threefYouTubeUsage;
        let blocked = true, inFlight = null, lastRefreshAt = -Infinity;
        const refreshPolicy = async (force = false) => {
          if (inFlight) return inFlight;
          const now = performance.now();
          if (!force && now - lastRefreshAt < 500) return;
          lastRefreshAt = now;
          const pending = (async () => {
            try {
              if (!bridge?.postMessage) throw new Error('usage bridge unavailable');
              const policy = await bridge.postMessage({ type: 'policy' });
              const remainingSeconds = Number.isSafeInteger(policy?.remainingSeconds) ? policy.remainingSeconds : 0;
              blocked = !policy || policy.youtubeQuotaBlocked !== false || remainingSeconds === 0;
            } catch (_) { blocked = true; }
          })();
          inFlight = pending;
          try { await pending; }
          finally { if (inFlight === pending) inFlight = null; }
        };
        document.addEventListener('keydown', event => {
          if (!blocked || !['ArrowLeft', 'ArrowRight'].includes(event.key)) return;
          const target = event.target;
          if (target instanceof HTMLElement && (target.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName))) return;
          event.preventDefault();
          event.stopImmediatePropagation();
        }, true);
        void refreshPolicy(true);
        setInterval(() => { void refreshPolicy(); }, 1000);
        window.addEventListener('yt-navigate-finish', () => { void refreshPolicy(true); }, true);
      } catch (_) {}
    })();
    """#

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
      let quotaBlocked = true, shortsBlocked = false;
      let lastPolicyAt = -Infinity, pendingReport = null, sending = false;
      let leaseMode = 'unknown', leaseRequestPending = false, accountLease = null;
      let accountIntervals = [], accountReportPending = null, accountReportSending = false;
      const leaseRetryIntervalMs = 30000;
      const policyRefreshIntervalMs = 2000;
      let policyRefreshInFlight = null;
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
      // Stop document-start autoplay synchronously while the first policy read is pending.
      // An allowed response still requires an explicit user play action.
      stop();
      const enforcePolicy = () => {
        const onShorts = /^\/shorts(?:\/|$)/i.test(location.pathname || '');
        blocked = quotaBlocked || (shortsBlocked && onShorts);
        if (blocked) stop();
      };
      document.addEventListener('keydown', event => {
        if (!blocked || !['ArrowLeft', 'ArrowRight'].includes(event.key)) return;
        const target = event.target;
        if (target instanceof HTMLElement && (target.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName))) return;
        event.preventDefault();
        event.stopImmediatePropagation();
      }, true);
      const refreshQuota = async (force = false) => {
        const now = performance.now();
        if (policyRefreshInFlight) return policyRefreshInFlight;
        if (!force && now - lastPolicyAt < policyRefreshIntervalMs) return;
        lastPolicyAt = now;
        const pending = (async () => {
          try {
            const policy = await request({type:'policy'});
            remainingSeconds = Number.isSafeInteger(policy?.remainingSeconds) ? policy.remainingSeconds : 0;
            quotaBlocked = !policy || policy.youtubeQuotaBlocked !== false || remainingSeconds === 0;
            shortsBlocked = policy?.blockShorts === true;
            enforcePolicy();
            if (blocked) { watchMs = 0; stop(); }
          } catch (_) { remainingSeconds = 0; quotaBlocked = true; blocked = true; watchMs = 0; stop(); }
        })();
        policyRefreshInFlight = pending;
        try { await pending; }
        finally { if (policyRefreshInFlight === pending) policyRefreshInFlight = null; }
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
            if (receipt?.allowed === false && receipt?.status !== 400) { quotaBlocked = true; blocked = true; stop(); }
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
          enforcePolicy();
          if (!blocked && (leaseMode === 'local' || accountLease)) {
            document.querySelectorAll('video').forEach(v => { if (v.paused) v.play().catch(() => {}); });
          }
        }
      };
      const sendAccountReport = async () => {
        if (!accountLease || !accountIntervals.length) return true;
        if (accountReportSending) return false;
        if (!accountReportPending) accountReportPending = {
          type:'leaseReport', report:{grantId:accountLease.grantId,reportId:crypto.randomUUID(),intervals:accountIntervals.slice(0,20).map(x => x.slice())}
        };
        accountReportSending = true;
        let queued = false;
        try {
          const result = await request(accountReportPending);
          if (result?.queued === true) {
            accountIntervals.splice(0, accountReportPending.report.intervals.length);
            accountReportPending = null;
            queued = true;
            await refreshQuota(true);
          }
        } catch (_) { /* retain intervals and report ID for a deduplicated retry */ }
        finally { accountReportSending = false; }
        return queued;
      };
      const moveAccountUsageToLocalLedger = async () => {
        if (!accountLease) return false;
        const intervals = accountReportPending?.report?.intervals || accountIntervals;
        const watchedMs = intervals.reduce((sum, range) => sum + Math.max(0, range[1] - range[0]), 0);
        const seconds = Math.ceil(watchedMs / 1000);
        if (seconds > 0) {
          const sourceReportId = accountReportPending?.report?.reportId || crypto.randomUUID();
          const report = {
            host: location.hostname.toLowerCase(), reportId:`lease-fallback-${sourceReportId}`,
            seconds, watchSeconds:seconds, playing:true, browser:'3f'
          };
          try {
            const result = await request({type:'report', report});
            if (result?.ok !== true) return false;
          } catch (_) { return false; }
        }
        // The native report route durably enqueues before returning success. Once
        // accepted, local policy includes these seconds and retries the upload.
        accountIntervals = [];
        accountReportPending = null;
        accountLease = null;
        leaseMode = 'local';
        lastLeaseAttemptAt = performance.now();
        await refreshQuota(true);
        enforcePolicy();
        return true;
      };
      const tick = async (flush = false) => {
        await refreshQuota();
        enforcePolicy();
        const host = location.hostname.toLowerCase();
        const onYouTube = isYouTubeHost(host);
        const now = performance.now(), elapsed = now - lastAt, current = snapshot();
        let watchedMs = 0;
        // WebKit can coalesce background timers; count only a bounded gap with matching media progress.
        const maxElapsedMs = document.visibilityState === 'hidden' ? 120000 : 15000;
        if (!blocked && onYouTube && elapsed > 0 && elapsed <= maxElapsedMs) {
          for (const [video, next] of current) {
            const prev = samples.get(video);
            if (!prev?.playing || !(prev.rate > 0)) continue;
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
            const reportAccepted = await sendAccountReport();
            if (reportAccepted && !accountReportPending && accountIntervals.length === 0) {
              await requestAccountLease(true);
            } else if (await moveAccountUsageToLocalLedger()) {
              if (!blocked) enforcePolicy();
            } else {
              quotaBlocked = true; blocked = true; stop();
            }
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
            if (remainingSeconds === 0) { quotaBlocked = true; blocked = true; watchMs = 0; stop(); }
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
      document.addEventListener('play', enforcePolicy, true);
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
      addEventListener('yt-navigate-finish', () => { enforcePolicy(); tick(true); }, true);
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

/// Durable last-known Focus Fence policy and aggregate-only usage queue. This is
/// deliberately local to the 3F app profile; the web page never receives URLs,
/// titles, account identifiers, or the persisted queue itself.
@MainActor
final class YouTubeOfflineQuotaStore {
    static let shared = YouTubeOfflineQuotaStore()
    private struct Snapshot: Codable {
        var fetchedAt: Date
        var quotaBlocked: Bool
        var quotaResetAt: Date?
        var scheduled: Bool
        var siteBlocked: Bool
        var blockShorts: Bool
        var dailyCapMinutes: Int
        var todaySeconds: Int
        var hourlyCapMinutes: Int?
        var hourlyRemainingSeconds: Int?
        var hourlyPolicyKnown: Bool
    }

    private struct LocalReport: Codable {
        var reportID: String
        var host: String
        var seconds: Int
        var watchSeconds: Int
        var createdAt: Date
        var acknowledged: Bool
    }

    private struct State: Codable {
        var snapshot: Snapshot?
        var reports: [LocalReport] = []
    }

    private let defaults: UserDefaults
    private let key = "threef.focusFence.youtubeOfflineQuota.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func saveServerSnapshot(rules: [String: Any], usage: FocusFenceYouTubeUsageSummary,
                            hourlyPolicyKnown: Bool, observedAt: Date = Date()) {
        var state = load()
        let reset = (rules["youtubeQuotaResetAfterSeconds"] as? Int).flatMap {
            (0...172_800).contains($0) ? $0 : nil
        }
        state.snapshot = Snapshot(
            fetchedAt: observedAt,
            quotaBlocked: (rules["youtubeQuotaBlocked"] as? Bool == true) || usage.blocked,
            quotaResetAt: reset.map { observedAt.addingTimeInterval(TimeInterval($0)) },
            scheduled: rules["youtubeBlockedByActiveSchedule"] as? Bool == true,
            siteBlocked: ThreeFBrowserControlController.youtubeSiteIsBlocked(rules: rules) ?? true,
            blockShorts: rules["blockShorts"] as? Bool == true,
            dailyCapMinutes: usage.dailyCapMinutes,
            todaySeconds: usage.todaySeconds,
            hourlyCapMinutes: usage.hourlyCapMinutes,
            hourlyRemainingSeconds: usage.hourlyRemainingSeconds,
            hourlyPolicyKnown: hourlyPolicyKnown
        )
        // A fresh server read after an acknowledged ingest includes that report.
        state.reports.removeAll { $0.acknowledged && $0.createdAt <= observedAt }
        save(state)
    }

    func enqueue(_ payload: [String: Any], now: Date = Date()) -> Bool {
        guard let reportID = payload["reportId"] as? String,
              let host = payload["host"] as? String,
              let seconds = payload["seconds"] as? Int,
              let watchSeconds = payload["watchSeconds"] as? Int else { return false }
        var state = load()
        guard !state.reports.contains(where: { $0.reportID == reportID }) else { return true }
        state.reports.append(LocalReport(reportID: reportID, host: host, seconds: seconds,
                                         watchSeconds: watchSeconds, createdAt: now, acknowledged: false))
        // Retain a bounded local ledger: one day's reports cover daily quota and
        // give a conservative rolling-hour fallback after a long disconnection.
        state.reports.removeAll { $0.acknowledged && now.timeIntervalSince($0.createdAt) > 86_400 }
        save(state)
        return true
    }

    func pendingReports() -> [[String: Any]] {
        load().reports.filter { !$0.acknowledged }.map {
            ["host": $0.host, "reportId": $0.reportID, "seconds": $0.seconds,
             "watchSeconds": $0.watchSeconds, "playing": true, "browser": "3f"]
        }
    }

    func acknowledge(reportID: String) {
        var state = load()
        guard let index = state.reports.firstIndex(where: { $0.reportID == reportID }) else { return }
        state.reports[index].acknowledged = true
        save(state)
    }

    func offlinePolicy(now: Date = Date()) -> [String: Any] {
        let state = load()
        guard let snapshot = state.snapshot else { return ["youtubeQuotaBlocked": true, "remainingSeconds": 0] }
        let localDay = Calendar.current.startOfDay(for: now)
        let baseDay = Calendar.current.startOfDay(for: snapshot.fetchedAt)
        let sameDay = localDay == baseDay
        let reportsToday = state.reports.filter { Calendar.current.startOfDay(for: $0.createdAt) == localDay }
        let addedToday = reportsToday.reduce(0) { $0 + $1.watchSeconds }
        let dailyUsed = (sameDay ? snapshot.todaySeconds : 0) + addedToday

        let recentReports = state.reports.filter { now.timeIntervalSince($0.createdAt) < 3_600 }
        let localRecentSeconds = recentReports.reduce(0) { $0 + $1.watchSeconds }
        let cachedHourlyRemaining: Int?
        if let cap = snapshot.hourlyCapMinutes, cap > 0,
           now.timeIntervalSince(snapshot.fetchedAt) < 3_600,
           let remaining = snapshot.hourlyRemainingSeconds {
            cachedHourlyRemaining = max(0, remaining - state.reports.filter {
                $0.createdAt > snapshot.fetchedAt && now.timeIntervalSince($0.createdAt) < 3_600
            }.reduce(0) { $0 + $1.watchSeconds })
        } else if let cap = snapshot.hourlyCapMinutes, cap > 0 {
            cachedHourlyRemaining = max(0, cap * 60 - localRecentSeconds)
        } else if snapshot.hourlyPolicyKnown {
            cachedHourlyRemaining = nil
        } else {
            cachedHourlyRemaining = 0
        }

        var remaining = [Int]()
        if snapshot.dailyCapMinutes > 0 { remaining.append(max(0, snapshot.dailyCapMinutes * 60 - dailyUsed)) }
        if let cachedHourlyRemaining { remaining.append(cachedHourlyRemaining) }
        let remainingSeconds = remaining.min() ?? -1
        let resetExpired = snapshot.quotaResetAt.map { now >= $0 } ?? false
        let quotaBlocked = snapshot.quotaBlocked && !resetExpired
        let blocked = snapshot.siteBlocked || snapshot.scheduled || quotaBlocked || remainingSeconds == 0
        return ["youtubeQuotaBlocked": blocked,
                "remainingSeconds": remainingSeconds,
                "blockShorts": snapshot.blockShorts,
                "youtubeBlockedByActiveSchedule": snapshot.scheduled,
                "offline": true,
                "observedAt": snapshot.fetchedAt.timeIntervalSince1970]
    }

    func offlineSummary(now: Date = Date()) -> FocusFenceYouTubeUsageSummary? {
        let state = load()
        guard let snapshot = state.snapshot else { return nil }
        let policy = offlinePolicy(now: now)
        let localDay = Calendar.current.startOfDay(for: now)
        let sameDay = localDay == Calendar.current.startOfDay(for: snapshot.fetchedAt)
        let todayUsed = (sameDay ? snapshot.todaySeconds : 0) + state.reports
            .filter { Calendar.current.startOfDay(for: $0.createdAt) == localDay }
            .reduce(0) { $0 + $1.watchSeconds }
        let recent = state.reports.filter { now.timeIntervalSince($0.createdAt) < 3_600 }
        let localRecentSeconds = recent.reduce(0) { $0 + $1.watchSeconds }
        let effectiveHourlyRemaining: Int? = snapshot.hourlyCapMinutes.flatMap { cap in
            guard cap > 0 else { return nil }
            if now.timeIntervalSince(snapshot.fetchedAt) < 3_600,
               let remaining = snapshot.hourlyRemainingSeconds {
                let afterSnapshot = state.reports.filter {
                    $0.createdAt > snapshot.fetchedAt && now.timeIntervalSince($0.createdAt) < 3_600
                }.reduce(0) { $0 + $1.watchSeconds }
                return max(0, remaining - afterSnapshot)
            }
            return max(0, cap * 60 - localRecentSeconds)
        }
        let hourlyUsed = snapshot.hourlyCapMinutes.map { cap in
            cap == 0 ? 0 : max(0, cap * 60 - (effectiveHourlyRemaining ?? 0))
        }
        let dataObject: [String: Any] = [
            "todaySeconds": todayUsed,
            "dailyCapMinutes": snapshot.dailyCapMinutes,
            "hourlyCapMinutes": snapshot.hourlyCapMinutes as Any? ?? NSNull(),
            "hourlyUsedSeconds": hourlyUsed as Any? ?? NSNull(),
            "hourlyRemainingSeconds": effectiveHourlyRemaining as Any? ?? NSNull(),
            "blocked": policy["youtubeQuotaBlocked"] as? Bool ?? true,
            "localOnly": true
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dataObject),
              let summary = FocusFenceYouTubeUsageSummary.decode(data) else { return nil }
        let resetSeconds = snapshot.quotaResetAt.map { max(0, Int($0.timeIntervalSince(now))) }
        let policyObject: [String: Any] = [
            "youtubeQuotaBlocked": policy["youtubeQuotaBlocked"] as? Bool ?? true,
            "youtubeBlockedByActiveSchedule": snapshot.scheduled,
            "youtubeQuotaResetAfterSeconds": resetSeconds as Any? ?? NSNull(),
            "blockShorts": snapshot.blockShorts
        ]
        guard let policyData = try? JSONSerialization.data(withJSONObject: policyObject),
              let playbackPolicy = FocusFenceYouTubePlaybackPolicy.decode(policyData) else { return summary }
        return summary.withPolicy(playbackPolicy, observedAt: now)
    }

    private func load() -> State {
        guard let data = defaults.data(forKey: key), let state = try? JSONDecoder().decode(State.self, from: data) else { return State() }
        return state
    }

    private func save(_ state: State) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }
}

@MainActor
final class YouTubeUsageScriptMessageHandler: NSObject, WKScriptMessageHandlerWithReply {
    static let name = "threefYouTubeUsage"
    private let offlineQuotaStore = YouTubeOfflineQuotaStore.shared

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        guard YouTubeUsageBridgePayload.isYouTubeHost(message.frameInfo.securityOrigin.host),
              let webView = message.webView,
              YouTubeUsageBridgePayload.isYouTubeHost(webView.url?.host ?? ""),
              let body = message.body as? [String: Any],
              let type = body["type"] as? String,
              message.frameInfo.isMainFrame || type == "policy" else {
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
        let qaRequested = FocusFenceQARouting.isQARequested()
        let baseURL = qaRequested ? FocusFenceQARouting.currentQARequestBaseURL() : URL(string: "http://127.0.0.1:17361")
        guard let baseURL else { return offlineQuotaStore.offlinePolicy() }
        var components = URLComponents(url: baseURL.appendingPathComponent("rules"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "browser", value: "3f")]
        guard let url = components.url else { return offlineQuotaStore.offlinePolicy() }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 5
        let session = qaRequested ? FocusFenceQARouting.makeSession() : URLSession.shared
        guard let (data, response) = try? await session.data(for: request),
              let response = response as? HTTPURLResponse,
              response.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocked = object["youtubeQuotaBlocked"] as? Bool,
              let youtubeSiteBlocked = ThreeFBrowserControlController.youtubeSiteIsBlocked(rules: object) else {
            return offlineQuotaStore.offlinePolicy()
        }
        var usageRequest = URLRequest(url: baseURL.appendingPathComponent("usage/youtube"))
        usageRequest.httpMethod = "GET"
        usageRequest.timeoutInterval = FocusFenceYouTubeUsageClient.requestTimeoutInterval
        usageRequest.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        guard let (usageData, usageResponse) = try? await session.data(for: usageRequest),
              (usageResponse as? HTTPURLResponse)?.statusCode == 200,
              let usage = FocusFenceYouTubeUsageSummary.decode(usageData),
              let usageObject = try? JSONSerialization.jsonObject(with: usageData) as? [String: Any] else {
            return offlineQuotaStore.offlinePolicy()
        }
        var remaining = [Int]()
        if usage.dailyCapMinutes > 0 {
            remaining.append(max(0, usage.dailyCapMinutes * 60 - usage.todaySeconds))
        }
        if let hourlyCapMinutes = usage.hourlyCapMinutes,
           let hourlyRemainingSeconds = usage.hourlyRemainingSeconds,
           hourlyCapMinutes > 0 {
            remaining.append(hourlyRemainingSeconds)
        }
        let remainingSeconds = remaining.min() ?? -1
        let result: [String: Any] = ["youtubeQuotaBlocked": blocked || youtubeSiteBlocked || usage.blocked || remainingSeconds == 0,
                                     "remainingSeconds": remainingSeconds,
                                     "blockShorts": object["blockShorts"] as? Bool ?? false,
                                     "youtubeBlockedByActiveSchedule": object["youtubeBlockedByActiveSchedule"] as? Bool ?? false]
        offlineQuotaStore.saveServerSnapshot(rules: object, usage: usage, hourlyPolicyKnown: usageObject["hourlyCapMinutes"] != nil && !(usageObject["hourlyCapMinutes"] is NSNull))
        await flushPendingReports(baseURL: baseURL, qaRequested: qaRequested)
        return result
    }

    private func sendReport(_ payload: [String: Any]) async -> Bool {
        let qaRequested = FocusFenceQARouting.isQARequested()
        let baseURL = qaRequested ? FocusFenceQARouting.currentQARequestBaseURL() : URL(string: "http://127.0.0.1:17361")
        guard offlineQuotaStore.enqueue(payload) else { return false }
        guard let baseURL else { return true }
        await flushPendingReports(baseURL: baseURL, qaRequested: qaRequested)
        return true
    }

    private func flushPendingReports(baseURL: URL, qaRequested: Bool) async {
        for payload in offlineQuotaStore.pendingReports() {
            var request = URLRequest(url: baseURL.appendingPathComponent("ingest"))
            request.httpMethod = "POST"
            request.timeoutInterval = 5
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            guard let data = try? JSONSerialization.data(withJSONObject: payload) else { continue }
            request.httpBody = data
            guard let (_, response) = try? await (qaRequested ? FocusFenceQARouting.makeSession() : .shared).data(for: request),
                  let response = response as? HTTPURLResponse, response.statusCode == 200,
                  let reportID = payload["reportId"] as? String else { continue }
            offlineQuotaStore.acknowledge(reportID: reportID)
        }
    }

    private func requestLease(_ payload: [String: Any]) async -> [String: Any] {
        let qaRequested = FocusFenceQARouting.isQARequested()
        let baseURL = qaRequested ? FocusFenceQARouting.currentQARequestBaseURL() : URL(string: "http://127.0.0.1:17361")
        guard let baseURL else { return ["ok": false, "error": "unavailable"] }
        var components = URLComponents(url: baseURL.appendingPathComponent("youtube/budget/grant"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "browser", value: "3f")]
        guard let url = components.url else { return ["ok": false, "error": "unavailable"] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            return ["ok": false, "error": "invalid_request"]
        }
        request.httpBody = data
        guard let (responseData, response) = try? await (qaRequested ? FocusFenceQARouting.makeSession() : .shared).data(for: request),
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
        let qaRequested = FocusFenceQARouting.isQARequested()
        let baseURL = qaRequested ? FocusFenceQARouting.currentQARequestBaseURL() : URL(string: "http://127.0.0.1:17361")
        guard let baseURL else { return ["queued": false] }
        var components = URLComponents(url: baseURL.appendingPathComponent("youtube/budget/report"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "browser", value: "3f")]
        guard let url = components.url else { return ["queued": false] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return ["queued": false] }
        request.httpBody = data
        guard let (responseData, response) = try? await (qaRequested ? FocusFenceQARouting.makeSession() : .shared).data(for: request),
              let response = response as? HTTPURLResponse,
              response.statusCode == 200,
              let body = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              body["ok"] as? Bool == true else { return ["queued": false] }
        return ["queued": true, "summary": body["summary"] ?? [:]]
    }
}
