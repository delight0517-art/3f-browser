import SwiftUI
import WebKit

enum BrowserNavigationAuthorizationDecision: Equatable {
    case allowed
    case blocked
    case youtubeBlocked
    case unavailable

    var isAllowed: Bool { self == .allowed }
}
import AppKit

@MainActor
final class ThreeFWindowAwareWebView: WKWebView {
    var onWindowAttachment: ((WKWebView) -> Void)?
    var contextMenuAction: ThreeFContextMenuAction?
    var selectedYouTubeKeyword: String?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        if let index = menu.items.firstIndex(where: {
            $0.identifier?.rawValue == ThreeFContextMenuPolicy.webKitOpenLinkInNewWindowIdentifier
        }) {
            let webKitItem = menu.items[index]
            menu.removeItem(at: index)
            let actions: [(ThreeFContextMenuAction, String)] = [
                (.openInNewTab, "링크를 새 탭으로 열기"),
                (.openInNewWindow, "링크를 새 창으로 열기")
            ]
            for (offset, item) in actions.enumerated() {
                let menuItem = NSMenuItem(title: item.1, action: #selector(openLinkFromContextMenu(_:)), keyEquivalent: "")
                menuItem.identifier = NSUserInterfaceItemIdentifier(item.0.rawValue)
                menuItem.target = self
                menuItem.representedObject = webKitItem
                menu.insertItem(menuItem, at: index + offset)
            }
        }

        if YouTubeUsageBridgePayload.isYouTubeHost(url?.host ?? ""),
           let keyword = selectedYouTubeKeyword,
           !menu.items.contains(where: { $0.identifier?.rawValue == ThreeFContextMenuAction.addYouTubeUnlimitedKeyword.rawValue }) {
            menu.addItem(.separator())
            let menuItem = NSMenuItem(
                title: "이 키워드 영상은 YouTube 시간 무제한 · 40분 뒤 Apply",
                action: #selector(addYouTubeUnlimitedKeyword(_:)),
                keyEquivalent: ""
            )
            menuItem.identifier = NSUserInterfaceItemIdentifier(ThreeFContextMenuAction.addYouTubeUnlimitedKeyword.rawValue)
            menuItem.target = self
            menuItem.representedObject = keyword
            menu.addItem(menuItem)
        }
    }

    override func didCloseMenu(_ menu: NSMenu, with event: NSEvent?) {
        super.didCloseMenu(menu, with: event)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.contextMenuAction = nil
        }
    }

    @objc private func openLinkFromContextMenu(_ menuItem: NSMenuItem) {
        guard let action = ThreeFContextMenuPolicy.action(for: menuItem.identifier?.rawValue),
              let webKitItem = menuItem.representedObject as? NSMenuItem,
              let selector = webKitItem.action else { return }
        contextMenuAction = action
        guard NSApp.sendAction(selector, to: webKitItem.target, from: webKitItem) else {
            contextMenuAction = nil
            return
        }
    }

    @objc private func addYouTubeUnlimitedKeyword(_ menuItem: NSMenuItem) {
        guard let keyword = menuItem.representedObject as? String else { return }
        _ = YouTubeTitleExemptionStore.shared.addPending(keyword)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            self.onWindowAttachment?(self)
        }
    }
}

