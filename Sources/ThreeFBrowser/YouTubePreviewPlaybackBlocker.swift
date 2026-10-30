import Foundation

enum YouTubePreviewPlaybackBlocker {
    static let script = #"""
    (() => {
      try {
        if (!/^(?:(?:www|m)\.)?youtube\.com$/i.test(location.hostname)) return;
        const cards = [
          'ytd-rich-item-renderer', 'ytd-video-renderer', 'ytd-compact-video-renderer',
          'ytd-reel-item-renderer', 'ytd-reel-video-renderer', 'ytd-video-preview',
          'ytd-rich-grid-media', 'ytm-shorts-lockup-view-model', 'ytm-reel-item-renderer',
          'ytm-media-item-renderer', 'ytm-rich-item-renderer'
        ].join(',');
        const marker = 'data-threef-preview-disabled';
        const styleID = 'threef-youtube-preview-disabled-style';
        const styleText = `html.threef-youtube-preview-disabled video[${marker}="1"] { visibility: hidden !important; }`;
        const isFeedPage = () => {
          if (!/^(?:(?:www|m)\.)?youtube\.com$/i.test(location.hostname)) return false;
          return location.pathname !== '/watch' && !/^\/shorts\/[A-Za-z0-9_-]{11}\/?$/.test(location.pathname);
        };
        const inCard = video => {
          if (video.closest(cards)) return true;
          for (let node = video.parentElement, depth = 0; node && depth < 7; node = node.parentElement, depth++) {
            if (node.querySelector('a[href*="/shorts/"], a[href*="watch?v="]')) return true;
          }
          return false;
        };
        const stop = video => {
          if (!isFeedPage() || !inCard(video)) return;
          video.setAttribute(marker, '1');
          video.autoplay = false;
          video.removeAttribute('autoplay');
          if (!video.paused) video.pause();
        };
        const refresh = () => {
          const root = document.documentElement;
          if (!root) return;
          const enabled = isFeedPage();
          root.classList.toggle('threef-youtube-preview-disabled', enabled);
          if (enabled) {
            if (!document.getElementById(styleID)) {
              const style = document.createElement('style');
              style.id = styleID;
              style.textContent = styleText;
              (document.head || root).appendChild(style);
            }
            for (const video of document.querySelectorAll('video')) stop(video);
          } else {
            for (const video of document.querySelectorAll(`video[${marker}="1"]`)) video.removeAttribute(marker);
            document.getElementById(styleID)?.remove();
          }
        };
        if (!window.__threefYoutubePreviewBlocker) {
          window.__threefYoutubePreviewBlocker = true;
          document.addEventListener('play', event => {
            const video = event.target;
            if (video instanceof HTMLVideoElement) stop(video);
          }, true);
          const observer = new MutationObserver(() => refresh());
          const observe = () => {
            if (document.documentElement) observer.observe(document.documentElement, {childList: true, subtree: true});
            refresh();
          };
          if (document.documentElement) observe();
          else document.addEventListener('DOMContentLoaded', observe, {once: true});
          window.addEventListener('yt-navigate-finish', refresh, true);
          window.addEventListener('popstate', refresh, true);
        } else {
          refresh();
        }
      } catch (_) {}
    })();
    """#
}
