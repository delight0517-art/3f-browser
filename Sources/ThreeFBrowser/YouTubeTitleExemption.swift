import Combine
import Foundation
import WebKit

struct YouTubeTitleKeywordRule: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let keyword: String
    let createdAt: Date
    let applyAfter: Date
}

@MainActor
final class YouTubeTitleExemptionStore: ObservableObject {
    static let shared = YouTubeTitleExemptionStore(preferences: BrowserPreferenceStore())
    static let applyDelay: TimeInterval = 40 * 60

    @Published private(set) var applied: [YouTubeTitleKeywordRule] = []
    @Published private(set) var pending: [YouTubeTitleKeywordRule] = []

    private struct State: Codable {
        var applied: [YouTubeTitleKeywordRule] = []
        var pending: [YouTubeTitleKeywordRule] = []
    }

    private let key = "youtube.titleTimeExemptions.v1"
    private let preferences: BrowserPreferenceStore

    init(preferences: BrowserPreferenceStore) {
        self.preferences = preferences
        guard let data = preferences.data(forKey: key),
              let state = try? JSONDecoder().decode(State.self, from: data) else { return }
        applied = state.applied.filter { Self.normalizedKeyword($0.keyword) != nil }
        pending = state.pending.filter { Self.normalizedKeyword($0.keyword) != nil }
    }

    @discardableResult
    func addPending(_ rawKeyword: String, now: Date = Date()) -> YouTubeTitleKeywordRule? {
        guard let keyword = Self.normalizedKeyword(rawKeyword),
              applied.count + pending.count < 200,
              !(applied + pending).contains(where: { Self.sameKeyword($0.keyword, keyword) }) else { return nil }
        let rule = YouTubeTitleKeywordRule(
            id: UUID().uuidString,
            keyword: keyword,
            createdAt: now,
            applyAfter: now.addingTimeInterval(Self.applyDelay)
        )
        pending.append(rule)
        save()
        return rule
    }

    @discardableResult
    func applyPending(id: String, now: Date = Date()) -> Bool {
        guard let index = pending.firstIndex(where: { $0.id == id }),
              pending[index].applyAfter <= now else { return false }
        applied.append(pending.remove(at: index))
        save()
        return true
    }

    @discardableResult
    func removeApplied(id: String) -> Bool {
        let originalCount = applied.count
        applied.removeAll { $0.id == id }
        guard applied.count != originalCount else { return false }
        save()
        return true
    }

    func matchingApplied(to title: String) -> [YouTubeTitleKeywordRule] {
        applied.filter { Self.title(title, contains: $0.keyword) }
    }

    func policyFields() -> [String: Any] {
        [
            "unlimitedTitleKeywords": applied.map(\.keyword),
            "appliedTitleKeywords": applied.map { ["id": $0.id, "keyword": $0.keyword] },
            "pendingTitleKeywords": pending.map {
                ["id": $0.id, "keyword": $0.keyword, "applyAfterMs": Int64($0.applyAfter.timeIntervalSince1970 * 1_000)]
            }
        ]
    }

    static func normalizedKeyword(_ raw: String) -> String? {
        let keyword = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !keyword.isEmpty, keyword.count <= 80,
              !keyword.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        return keyword
    }

    static func title(_ title: String, contains keyword: String) -> Bool {
        title.range(of: keyword, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private static func sameKeyword(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive], range: nil, locale: .current) == .orderedSame
    }

    private func save() {
        let state = State(applied: applied, pending: pending)
        guard let data = try? JSONEncoder().encode(state) else { return }
        preferences.set(data, forKey: key)
    }
}

enum YouTubeTitleExemptionScripts {
    static let selectionMessageName = "threefYouTubeKeywordSelection"