struct BrowserWebView: NSViewRepresentable {
    @Binding var url: URL?
    @Binding var requestID: Int
    @Binding var webView: WKWebView?
    var authorizeNavigation: ((URL, @escaping (BrowserNavigationAuthorizationDecision) -> Void) -> Void)? = nil
    var onRejectedNavigation: ((URL, BrowserNavigationAuthorizationDecision) -> Void)? = nil
    var allowsDownloads = true
    var onDownloadStatus: ((String) -> Void)? = nil
    var onWindowAttached: ((WKWebView) -> Void)? = nil
    var onNavigationStarted: ((URL?) -> Void)? = nil
    var onNavigationCommitted: ((URL?) -> Void)? = nil
    var onLoadingChanged: ((Bool) -> Void)? = nil
    var onNavigationFailed: ((Error) -> Void)? = nil
    var onOpenLinkInNewTab: ((URL) -> Void)? = nil
    var onOpenBackgroundTab: ((URL) -> Void)? = nil
    var onOpenLinkInNewWindow: ((URL) -> Void)? = nil
    let onNavigation: (URL?, String?) -> Void
    let onNavigationState: (Bool, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    static func standardWebKitApplicationNameForUserAgent(safariShortVersion: String? = nil) -> String {
        let rawVersion = safariShortVersion ?? installedSafariShortVersion()
        let sanitized = rawVersion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let validVersion = !sanitized.isEmpty
            && sanitized.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") })
            && sanitized.first?.isNumber == true
            && sanitized.last?.isNumber == true
        let version = validVersion ? sanitized : "18.0"
        return "Version/\(version) Safari/605.1.15"
    }

    private static func installedSafariShortVersion() -> String? {
        let safariURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari")
            ?? URL(fileURLWithPath: "/Applications/Safari.app", isDirectory: true)
        return Bundle(url: safariURL)?.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    @MainActor
    static func makeWebViewConfiguration(
        backgroundLinkDelegate: ThreeFBackgroundLinkDelegate? = nil
    ) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.applicationNameForUserAgent = standardWebKitApplicationNameForUserAgent()
        configuration.processPool = ThreeFBrowserProcessPool.shared
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        if OptionalFeatureAvailability.focusFenceEnforcement {
            configuration.userContentController.addUserScript(WKUserScript(
                source: FocusFenceSearchResultFilter.prepaintGateScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }
        let cachedPolicy = FocusFenceQARouting.isQARequested() ? nil : FocusFenceRulesCache.production.load()
        configuration.userContentController.addUserScript(WKUserScript(
            source: FocusFenceSearchResultFilter.youtubeTitleFilterScript(rules: cachedPolicy),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        if BrowserSessionStore.isolatedQAProfileEnabled {
            configuration.websiteDataStore = .nonPersistent()
        }
        if OptionalFeatureAvailability.youtubeUsageReporting {
            configuration.userContentController.add(
                YouTubeKeywordSelectionScriptMessageHandler(),
                contentWorld: .defaultClient,
                name: YouTubeTitleExemptionScripts.selectionMessageName
            )
            configuration.userContentController.addUserScript(WKUserScript(
                source: YouTubeTitleExemptionScripts.selection,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true,
                in: .defaultClient
            ))
        }
        configuration.userContentController.add(
            BrowserDiagnosticsScriptMessageHandler(),
            contentWorld: .defaultClient,
            name: BrowserDiagnosticsScriptMessageHandler.name
        )
        configuration.userContentController.addUserScript(WKUserScript(
            source: BrowserDiagnosticsScriptMessageHandler.script,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: .defaultClient
        ))
        if let backgroundLinkDelegate {
            let handler = ThreeFBackgroundLinkScriptMessageHandler()
            handler.delegate = backgroundLinkDelegate
            configuration.userContentController.add(
                handler,
                contentWorld: ThreeFBackgroundLinkPolicy.contentWorld,
                name: ThreeFBackgroundLinkPolicy.messageName
            )
            configuration.userContentController.addUserScript(WKUserScript(
                source: ThreeFBackgroundLinkPolicy.script,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true,
                in: ThreeFBackgroundLinkPolicy.contentWorld
            ))
        }
        if OptionalFeatureAvailability.youtubeUsageReporting {
            configuration.userContentController.addScriptMessageHandler(
                YouTubeUsageScriptMessageHandler(),
                contentWorld: .defaultClient,
                name: YouTubeUsageScriptMessageHandler.name
            )
        }
        if OptionalFeatureAvailability.youtubePreviewBlocking {
            configuration.userContentController.addUserScript(WKUserScript(
                source: YouTubePreviewPlaybackBlocker.script,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }
        if OptionalFeatureAvailability.youtubeUsageReporting {
            configuration.userContentController.addUserScript(WKUserScript(
                source: YouTubeTitleExemptionScripts.overlay,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true,
                in: .defaultClient
            ))
            configuration.userContentController.addUserScript(WKUserScript(
                source: YouTubeUsageReporter.script,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true,
                in: .defaultClient
            ))
            configuration.userContentController.addUserScript(WKUserScript(
                source: YouTubeUsageReporter.iframeKeyboardBlockerScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: .defaultClient
            ))
        }
        return configuration
    }

    func makeNSView(context: Context) -> WKWebView {
        let coordinator = context.coordinator
        let configuration = Self.makeWebViewConfiguration(
            backgroundLinkDelegate: onOpenBackgroundTab != nil ? coordinator : nil
        )
        let view = ThreeFWindowAwareWebView(frame: .zero, configuration: configuration)
        view.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"
        context.coordinator.parent = self
        view.navigationDelegate = context.coordinator
        view.uiDelegate = coordinator
        view.onWindowAttachment = { [weak coordinator] attachedView in
            coordinator?.parent.onWindowAttached?(attachedView)
        }
        DispatchQueue.main.async { webView = view }
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        if view.window != nil {
            onWindowAttached?(view)
        }
        guard let url, context.coordinator.lastRequestID != requestID else { return }
        context.coordinator.lastRequestID = requestID
        if url.isFileURL {
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            view.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, ThreeFBackgroundLinkDelegate {
        enum NavigationDecision: Equatable {
            case allow
            case cancel
            case download
        }

        var parent: BrowserWebView
        var lastRequestID = -1
        private var activePopups: [ObjectIdentifier: ThreeFManagedPopupWindowController] = [:]

        init(parent: BrowserWebView) {
            self.parent = parent
        }

        func webView(
            _ webView: WKWebView,
            runOpenPanelWith parameters: WKOpenPanelParameters,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping ([URL]?) -> Void
        ) {
            // Attach to the requesting tab's window, including secondary browser windows.
            guard let window = webView.window, window.attachedSheet == nil else {
                completionHandler(nil)
                return
            }
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = parameters.allowsDirectories
            panel.allowsMultipleSelection = parameters.allowsMultipleSelection
            panel.beginSheetModal(for: window) { response in
                completionHandler(response == .OK ? panel.urls : nil)
            }
        }

        @MainActor
        func openBackgroundLink(_ url: URL) {
            guard let destination = ThreeFContextMenuPolicy.safeHTTPURL(url),
                  let authorizeNavigation = parent.authorizeNavigation,
                  let onOpenBackgroundTab = parent.onOpenBackgroundTab else { return }
            authorizeNavigation(destination) { [weak self] decision in
                guard let self else { return }
                guard decision.isAllowed else {
                    self.parent.onRejectedNavigation?(destination, decision)
                    return
                }
                onOpenBackgroundTab(destination)
            }
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let source = webView as? ThreeFWindowAwareWebView,
               let action = source.contextMenuAction {
                source.contextMenuAction = nil
                guard navigationAction.targetFrame == nil,
                      navigationAction.navigationType == .linkActivated,
                      !navigationAction.shouldPerformDownload,
                      let url = ThreeFContextMenuPolicy.safeHTTPURL(navigationAction.request.url),
                      let authorizeNavigation = parent.authorizeNavigation else { return nil }

                authorizeNavigation(url) { [weak self] decision in
                    guard let self else { return }
                    if decision.isAllowed, GoogleOAuthNavigationPolicy.requiresSystemBrowser(for: url) {
                        self.openOAuthInSystemBrowser(url, sourceURL: webView.url)
                        return
                    }
                    guard let intent = ThreeFContextMenuPolicy.intent(action: action, url: url, isAllowed: decision.isAllowed) else {
                        if !decision.isAllowed { self.parent.onRejectedNavigation?(url, decision) }
                        return
                    }
                    switch intent {
                    case .newTab(let destination): self.parent.onOpenLinkInNewTab?(destination)
                    case .newWindow(let destination): self.parent.onOpenLinkInNewWindow?(destination)
                    }
                }
                return nil
            }

            if let url = navigationAction.request.url,
               GoogleOAuthNavigationPolicy.requiresSystemBrowser(for: url) {
                guard !navigationAction.shouldPerformDownload else { return nil }
                guard let authorizeNavigation = parent.authorizeNavigation else {
                    let decision = Self.navigationDecision(
                        isAllowed: nil,
                        shouldDownload: navigationAction.shouldPerformDownload,
                        allowsDownloads: parent.allowsDownloads
                    )
                    if decision == .allow {
                        openOAuthInSystemBrowser(url, sourceURL: webView.url)
                    }
                    return nil
                }
                authorizeNavigation(url) { [weak self] decision in
                    guard let self else { return }
                    self.onMain {
                        guard decision.isAllowed else {
                            self.parent.onRejectedNavigation?(url, decision)
                            return
                        }
                        self.openOAuthInSystemBrowser(url, sourceURL: webView.url)
                    }
                }
                return nil
            }
            let hasExplicitSize = windowFeatures.width != nil || windowFeatures.height != nil
            if navigationAction.targetFrame == nil,
               Self.shouldOpenManagedPopup(
                   navigationType: navigationAction.navigationType,
                   url: navigationAction.request.url,
                   hasExplicitWindowSize: hasExplicitSize
               ),
               GoogleOAuthHandoffDiagnostics.shared.allowPopup() {
                return openManagedPopup(
                    configuration: configuration,
                    openerURL: GoogleOAuthNavigationPolicy.safeHTTPSPageURL(webView.url),
                    windowFeatures: windowFeatures
                )
            }
            Self.routePopup(
                targetFrameIsAbsent: navigationAction.targetFrame == nil,
                url: navigationAction.request.url,
                openInNewTab: parent.onOpenLinkInNewTab
            )
            return nil
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping () -> Void
        ) {
            onMain {
                ThreeFWebKitDialogPresenter.runAlert(on: webView, message: message, frame: frame, completionHandler: completionHandler)
            }
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (Bool) -> Void
        ) {
            onMain {
                ThreeFWebKitDialogPresenter.runConfirm(on: webView, message: message, frame: frame, completionHandler: completionHandler)
            }
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptTextInputPanelWithPrompt prompt: String,
            defaultText: String?,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (String?) -> Void
        ) {
            onMain {
                ThreeFWebKitDialogPresenter.runPrompt(
                    on: webView,
                    prompt: prompt,
                    defaultText: defaultText,
                    frame: frame,
                    completionHandler: completionHandler
                )
            }
        }

        static func shouldOpenManagedPopup(
            navigationType: WKNavigationType,
            url: URL?,
            hasExplicitWindowSize: Bool
        ) -> Bool {
            guard navigationType != .linkActivated else { return false }
            if hasExplicitWindowSize { return true }
            guard let url else { return true }
            return url.scheme?.lowercased() == "about"
        }

        @MainActor
        private func openManagedPopup(
            configuration: WKWebViewConfiguration,
            openerURL: URL?,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView {
            let controller = ThreeFManagedPopupWindowController(
                configuration: configuration,
                windowFeatures: windowFeatures,
                openerURL: openerURL,
                authorizeNavigation: parent.authorizeNavigation,
                onRejectedNavigation: parent.onRejectedNavigation,
                allowsDownloads: parent.allowsDownloads,
                openOAuthInSystemBrowser: { [weak self] url, sourceURL in
                    self?.openOAuthInSystemBrowser(url, sourceURL: sourceURL)
                },
                openLinkInNewTab: parent.onOpenLinkInNewTab,
                onClose: { [weak self] identifier in
                    self?.activePopups.removeValue(forKey: identifier)
                }
            )
            activePopups[ObjectIdentifier(controller)] = controller
            controller.show()
            return controller.popupWebView
        }

        private func openOAuthInSystemBrowser(_ url: URL, sourceURL: URL?) {
            GoogleOAuthHandoffDiagnostics.shared.handoff(url, sourceURL: sourceURL)
        }

        @discardableResult
        static func routePopup(
            targetFrameIsAbsent: Bool,
            url: URL?,
            openInNewTab: ((URL) -> Void)?
        ) -> Bool {
            guard targetFrameIsAbsent,
                  let destination = ThreeFContextMenuPolicy.safeHTTPURL(url),
                  let openInNewTab else { return false }
            guard GoogleOAuthHandoffDiagnostics.shared.allowPopup() else { return true }
            openInNewTab(destination)
            return true
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            onMain {
                GoogleOAuthHandoffDiagnostics.shared.recordNavigation(.navigationCommitted, url: webView.url)
                self.parent.onNavigationCommitted?(webView.url)
                // Google search pages can keep WebKit in a loading state while
                // late resources finish. Release the prepaint policy gate as
                // soon as the document is committed; the injected observer
                // continues filtering results as Google fills in the page.
                self.filterSearchResultsIfNeeded(in: webView)
                self.filterSensitiveYouTubeTitlesIfNeeded(in: webView)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onMain {
                GoogleOAuthHandoffDiagnostics.shared.recordNavigation(.navigationFinished, url: webView.url)
                if webView.url?.host?.lowercased() == "accounts.google.com" {
                    GoogleOAuthHandoffDiagnostics.shared.record(.opened, key: "google-login")
                }
                self.parent.onLoadingChanged?(false)
                self.parent.onNavigation(webView.url, webView.title)
                self.parent.onNavigationState(webView.canGoBack, webView.canGoForward)
                ThreeFBrowserControlController.shared.navigationDidFinish(for: webView)
                self.filterSensitiveYouTubeTitlesIfNeeded(in: webView)
            }
        }

        private func filterSensitiveYouTubeTitlesIfNeeded(in webView: WKWebView) {
            guard let url = webView.url,
                  FocusFenceSearchResultFilter.isYouTubeURL(url) else { return }
            Task { @MainActor [weak webView] in
                guard let webView, webView.url == url else { return }
                let rules = await ThreeFBrowserControlController.fetchFocusFenceRules()
                guard webView.url == url else { return }
                let script = FocusFenceSearchResultFilter.youtubeTitleFilterScript(rules: rules)
                _ = try? await webView.evaluateJavaScript(script)
            }
        }

        private func filterSearchResultsIfNeeded(in webView: WKWebView) {
            guard OptionalFeatureAvailability.focusFenceEnforcement,
                  let url = webView.url, FocusFenceSearchResultFilter.isSearchResultsURL(url) else { return }
            Task { @MainActor [weak webView] in
                guard let webView, webView.url == url else { return }
                guard let rules = await ThreeFBrowserControlController.fetchFocusFenceRules(),
                      webView.url == url,
                      let script = FocusFenceSearchResultFilter.script(for: url, rules: rules) else {
                    let failure = #"""
                    (() => {
                      const root = document.documentElement;
                      if (!root) return;
                      root.dataset.threefSearchGate = 'unfiltered';
                      let notice = document.getElementById('threef-search-policy-notice');
                      if (!notice && document.body) {
                        notice = document.createElement('div');
                        notice.id = 'threef-search-policy-notice';
                        notice.setAttribute('role', 'status');
                        notice.setAttribute('aria-live', 'polite');
                        notice.style.cssText = 'position:fixed;top:12px;left:50%;transform:translateX(-50%);z-index:2147483647;max-width:90vw;padding:10px 14px;border-radius:10px;background:#fff7d6;color:#493900;box-shadow:0 2px 12px #0003;font:13px system-ui,sans-serif;text-align:center';
                        document.body.appendChild(notice);
                      }
                      if (notice) {
                        notice.textContent = '검색은 계속할 수 있어요. 저장된 Focus Fence 규칙을 불러오지 못해 검색 결과 필터가 꺼졌습니다. 차단 대상 이동은 규칙을 다시 불러올 때까지 보류됩니다.';
                        setTimeout(() => notice.remove(), 8000);
                      }
                    })();
                    """#
                    _ = try? await webView.evaluateJavaScript(failure)
                    return
                }
                _ = try? await webView.evaluateJavaScript(script)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onMain {
                GoogleOAuthHandoffDiagnostics.shared.recordNavigationFailure(error, url: webView.url)
                GoogleOAuthHandoffDiagnostics.shared.record(.openFailed, detail: "WebKit error \((error as NSError).code)", key: "navigation-\((error as NSError).code)")
                self.parent.onLoadingChanged?(webView.isLoading)
                self.parent.onNavigationFailed?(error)
                ThreeFBrowserControlController.shared.navigationDidFail(for: webView)
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onMain {
                GoogleOAuthHandoffDiagnostics.shared.recordNavigationFailure(error, url: webView.url)
                GoogleOAuthHandoffDiagnostics.shared.record(.openFailed, detail: "WebKit error \((error as NSError).code)", key: "navigation-\((error as NSError).code)")
                self.parent.onLoadingChanged?(webView.isLoading)
                self.parent.onNavigationFailed?(error)
                ThreeFBrowserControlController.shared.navigationDidFail(for: webView)
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            onMain {
                GoogleOAuthHandoffDiagnostics.shared.recordNavigation(.navigationStarted, url: webView.url)
                self.parent.onNavigationStarted?(webView.url)
                self.parent.onLoadingChanged?(true)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if ThreeFBackgroundLinkPolicy.isBackgroundLink(
                navigationType: navigationAction.navigationType,
                buttonNumber: navigationAction.buttonNumber,
                isMainFrame: navigationAction.sourceFrame.isMainFrame
            ), let destination = ThreeFContextMenuPolicy.safeHTTPURL(navigationAction.request.url) {
                decisionHandler(.cancel)
                openBackgroundLink(destination)
                return
            }
            Self.handleNavigationActionPolicy(
                navigationAction,
                webViewURL: webView.url,
                allowMainFrameBlankAbout: false,
                authorizeNavigation: parent.authorizeNavigation,
                allowsDownloads: parent.allowsDownloads,
                onRejectedNavigation: parent.onRejectedNavigation,
                onSystemBrowserOAuth: { [weak self] url, sourceURL in
                    self?.openOAuthInSystemBrowser(url, sourceURL: sourceURL)
                },
                decisionHandler: decisionHandler
            )
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            Self.handleNavigationResponsePolicy(
                navigationResponse,
                webViewURL: webView.url,
                authorizeNavigation: parent.authorizeNavigation,
                allowsDownloads: parent.allowsDownloads,
                onRejectedNavigation: parent.onRejectedNavigation,
                decisionHandler: decisionHandler
            )
        }

        @MainActor
        static func handleNavigationActionPolicy(
            _ navigationAction: WKNavigationAction,
            webViewURL: URL?,
            allowMainFrameBlankAbout: Bool,
            authorizeNavigation: ((URL, @escaping (BrowserNavigationAuthorizationDecision) -> Void) -> Void)?,
            allowsDownloads: Bool,
            onRejectedNavigation: ((URL, BrowserNavigationAuthorizationDecision) -> Void)?,
            onSystemBrowserOAuth: @escaping (URL, URL?) -> Void,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let targetFrameIsMainFrame = navigationAction.targetFrame?.isMainFrame
            let isCloudflareChallengeFrame = !(targetFrameIsMainFrame ?? true)
                && GoogleOAuthHandoffDiagnostics.isCloudflareChallengeURL(navigationAction.request.url)
            let allowsCloudflareChallenge = CloudflareLoginNavigationPolicy.allowsChallengeFrame(
                navigationAction.request.url,
                topLevelURL: webViewURL,
                targetFrameIsMainFrame: targetFrameIsMainFrame
            )
            if isCloudflareChallengeFrame {
                GoogleOAuthHandoffDiagnostics.shared.recordCloudflareChallenge(allowed: allowsCloudflareChallenge)
            }
            if allowsCloudflareChallenge {
                decisionHandler(.allow)
                return
            }
            if allowsEmbeddedSubframeDocument(
                navigationAction.request.url,
                targetFrameIsMainFrame: targetFrameIsMainFrame
            ) {
                decisionHandler(.allow)
                return
            }
            if allowMainFrameBlankAbout,
               targetFrameIsMainFrame == true,
               isBlankAboutDocument(navigationAction.request.url) {
                decisionHandler(.allow)
                return
            }
            guard let url = navigationAction.request.url,
                  let scheme = url.scheme?.lowercased(), ["http", "https", "file"].contains(scheme),
                  url.user == nil, url.password == nil else {
                recordCloudflareSubframeCancelIfNeeded(
                    url: navigationAction.request.url,
                    topLevelURL: webViewURL,
                    targetFrameIsMainFrame: targetFrameIsMainFrame
                )
                decisionHandler(.cancel)
                return
            }
            guard let authorize = authorizeNavigation else {
                let decision = navigationDecision(
                    isAllowed: nil,
                    shouldDownload: navigationAction.shouldPerformDownload,
                    allowsDownloads: allowsDownloads
                )
                if decision == .cancel {
                    recordCloudflareSubframeCancelIfNeeded(
                        url: url,
                        topLevelURL: webViewURL,
                        targetFrameIsMainFrame: targetFrameIsMainFrame
                    )
                }
                decisionHandler(webKitActionPolicy(decision))
                return
            }
            authorize(url) { decision in
                runOnMain {
                    if !decision.isAllowed { onRejectedNavigation?(url, decision) }
                    let navigationDecision = navigationDecision(
                        isAllowed: decision.isAllowed,
                        shouldDownload: navigationAction.shouldPerformDownload,
                        allowsDownloads: allowsDownloads
                    )
                    if navigationDecision == .allow, GoogleOAuthNavigationPolicy.requiresSystemBrowser(for: url) {
                        decisionHandler(.cancel)
                        onSystemBrowserOAuth(url, webViewURL)
                        return
                    }
                    if navigationDecision == .cancel {
                        recordCloudflareSubframeCancelIfNeeded(
                            url: url,
                            topLevelURL: webViewURL,
                            targetFrameIsMainFrame: targetFrameIsMainFrame
                        )
                    }
                    decisionHandler(webKitActionPolicy(navigationDecision))
                }
            }
        }

        @MainActor
        static func handleNavigationResponsePolicy(
            _ navigationResponse: WKNavigationResponse,
            webViewURL: URL?,
            authorizeNavigation: ((URL, @escaping (BrowserNavigationAuthorizationDecision) -> Void) -> Void)?,
            allowsDownloads: Bool,
            onRejectedNavigation: ((URL, BrowserNavigationAuthorizationDecision) -> Void)?,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            GoogleOAuthHandoffDiagnostics.shared.recordHTTPResponse(
                navigationResponse.response,
                isMainFrame: navigationResponse.isForMainFrame
            )
            let allowsCloudflareChallenge = CloudflareLoginNavigationPolicy.allowsChallengeFrame(
                navigationResponse.response.url,
                topLevelURL: webViewURL,
                targetFrameIsMainFrame: navigationResponse.isForMainFrame
            )
            if !navigationResponse.isForMainFrame,
               GoogleOAuthHandoffDiagnostics.isCloudflareChallengeURL(navigationResponse.response.url) {
                GoogleOAuthHandoffDiagnostics.shared.recordCloudflareChallenge(allowed: allowsCloudflareChallenge)
            }
            if allowsCloudflareChallenge {
                decisionHandler(.allow)
                return
            }
            if allowsEmbeddedSubframeDocument(
                navigationResponse.response.url,
                targetFrameIsMainFrame: navigationResponse.isForMainFrame
            ) {
                decisionHandler(.allow)
                return
            }
            let disposition = (navigationResponse.response as? HTTPURLResponse)?
                .value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
            let isAttachment = disposition.contains("attachment")
            let shouldDownload = isAttachment || !navigationResponse.canShowMIMEType
            guard let url = navigationResponse.response.url,
                  let scheme = url.scheme?.lowercased(), ["http", "https", "file"].contains(scheme),
                  url.user == nil, url.password == nil,
                  let authorize = authorizeNavigation else {
                decisionHandler(webKitResponsePolicy(navigationDecision(
                    isAllowed: nil,
                    shouldDownload: shouldDownload,
                    allowsDownloads: allowsDownloads
                )))
                return
            }
            authorize(url) { decision in
                runOnMain {
                    if !decision.isAllowed { onRejectedNavigation?(url, decision) }
                    decisionHandler(webKitResponsePolicy(navigationDecision(
                        isAllowed: decision.isAllowed,
                        shouldDownload: shouldDownload,
                        allowsDownloads: allowsDownloads
                    )))
                }
            }
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            beginDownload(download)
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            beginDownload(download)
        }

        func download(
            _ download: WKDownload,
            decideDestinationUsing response: URLResponse,
            suggestedFilename: String,
            completionHandler: @escaping (URL?) -> Void
        ) {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = suggestedFilename
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            panel.begin { [weak self] result in
                guard result == .OK, let destination = panel.url else {
                    self?.parent.onDownloadStatus?("다운로드 취소됨")
                    completionHandler(nil)
                    return
                }
                let availableDestination = Self.nonExistingDestination(for: destination)
                let savedName = availableDestination.lastPathComponent
                self?.parent.onDownloadStatus?("다운로드 중 · \(savedName)")
                completionHandler(availableDestination)
            }
        }

        func downloadDidFinish(_ download: WKDownload) {
            onMain { self.parent.onDownloadStatus?("다운로드 완료") }
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            onMain { self.parent.onDownloadStatus?("다운로드 실패 · \(error.localizedDescription)") }
        }

        private func beginDownload(_ download: WKDownload) {
            download.delegate = self
            parent.onDownloadStatus?("저장 위치 선택")
        }

        static func navigationDecision(
            isAllowed: Bool?,
            shouldDownload: Bool,
            allowsDownloads: Bool
        ) -> NavigationDecision {
            guard isAllowed == true else { return .cancel }
            if shouldDownload { return allowsDownloads ? .download : .cancel }
            return .allow
        }

        static func allowsEmbeddedAboutDocument(_ url: URL?, targetFrameIsMainFrame: Bool?) -> Bool {
            guard targetFrameIsMainFrame == false,
                  let url,
                  url.scheme?.lowercased() == "about",
                  url.host == nil || url.host?.isEmpty == true else { return false }
            return ["blank", "srcdoc"].contains(url.path.lowercased())
        }

        static func isBlankAboutDocument(_ url: URL?) -> Bool {
            guard let url,
                  url.scheme?.lowercased() == "about",
                  url.host == nil || url.host?.isEmpty == true else { return false }
            return url.path.lowercased() == "blank"
        }

        static func allowsEmbeddedSubframeDocument(_ url: URL?, targetFrameIsMainFrame: Bool?) -> Bool {
            if allowsEmbeddedAboutDocument(url, targetFrameIsMainFrame: targetFrameIsMainFrame) {
                return true
            }
            guard targetFrameIsMainFrame == false,
                  let url,
                  let scheme = url.scheme?.lowercased() else { return false }
            if scheme == "blob" {
                let raw = url.absoluteString
                guard raw.lowercased().hasPrefix("blob:"),
                      let inner = URL(string: String(raw.dropFirst(5))),
                      inner.scheme?.lowercased() == "https",
                      let innerHost = inner.host, !innerHost.isEmpty,
                      inner.user == nil, inner.password == nil else { return false }
                return true
            }
            if scheme == "data" {
                return url.host == nil || url.host?.isEmpty == true
            }
            return false
        }

        @MainActor
        static func recordCloudflareSubframeCancelIfNeeded(
            url: URL?,
            topLevelURL: URL?,
            targetFrameIsMainFrame: Bool?
        ) {
            guard targetFrameIsMainFrame == false,
                  topLevelURL?.host?.lowercased() == "dash.cloudflare.com" else { return }
            let rawScheme = url?.scheme?.lowercased() ?? "none"
            let sanitized = rawScheme.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
            let schemeLabel = sanitized.isEmpty ? "unknown" : sanitized
            GoogleOAuthHandoffDiagnostics.shared.record(
                .openFailed,
                detail: "Cloudflare 하위 프레임 차단 · \(schemeLabel)",
                key: "cf-subframe-cancel-\(schemeLabel)"
            )
        }

        private static func webKitActionPolicy(_ decision: NavigationDecision) -> WKNavigationActionPolicy {
            switch decision {
            case .allow: return .allow
            case .cancel: return .cancel
            case .download: return .download
            }
        }

        private static func webKitResponsePolicy(_ decision: NavigationDecision) -> WKNavigationResponsePolicy {
            switch decision {
            case .allow: return .allow
            case .cancel: return .cancel
            case .download: return .download
            }
        }

        private static func nonExistingDestination(for requestedURL: URL) -> URL {
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: requestedURL.path) else { return requestedURL }
            let directory = requestedURL.deletingLastPathComponent()
            let baseName = requestedURL.deletingPathExtension().lastPathComponent
            let fileExtension = requestedURL.pathExtension
            var suffix = 2
            while true {
                var candidate = directory.appendingPathComponent("\(baseName) (\(suffix))")
                if !fileExtension.isEmpty { candidate.appendPathExtension(fileExtension) }
                if !fileManager.fileExists(atPath: candidate.path) { return candidate }
                suffix += 1
            }
        }

        private static func runOnMain(_ action: @escaping @MainActor () -> Void) {
            if Thread.isMainThread {
                MainActor.assumeIsolated(action)
            } else {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated(action)
                }
            }
        }

        private func onMain(_ action: @escaping @MainActor () -> Void) {
            Self.runOnMain(action)
        }
    }
}

@MainActor
private enum ThreeFWebKitDialogPresenter {
    static func runAlert(on webView: WKWebView, message: String, frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = makeAlert(title: frameTitle(for: frame), message: message)
        alert.addButton(withTitle: "확인")
        present(alert, on: webView, onResponse: { _ in completionHandler() }, fallback: completionHandler)
    }

    static func runConfirm(on webView: WKWebView, message: String, frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = makeAlert(title: frameTitle(for: frame), message: message)
        alert.addButton(withTitle: "확인")
        alert.addButton(withTitle: "취소")
        present(alert, on: webView, onResponse: { completionHandler($0 == .alertFirstButtonReturn) }, fallback: { completionHandler(false) })
    }

    static func runPrompt(
        on webView: WKWebView,
        prompt: String,
        defaultText: String?,
        frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let alert = makeAlert(title: frameTitle(for: frame), message: prompt)
        alert.addButton(withTitle: "확인")
        alert.addButton(withTitle: "취소")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.stringValue = defaultText ?? ""
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        present(alert, on: webView, onResponse: { response in
            completionHandler(response == .alertFirstButtonReturn ? input.stringValue : nil)
        }, fallback: { completionHandler(nil) })
    }

    private static func frameTitle(for frame: WKFrameInfo) -> String {
        let host = frame.securityOrigin.host
        return host.isEmpty ? "3F Browser" : host
    }

    private static func makeAlert(title: String, message: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        return alert
    }

    private static func present(
        _ alert: NSAlert,
        on webView: WKWebView,
        onResponse: @escaping (NSApplication.ModalResponse) -> Void,
        fallback: @escaping () -> Void
    ) {
        guard let window = webView.window else {
            fallback()
            return
        }
        if window.attachedSheet == nil {
            alert.beginSheetModal(for: window, completionHandler: onResponse)
        } else {
            onResponse(alert.runModal())
        }
    }
}

@MainActor
private final class ThreeFManagedPopupWindowController: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    private let window: NSWindow
    private let webView: WKWebView
    private let openerURL: URL?
    private let authorizeNavigation: ((URL, @escaping (BrowserNavigationAuthorizationDecision) -> Void) -> Void)?
    private let onRejectedNavigation: ((URL, BrowserNavigationAuthorizationDecision) -> Void)?
    private let allowsDownloads: Bool
    private let openOAuthInSystemBrowser: (URL, URL?) -> Void
    private let openLinkInNewTab: ((URL) -> Void)?
    private let onClose: (ObjectIdentifier) -> Void
    private var isClosed = false

    init(
        configuration: WKWebViewConfiguration,
        windowFeatures: WKWindowFeatures,
        openerURL: URL?,
        authorizeNavigation: ((URL, @escaping (BrowserNavigationAuthorizationDecision) -> Void) -> Void)?,
        onRejectedNavigation: ((URL, BrowserNavigationAuthorizationDecision) -> Void)?,
        allowsDownloads: Bool,
        openOAuthInSystemBrowser: @escaping (URL, URL?) -> Void,
        openLinkInNewTab: ((URL) -> Void)?,
        onClose: @escaping (ObjectIdentifier) -> Void
    ) {
        self.openerURL = openerURL
        self.authorizeNavigation = authorizeNavigation
        self.onRejectedNavigation = onRejectedNavigation
        self.allowsDownloads = allowsDownloads
        self.openOAuthInSystemBrowser = openOAuthInSystemBrowser
        self.openLinkInNewTab = openLinkInNewTab
        self.onClose = onClose

        let requestedWidth = CGFloat(windowFeatures.width?.doubleValue ?? 560)
        let requestedHeight = CGFloat(windowFeatures.height?.doubleValue ?? 680)
        let width = min(max(requestedWidth, 420), 1000)
        let height = min(max(requestedHeight, 480), 860)
        let contentRect = NSRect(x: 0, y: 0, width: width, height: height)

        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "로그인 · 3F Browser"
        window.isReleasedWhenClosed = false
        window.center()

        let webView = WKWebView(frame: contentRect, configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        window.contentView = webView

        self.window = window
        self.webView = webView
        super.init()

        window.delegate = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    var popupWebView: WKWebView { webView }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    private func closePopup() {
        guard !isClosed else { return }
        isClosed = true
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        isClosed = true
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        onClose(ObjectIdentifier(self))
    }

    func webViewDidClose(_ webView: WKWebView) {
        closePopup()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        window.title = title.isEmpty ? (webView.url?.host ?? "로그인 · 3F Browser") : title
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        let sourceURL = GoogleOAuthNavigationPolicy.safeHTTPSPageURL(webView.url) ?? openerURL
        if GoogleOAuthNavigationPolicy.requiresSystemBrowser(for: url) {
            guard let authorizeNavigation else { return nil }
            authorizeNavigation(url) { [weak self] decision in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard decision.isAllowed else {
                        self.onRejectedNavigation?(url, decision)
                        return
                    }
                    self.openOAuthInSystemBrowser(url, sourceURL)
                }
            }
            return nil
        }
        BrowserWebView.Coordinator.routePopup(
            targetFrameIsAbsent: navigationAction.targetFrame == nil,
            url: url,
            openInNewTab: openLinkInNewTab
        )
        return nil
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        BrowserWebView.Coordinator.handleNavigationActionPolicy(
            navigationAction,
            webViewURL: webView.url,
            allowMainFrameBlankAbout: true,
            authorizeNavigation: authorizeNavigation,
            allowsDownloads: allowsDownloads,
            onRejectedNavigation: { [weak self] url, decision in
                self?.onRejectedNavigation?(url, decision)
                if webView.url == nil || BrowserWebView.Coordinator.isBlankAboutDocument(webView.url) {
                    self?.closePopup()
                }
            },
            onSystemBrowserOAuth: { [weak self] url, currentURL in
                guard let self else { return }
                let sourceURL = GoogleOAuthNavigationPolicy.safeHTTPSPageURL(currentURL) ?? self.openerURL
                self.openOAuthInSystemBrowser(url, sourceURL)
                if currentURL == nil || BrowserWebView.Coordinator.isBlankAboutDocument(currentURL) {
                    self.closePopup()
                }
            },
            decisionHandler: decisionHandler
        )
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        BrowserWebView.Coordinator.handleNavigationResponsePolicy(
            navigationResponse,
            webViewURL: webView.url,
            authorizeNavigation: authorizeNavigation,
            allowsDownloads: allowsDownloads,
            onRejectedNavigation: onRejectedNavigation,
            decisionHandler: decisionHandler
        )
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        ThreeFWebKitDialogPresenter.runAlert(on: webView, message: message, frame: frame, completionHandler: completionHandler)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        ThreeFWebKitDialogPresenter.runConfirm(on: webView, message: message, frame: frame, completionHandler: completionHandler)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        ThreeFWebKitDialogPresenter.runPrompt(
            on: webView,
            prompt: prompt,
            defaultText: defaultText,
            frame: frame,
            completionHandler: completionHandler
        )
    }
}
