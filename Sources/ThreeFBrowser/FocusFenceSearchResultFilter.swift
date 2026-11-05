import Foundation

enum FocusFenceSearchResultFilter {
    static let classifierSource = #"""
    function threefNormalizeHost(value) {
      return String(value || '').toLocaleLowerCase().replace(/^www\./, '').replace(/^\.+|\.+$/g, '');
    }
    function threefShouldHideResult(host, path, title, snippet, rules) {
      const normalizedHost = threefNormalizeHost(host);
      const blockedDomains = (rules.blockedDomains || []).map(threefNormalizeHost);
      if (blockedDomains.some(domain => domain && (normalizedHost === domain || normalizedHost.endsWith('.' + domain)))) return true;

      const blockedParts = (rules.blockedUrlParts || []).map(value => String(value).toLocaleLowerCase());
      const destination = (normalizedHost + String(path || '')).toLocaleLowerCase();
      if (blockedParts.some(part => part && destination.includes(part))) return true;

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
      const configuredTerms = (rules.keywords || []).map(value => String(value).normalize('NFKC').toLocaleLowerCase());
      const configuredDirectorySignal = configuredTerms.some(term => term.length >= 3 && combined.includes(term))
        && directoryAnywhere && adult.test(combined);

      // Require adult and directory context together. A neutral article that
      // only mentions the .porn TLD remains visible.
      return directoryInPrimary || pornTLDListing || adultIPListing || configuredDirectorySignal
        || (adult.test(primary) && directoryAnywhere);
    }
    function threefShouldHideImageSearchQuery(query, rules) {
      const normalized = String(query || '').normalize('NFKC').toLocaleLowerCase().replace(/\s+/gu, ' ').trim();
      if (!normalized) return false;
      const compact = normalized.replace(/[\s\p{P}\p{S}]+/gu, '');
      const directory = /주소|link|링크|모음|모움|사이트|\bsite\b|\bwebsites?\b|\bdirector(?:y|ies)\b|\blists?\b|\bcollections?\b/u;
      const addressDirectory = /주소.{0,24}(?:link|링크|모음|모움|사이트|site|list|directory)|(?:link|링크|모음|모움|사이트|site|list|directory).{0,24}주소/u;
      const adultDirectory = /\b(?:adult|porn|xxx|sex)\b|성인|포르노|야동/u.test(normalized) && directory.test(normalized);
      const configuredDirectory = (rules.keywords || []).some(value => {
        const term = String(value || '').normalize('NFKC').toLocaleLowerCase().trim();
        return Boolean(term && directory.test(term) && normalized.includes(term));
      });
      return addressDirectory.test(normalized) || adultDirectory || configuredDirectory
        || (compact.includes('주소') && /(?:link|링크|모음|모움|사이트|site|list|directory)/u.test(compact));
    }
    """#

    static let prepaintGateScript = #"""
    (() => {
      const host = location.hostname.toLocaleLowerCase();
      const google = host === 'google.com' || /(^|\.)google\.[a-z.]+$/.test(host);
      if (!google || location.pathname !== '/search') return;
      const params = new URL(location.href).searchParams;
      if (params.get('tbm') !== 'isch' && params.get('udm') !== '2') return;
      const root = document.documentElement;
      if (!root) return;
      root.dataset.threefSearchGate = 'pending';
      const style = document.createElement('style');
      style.textContent = 'html[data-threef-search-gate="pending"] body > :not(#threef-search-policy-notice), html[data-threef-search-gate="blocked"] body > :not(#threef-search-policy-notice) { visibility: hidden !important; }';
      (document.head || root).appendChild(style);
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
          function applyImageQueryPolicy() {
            if (!isGoogleImagesSearch()) {
              document.documentElement?.removeAttribute('data-threef-search-gate');
              document.getElementById('threef-search-policy-notice')?.remove();
              return;
            }
            if (!threefShouldHideImageSearchQuery(new URL(location.href).searchParams.get('q'), rules)) {
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
              const shouldHide = threefShouldHideResult(target.hostname, target.pathname + target.search, title, snippet, rules);
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
