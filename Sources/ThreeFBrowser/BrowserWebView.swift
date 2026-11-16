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

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
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
        let coordinator = context.coordinator
        if OptionalFeatureAvailability.youtubeUsageReporting {
            configuration.userContentController.add(
                YouTubeKeywordSelectionScriptMessageHandler(),
                name: YouTubeTitleExemptionScripts.selectionMessageName
            )
            configuration.userContentController.addUserScript(WKUserScript(
                source: YouTubeTitleExemptionScripts.selection,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
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
        if onOpenBackgroundTab != nil {
            let handler = ThreeFBackgroundLinkScriptMessageHandler()
            handler.delegate = coordinator
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
        let view = ThreeFWindowAwareWebView(frame: .zero, configuration: configuration)
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
                    guard decision.isAllowed else {
                        self.parent.onRejectedNavigation?(url, decision)
                        return
                    }
                    self.openOAuthInSystemBrowser(url, sourceURL: webView.url)
                }
                return nil
            }
            Self.routePopup(
                targetFrameIsAbsent: navigationAction.targetFrame == nil,
                url: navigationAction.request.url,
                openInNewTab: parent.onOpenLinkInNewTab
            )
            return nil
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
            let isCloudflareChallengeFrame = !((navigationAction.targetFrame?.isMainFrame) ?? true)
                && GoogleOAuthHandoffDiagnostics.isCloudflareChallengeURL(navigationAction.request.url)
            let allowsCloudflareChallenge = CloudflareLoginNavigationPolicy.allowsChallengeFrame(
                navigationAction.request.url,
                topLevelURL: webView.url,
                targetFrameIsMainFrame: navigationAction.targetFrame?.isMainFrame
            )
            if isCloudflareChallengeFrame {
                GoogleOAuthHandoffDiagnostics.shared.recordCloudflareChallenge(allowed: allowsCloudflareChallenge)
            }
            if allowsCloudflareChallenge {
                decisionHandler(.allow)
                return
            }
            if ThreeFBackgroundLinkPolicy.isBackgroundLink(
                navigationType: navigationAction.navigationType,
                buttonNumber: navigationAction.buttonNumber,
                isMainFrame: navigationAction.sourceFrame.isMainFrame
            ), let destination = ThreeFContextMenuPolicy.safeHTTPURL(navigationAction.request.url) {
                decisionHandler(.cancel)
                openBackgroundLink(destination)
                return
            }
            if Self.allowsEmbeddedAboutDocument(
                navigationAction.request.url,
                targetFrameIsMainFrame: navigationAction.targetFrame?.isMainFrame
            ) {
                decisionHandler(.allow)
                return
            }
            guard let url = navigationAction.request.url,
                  let scheme = url.scheme?.lowercased(), ["http", "https", "file"].contains(scheme),
                  url.user == nil, url.password == nil else {
                decisionHandler(.cancel)
                return
            }
            guard let authorize = parent.authorizeNavigation else {
                let navigationDecision = Self.navigationDecision(isAllowed: nil, shouldDownload: navigationAction.shouldPerformDownload, allowsDownloads: parent.allowsDownloads)
                if navigationDecision == .allow, GoogleOAuthNavigationPolicy.requiresSystemBrowser(for: url) {
                    decisionHandler(.cancel)
                    openOAuthInSystemBrowser(url, sourceURL: webView.url)
                    return
                }
                decisionHandler(Self.webKitActionPolicy(navigationDecision))
                return
            }
            authorize(url) { [weak self] decision in
                if !decision.isAllowed { self?.parent.onRejectedNavigation?(url, decision) }
                let navigationDecision = Self.navigationDecision(isAllowed: decision.isAllowed, shouldDownload: navigationAction.shouldPerformDownload, allowsDownloads: self?.parent.allowsDownloads ?? false)
                if navigationDecision == .allow, GoogleOAuthNavigationPolicy.requiresSystemBrowser(for: url) {
                    decisionHandler(.cancel)
                    self?.openOAuthInSystemBrowser(url, sourceURL: webView.url)
                    return
                }
                decisionHandler(Self.webKitActionPolicy(navigationDecision))
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            GoogleOAuthHandoffDiagnostics.shared.recordHTTPResponse(
                navigationResponse.response,
                isMainFrame: navigationResponse.isForMainFrame
            )
            let allowsCloudflareChallenge = CloudflareLoginNavigationPolicy.allowsChallengeFrame(
                navigationResponse.response.url,
                topLevelURL: webView.url,
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
            if Self.allowsEmbeddedAboutDocument(
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
                  let authorize = parent.authorizeNavigation else {
                decisionHandler(Self.webKitResponsePolicy(Self.navigationDecision(isAllowed: nil, shouldDownload: shouldDownload, allowsDownloads: parent.allowsDownloads)))
                return
            }
            authorize(url) { [weak self] decision in
                if !decision.isAllowed { self?.parent.onRejectedNavigation?(url, decision) }
                decisionHandler(Self.webKitResponsePolicy(Self.navigationDecision(isAllowed: decision.isAllowed, shouldDownload: shouldDownload, allowsDownloads: self?.parent.allowsDownloads ?? false)))
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
                  url.host == nil,
                  url.query == nil,
                  url.fragment == nil else { return false }
            return ["blank", "srcdoc"].contains(url.path.lowercased())
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

        private func onMain(_ action: @escaping () -> Void) {
            if Thread.isMainThread {
                action()
            } else {
                DispatchQueue.main.async(execute: action)
            }
        }
    }
}
