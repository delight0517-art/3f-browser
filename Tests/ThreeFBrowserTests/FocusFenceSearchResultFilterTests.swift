import Foundation
import JavaScriptCore
import XCTest
@testable import ThreeFBrowser

final class FocusFenceSearchResultFilterTests: XCTestCase {
    func testSearchResultHostsAndPathsAreRecognized() {
        XCTAssertTrue(FocusFenceSearchResultFilter.isSearchResultsURL(URL(string: "https://www.google.com/search?q=test")!))
        XCTAssertTrue(FocusFenceSearchResultFilter.isSearchResultsURL(URL(string: "https://www.google.co.kr/search?q=test")!))
        XCTAssertTrue(FocusFenceSearchResultFilter.isSearchResultsURL(URL(string: "https://www.bing.com/search?q=test")!))
        XCTAssertTrue(FocusFenceSearchResultFilter.isSearchResultsURL(URL(string: "https://duckduckgo.com/?q=test")!))
        XCTAssertFalse(FocusFenceSearchResultFilter.isSearchResultsURL(URL(string: "https://example.com/search?q=test")!))
        XCTAssertFalse(FocusFenceSearchResultFilter.isSearchResultsURL(URL(string: "https://www.google.com/maps")!))
    }

    func testGoogleImagesSearchURLsAreRecognizedAndUseImageResultHandling() throws {
        let imageSearch = try XCTUnwrap(URL(string: "https://www.google.co.kr/search?q=blocked.example&tbm=isch"))
        XCTAssertTrue(FocusFenceSearchResultFilter.isSearchResultsURL(imageSearch))
        XCTAssertTrue(FocusFenceSearchResultFilter.isGoogleImagesResultsURL(imageSearch))
        XCTAssertFalse(FocusFenceSearchResultFilter.isGoogleImagesResultsURL(
            URL(string: "https://www.google.co.kr/search?q=blocked.example")!
        ))
        let modernImageSearch = try XCTUnwrap(URL(string: "https://www.google.co.kr/search?q=주소모음&udm=2"))
        XCTAssertTrue(FocusFenceSearchResultFilter.isSearchResultsURL(modernImageSearch))
        XCTAssertTrue(FocusFenceSearchResultFilter.isGoogleImagesResultsURL(modernImageSearch))
        XCTAssertFalse(FocusFenceSearchResultFilter.isGoogleImagesResultsURL(
            URL(string: "https://example.com/search?q=x&tbm=isch")!
        ))

        let rules = Data(#"{"blockedDomains":["blocked.example"],"blockedUrlParts":[],"keywords":[],"blockExceptions":[]}"#.utf8)
        let script = try XCTUnwrap(FocusFenceSearchResultFilter.script(for: imageSearch, rules: rules))
        XCTAssertTrue(script.contains("div.isv-r"))
        XCTAssertTrue(script.contains("imgrefurl"))
        XCTAssertTrue(script.contains("searchParams.get('tbm') === 'isch'"))
        XCTAssertTrue(script.contains("searchParams.get('udm') === '2'"))
        XCTAssertTrue(script.contains("threefShouldHideImageSearchQuery"))
        XCTAssertTrue(FocusFenceSearchResultFilter.prepaintGateScript.contains("root.dataset.threefSearchGate = 'pending'"))
        XCTAssertTrue(FocusFenceSearchResultFilter.prepaintGateScript.contains("const google = host === 'google.com'"))
    }

    func testClassifierBlocksConfiguredDestinationsAndAdultDirectoriesButKeepsNeutralMentions() throws {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript(FocusFenceSearchResultFilter.classifierSource)

        XCTAssertTrue(classify(context, host: "sub.adult.example", path: "/page", title: "Ordinary page", snippet: ""))
        XCTAssertTrue(classify(context, host: "safe.example", path: "/forbidden-tag", title: "Ordinary page", snippet: ""))
        XCTAssertTrue(classify(context, host: "directory.example", path: "/", title: "Adult domains list", snippet: "A list of porn websites and .porn extensions"))
        XCTAssertTrue(classify(context, host: "adult.example", path: "/", title: "주소모음 사이트", snippet: "사이트 주소 모음"),
                      "a destination covered by Focus Fence's blocked-domain rules must be hidden from ordinary Google result cards too")
        XCTAssertTrue(classify(context, host: "directory.example", path: "/", title: "Adult site directory", snippet: "A list of adult websites"))
        XCTAssertFalse(classify(context, host: "neutral.example", path: "/", title: "주소모음 사이트", snippet: "지역 주소 목록"))
        XCTAssertTrue(classify(context, host: "list.example", path: "/ips", title: "Porn IP address list", snippet: "Adult site IP addresses"))
        XCTAssertFalse(classify(context, host: "neutral.example", path: "/article", title: "Understanding the .porn top-level domain", snippet: "A neutral technical explanation."))
        XCTAssertFalse(classify(context, host: "neutral.example", path: "/article", title: "How browsers handle adult content", snippet: "This article discusses safety controls."))

        let search = SearchProvider.google.searchURL(for: "porn websites")
        XCTAssertTrue(SearchProvider.google.ownsSearchURL(try XCTUnwrap(search)))
    }

    func testIndexedDomainLookupMatchesLinearReferenceForLargeRuleSet() throws {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript(FocusFenceSearchResultFilter.classifierSource)
        let result = context.evaluateScript(#"""
        (() => {
          const rules = {
            blockedDomains: Array.from({ length: 3002 }, (_, index) => `site-${index}.example`),
            blockedUrlParts: [], keywords: []
          };
          const index = threefBuildRuleIndex(rules);
          const hosts = Array.from({ length: 600 }, (_, value) => {
            const number = value % rules.blockedDomains.length;
            if (value % 3 === 0) return `sub.site-${number}.example`;
            if (value % 3 === 1) return `site-${number}.example.evil`;
            return `notsite-${number}.example`;
          });
          const expected = hosts.map(host => rules.blockedDomains.some(domain =>
            host === domain || host.endsWith('.' + domain)));
          const actual = hosts.map(host => threefDomainIsBlocked(threefNormalizeHost(host), index));
          return `${actual.every((blocked, position) => blocked === expected[position])}:${actual.filter(Boolean).length}:${index.blockedDomains instanceof Set}`;
        })()
        """#)

        XCTAssertEqual(result?.toString(), "true:200:true")
    }

    func testImageSearchQueryUsesSharedPolicyTermsAndKeepsAllowedQueriesVisible() throws {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript(FocusFenceSearchResultFilter.classifierSource)
        let rules = #"{"keywords":["주소모음","링크 모음"]}"#

        XCTAssertTrue(queryIsBlocked(context, query: "주소모음", rules: rules))
        XCTAssertTrue(queryIsBlocked(context, query: "성인 사이트 링크 모음", rules: rules))
        XCTAssertTrue(queryIsBlocked(context, query: "porn websites list", rules: rules))
        XCTAssertFalse(queryIsBlocked(context, query: "풍경 사진", rules: rules))
        XCTAssertFalse(queryIsBlocked(context, query: "주소 검색", rules: rules))

        let mirrorRules = #"{"blockedDomains":["yadongkorea17.com"],"blockedUrlParts":["yadongkorea"],"keywords":[],"blockExceptions":[]}"#
        XCTAssertTrue(queryIsBlocked(context, query: "yadongkorea17", rules: mirrorRules))
        XCTAssertTrue(queryIsBlocked(context, query: "yadongkorea999.com", rules: mirrorRules))
        XCTAssertFalse(queryIsBlocked(context, query: "myyadongkorea17", rules: mirrorRules))
    }

    private func installOrdinarySearchURLShim(in context: JSContext) {
        context.evaluateScript(#"""
        globalThis.URL = function(value, base) {
          const raw = String(value);
          const absolute = /^[a-z][a-z0-9+.-]*:\/\//i.test(raw) ? raw : String(base || 'https://www.google.co.kr/') + raw;
          const match = absolute.match(/^([a-z][a-z0-9+.-]*:)\/\/([^/?#]+)([^?#]*)(?:\?([^#]*))?/i);
          if (!match) throw new TypeError('Invalid URL');
          this.protocol = match[1].toLowerCase(); this.hostname = match[2].toLowerCase();
          this.pathname = match[3] || '/'; this.href = absolute;
          const params = new Map((match[4] || '').split('&').filter(Boolean).map(pair => {
            const equals = pair.indexOf('=');
            const decode = part => decodeURIComponent(part.replace(/\+/g, ' '));
            return [decode(equals < 0 ? pair : pair.slice(0, equals)), decode(equals < 0 ? '' : pair.slice(equals + 1))];
          }));
          this.searchParams = { get(name) { return params.has(name) ? params.get(name) : null; } };
        };
        """#)
    }

    func testOrdinaryGoogleSearchPrepaintGateWaitsForValidRulesAndReleasesSafeQueryAfterScan() throws {
        func makeContext(query: String) throws -> JSContext {
            let context = try XCTUnwrap(JSContext())
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            context.evaluateScript(#"""
            globalThis.location = { hostname: 'www.google.co.kr', pathname: '/search', href: 'https://www.google.co.kr/search?q=\#(encoded)' };
            const root = { dataset: {}, appendChild(style) { globalThis.injectedStyle = style; },
              setAttribute(name, value) { this.dataset[name.slice(5).replace(/-([a-z])/g, (_, c) => c.toUpperCase())] = value; },
              removeAttribute(name) { delete this.dataset[name.slice(5).replace(/-([a-z])/g, (_, c) => c.toUpperCase())]; } };
            globalThis.document = { documentElement: root, head: null,
              createElement() { return { textContent: '' }; } };
            """#)
            installOrdinarySearchURLShim(in: context)
            return context
        }
        let queryContext = try makeContext(query: "성인 주소 모음")
        queryContext.evaluateScript(FocusFenceSearchResultFilter.prepaintGateScript)
        XCTAssertEqual(queryContext.evaluateScript("document.documentElement.dataset.threefSearchGate")?.toString(), "pending")
        XCTAssertTrue(queryContext.evaluateScript("injectedStyle.textContent")?.toString().contains("data-threef-search-gate=\"pending\"") == true)

        let safeContext = try makeContext(query: "landscape")
        safeContext.evaluateScript(FocusFenceSearchResultFilter.prepaintGateScript)
        XCTAssertEqual(safeContext.evaluateScript("document.documentElement.dataset.threefSearchGate")?.toString(), "pending")

        // The rules script must classify the URLSearchParams-decoded query and
        // replace the pending whole-page gate with a policy notice when blocked.
        let policyContext = try XCTUnwrap(JSContext())
        policyContext.evaluateScript(#"""
        globalThis.location = { hostname: 'www.google.co.kr', pathname: '/search', href: 'https://www.google.co.kr/search?q=성인%20주소%20모음' };
        const root = { dataset: { threefSearchGate: 'pending' }, attrs: { 'data-threef-search-gate': 'pending' },
          contains() { return true; }, setAttribute(name, value) { this.attrs[name] = value; this.dataset[name.slice(5).replace(/-([a-z])/g, (_, c) => c.toUpperCase())] = value; },
          removeAttribute(name) { delete this.attrs[name]; delete this.dataset[name.slice(5).replace(/-([a-z])/g, (_, c) => c.toUpperCase())]; } };
        const body = { notice: null, appendChild(node) { this.notice = node; }, removeChild(node) { if (this.notice === node) this.notice = null; } };
        globalThis.document = { documentElement: root, body, querySelectorAll() { return []; },
          getElementById(id) { return id === 'threef-search-policy-notice' ? body.notice : null; },
          createElement() { return { id: '', style: {}, setAttribute() {}, remove() { body.notice = null; } }; } };
        globalThis.addEventListener = () => {}; globalThis.requestAnimationFrame = callback => callback();
        globalThis.MutationObserver = function() { this.observe = () => {}; };
        globalThis.history = { pushState() {}, replaceState() {} };
        """#)
        installOrdinarySearchURLShim(in: policyContext)
        let rules = Data(#"{"blockedDomains":[],"blockedUrlParts":[],"keywords":[],"blockExceptions":[]}"#.utf8)
        let blockedURL = try XCTUnwrap(URL(string: "https://www.google.co.kr/search?q=성인%20주소%20모음"))
        let blockedScript = try XCTUnwrap(FocusFenceSearchResultFilter.script(for: blockedURL, rules: rules))
        policyContext.evaluateScript(blockedScript)
        XCTAssertEqual(policyContext.evaluateScript("document.documentElement.dataset.threefSearchGate")?.toString(), "blocked")
        XCTAssertTrue(policyContext.evaluateScript("Boolean(document.getElementById('threef-search-policy-notice'))")?.toBool() ?? false)

        // For a safe query, the pending gate should remain until a valid-rules
        // scan has run, then be released.
        let safeRulesContext = try XCTUnwrap(JSContext())
        safeRulesContext.evaluateScript(#"""
        globalThis.location = { hostname: 'www.google.co.kr', pathname: '/search', href: 'https://www.google.co.kr/search?q=landscape' };
        const root = { dataset: { threefSearchGate: 'pending' }, removeAttribute(name) { delete this.dataset[name.slice(5).replace(/-([a-z])/g, (_, c) => c.toUpperCase())]; }, setAttribute(name, value) { this.dataset[name.slice(5).replace(/-([a-z])/g, (_, c) => c.toUpperCase())] = value; }, contains() { return true; } };
        globalThis.document = { documentElement: root, body: { appendChild() {} }, querySelectorAll() { return []; }, getElementById() { return null; }, createElement() { return { style: {}, setAttribute() {}, remove() {} }; } };
        globalThis.addEventListener = () => {}; globalThis.requestAnimationFrame = callback => callback();
        globalThis.MutationObserver = function() { this.observe = () => {}; }; globalThis.history = { pushState() {}, replaceState() {} };
        """#)
        installOrdinarySearchURLShim(in: safeRulesContext)
        safeRulesContext.evaluateScript(FocusFenceSearchResultFilter.prepaintGateScript)
        XCTAssertEqual(safeRulesContext.evaluateScript("document.documentElement.dataset.threefSearchGate")?.toString(), "pending")
        let safeURL = try XCTUnwrap(URL(string: "https://www.google.co.kr/search?q=landscape"))
        safeRulesContext.evaluateScript(try XCTUnwrap(FocusFenceSearchResultFilter.script(for: safeURL, rules: rules)))
        XCTAssertEqual(
            safeRulesContext.evaluateScript("typeof document.documentElement.dataset.threefSearchGate")?.toString(),
            "undefined"
        )
    }

    func testOrdinaryGoogleRedirectResultUnwrapsDestinationAndHidesBlockedCard() throws {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript(#"""
        globalThis.location = { hostname: 'www.google.co.kr', pathname: '/search', href: 'https://www.google.co.kr/search?q=adult' };
        const card = { dataset: {}, innerText: 'Adult directory', _attrs: {}, hasAttribute(name) { return Object.hasOwn(this._attrs, name); }, getAttribute(name) { return this._attrs[name] ?? null; }, setAttribute(name, value) { this._attrs[name] = value; }, removeAttribute(name) { delete this._attrs[name]; }, style: { setProperty(name, value) { card.hidden = value === 'none'; } } };
        const link = { href: 'https://www.google.co.kr/url?opi=79508299&q=https%3A%2F%2Fjusonawal.com%2Fadult%2F', innerText: 'Adult directory', parentElement: null, closest() { return card; }, getAttribute() { return null; }, querySelector() { return null; } };
        globalThis.document = { documentElement: { contains() { return true; }, removeAttribute() {}, setAttribute() {} }, body: { appendChild() {} }, querySelectorAll() { return [link]; }, getElementById() { return null; }, createElement() { return { style: {}, setAttribute() {}, remove() {} }; } };
        globalThis.addEventListener = () => {}; globalThis.requestAnimationFrame = callback => callback();
        globalThis.MutationObserver = function() { this.observe = () => {}; }; globalThis.history = { pushState() {}, replaceState() {} };
        """#)
        installOrdinarySearchURLShim(in: context)
        let rules = Data(#"{"blockedDomains":["jusonawal.com"],"blockedUrlParts":[],"keywords":[],"blockExceptions":[]}"#.utf8)
        let url = try XCTUnwrap(URL(string: "https://www.google.co.kr/search?q=adult"))
        context.evaluateScript(try XCTUnwrap(FocusFenceSearchResultFilter.script(for: url, rules: rules)))
        XCTAssertTrue(context.evaluateScript("Boolean(card.hidden)")?.toBool() ?? false)
    }

    func testPrepaintGateActivatesForBothGoogleImageFormatsBeforePolicyRead() throws {
        let imageContext = try XCTUnwrap(JSContext())
        imageContext.evaluateScript(#"""
        globalThis.location = { hostname: 'www.google.co.kr', pathname: '/search', href: 'https://www.google.co.kr/search?q=landscape&udm=2' };
        globalThis.URL = function(value) {
          const query = String(value).split('?')[1] || '';
          const params = new Map(query.split('&').filter(Boolean).map(pair => pair.split('=').map(decodeURIComponent)));
          this.searchParams = { get(name) { return params.get(name) || null; } };
        };
        const root = { dataset: {}, appendChild(style) { globalThis.injectedStyle = style; } };
        globalThis.document = { documentElement: root, head: null, createElement() { return { textContent: '' }; } };
        """#)
        imageContext.evaluateScript(FocusFenceSearchResultFilter.prepaintGateScript)
        XCTAssertEqual(imageContext.evaluateScript("document.documentElement.dataset.threefSearchGate")?.toString(), "pending")
        XCTAssertTrue(imageContext.evaluateScript("injectedStyle.textContent")?.toString().contains("data-threef-search-gate=\"pending\"") == true)

        let legacyContext = try XCTUnwrap(JSContext())
        legacyContext.evaluateScript(#"""
        globalThis.location = { hostname: 'www.google.co.kr', pathname: '/search', href: 'https://www.google.co.kr/search?q=주소모음&tbm=isch' };
        globalThis.URL = function(value) {
          const query = String(value).split('?')[1] || '';
          const params = new Map(query.split('&').filter(Boolean).map(pair => pair.split('=').map(decodeURIComponent)));
          this.searchParams = { get(name) { return params.get(name) || null; } };
        };
        globalThis.document = { documentElement: { dataset: {}, appendChild() {} }, head: null, createElement() { return { textContent: '' }; } };
        """#)
        legacyContext.evaluateScript(FocusFenceSearchResultFilter.prepaintGateScript)
        XCTAssertEqual(legacyContext.evaluateScript("document.documentElement.dataset.threefSearchGate")?.toString(), "pending")

        let ordinaryContext = try XCTUnwrap(JSContext())
        ordinaryContext.evaluateScript(#"""
        globalThis.location = { hostname: 'www.google.co.kr', pathname: '/search', href: 'https://www.google.co.kr/search?q=landscape' };
        globalThis.URL = function(value) {
          const query = String(value).split('?')[1] || '';
          const params = new Map(query.split('&').filter(Boolean).map(pair => pair.split('=').map(decodeURIComponent)));
          this.searchParams = { get(name) { return params.get(name) || null; } };
        };
        globalThis.document = { documentElement: { dataset: {} } };
        """#)
        ordinaryContext.evaluateScript(FocusFenceSearchResultFilter.prepaintGateScript)
        XCTAssertEqual(ordinaryContext.evaluateScript("document.documentElement.dataset.threefSearchGate")?.toString(), "pending")
    }

    func testImageFilterRestoresExactStyleAndRunsOnHistoryTransitionsSynchronously() throws {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript(#"""
        globalThis.location = { hostname: 'www.google.co.kr', pathname: '/search', href: 'https://www.google.co.kr/search?q=landscape&udm=2' };
        globalThis.URL = function(value) {
          const match = String(value).match(/^https?:\/\/([^/?#]+)([^?#]*)(?:\?([^#]*))?/i);
          const query = new Map((match?.[3] || '').split('&').filter(Boolean).map(pair => pair.split('=').map(decodeURIComponent)));
          this.protocol = String(value).startsWith('https:') ? 'https:' : 'http:';
          this.hostname = match?.[1] || '';
          this.pathname = match?.[2] || '/';
          this.searchParams = { get(name) { return query.get(name) || null; } };
        };
        const originalStyle = 'color: red; display: grid !important; margin: 2px';
        const card = {
          dataset: {}, _style: originalStyle, innerText: 'A neutral result',
          style: {
            setProperty(name, value, priority) { card._style = card._style + '; ' + name + ': ' + value + (priority ? ' !important' : ''); },
            get display() { return (Array.from((card._style || '').matchAll(/(?:^|;)\s*display:\s*([^;]+)/gi)).at(-1)?.[1] || '').replace(/\s*!important$/i, '').trim(); }
          },
          hasAttribute(name) { return name === 'style' && card._style !== null; },
          getAttribute(name) { return name === 'style' ? card._style : null; },
          setAttribute(name, value) { if (name === 'style') card._style = value; },
          removeAttribute(name) { if (name === 'style') card._style = null; }
        };
        const link = {
          href: 'https://adult.example/directory', innerText: 'A neutral result', parentElement: null,
          getAttribute() { return null; }, querySelector() { return null; }, closest() { return card; }
        };
        const root = {
          dataset: {}, attrs: {},
          contains() { return true; },
          setAttribute(name, value) { this.attrs[name] = value; if (name.startsWith('data-')) this.dataset[name.slice(5).replace(/-([a-z])/g, (_, c) => c.toUpperCase())] = value; },
          removeAttribute(name) { delete this.attrs[name]; if (name.startsWith('data-')) delete this.dataset[name.slice(5).replace(/-([a-z])/g, (_, c) => c.toUpperCase())]; }
        };
        const body = { notice: null, appendChild(node) { body.notice = node; }, removeChild(node) { if (body.notice === node) body.notice = null; } };
        globalThis.document = {
          documentElement: root, body,
          querySelectorAll(selector) { return selector === 'a[href]' ? [link] : []; },
          getElementById(id) { return id === 'threef-search-policy-notice' ? body.notice : null; },
          createElement() { return { id: '', style: {}, setAttribute() {}, remove() { body.notice = null; } }; }
        };
        const listeners = {};
        globalThis.addEventListener = (name, callback) => { listeners[name] = callback; };
        const frames = [];
        globalThis.requestAnimationFrame = callback => { frames.push(callback); };
        globalThis.MutationObserver = function() { this.observe = () => {}; };
        const setLocation = url => { location.href = url; location.pathname = new URL(url).pathname; };
        globalThis.history = {
          pushState(_state, _title, url) { setLocation(url); return 'push-result'; },
          replaceState(_state, _title, url) { setLocation(url); return 'replace-result'; }
        };
        globalThis.__test = { card, link, root, listeners, originalStyle, frames };
        """#)

        let rules = Data(#"{"blockedDomains":["adult.example"],"blockedUrlParts":[],"keywords":["주소모음"],"blockExceptions":[]}"#.utf8)
        let imageSearch = try XCTUnwrap(URL(string: "https://www.google.co.kr/search?q=landscape&udm=2"))
        let filterScript = try XCTUnwrap(FocusFenceSearchResultFilter.script(for: imageSearch, rules: rules))
        context.evaluateScript(filterScript)
        XCTAssertTrue(context.evaluateScript("__test.card.dataset.threefFiltered === '1'")?.toBool() ?? false)

        context.evaluateScript("__test.link.href = 'https://safe.example/article';")
        XCTAssertEqual(context.evaluateScript("history.pushState({}, '', 'https://www.google.co.kr/search?q=landscape&udm=2')")?.toString(), "push-result")
        XCTAssertEqual(context.evaluateScript("__test.card.getAttribute('style')")?.toString(), "color: red; display: grid !important; margin: 2px")
        XCTAssertFalse(context.evaluateScript("Boolean(__test.card.dataset.threefFiltered)")?.toBool() ?? true)
        XCTAssertFalse(context.evaluateScript("Boolean(__test.root.dataset.threefSearchGate)")?.toBool() ?? true)

        context.evaluateScript("__test.link.href = 'https://adult.example/directory';")
        XCTAssertEqual(context.evaluateScript("history.replaceState({}, '', 'https://www.google.co.kr/search?q=landscape&udm=2')")?.toString(), "replace-result")
        XCTAssertEqual(context.evaluateScript("__test.card.style.display")?.toString(), "none")
        XCTAssertFalse(context.evaluateScript("Boolean(__test.root.dataset.threefSearchGate)")?.toBool() ?? true)

        context.evaluateScript("history.pushState({}, '', 'https://www.google.co.kr/search?q=landscape')")
        XCTAssertFalse(context.evaluateScript("Boolean(__test.root.dataset.threefSearchGate)")?.toBool() ?? true)
        XCTAssertFalse(context.evaluateScript("Boolean(document.getElementById('threef-search-policy-notice'))")?.toBool() ?? true)
        XCTAssertEqual(context.evaluateScript("__test.card.style.display")?.toString(), "none",
                       "ordinary Google Search still applies shared Focus Fence destination rules")

        context.evaluateScript("history.pushState({}, '', 'https://www.google.co.kr/search?q=landscape&udm=2')")
        XCTAssertFalse(context.evaluateScript("Boolean(__test.root.dataset.threefSearchGate)")?.toBool() ?? true)

        context.evaluateScript("history.pushState({}, '', 'https://www.google.co.kr/?q=landscape&udm=2')")
        XCTAssertEqual(context.evaluateScript("__test.card.getAttribute('style')")?.toString(), "color: red; display: grid !important; margin: 2px")
        XCTAssertFalse(context.evaluateScript("Boolean(__test.root.dataset.threefSearchGate)")?.toBool() ?? true)

        context.evaluateScript("history.pushState({}, '', 'https://www.google.co.kr/search?q=landscape&udm=2')")
        XCTAssertEqual(context.evaluateScript("__test.card.style.display")?.toString(), "none")

        context.evaluateScript("__test.link.href = 'https://safe.example/article'; location.href = 'https://www.google.co.kr/search?q=landscape&udm=2'; __test.listeners.popstate();")
        XCTAssertEqual(context.evaluateScript("__test.card.getAttribute('style')")?.toString(), "color: red; display: grid !important; margin: 2px")
        XCTAssertFalse(context.evaluateScript("Boolean(__test.card.dataset.threefFiltered)")?.toBool() ?? true)
        XCTAssertFalse(context.evaluateScript("Boolean(__test.root.dataset.threefSearchGate)")?.toBool() ?? true)

        context.evaluateScript("__test.frames.shift()();")
        XCTAssertEqual(context.evaluateScript("__test.card.getAttribute('style')")?.toString(), "color: red; display: grid !important; margin: 2px")
        XCTAssertFalse(context.evaluateScript("Boolean(__test.card.dataset.threefFiltered)")?.toBool() ?? true)
    }

    func testLateUnknownImageResultRootIsFilteredAfterMutation() throws {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript(#"""
        globalThis.location = { hostname: 'www.google.co.kr', pathname: '/search', href: 'https://www.google.co.kr/search?q=landscape&udm=2' };
        globalThis.URL = function(value) {
          const match = String(value).match(/^https?:\/\/([^/?#]+)([^?#]*)(?:\?([^#]*))?/i);
          const query = new Map((match?.[3] || '').split('&').filter(Boolean).map(pair => pair.split('=').map(decodeURIComponent)));
          this.protocol = String(value).startsWith('https:') ? 'https:' : 'http:';
          this.hostname = match?.[1] || '';
          this.pathname = match?.[2] || '/';
          this.searchParams = { get(name) { return query.get(name) || null; } };
        };
        const card = {
          dataset: {}, innerText: '성인 사이트 주소모음', _style: '',
          style: { setProperty(name, value) { card._style = `${name}: ${value}`; }, get display() { return card._style.split(': ')[1] || ''; } },
          hasAttribute(name) { return name === 'style' && this._style !== ''; },
          getAttribute(name) { return name === 'style' ? this._style : null; },
          setAttribute(name, value) { if (name === 'style') this._style = value; },
          removeAttribute(name) { if (name === 'style') this._style = ''; }
        };
        const fallbackParent = { parentElement: card };
        const lateLink = {
          href: 'https://adult.example/directory', innerText: '성인 사이트 주소모음', parentElement: fallbackParent,
          closest() { return null; }, getAttribute() { return null; }, querySelector() { return null; }
        };
        const links = [];
        const root = {
          dataset: {}, contains() { return true; },
          setAttribute(name, value) { if (name === 'data-threef-search-gate') this.dataset.threefSearchGate = value; },
          removeAttribute(name) { if (name === 'data-threef-search-gate') delete this.dataset.threefSearchGate; }
        };
        globalThis.document = {
          documentElement: root, body: { appendChild() {} },
          querySelectorAll(selector) { return selector === 'a[href]' ? links : []; },
          getElementById() { return null; }, createElement() { return { style: {}, setAttribute() {}, remove() {} }; }
        };
        globalThis.addEventListener = () => {};
        globalThis.requestAnimationFrame = callback => callback();
        globalThis.MutationObserver = function(callback) { this.observe = () => { globalThis.__mutationCallback = callback; }; };
        globalThis.history = { pushState() {}, replaceState() {} };
        globalThis.__test = { links, lateLink, card, mutate() { globalThis.__mutationCallback(); } };
        """#)

        let rules = Data(#"{"blockedDomains":["adult.example"],"blockedUrlParts":[],"keywords":["주소모음"],"blockExceptions":[]}"#.utf8)
        let url = try XCTUnwrap(URL(string: "https://www.google.co.kr/search?q=landscape&udm=2"))
        let script = try XCTUnwrap(FocusFenceSearchResultFilter.script(for: url, rules: rules))
        context.evaluateScript(script)

        XCTAssertFalse(context.evaluateScript("Boolean(__test.card.dataset.threefFiltered)")?.toBool() ?? true)
        context.evaluateScript("__test.links.push(__test.lateLink); __test.mutate();")
        XCTAssertEqual(context.evaluateScript("__test.card.style.display")?.toString(), "none")
        XCTAssertEqual(context.evaluateScript("__test.card.dataset.threefFiltered")?.toString(), "1")
    }

    func testFilterScriptRequiresValidRulesAndSearchResultsPage() {
        let rules = Data(#"{"blockedDomains":["adult.example"],"blockedUrlParts":[],"keywords":[],"blockExceptions":[]}"#.utf8)
        let searchURL = URL(string: "https://www.google.com/search?q=adult.example")!
        XCTAssertNotNil(FocusFenceSearchResultFilter.script(for: searchURL, rules: rules))
        XCTAssertNil(FocusFenceSearchResultFilter.script(for: URL(string: "https://example.com/search")!, rules: rules))
        XCTAssertNil(FocusFenceSearchResultFilter.script(for: searchURL, rules: Data("{}".utf8)))
    }

    private func classify(_ context: JSContext, host: String, path: String, title: String, snippet: String) -> Bool {
        let rules = #"{"blockedDomains":["adult.example"],"blockedUrlParts":["forbidden-tag"],"keywords":["directory"],"blockExceptions":[]}"#
        let arguments = [host, path, title, snippet].map(Self.javascriptString).joined(separator: ",")
        let result = context.evaluateScript("(() => threefShouldHideResult(\(arguments), threefBuildRuleIndex(\(rules))) )()")
        return result?.toBool() ?? false
    }

    private func queryIsBlocked(_ context: JSContext, query: String, rules: String) -> Bool {
        let argument = Self.javascriptString(query)
        return context.evaluateScript("threefShouldHideImageSearchQuery(\(argument), threefBuildRuleIndex(\(rules)))")?.toBool() ?? false
    }

    private static func javascriptString(_ value: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [value])) ?? Data("[\"\"]".utf8)
        let array = String(data: data, encoding: .utf8) ?? "[\"\"]"
        return String(array.dropFirst().dropLast())
    }
}