    static let selection = #"""
    (() => {
      const bridge = window.webkit?.messageHandlers?.threefYouTubeKeywordSelection;
      if (!bridge?.postMessage || window.__threefKeywordSelectionReporter) return;
      window.__threefKeywordSelectionReporter = true;
      let last = null;
      const send = () => {
        const selected = String(window.getSelection?.() || '').trim().replace(/\s+/g, ' ').slice(0, 80);
        if (selected === last) return;
        last = selected;
        bridge.postMessage(selected);
      };
      document.addEventListener('selectionchange', () => setTimeout(send, 0), true);
      document.addEventListener('contextmenu', send, true);
      document.addEventListener('mouseup', () => setTimeout(send, 0), true);
    })();
    """#

    static let overlay = #"""
    (() => {
      const bridge = window.webkit?.messageHandlers?.threefYouTubeUsage;
      if (!bridge?.postMessage || window.__threefKeywordExemptionOverlay) return;
      window.__threefKeywordExemptionOverlay = true;
      let policy = null, lastRefresh = 0, refreshing = null;
      const videoRoute = () => /^\/(?:watch|shorts|live|embed)(?:\/|$)/i.test(location.pathname || '');
      const videoTitle = () => (document.querySelector('meta[property="og:title"]')?.content || document.title || '')
        .replace(/\s*[-|·]\s*YouTube\s*$/i, '').trim();
      const normalize = value => String(value || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
      const matches = (title, keyword) => normalize(title).includes(normalize(keyword));
      const refresh = async (force = false) => {
        if (refreshing) return refreshing;
        if (!force && performance.now() - lastRefresh < 1500) return;
        lastRefresh = performance.now();
        refreshing = bridge.postMessage({type:'policy'}).then(value => { policy = value; render(); }).catch(() => {})
          .finally(() => { refreshing = null; });
        return refreshing;
      };
      const action = async (type, id) => {
        try { await bridge.postMessage({type, id}); } catch (_) {}
        await refresh(true);
      };
      const render = () => {
        const id = '__threef_youtube_keyword_exemptions';
        let panel = document.getElementById(id);
        if (!videoRoute() || !policy) { panel?.remove(); return; }
        const title = videoTitle();
        const applied = (policy.appliedTitleKeywords || []).filter(rule => matches(title, rule.keyword));
        const pending = (policy.pendingTitleKeywords || []).filter(rule => matches(title, rule.keyword));
        if (!applied.length && !pending.length) { panel?.remove(); return; }
        if (!panel) {
          panel = document.createElement('section'); panel.id = id;
          panel.style.cssText = 'position:fixed;right:16px;bottom:16px;z-index:2147483646;max-width:300px;padding:10px 12px;border-radius:12px;background:rgba(28,24,36,.92);color:#fff;font:12px system-ui,sans-serif;box-shadow:0 4px 18px #0005;pointer-events:auto';
          document.documentElement.appendChild(panel);
        }
        panel.replaceChildren();
        const heading = document.createElement('div'); heading.textContent = 'YouTube 시간 무제한 키워드';
        heading.style.cssText = 'font-weight:700;margin-bottom:6px'; panel.appendChild(heading);
        for (const rule of applied) {
          const row = document.createElement('div'); row.style.cssText = 'display:flex;align-items:center;gap:10px;margin-top:4px';
          const name = document.createElement('span'); name.textContent = rule.keyword; name.style.cssText = 'flex:1;overflow-wrap:anywhere';
          const remove = document.createElement('button'); remove.type = 'button'; remove.textContent = '×';
          remove.title = `“${rule.keyword}” 키워드 즉시 제거`;
          remove.style.cssText = 'border:0;border-radius:10px;background:#ffffff22;color:#fff;font-size:16px;line-height:20px;width:24px;height:24px;cursor:pointer';
          remove.addEventListener('click', () => { void action('removeTitleKeyword', rule.id); });
          row.append(name, remove); panel.appendChild(row);
        }
        for (const rule of pending) {
          const row = document.createElement('div'); row.style.cssText = 'display:flex;align-items:center;gap:8px;margin-top:6px';
          const name = document.createElement('span'); name.textContent = rule.keyword; name.style.cssText = 'flex:1;overflow-wrap:anywhere'; row.appendChild(name);
          const waitMs = Number(rule.applyAfterMs) - Date.now();
          if (waitMs > 0) {
            const wait = document.createElement('span'); wait.textContent = `Apply까지 ${Math.ceil(waitMs / 60000)}분`;
            wait.style.cssText = 'opacity:.78;white-space:nowrap'; row.appendChild(wait);
          } else {
            const apply = document.createElement('button'); apply.type = 'button'; apply.textContent = 'Apply';
            apply.style.cssText = 'border:0;border-radius:7px;padding:4px 8px;background:#a78bfa;color:#201737;font-weight:700;cursor:pointer';
            apply.addEventListener('click', () => { void action('applyTitleKeyword', rule.id); }); row.appendChild(apply);
          }
          panel.appendChild(row);
        }
      };
      void refresh(true);
      setInterval(() => { render(); void refresh(); }, 1000);
      addEventListener('yt-navigate-finish', () => { void refresh(true); }, true);
    })();
    """#
}

@MainActor
final class YouTubeKeywordSelectionScriptMessageHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              YouTubeUsageBridgePayload.isYouTubeHost(message.webView?.url?.host ?? ""),
              let selected = message.body as? String,
              let webView = message.webView as? ThreeFWindowAwareWebView else { return }
        webView.selectedYouTubeKeyword = YouTubeTitleExemptionStore.normalizedKeyword(selected)
    }
}
