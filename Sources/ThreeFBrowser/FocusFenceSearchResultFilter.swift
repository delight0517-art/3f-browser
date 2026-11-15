import Foundation

enum FocusFenceSearchResultFilter {
    private static let builtInSensitiveTitleKeywords = ["야짤", "후방주의", "후방 주의", "은꼴"]

    static let classifierSource = #"""
    function threefNormalizeHost(value) {
      return String(value || '').toLocaleLowerCase().replace(/^www\./, '').replace(/^\.+|\.+$/g, '');
    }
    function threefBuildRuleIndex(rules) {
      return {
        blockedDomains: new Set((rules.blockedDomains || []).map(threefNormalizeHost).filter(Boolean)),
        blockedUrlParts: (rules.blockedUrlParts || []).map(value => String(value || '').toLocaleLowerCase()).filter(Boolean),
        keywords: (rules.keywords || []).map(value => String(value || '').normalize('NFKC').toLocaleLowerCase().trim()),
        sensitiveTitleKeywords: [...new Set([
          '야짤', '후방주의', '후방 주의', '은꼴',
          ...(rules.keywords || []), ...(rules.adultProtectedKeywords || [])
        ].map(threefNormalizeSensitiveText).filter(value => value.length >= 2))]
      };
    }
    function threefNormalizeSensitiveText(value) {
      return String(value || '').normalize('NFKC').toLocaleLowerCase().replace(/[\s\p{P}\p{S}]+/gu, '');
    }
    function threefTitleMatchesSensitiveKeyword(title, ruleIndex) {
      const normalized = threefNormalizeSensitiveText(title);
      return Boolean(normalized) && ruleIndex.sensitiveTitleKeywords.some(keyword => normalized.includes(keyword));
    }
    function threefDomainIsBlocked(host, ruleIndex) {
      let candidate = host;
      while (candidate) {
        if (ruleIndex.blockedDomains.has(candidate)) return true;
        const separator = candidate.indexOf('.');
        if (separator < 0) break;
        candidate = candidate.slice(separator + 1);
      }
      return false;
    }
    function threefShouldHideResult(host, path, title, snippet, ruleIndex) {
      const normalizedHost = threefNormalizeHost(host);
      if (threefDomainIsBlocked(normalizedHost, ruleIndex)) return true;
      if (threefTitleMatchesSensitiveKeyword(title, ruleIndex)) return true;

      const destination = (normalizedHost + String(path || '')).toLocaleLowerCase();
      if (ruleIndex.blockedUrlParts.some(part => destination.includes(part))) return true;

      const primary = String(title || '').normalize('NFKC').toLocaleLowerCase() + ' ' + destination;
      const combined = primary + ' ' + String(snippet || '').normalize('NFKC').toLocaleLowerCase();
      const adult = /\b(adult|porn|xxx|sex sites?)\b|성인|포르노|야동/;
      const pornTLDListing = /\.porn\b/.test(combined)
        && /\b(list|directory|collection|domain list|tld list|extension list)\b|목록|모음/.test(combined);
      if (!adult.test(combined.replace(/\.porn\b/g, ' ')) && !pornTLDListing) return false;
      const directory = /\b(site lists?|websites?|extensions?|domains?|directories|directory|lists?|collections?)\b|목록|모음|주소록/;
      const directoryInPrimary = directory.test(primary);
      const directoryAnywhere = directoryInPrimary || directory.test(combined);
      const adultIPListing = /\b(ip addresses?|ip lists?|ipv[46])\b/.test(combined)
        && /\b(list|directory|database|collection)\b|목록|모음/.test(combined);
      const configuredDirectorySignal = ruleIndex.keywords.some(term => term.length >= 3 && combined.includes(term))
        && directoryAnywhere && adult.test(combined);

      // Require adult and directory context together. A neutral article that
      // only mentions the .porn TLD remains visible.
      return pornTLDListing || adultIPListing || configuredDirectorySignal || (adult.test(combined) && directoryAnywhere);
    }
    function threefShouldHideImageSearchQuery(query, ruleIndex) {
      const normalized = String(query || '').normalize('NFKC').toLocaleLowerCase().replace(/\s+/gu, ' ').trim();
      if (!normalized) return false;
      if (threefTitleMatchesSensitiveKeyword(normalized, ruleIndex)) return true;
      const blockedURLPartQuery = ruleIndex.blockedUrlParts.some(rawPart => {
        const part = String(rawPart || '').toLocaleLowerCase().trim();
        if (!/^[a-z0-9-]{4,}$/.test(part)) return false;
        const escaped = part.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        return new RegExp(`(^|[^a-z0-9])${escaped}[0-9]*(?=$|[^a-z0-9])`).test(normalized);
      });
      if (blockedURLPartQuery) return true;
      const compact = normalized.replace(/[\s\p{P}\p{S}]+/gu, '');
      const directory = /주소|link|링크|모음|모움|사이트|\bsite\b|\bwebsites?\b|\bdirector(?:y|ies)\b|\blists?\b|\bcollections?\b/u;
      const addressDirectory = /주소.{0,24}(?:link|링크|모음|모움|사이트|site|list|directory)|(?:link|링크|모음|모움|사이트|site|list|directory).{0,24}주소/u;
      const adultDirectory = /\b(?:adult|porn|xxx|sex)\b|성인|포르노|야동/u.test(normalized) && directory.test(normalized);
      const configuredDirectory = ruleIndex.keywords.some(term => Boolean(term && directory.test(term) && normalized.includes(term)));
      return addressDirectory.test(normalized) || adultDirectory || configuredDirectory
        || (compact.includes('주소') && /(?:link|링크|모음|모움|사이트|site|list|directory)/u.test(compact));
    }
    """#

    static func youtubeTitleFilterScript(rules: Data?) -> String {
        let rulesJSON: String
        if let rules, ThreeFBrowserControlController.usableFocusFenceRules(rules),
           let serialized = String(data: rules, encoding: .utf8) {
            rulesJSON = serialized
        } else {
            rulesJSON = "{}"
        }
        return #"""
        (() => {
          const rules = \#(rulesJSON);
          const builtInKeywords = ['야짤', '후방주의', '후방 주의', '은꼴'];
          \#(classifierSource)
          const host = location.hostname.toLocaleLowerCase();
          if (!(host === 'youtube.com' || host.endsWith('.youtube.com') || host === 'youtu.be')) return;
          const initialRules = { ...rules, keywords: [...(rules.keywords || []), ...builtInKeywords] };
          const previous = window.__threefSensitiveTitlePolicy;
          if (previous) { previous.update(initialRules); return; }
          const state = { rules: initialRules, hidden: new Set(), queued: false };
          window.__threefSensitiveTitlePolicy = state;
          const style = document.createElement('style');
          style.textContent = '[data-threef-sensitive-title-hidden="1"]{display:none!important} html[data-threef-sensitive-watch="1"] ytd-player,html[data-threef-sensitive-watch="1"] #player{display:none!important}';
          (document.head || document.documentElement)?.appendChild(style);
          function index() { return threefBuildRuleIndex(state.rules); }
          function setHidden(node, hidden) {
            if (!node) return;
            if (hidden && node.dataset.threefSensitiveTitleHidden !== '1') {
              node.dataset.threefSensitiveHadStyle = String(node.hasAttribute('style'));
              node.dataset.threefSensitiveOldStyle = node.getAttribute('style') || '';
              node.dataset.threefSensitiveTitleHidden = '1';
              node.style.setProperty('display', 'none', 'important');
              state.hidden.add(node);
            } else if (!hidden && node.dataset.threefSensitiveTitleHidden === '1') {
              if (node.dataset.threefSensitiveHadStyle === 'true') node.setAttribute('style', node.dataset.threefSensitiveOldStyle || '');
              else node.removeAttribute('style');
              delete node.dataset.threefSensitiveHadStyle;
              delete node.dataset.threefSensitiveOldStyle;
              delete node.dataset.threefSensitiveTitleHidden;
              state.hidden.delete(node);
            }
          }
          function titleOf(card) {
            const title = card.querySelector('#video-title, #video-title-link, a[title][href*="watch"], a[href*="/shorts/"]');
            return title?.getAttribute('title') || title?.getAttribute('aria-label') || title?.innerText || '';
          }
          function queryIsSensitive(ruleIndex) {
            try { return threefTitleMatchesSensitiveKeyword(new URL(location.href).searchParams.get('search_query'), ruleIndex); }
            catch { return false; }
          }
          function videoPageTitle() {
            return document.querySelector('ytd-watch-metadata h1, #title h1, h1 yt-formatted-string')?.innerText
              || document.querySelector('meta[property="og:title"]')?.content
              || document.title || '';
          }
          function notice(message) {
            let node = document.getElementById('threef-sensitive-title-notice');
            if (!node && document.body) {
              node = document.createElement('div');
              node.id = 'threef-sensitive-title-notice';
              node.setAttribute('role', 'status');
              node.style.cssText = 'position:fixed;top:12px;left:50%;transform:translateX(-50%);z-index:2147483647;padding:10px 14px;border-radius:10px;background:#241b2e;color:white;font:13px system-ui,sans-serif;text-align:center;box-shadow:0 2px 12px #0005';
              document.body.appendChild(node);
            }
            if (node) node.textContent = message;
          }
          function scan() {
            const ruleIndex = index();
            const blockedQuery = queryIsSensitive(ruleIndex);
            const results = document.querySelector('#contents, ytd-section-list-renderer, ytd-search #primary');
            if (results) setHidden(results, blockedQuery);
            if (blockedQuery) notice('Focus Fence 키워드가 포함된 영상 검색 결과를 숨겼습니다.');
            else if (location.pathname === '/results') document.getElementById('threef-sensitive-title-notice')?.remove();

            const cards = 'ytd-video-renderer, ytd-rich-item-renderer, ytd-compact-video-renderer, ytd-reel-item-renderer, yt-lockup-view-model, ytd-grid-video-renderer';
            for (const card of document.querySelectorAll(cards)) {
              setHidden(card, threefTitleMatchesSensitiveKeyword(titleOf(card), ruleIndex));
            }
            const suggestions = 'ytd-searchbox [role="option"], .ytSearchboxComponentSuggestion, ytd-compact-suggestion, #suggestions [role="option"]';
            for (const suggestion of document.querySelectorAll(suggestions)) {
              setHidden(suggestion, threefTitleMatchesSensitiveKeyword(suggestion.innerText || suggestion.textContent, ruleIndex));
            }

            const watchPage = location.pathname === '/watch' || location.pathname.startsWith('/shorts/');
            const blockedTitle = watchPage && threefTitleMatchesSensitiveKeyword(videoPageTitle(), ruleIndex);
            if (blockedTitle) {
              document.documentElement.dataset.threefSensitiveWatch = '1';
              document.querySelector('video')?.pause();
              notice('Focus Fence 키워드가 포함된 영상은 숨겼습니다.');
            } else {
              delete document.documentElement.dataset.threefSensitiveWatch;
              if (!blockedQuery) document.getElementById('threef-sensitive-title-notice')?.remove();
            }
            for (const node of state.hidden) if (!document.documentElement?.contains(node)) state.hidden.delete(node);
          }
          function schedule() {
            if (state.queued) return;
            state.queued = true;
            requestAnimationFrame(() => { state.queued = false; scan(); });
          }
          state.update = nextRules => {
            state.rules = { ...nextRules, keywords: [...(nextRules.keywords || []), ...builtInKeywords] };
            schedule();
          };
          scan();
          new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true, characterData: true });
          addEventListener('popstate', schedule, true);
          addEventListener('yt-navigate-finish', schedule, true);
        })();
        """#
    }

    static func historyEntryContainsSensitiveKeyword(title: String, url: String, rules: Data?) -> Bool {
        var candidates = [title, url]
        if let components = URLComponents(string: url) {
            candidates.append(contentsOf: components.queryItems?.compactMap(\.value) ?? [])
        }
        for value in [title, url] {
            var decoded = value
            for _ in 0..<2 {
                guard let next = decoded.removingPercentEncoding, next != decoded else { break }
                candidates.append(next)
                decoded = next
            }
        }
        let terms = sensitiveTitleKeywords(rules: rules)
        return candidates.contains { candidate in
            let normalized = compactSensitiveText(candidate)
            return terms.contains { normalized.contains($0) }
        }
    }

    private static func sensitiveTitleKeywords(rules: Data?) -> [String] {
        var terms = builtInSensitiveTitleKeywords
        if let rules,
           let dictionary = try? JSONSerialization.jsonObject(with: rules) as? [String: Any] {
            terms += dictionary["keywords"] as? [String] ?? []
            terms += dictionary["adultProtectedKeywords"] as? [String] ?? []
        }
        return Array(Set(terms.map(compactSensitiveText).filter { $0.count >= 2 }))
    }

    private static func compactSensitiveText(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping
            .lowercased()
            .unicodeScalars
            .filter {
                !CharacterSet.whitespacesAndNewlines.contains($0)
                    && !CharacterSet.punctuationCharacters.contains($0)
                    && !CharacterSet.symbols.contains($0)
            }
            .map(String.init)
            .joined()
    }

    static func isYouTubeURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")
    }

    static let prepaintGateScript = #"""
    (() => {
      const host = location.hostname.toLocaleLowerCase();
      const google = host === 'google.com' || /(^|\.)google\.[a-z.]+$/.test(host);
      if (!google || location.pathname !== '/search') return;
      const root = document.documentElement;
      if (!root) return;
      root.dataset.threefSearchGate = 'pending';
      const style = document.createElement('style');
      style.textContent = 'html[data-threef-search-gate="pending"] #threef-search-policy-notice { pointer-events: none; }';
      (document.head || root).appendChild(style);
      const notice = document.createElement('div');
      notice.id = 'threef-search-policy-notice';
      notice.setAttribute('role', 'status');
      notice.setAttribute('aria-live', 'polite');
      notice.textContent = 'Focus Fence 정책 확인 중…';
      notice.style.cssText = 'position:fixed;top:12px;left:50%;transform:translateX(-50%);z-index:2147483647;max-width:90vw;padding:10px 14px;border-radius:10px;background:#fff7d6;color:#493900;box-shadow:0 2px 12px #0003;font:13px system-ui,sans-serif;text-align:center;pointer-events:none';
      (document.body || root).appendChild(notice);
      // The native policy fetch can time out after this document-start script
      // runs. Never leave the user with a permanent "checking" banner. Search
      // navigation remains available; a later policy injection still filters
      // results and can replace this status with a specific block notice.
      setTimeout(() => {
        if (root.dataset.threefSearchGate !== 'pending') return;
        root.removeAttribute('data-threef-search-gate');
        const currentNotice = document.getElementById('threef-search-policy-notice');
        if (!currentNotice) return;
        currentNotice.textContent = '검색은 계속할 수 있어요. Focus Fence 규칙 응답이 지연되어 검색 결과 필터가 아직 적용되지 않았습니다.';
        setTimeout(() => currentNotice.remove(), 8000);
      }, 2500);
    })();
    """#

    static func script(for url: URL, rules: Data) -> String? {
        guard isSearchResultsURL(url),
              ThreeFBrowserControlController.usableFocusFenceRules(rules),
              let json = String(data: rules, encoding: .utf8) else { return nil }
        return #"""
        (() => {
          const rules = \#(json);
          \#(classifierSource)
          const ruleIndex = threefBuildRuleIndex(rules);
          const searchHost = location.hostname.toLocaleLowerCase();
          if (!(searchHost === 'google.com' || /(^|\.)google\.[a-z.]+$/.test(searchHost)
            || searchHost === 'bing.com' || searchHost.endsWith('.bing.com')
            || searchHost === 'duckduckgo.com' || searchHost.endsWith('.duckduckgo.com'))) return;
          const filteredCards = new Set();
          function isSearchResultsPage() {
            if (searchHost === 'google.com' || /(^|\.)google\.[a-z.]+$/.test(searchHost)
              || searchHost === 'bing.com' || searchHost.endsWith('.bing.com')) return location.pathname === '/search';
            return location.pathname === '/';
          }
          function isGoogleImagesSearch() {
            return isSearchResultsPage()
              && (searchHost === 'google.com' || /(^|\.)google\.[a-z.]+$/.test(searchHost))
              && (new URL(location.href).searchParams.get('tbm') === 'isch'
                || new URL(location.href).searchParams.get('udm') === '2');
          }
          function restoreCard(card) {
            if (card.dataset.threefFiltered !== '1') return;
            if (card.dataset.threefOriginalStylePresent === 'true') {
              card.setAttribute('style', card.dataset.threefOriginalStyleAttribute || '');
            } else {
              card.removeAttribute('style');
            }
            delete card.dataset.threefFiltered;
            delete card.dataset.threefOriginalStylePresent;
            delete card.dataset.threefOriginalStyleAttribute;
            filteredCards.delete(card);
          }
          function restoreFilteredCards() {
            for (const card of filteredCards) restoreCard(card);
          }
          function applyGoogleQueryPolicy() {
            const googleSearch = isSearchResultsPage()
              && (searchHost === 'google.com' || /(^|\.)google\.[a-z.]+$/.test(searchHost));
            if (!googleSearch) return false;
            if (!threefShouldHideImageSearchQuery(new URL(location.href).searchParams.get('q'), ruleIndex)) {
              return false;
            }
            document.documentElement?.setAttribute('data-threef-search-gate', 'blocked');
            let notice = document.getElementById('threef-search-policy-notice');
            if (!notice && document.body) {
              notice = document.createElement('div');
              notice.id = 'threef-search-policy-notice';
              notice.setAttribute('role', 'status');
              notice.setAttribute('aria-live', 'polite');
              notice.style.cssText = 'position:fixed;inset:0;z-index:2147483647;display:grid;place-items:center;padding:24px;background:#fff;color:#263244;font:16px system-ui,sans-serif;text-align:center';
              document.body.appendChild(notice);
            }
            if (notice) notice.textContent = 'Focus Fence 정책에 따라 이 검색어의 결과를 숨겼습니다.';
            return true;
          }
          function applyImageQueryPolicy() {
            if (!isGoogleImagesSearch()) {
              if (!(searchHost === 'google.com' || /(^|\.)google\.[a-z.]+$/.test(searchHost))) {
                document.documentElement?.removeAttribute('data-threef-search-gate');
                document.getElementById('threef-search-policy-notice')?.remove();
              }
              return;
            }
            if (!threefShouldHideImageSearchQuery(new URL(location.href).searchParams.get('q'), ruleIndex)) {
              document.documentElement?.removeAttribute('data-threef-search-gate');
              document.getElementById('threef-search-policy-notice')?.remove();
              return;
            }
            document.documentElement?.setAttribute('data-threef-search-gate', 'blocked');
            if (document.body && !document.getElementById('threef-search-policy-notice')) {
              const notice = document.createElement('div');
              notice.id = 'threef-search-policy-notice';
              notice.setAttribute('role', 'status');
              notice.textContent = 'Focus Fence 정책에 따라 이 이미지 검색어의 결과를 숨겼습니다.';
              notice.style.cssText = 'position:fixed;inset:0;z-index:2147483647;display:grid;place-items:center;padding:24px;background:#fff;color:#263244;font:16px system-ui,sans-serif;text-align:center';
              document.body.appendChild(notice);
            }
          }
          function cardFor(link, imageSearch) {
            const selectors = searchHost.includes('bing.') ? ['li.b_algo']
              : searchHost.includes('duckduckgo.') ? ['article[data-testid="result"]', '[data-testid="result"]']
              : imageSearch ? ['div.isv-r', 'div.eA0Zlc', 'div.MjjYud', 'div.g']
              : ['div.MjjYud', 'div.g'];
            for (const selector of selectors) {
              const card = link.closest(selector);
              if (card) return card;
            }
            return link.parentElement?.parentElement || null;
          }
          function destinationFor(link, imageSearch) {
            let target;
            try { target = new URL(link.href, location.href); } catch { return null; }
            if (target.hostname.toLocaleLowerCase() === searchHost && target.pathname === '/url') {
              const redirect = target.searchParams.get('q') || target.searchParams.get('url');
              if (!redirect) return null;
              try {
                const destination = new URL(redirect);
                return /^https?:$/.test(destination.protocol) ? destination : null;
              } catch { return null; }
            }
            if (!imageSearch || target.hostname.toLocaleLowerCase() !== searchHost || target.pathname !== '/imgres') return target;
            const sourcePage = target.searchParams.get('imgrefurl');
            if (!sourcePage) return null;
            try {
              const destination = new URL(sourcePage);
              return /^https?:$/.test(destination.protocol) ? destination : null;
            } catch { return null; }
          }
          function scan() {
            for (const card of filteredCards) {
              if (!document.documentElement.contains(card)) filteredCards.delete(card);
            }
            if (applyGoogleQueryPolicy()) return;
            applyImageQueryPolicy();
            if (!isSearchResultsPage()) {
              restoreFilteredCards();
              return;
            }
            const imageSearch = isGoogleImagesSearch();
            const seen = new Set();
            for (const link of document.querySelectorAll('a[href]')) {
              const target = destinationFor(link, imageSearch);
              if (!target) continue;
              if (!/^https?:$/.test(target.protocol) || target.hostname.toLocaleLowerCase() === searchHost) continue;
              const card = cardFor(link, imageSearch);
              if (!card || seen.has(card)) continue;
              seen.add(card);
              const title = link.innerText || link.getAttribute('aria-label') || link.querySelector('img')?.alt || '';
              const snippet = card.innerText || '';
              const shouldHide = threefShouldHideResult(target.hostname, target.pathname + target.search, title, snippet, ruleIndex);
              if (shouldHide && card.dataset.threefFiltered !== '1') {
                card.dataset.threefFiltered = '1';
                card.dataset.threefOriginalStylePresent = String(card.hasAttribute('style'));
                card.dataset.threefOriginalStyleAttribute = card.getAttribute('style') || '';
                filteredCards.add(card);
                card.style.setProperty('display', 'none', 'important');
              } else if (!shouldHide && card.dataset.threefFiltered === '1') {
                restoreCard(card);
              }
            }
            // Google searches are gated before paint. Once valid policy rules
            // have been applied to the query and every visible result, release
            // the gate for ordinary/safe queries so the page cannot stay blank.
            const googleSearch = (searchHost === 'google.com' || /(^|\.)google\.[a-z.]+$/.test(searchHost))
              && isSearchResultsPage();
            if (googleSearch && document.documentElement?.dataset.threefSearchGate === 'pending') {
              document.documentElement.removeAttribute('data-threef-search-gate');
              document.getElementById('threef-search-policy-notice')?.remove();
            }
          }
          let queued = false;
          const schedule = () => {
            if (queued) return;
            queued = true;
            requestAnimationFrame(() => { queued = false; scan(); });
          };
          function onHistoryNavigation() {
            applyImageQueryPolicy();
            scan();
            schedule();
          }
          for (const method of ['pushState', 'replaceState']) {
            const original = history[method];
            if (typeof original !== 'function') continue;
            history[method] = function(...args) {
              const result = Reflect.apply(original, this, args);
              onHistoryNavigation();
              return result;
            };
          }
          scan();
          new MutationObserver(() => { applyImageQueryPolicy(); schedule(); }).observe(document.documentElement, { childList: true, subtree: true });
          addEventListener('popstate', onHistoryNavigation, true);
        })();
        """#
    }

    static func isSearchResultsURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        if host == "google.com" || host.hasSuffix(".google.com")
            || host.range(of: #"(^|\.)google\.[a-z.]+$"#, options: .regularExpression) != nil {
            return url.path == "/search"
        }
        if host == "bing.com" || host.hasSuffix(".bing.com") {
            return url.path == "/search"
        }
        if host == "duckduckgo.com" || host.hasSuffix(".duckduckgo.com") {
            return url.path == "/"
        }
        return false
    }

    static func isGoogleImagesResultsURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        let isGoogleHost = host == "google.com"
            || host.hasSuffix(".google.com")
            || host.range(of: #"(^|\.)google\.[a-z.]+$"#, options: .regularExpression) != nil
        guard isGoogleHost, url.path == "/search",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.queryItems?.contains {
            ($0.name == "tbm" && $0.value == "isch") || ($0.name == "udm" && $0.value == "2")
        } == true
    }
}
