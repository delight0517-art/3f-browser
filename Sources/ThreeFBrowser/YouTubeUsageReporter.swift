import Foundation

enum YouTubeUsageReporter {
    static let script = #"""
    (() => {
      if (window.__threefFFUsageReporter) return;
      window.__threefFFUsageReporter = true;
      const endpoint = 'http://127.0.0.1:17361';
      let lastAt = performance.now(), lastURL = location.href, samples = new Map();
      let dwellMs = 0, watchMs = 0, blocked = true;
      const isYouTubeHost = value => {
        const host = value.toLowerCase().replace(/^\.+|\.+$/g, '');
        return host === 'youtu.be' || ((host === 'youtube.com' || host.endsWith('.youtube.com')) && host !== 'music.youtube.com');
      };
      const snapshot = () => new Map([...document.querySelectorAll('video')].map(v => [v, {
        t: v.currentTime, src: v.currentSrc, playing: !v.paused && !v.ended && !v.seeking && v.readyState >= 2, rate: v.playbackRate
      }]));
      samples = snapshot();
      const stop = () => { if (isYouTubeHost(location.hostname)) document.querySelectorAll('video').forEach(v => { if (!v.paused) v.pause(); }); };
      const refreshQuota = async () => {
        try {
          const u = new URL(endpoint + '/rules'); u.searchParams.set('browser','3f');
          const r = await fetch(u,{cache:'no-store'}), policy = r.ok ? await r.json() : null;
          blocked = !policy || policy.youtubeQuotaBlocked !== false;
          if (blocked) stop();
        } catch (_) { blocked = true; stop(); }
      };
      const tick = async () => {
        const now = performance.now(), elapsed = now - lastAt, current = snapshot(), same = lastURL === location.href;
        if (!same) { dwellMs = 0; watchMs = 0; }
        if (same && document.visibilityState === 'visible' && elapsed > 0 && elapsed <= 15000) {
          dwellMs += elapsed;
          for (const [video, next] of current) {
            const prev = samples.get(video);
            if (!prev?.playing || prev.src !== next.src || !(prev.rate > 0)) continue;
            const progress = next.t - prev.t;
            if (progress > 0 && progress <= elapsed / 1000 * prev.rate + 0.5) watchMs += Math.min(elapsed, progress / prev.rate * 1000);
          }
        }
        lastAt = now; lastURL = location.href; samples = current;
        if (blocked) stop();
        const host = location.hostname.toLowerCase();
        if (!isYouTubeHost(host)) return;
        const seconds = Math.floor(dwellMs / 1000), watched = Math.min(seconds, Math.floor(watchMs / 1000));
        if (!seconds) return;
        try {
          const r = await fetch(endpoint + '/ingest', {method:'POST', headers:{'Content-Type':'application/json'},
            body:JSON.stringify({host,reportId:crypto.randomUUID(),seconds,watchSeconds:watched,playing:watched>0,browser:'3f'})});
          if (!r.ok) return;
          dwellMs -= seconds * 1000; watchMs -= watched * 1000;
          await refreshQuota();
        } catch (_) { /* retain elapsed usage and retry next tick */ }
      };
      document.addEventListener('play', () => { if (blocked) stop(); }, true);
      refreshQuota();
      setInterval(tick, 5000);
      addEventListener('yt-navigate-finish', () => { lastAt = performance.now(); lastURL = location.href; samples = snapshot(); }, true);
    })();
    """#
}
