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
          function isGoogleImagesSearch() {
            return (searchHost === 'google.com' || /(^|\.)google\.[a-z.]+$/.test(searchHost))
              && new URL(location.href).searchParams.get('tbm') === 'isch';
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
                card.dataset.threefOriginalDisplay = card.style.display;
                card.style.setProperty('display', 'none', 'important');
              }
            }
          }
          let queued = false;
          const schedule = () => {
            if (queued) return;
            queued = true;
            requestAnimationFrame(() => { queued = false; scan(); });
          };
          scan();
          new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
          addEventListener('popstate', schedule, true);
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
        return components.queryItems?.contains { $0.name == "tbm" && $0.value == "isch" } == true
    }
}
