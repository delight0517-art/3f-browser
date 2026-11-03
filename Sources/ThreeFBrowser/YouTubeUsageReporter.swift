import Foundation

enum YouTubeUsageReporter {
    static let script = #"""
    (() => {
      if (window.__threefFFUsageReporter) return;
      window.__threefFFUsageReporter = true;
      const endpoint = 'http://127.0.0.1:17361';
      let lastAt = performance.now(), lastURL = location.href, samples = new Map();
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
          const u = new URL(endpoint + '/rules'); u.searchParams.set('browser','3f');
          const r = await fetch(u,{cache:'no-store'}), policy = r.ok ? await r.json() : null;
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
        lastAt = now; lastURL = location.href; samples = current;
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
          const r = await fetch(endpoint + '/ingest', {method:'POST', headers:{'Content-Type':'application/json'},
            body:JSON.stringify(pendingReport)});
          if (r.ok) {
            pendingReport = null;
            await refreshQuota(true);
          }
        } catch (_) { /* retain the batch and report ID for a deduplicated retry */ }
        finally { sending = false; }
      };
      document.addEventListener('play', () => { if (blocked) stop(); }, true);
      document.addEventListener('playing', event => {
        if (!event.target || event.target.tagName !== 'VIDEO') return;
        lastAt = performance.now(); lastURL = location.href;
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
