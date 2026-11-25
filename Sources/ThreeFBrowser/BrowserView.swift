import SwiftUI
import WebKit
import AppKit

struct BrowserView: View {
    @StateObject private var model: BrowserModel
    @EnvironmentObject private var externalURLs: ThreeFURLRouter
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var webView: WKWebView?
    @State private var tabWebViews: [UUID: WKWebView] = [:]
    @State private var mountedTabIDs: Set<UUID> = []
    @State private var tabNavigationRequestIDs: [UUID: Int] = [:]
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var tabs: [BrowserSessionTab]
    @State private var selectedTabID: UUID?
    @State private var navigationFeedbackPulse = false
    @State private var readerArticle: ReaderArticle?
    @State private var readerFailure: String?
    @State private var isExtractingReaderArticle = false
    @State private var isShowingHistoryPopover = false
    @State private var isShowingWildcardBlockSheet = false
    @State private var historySearchQuery = ""
    @State private var googleSuggestions: [String] = []
    @State private var suggestionFetchTask: Task<Void, Never>?
    @State private var isShowingAISidePanel = false
    @State private var aiSidePanelWebView: WKWebView?
    @State private var aiSidePanelURL: URL? = AIModeNavigationPolicy.onlyChatURL
    @State private var aiSidePanelRequestID = 1
    @State private var assignedWindowID: String?
    @State private var didRestoreSession = false
    @State private var isWindowClosing = false
    @State private var isAppTerminating = false
    @FocusState private var isAddressFocused: Bool
    private let embedded: Bool
    private let aiMode: Bool
    private let installedWebApp: InstalledWebApp?
    private let authorizeNavigation: ((URL, @escaping (BrowserNavigationAuthorizationDecision) -> Void) -> Void)?
    private let onWebView: ((BrowserModel, WKWebView) -> Void)?
    private let onPageStateChange: ((URL?) -> Void)?
    private let onBlockedNavigation: ((URL) -> Void)?

    private var sessionStorageWindowID: String {
        assignedWindowID ?? (aiMode ? "primary-ai-mode-window" : "primary-browser-window")
    }
    private var sessionStorageDirectory: URL {
        aiMode ? BrowserSessionStore.defaultDirectory.appendingPathComponent("ai-mode-sessions", isDirectory: true) : BrowserSessionStore.defaultDirectory
    }

    init(
        embedded: Bool = false,
        aiMode: Bool = false,
        installedWebApp: InstalledWebApp? = nil,
        authorizeNavigation: ((URL, @escaping (BrowserNavigationAuthorizationDecision) -> Void) -> Void)? = nil,
        onWebView: ((BrowserModel, WKWebView) -> Void)? = nil,
        onPageStateChange: ((URL?) -> Void)? = nil,
        onBlockedNavigation: ((URL) -> Void)? = nil
    ) {
        self.embedded = embedded
        self.aiMode = aiMode
        self.installedWebApp = installedWebApp
        self.authorizeNavigation = authorizeNavigation
        self.onWebView = onWebView
        self.onPageStateChange = onPageStateChange
        self.onBlockedNavigation = onBlockedNavigation
        _model = StateObject(wrappedValue: BrowserModel())
        let initialTab = BrowserSessionTab(
            title: aiMode ? "Only Chat" : (installedWebApp?.title ?? "새 탭"),
            url: aiMode ? AIModeNavigationPolicy.onlyChatURL : installedWebApp?.destination
        )
        _tabs = State(initialValue: [initialTab])
        _selectedTabID = State(initialValue: initialTab.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            if aiMode {
                HStack(spacing: 0) {
                    aiModeSidebar
                    browserContent
                }
            } else if embedded {
                tabStrip
            } else if installedWebApp == nil {
                VStack(spacing: 0) {
                    tabStrip
                    addressBar
                        .zIndex(100)
                    if !model.theme.quickLinks.isEmpty || !model.installedWebApps.isEmpty { quickLinksBar }
                }
                .background(ThreeFPalette.canvas)
            }
            if !embedded && installedWebApp == nil && model.shouldShowYouTubeUsage { youtubePolicyStatus }
            HStack(spacing: 0) {
                browserContent
                if !aiMode && !embedded && installedWebApp == nil && isShowingAISidePanel {
                    Divider()
                    aiSidePanel
                        .frame(width: 420)
                }
            }
            if !embedded && installedWebApp == nil { statusBar }
        }
        .padding(.top, (embedded || aiMode || installedWebApp != nil) ? 0 : 28)
        .frame(minWidth: aiMode ? 1120 : (embedded ? 280 : (installedWebApp == nil ? 760 : 520)), minHeight: aiMode ? 680 : (embedded ? 220 : (installedWebApp == nil ? 520 : 360)))
        .navigationTitle(aiMode ? "3F AI Mod" : (installedWebApp?.title ?? "3F Browser"))
        .tint(model.theme.color)
        .sheet(isPresented: $model.isShowingSettings) {
            BrowserSettingsView(model: model)
        }
        .sheet(item: $model.pendingMediaSiteCandidate) { candidate in
            MediaSiteCandidateSheet(
                candidate: candidate,
                onResolved: model.resolveMediaSiteCandidate,
                onDeferred: model.deferMediaSiteCandidate
            )
        }
        .onAppear {
            registerBrowserWindowPresenter()
            consumeExternalURLs()
        }
        .onAppear(perform: initializeWindow)
        .onChange(of: model.currentURL) { _, url in
            updateActiveTab(url: url, title: url?.host)
            onPageStateChange?(url)
        }
        .onChange(of: model.navigationRequestID) { _, _ in
            if let selectedTabID { tabNavigationRequestIDs[selectedTabID] = model.navigationRequestID }
            pulseNavigationFeedback()
        }
        .onChange(of: selectedTabID) { _, tabID in
            guard let tabID else { webView = nil; return }
            mountedTabIDs.insert(tabID)
            webView = tabWebViews[tabID]
        }
        .onChange(of: webView) { _, _ in
            attachWebViewIfActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard ThreeFBrowserWindowRouting.targets(notification.object as? NSWindow, window: webView?.window) else { return }
            try? BrowserSessionStore.markWindowActive(sessionStorageWindowID, in: sessionStorageDirectory)
            attachWebViewIfActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            isAppTerminating = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            handleBrowserWindowWillClose(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .threeFCloseSelectedTab)) { notification in
            guard !embedded,
                  ThreeFBrowserWindowRouting.targets(notification.object as? NSWindow, window: webView?.window),
                  let selectedTabID,
                  let selectedTab = tabs.first(where: { $0.id == selectedTabID }) else { return }
            closeTab(selectedTab)
        }
        .onChange(of: externalURLs.pendingURLs) { _, _ in consumeExternalURLs() }
        .task(id: model.youtubeUsagePollKey) {
            guard !embedded, model.shouldShowYouTubeUsage else {
                model.clearYouTubeUsage()
                return
            }
            while !Task.isCancelled {
                if let url = BrowserNavigationURLSync.changedURL(
                    modelURL: model.currentURL,
                    webViewURL: webView?.url
                ) {
                    let title = webView?.title
                    model.pageDidNavigate(to: url, title: title)
                    updateActiveTab(url: url, title: title)
                }
                await model.refreshYouTubeUsage()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
        .onDisappear {
            if !isWindowClosing { saveCurrentTab() }
        }
    }

    private var browserContent: some View {
        ZStack {
            ForEach(tabs.filter { mountedTabIDs.contains($0.id) }) { tab in
                tabWebContent(for: tab)
                    .opacity(selectedTabID == tab.id ? 1 : 0)
                    .allowsHitTesting(selectedTabID == tab.id)
                    .zIndex(selectedTabID == tab.id ? 1 : 0)
            }

            if model.currentURL == nil { newTabPage }
        }
        .overlay(alignment: .bottomTrailing) {
            if !embedded, model.isYouTubeFeedContext {
                Text(model.youtubeUsageSummary?.compactFeedStatus ?? "피드 사용량 확인 중")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(ThreeFPalette.ink.opacity(0.82))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().stroke(ThreeFPalette.border.opacity(0.65), lineWidth: 1))
                    .padding(12)
                    .allowsHitTesting(false)
                    .accessibilityLabel("YouTube 피드 사용량 · \(model.youtubeUsageSummary?.compactFeedStatus ?? "사용량 확인 중")")
            }
        }
        .sheet(item: $readerArticle) { article in
            ReaderModeView(article: article)
        }
        .sheet(isPresented: $isShowingWildcardBlockSheet) {
            WildcardBlockSheet(currentURL: model.currentURL) { pattern, hideTitle, blockUrl in
                if blockUrl, let current = model.currentURL,
                   WildcardBlockStore.shared.matchesBlockedUrl(current) {
                    webView?.load(URLRequest(url: URL(string: "about:blank")!))
                    model.currentURL = nil
                    if let selectedTabID { updateTab(tabID: selectedTabID, url: nil, title: "새 탭") }
                } else if hideTitle || blockUrl {
                    webView?.reload()
                }
                Task { await WildcardBlockStore.shared.syncWithBlueCloud() }
            }
        }
        .alert("읽기 모드를 열 수 없습니다.", isPresented: Binding(
            get: { readerFailure != nil },
            set: { if !$0 { readerFailure = nil } }
        )) {
            Button("확인", role: .cancel) { readerFailure = nil }
        } message: {
            Text(readerFailure ?? "페이지 본문을 찾지 못했습니다.")
        }
    }

    private func tabWebContent(for tab: BrowserSessionTab) -> some View {
        let tabID = tab.id
        let url = Binding<URL?>(
            get: {
                guard let savedURL = tabs.first(where: { $0.id == tabID })?.url else { return nil }
                return selectedTabID == tabID ? model.currentURL : savedURL
            },
            set: { updateTab(tabID: tabID, url: $0, title: $0?.host) }
        )
        let requestID = Binding<Int>(
            get: { tabNavigationRequestIDs[tabID] ?? 0 },
            set: { tabNavigationRequestIDs[tabID] = $0 }
        )
        let tabWebView = Binding<WKWebView?>(
            get: { tabWebViews[tabID] },
            set: { view in
                tabWebViews[tabID] = view
                if selectedTabID == tabID { webView = view }
            }
        )
        return BrowserWebView(
            url: url,
            requestID: requestID,
            webView: tabWebView,
            authorizeNavigation: authorizeNavigation,
            onRejectedNavigation: { rejectedURL, decision in
                guard selectedTabID == tabID else { return }
                model.pageDidRejectNavigation(decision, for: rejectedURL)
                onBlockedNavigation?(rejectedURL)
            },
            allowsDownloads: !embedded,
            onDownloadStatus: { if selectedTabID == tabID { model.downloadStatus = $0 } },
            onWindowAttached: { attachedView in
                guard selectedTabID == tabID else { return }
                guard ThreeFBrowserWindowRouting.targets(attachedView.window, window: NSApp.keyWindow) else { return }
                onWebView?(model, attachedView)
            },
            onNavigationStarted: { if selectedTabID == tabID { model.pageDidStartNavigation(to: $0) } },
            onNavigationCommitted: { if selectedTabID == tabID { model.pageDidCommitNavigation(to: $0) } },
            onLoadingChanged: { if selectedTabID == tabID { model.isLoading = $0 } },
            onNavigationFailed: { if selectedTabID == tabID { model.pageDidFailToNavigate($0) } },
            onOpenLinkInNewTab: addTab(for:),
            onOpenBackgroundTab: addBackgroundTab(for:),
            onOpenLinkInNewWindow: openLinkInNewWindow,
            onNavigation: { value, title in
                updateTab(tabID: tabID, url: value, title: title)
                if selectedTabID == tabID { model.pageDidNavigate(to: value, title: title) }
            },
            onNavigationState: { back, forward in
                if selectedTabID == tabID { canGoBack = back; canGoForward = forward }
            }
        )
    }

    private func updateTab(tabID: UUID, url: URL?, title: String?) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[index].url = url
        if aiMode, let url, AIModeNavigationPolicy.isOnlyChatLocalOrigin(url) {
            tabs[index].title = "Only Chat"
        } else {
            tabs[index].title = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? url?.host ?? "새 탭"
        }
        saveSession()
    }

    private func consumeExternalURLs() {
        externalURLs.takePendingURLs().forEach { model.openExternalURL($0, authorize: authorizeNavigation) }
    }

    private func registerBrowserWindowPresenter() {
        var openWindowRequested = false
        let presenter: () -> Bool = { [openWindow] in
            let window = NSApp.windows.first { $0.title == "3F Browser" }
            if let window {
                openWindowRequested = false
                if window.isMiniaturized { window.deminiaturize(nil) }
                window.makeKeyAndOrderFront(nil)
            } else {
                if !openWindowRequested {
                    openWindow(id: "browser")
                    openWindowRequested = true
                }
            }
            NSApp.activate(ignoringOtherApps: true)
            return NSApp.windows.contains { $0.title == "3F Browser" && $0.isVisible && $0.isKeyWindow }
        }
        externalURLs.setBrowserWindowPresenter(presenter)
        ThreeFBrowserControlController.shared.setBrowserWindowPresenter(presenter)
    }

    private func attachWebViewIfActive() {
        guard let webView,
              let window = webView.window,
              ThreeFBrowserWindowRouting.targets(window, window: NSApp.keyWindow) else { return }
        onWebView?(model, webView)
    }

    private var addressBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 9) {
                Text("3F")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(model.theme.color, in: RoundedRectangle(cornerRadius: 10))
                Text("3F Browser")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ThreeFPalette.ink)
            }
            .padding(.trailing, 5)

            chromeButton("chevron.left", help: "뒤로", disabled: !canGoBack || model.currentURL == nil) {
                webView?.goBack()
            }
            chromeButton("chevron.right", help: "앞으로", disabled: !canGoForward || model.currentURL == nil) {
                webView?.goForward()
            }
            chromeButton(model.currentURL == nil ? "magnifyingglass" : "arrow.clockwise",
                         help: model.currentURL == nil ? "검색" : "새로고침") {
                if model.currentURL == nil { submitAddressBar() }
                else { webView?.reload() }
            }

            HStack(spacing: 10) {
                if model.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                        .help("페이지를 여는 중")
                        .accessibilityLabel("페이지를 여는 중")
                        .transition(.opacity)
                    Text("이동 중")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(model.theme.color)
                        .fixedSize()
                        .accessibilityHidden(true)
                        .transition(.opacity)
                } else {
                    Image(systemName: model.currentURL == nil ? "magnifyingglass" : "globe")
                        .foregroundStyle(ThreeFPalette.muted)
                        .transition(.opacity)
                }
                TextField("검색 또는 웹 주소 입력", text: $model.addressText, prompt: Text("검색 또는 웹 주소 입력").foregroundColor(ThreeFPalette.muted))
                    .focused($isAddressFocused)
                    .textFieldStyle(.plain)
                    .foregroundStyle(ThreeFPalette.ink)
                    .tint(model.theme.color)
                    .font(.system(size: 14))
                    .onSubmit {
                        isAddressFocused = false
                        submitAddressBar()
                    }
                if !model.addressText.isEmpty {
                    Button { model.addressText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(ThreeFPalette.muted.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                    .help("지우기")
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 38)
            .background(ThreeFPalette.raised, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(
                model.isLoading
                    ? model.theme.color.opacity(navigationFeedbackPulse ? 1 : 0.48)
                    : ThreeFPalette.border,
                lineWidth: model.isLoading ? (navigationFeedbackPulse ? 2.5 : 1.5) : 1
            ))
            .onChange(of: model.addressText) { _, newValue in
                fetchGoogleSuggestions(for: newValue)
            }
            .overlay(alignment: .topLeading) {
                if isAddressFocused && !model.addressText.isEmpty {
                    let recentSuggestions = model.autocompleteSuggestions(for: model.addressText)
                    if !recentSuggestions.isEmpty || !googleSuggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(recentSuggestions.enumerated()), id: \.element.id) { index, entry in
                                Button {
                                    model.addressText = entry.url
                                    isAddressFocused = false
                                    submitAddressBar()
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .font(.system(size: 11))
                                            .foregroundStyle(ThreeFPalette.muted)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.title.isEmpty ? entry.url : entry.title)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(ThreeFPalette.ink)
                                                .lineLimit(1)
                                            Text(entry.url)
                                                .font(.system(size: 10))
                                                .foregroundStyle(ThreeFPalette.muted)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if index < recentSuggestions.count - 1 || !googleSuggestions.isEmpty {
                                    Divider().padding(.horizontal, 6)
                                }
                            }
                            ForEach(Array(googleSuggestions.enumerated()), id: \.offset) { index, suggestion in
                                Button {
                                    model.addressText = suggestion
                                    isAddressFocused = false
                                    submitAddressBar()
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "magnifyingglass")
                                            .font(.system(size: 11))
                                            .foregroundStyle(ThreeFPalette.muted)
                                        Text(suggestion)
                                            .font(.system(size: 12))
                                            .foregroundStyle(ThreeFPalette.ink)
                                            .lineLimit(1)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if index < googleSuggestions.count - 1 {
                                    Divider().padding(.horizontal, 6)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ThreeFPalette.border, lineWidth: 1))
                        .shadow(color: ThreeFPalette.ink.opacity(0.12), radius: 8, y: 4)
                        .offset(y: 42)
                        .zIndex(200)
                    }
                }
            }
            .shadow(color: ThreeFPalette.ink.opacity(0.04), radius: 3, y: 1)
            .animation(.easeInOut(duration: 0.18), value: model.isLoading)
            .animation(.easeInOut(duration: 0.14), value: navigationFeedbackPulse)
            if let notice = model.addressBlockNotice {
                Text(notice).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(1)
            }

            chromeButton("plus", help: "새 탭", prominent: true) { addTab() }
            chromeButton("hand.raised.slash", help: "와일드카드 차단하기") {
                isShowingWildcardBlockSheet = true
            }
            chromeButton("star", help: "북마크 추가", disabled: model.currentURL == nil) {
                model.addBookmarkForCurrentPage()
            }
            chromeButton("square.and.arrow.down", help: "현재 웹사이트를 앱으로 설치", disabled: model.currentURL == nil) {
                installCurrentWebsiteAsApp()
            }
            chromeButton("text.alignleft", help: "읽기 모드", disabled: model.currentURL == nil || isExtractingReaderArticle) {
                openReaderMode()
            }
            chromeButton("clock.arrow.circlepath", help: "방문 기록") {
                isShowingHistoryPopover.toggle()
            }
            .popover(isPresented: $isShowingHistoryPopover, arrowEdge: .bottom) {
                historyPopover
            }
            chromeButton("gearshape", help: "설정") { model.isShowingSettings = true }
            chromeButton("sparkles", help: isShowingAISidePanel ? "AI 사이드 패널 닫기" : "AI 사이드 패널 열기", prominent: true) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isShowingAISidePanel.toggle()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var historyPopover: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(model.theme.color)
                Text("방문 기록")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if !model.history.isEmpty {
                    Button("전체 삭제", role: .destructive) {
                        model.clearHistory()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Divider()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(ThreeFPalette.muted)
                TextField("방문 기록 검색 (제목 또는 URL)", text: $historySearchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !historySearchQuery.isEmpty {
                    Button { historySearchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(ThreeFPalette.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(ThreeFPalette.raised)
            Divider()
            let filteredHistory = model.history.filter { entry in
                let q = historySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !q.isEmpty else { return true }
                return entry.title.localizedCaseInsensitiveContains(q) || entry.url.localizedCaseInsensitiveContains(q)
            }
            if filteredHistory.isEmpty {
                VStack(spacing: 6) {
                    Text(model.history.isEmpty ? "방문 기록이 없습니다." : "검색 결과가 없습니다.")
                        .font(.system(size: 12))
                        .foregroundStyle(ThreeFPalette.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredHistory) { entry in
                            HStack(spacing: 8) {
                                Button {
                                    if let url = URL(string: entry.url) {
                                        model.navigate(to: url, authorize: authorizeNavigation)
                                        isShowingHistoryPopover = false
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.title.isEmpty ? entry.url : entry.title)
                                            .font(.system(size: 12, weight: .medium))
                                            .lineLimit(1)
                                            .foregroundStyle(ThreeFPalette.ink)
                                        Text(entry.url)
                                            .font(.system(size: 10))
                                            .lineLimit(1)
                                            .foregroundStyle(ThreeFPalette.muted)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Button {
                                    if let url = URL(string: entry.url) {
                                        addTab(for: url)
                                        isShowingHistoryPopover = false
                                    }
                                } label: {
                                    Image(systemName: "plus.square.on.square")
                                        .font(.system(size: 11))
                                        .foregroundStyle(ThreeFPalette.muted)
                                }
                                .buttonStyle(.plain)
                                .help("새 탭에서 열기")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.clear))
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 340)
            }
        }
        .frame(width: 360)
        .background(ThreeFPalette.canvas)
    }

    private var aiSidePanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(model.theme.color)
                Text("AI 사이드 패널")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Button("Only Chat") {
                    aiSidePanelURL = AIModeNavigationPolicy.onlyChatURL
                    aiSidePanelRequestID += 1
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                Button("Gemini") {
                    aiSidePanelURL = URL(string: "https://gemini.google.com")
                    aiSidePanelRequestID += 1
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                Button {
                    sendCurrentPageContextToAISidePanel()
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("현재 페이지 내용을 AI 입력창/클립보드로 전달")
                .disabled(model.currentURL == nil)
                Button {
                    aiSidePanelWebView?.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("새로고침")
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isShowingAISidePanel = false
                    }
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("사이드 패널 닫기")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(ThreeFPalette.canvas)
            Divider()
            BrowserWebView(
                url: $aiSidePanelURL,
                requestID: $aiSidePanelRequestID,
                webView: $aiSidePanelWebView,
                authorizeNavigation: authorizeNavigation,
                onNavigation: { url, title in
                    if let url { aiSidePanelURL = url }
                    _ = title
                },
                onNavigationState: { _, _ in }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(ThreeFPalette.canvas)
    }

    private func sendCurrentPageContextToAISidePanel() {
        guard let currentWebView = webView else { return }
        let script = """
        (() => {
            const title = document.title || '';
            const url = location.href || '';
            const sel = (window.getSelection()?.toString() || '').trim();
            const bodyText = (document.body?.innerText || '').trim().slice(0, 3000);
            const content = sel ? `[선택 텍스트]\\n${sel}` : `[본문 요약용 발췌]\\n${bodyText}`;
            return `현재 페이지 분석 요청:\\n제목: ${title}\\nURL: ${url}\\n\\n${content}`;
        })();
        """
        currentWebView.evaluateJavaScript(script) { result, _ in
            guard let text = result as? String, !text.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            let encoded = (try? JSONSerialization.data(withJSONObject: [text]))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            let injectScript = """
            (() => {
                const text = \(encoded)[0];
                const el = document.querySelector('textarea, [contenteditable="true"], input[type="text"]');
                if (!el) return false;
                el.focus();
                if (el.tagName === 'TEXTAREA' || el.tagName === 'INPUT') {
                    el.value = text;
                    el.dispatchEvent(new Event('input', { bubbles: true }));
                } else {
                    el.innerText = text;
                    el.dispatchEvent(new InputEvent('input', { bubbles: true }));
                }
                return true;
            })();
            """
            aiSidePanelWebView?.evaluateJavaScript(injectScript, completionHandler: nil)
        }
    }

    private var aiModeSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(model.theme.color, in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 1) {
                    Text("3F AI Mod").font(.system(size: 13, weight: .semibold))
                    Text("Only Chat 작업공간").font(.system(size: 10)).foregroundStyle(ThreeFPalette.muted)
                }
                Spacer(minLength: 0)
            }
            Divider()
            HStack {
                Text("열린 창").font(.system(size: 11, weight: .semibold)).foregroundStyle(ThreeFPalette.muted)
                Spacer()
                Button { addTab() } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain).help("AI Mod 탭 열기")
            }
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(tabs) { tab in
                        HStack(spacing: 6) {
                            Button { selectTab(tab) } label: {
                                Label(tab.title, systemImage: tab.title == "Only Chat" ? "bubble.left.and.bubble.right" : "globe")
                                    .font(.system(size: 11, weight: selectedTabID == tab.id ? .semibold : .regular))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 9).padding(.vertical, 8)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(selectedTabID == tab.id ? ThreeFPalette.raised : .clear, in: RoundedRectangle(cornerRadius: 8))
                            Button { closeTab(tab) } label: {
                                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                            }
                            .buttonStyle(.plain).help("탭 닫기")
                        }
                    }
                }
            }
            Divider()
            Label("대화 목록은 Only Chat 화면에서 표시됩니다", systemImage: "list.bullet")
                .font(.system(size: 10)).foregroundStyle(ThreeFPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { openWindow(id: "browser") } label: {
                Label("일반 브라우저", systemImage: "globe")
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(width: 218)
        .background(ThreeFPalette.canvas)
        .overlay(alignment: .trailing) { Rectangle().fill(ThreeFPalette.border).frame(width: 1) }
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tabs) { tab in
                    HStack(spacing: 8) {
                        Button { selectTab(tab) } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "globe")
                                    .font(.system(size: 10, weight: .medium))
                                Text(tab.title)
                                    .lineLimit(1)
                                    .frame(maxWidth: 170, alignment: .leading)
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ThreeFPalette.ink)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                        }
                        .buttonStyle(.plain)
                        Button { closeTab(tab) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(ThreeFPalette.muted)
                        }
                        .buttonStyle(.plain)
                        .help("탭 닫기")
                    }
                    .padding(.trailing, 7)
                    .background(selectedTabID == tab.id ? ThreeFPalette.raised : ThreeFPalette.surface.opacity(0.65),
                                in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(ThreeFPalette.border.opacity(0.8), lineWidth: 1))
                }
                Button(action: addTab) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ThreeFPalette.muted)
                        .frame(width: 30, height: 30)
                        .background(ThreeFPalette.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .help("새 탭")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 2)
        }
        .background(ThreeFPalette.canvas)
    }

    private func addTab() {
        saveCurrentTab()
        let tab = BrowserSessionTab(title: aiMode ? "새 AI 탭" : "새 탭")
        tabs.append(tab)
        selectedTabID = tab.id
        model.showNewTab()
        canGoBack = false
        canGoForward = false
        saveSession()
    }

    private func openReaderMode() {
        guard let webView,
              let currentURL = webView.url,
              ["http", "https"].contains(currentURL.scheme?.lowercased() ?? ""),
              let resourceURL = Bundle.module.url(forResource: "Readability", withExtension: "js") else {
            readerFailure = "웹페이지를 열고 다시 시도해 주세요."
            return
        }

        do {
            let readabilitySource = try String(contentsOf: resourceURL, encoding: .utf8)
            let script = """
            (() => {
              const module = undefined;
              const exports = undefined;
            \(readabilitySource)
              const article = new Readability(document.cloneNode(true), { maxElemsToParse: 15000 }).parse();
              if (!article || !article.textContent || !article.textContent.trim()) return null;
              return JSON.stringify({
                title: article.title || document.title || "읽기 모드",
                byline: article.byline || "",
                siteName: article.siteName || location.hostname,
                excerpt: article.excerpt || "",
                text: article.textContent,
                sourceURL: location.href
              });
            })()
            """
            isExtractingReaderArticle = true
            webView.evaluateJavaScript(script, in: nil, in: .defaultClient) { result in
                DispatchQueue.main.async {
                    isExtractingReaderArticle = false
                    switch result {
                    case .success(let value):
                        guard let json = value as? String,
                              let data = json.data(using: .utf8),
                              let article = try? JSONDecoder().decode(ReaderArticle.self, from: data),
                              !article.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            readerFailure = "이 페이지에서 읽을 본문을 찾지 못했습니다."
                            return
                        }
                        readerArticle = article
                    case .failure(let error):
                        readerFailure = error.localizedDescription
                    }
                }
            }
        } catch {
            isExtractingReaderArticle = false
            readerFailure = "읽기 모듈을 불러오지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func addTab(for url: URL) {
        guard let url = ThreeFContextMenuPolicy.safeHTTPURL(url) else { return }
        saveCurrentTab()
        let tab = BrowserSessionTab(title: url.host ?? "새 탭")
        tabs.append(tab)
        selectedTabID = BrowserTabSelectionPolicy.selectedTabID(
            currentSelection: selectedTabID,
            newlyOpenedTabID: tab.id,
            opensInBackground: false
        )
        tabNavigationRequestIDs[tab.id] = model.navigationRequestID + 1
        model.navigate(to: url, authorize: authorizeNavigation)
        canGoBack = false
        canGoForward = false
        saveSession()
    }

    private func addBackgroundTab(for url: URL) {
        guard let url = ThreeFContextMenuPolicy.safeHTTPURL(url) else { return }
        saveCurrentTab()
        let tab = BrowserSessionTab(title: url.host ?? "새 탭", url: url)
        tabs.append(tab)
        selectedTabID = BrowserTabSelectionPolicy.selectedTabID(
            currentSelection: selectedTabID,
            newlyOpenedTabID: tab.id,
            opensInBackground: true
        )
        saveSession()
    }

    private func openLinkInNewWindow(_ url: URL) {
        guard ThreeFContextMenuWindowRoute.enqueue(url) else { return }
        openWindow(id: "browser")
    }

    private func fetchGoogleSuggestions(for query: String) {
        suggestionFetchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("://"),
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://suggestqueries.google.com/complete/search?client=firefox&q=\(encoded)") else {
            googleSuggestions = []
            return
        }
        suggestionFetchTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled,
                      let json = try JSONSerialization.jsonObject(with: data) as? [Any],
                      json.count > 1,
                      let items = json[1] as? [String] else { return }
                await MainActor.run {
                    googleSuggestions = Array(items.prefix(5))
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run { googleSuggestions = [] }
                }
            }
        }
    }

    private func submitAddressBar() {
        model.submit(model.addressText, authorize: authorizeNavigation)
    }

    private func navigateToQuickLink(_ link: BrowserQuickLink) {
        guard link.destination != nil else { return }
        model.openQuickLink(link, authorize: authorizeNavigation)
        guard model.isLoading else { return }
        webView?.window?.makeFirstResponder(nil)
    }

    private func installCurrentWebsiteAsApp() {
        guard installedWebApp == nil,
              let app = model.installCurrentWebsiteAsApp(title: webView?.title, url: webView?.url ?? model.currentURL) else { return }
        openWindow(value: app)
    }

    private func installQuickLinkAsApp(_ link: BrowserQuickLink) {
        guard !embedded, installedWebApp == nil,
              let app = model.installCurrentWebsiteAsApp(title: link.title, url: link.destination) else { return }
        openWindow(value: app)
    }

    private func openInstalledWebApp(_ app: InstalledWebApp) {
        guard app.isValid else { return }
        openWindow(value: app)
    }

    func installedApp(for link: BrowserQuickLink) -> InstalledWebApp? {
        guard let destination = link.destination else { return nil }
        return model.installedWebApps.first { $0.destination == destination }
    }

    private func pulseNavigationFeedback() {
        let requestID = model.navigationRequestID
        navigationFeedbackPulse = false
        DispatchQueue.main.async {
            guard model.navigationRequestID == requestID else { return }
            withAnimation(.easeOut(duration: 0.12)) { navigationFeedbackPulse = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
            guard model.navigationRequestID == requestID else { return }
            withAnimation(.easeInOut(duration: 0.18)) { navigationFeedbackPulse = false }
        }
    }

    private func selectTab(_ tab: BrowserSessionTab) {
        guard selectedTabID != tab.id else { return }
        saveCurrentTab()
        selectedTabID = tab.id
        mountedTabIDs.insert(tab.id)
        webView = tabWebViews[tab.id]
        canGoBack = false
        canGoForward = false
        if let url = tab.url {
            model.currentURL = url
            model.addressText = url.absoluteString
            model.isLoading = tabWebViews[tab.id]?.isLoading ?? false
        } else {
            model.showNewTab()
        }
        saveSession()
    }

    private func closeTab(_ tab: BrowserSessionTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        if tabs.count == 1 {
            closeCurrentWindow()
            return
        }
        let wasSelected = selectedTabID == tab.id
        tabs.remove(at: index)
        mountedTabIDs.remove(tab.id)
        tabWebViews.removeValue(forKey: tab.id)
        tabNavigationRequestIDs.removeValue(forKey: tab.id)
        guard wasSelected else { saveSession(); return }
        let replacement = tabs[min(index, tabs.count - 1)]
        selectedTabID = replacement.id
        mountedTabIDs.insert(replacement.id)
        webView = tabWebViews[replacement.id]
        canGoBack = false
        canGoForward = false
        if let url = replacement.url {
            model.currentURL = url
            model.addressText = url.absoluteString
            model.isLoading = tabWebViews[replacement.id]?.isLoading ?? false
        } else {
            model.showNewTab()
        }
        saveSession()
    }

    private func closeCurrentWindow() {
        guard !embedded, !isWindowClosing else { return }
        saveCurrentTab()
        isWindowClosing = true
        if !isAppTerminating, installedWebApp == nil {
            try? BrowserSessionStore.remove(windowID: sessionStorageWindowID, from: sessionStorageDirectory)
        }
        dismiss()
    }

    private func handleBrowserWindowWillClose(_ notification: Notification) {
        guard !embedded, installedWebApp == nil, !isWindowClosing,
              ThreeFBrowserWindowRouting.targets(notification.object as? NSWindow, window: webView?.window) else { return }
        saveCurrentTab()
        if !isAppTerminating {
            isWindowClosing = true
            try? BrowserSessionStore.remove(windowID: sessionStorageWindowID, from: sessionStorageDirectory)
        }
    }

    private func saveCurrentTab() {
        guard installedWebApp == nil, !isWindowClosing,
              let selectedTabID, let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        tabs[index].url = model.currentURL
        if let host = model.currentURL?.host { tabs[index].title = host }
        saveSession()
    }

    private func updateActiveTab(url: URL?, title: String?) {
        guard let selectedTabID, let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        tabs[index].url = url
        if aiMode, let url, AIModeNavigationPolicy.isOnlyChatLocalOrigin(url) {
            tabs[index].title = "Only Chat"
        } else {
            tabs[index].title = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? url?.host ?? "새 탭"
        }
        saveSession()
    }

    private func saveSession() {
        guard !embedded, installedWebApp == nil, !isWindowClosing else { return }
        try? BrowserSessionStore.save(
            BrowserSessionSnapshot(tabs: tabs, selectedTabID: selectedTabID),
            to: sessionStorageDirectory,
            windowID: sessionStorageWindowID
        )
    }

    private func initializeWindow() {
        if embedded {
            if let selectedTabID { mountedTabIDs.insert(selectedTabID) }
            return
        }
        guard !didRestoreSession else { return }
        didRestoreSession = true
        if let installedWebApp, let destination = installedWebApp.destination {
            if let selectedTabID {
                mountedTabIDs.insert(selectedTabID)
                tabNavigationRequestIDs[selectedTabID] = model.navigationRequestID + 1
            }
            model.navigate(to: destination, authorize: authorizeNavigation)
            return
        }
        let windowID = assignedWindowID ?? BrowserWindowSessionCoordinator.shared.claimWindowID(aiMode: aiMode)
        assignedWindowID = windowID
        let session = try? BrowserSessionStore.restoreWindow(windowID, in: sessionStorageDirectory)
        let extraWindowCount = BrowserWindowSessionCoordinator.shared.consumePendingRestoreSpawnCount(aiMode: aiMode)
        for _ in 0..<extraWindowCount {
            openWindow(id: aiMode ? "ai-mode" : "browser")
        }
        if !aiMode, BrowserWindowSessionCoordinator.shared.consumeShouldOpenInitialAIModeWindow() {
            openWindow(id: "ai-mode")
        }
        if !aiMode, let destination = ThreeFContextMenuWindowRoute.takeNext() {
            if let selectedTabID {
                mountedTabIDs.insert(selectedTabID)
                tabNavigationRequestIDs[selectedTabID] = model.navigationRequestID + 1
            }
            model.navigate(to: destination, authorize: authorizeNavigation)
            return
        }
        guard let session else {
            if let selectedTabID { mountedTabIDs.insert(selectedTabID) }
            if aiMode, let url = tabs.first?.url {
                if let selectedTabID { tabNavigationRequestIDs[selectedTabID] = model.navigationRequestID + 1 }
                model.navigate(to: url, authorize: authorizeNavigation)
            }
            return
        }
        tabs = session.tabs
        selectedTabID = session.selectedTabID ?? session.tabs.first?.id
        if let selectedTabID { mountedTabIDs.insert(selectedTabID) }
        if let selectedTabID,
           let restoredURL = tabs.first(where: { $0.id == selectedTabID })?.url {
            tabNavigationRequestIDs[selectedTabID] = model.navigationRequestID + 1
            model.navigate(to: restoredURL, authorize: authorizeNavigation)
        }
    }

    private var newTabPage: some View {
        ZStack {
            ThreeFPalette.canvas.ignoresSafeArea()
            Circle()
                .fill(model.theme.color.opacity(0.08))
                .frame(width: 420, height: 420)
                .offset(x: 520, y: -240)
                .accessibilityHidden(true)
            Circle()
                .fill(Color.white.opacity(0.55))
                .frame(width: 300, height: 300)
                .offset(x: -520, y: 260)
                .accessibilityHidden(true)

            GeometryReader { geometry in
                let compact = geometry.size.height < 430
                VStack(spacing: compact ? 14 : 24) {
                VStack(spacing: compact ? 6 : 12) {
                    Text("3F")
                        .font(.system(size: compact ? 42 : 56, weight: .heavy, design: .rounded))
                        .foregroundStyle(model.theme.color)
                    Text("나만의 방식으로, 웹을 시작하세요")
                        .font(.system(size: compact ? 19 : 25, weight: .bold))
                        .foregroundStyle(ThreeFPalette.ink)
                    Text("주소는 Enter를 누르면 이동하고, 바로가기는 한 번 클릭하면 곧바로 엽니다.")
                        .font(.system(size: compact ? 12 : 14))
                        .foregroundStyle(ThreeFPalette.muted)
                }

                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(ThreeFPalette.muted)
                    TextField("검색 또는 웹 주소 입력", text: $model.addressText, prompt: Text("검색 또는 웹 주소 입력").foregroundColor(ThreeFPalette.muted))
                        .textFieldStyle(.plain)
                        .foregroundStyle(ThreeFPalette.ink)
                        .tint(model.theme.color)
                        .font(.system(size: 15))
                        .onSubmit { submitAddressBar() }
                    Button { model.submit(model.addressText, authorize: authorizeNavigation) } label: {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(model.theme.color, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .help("검색")
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.leading, 16)
                .padding(.trailing, 8)
                .frame(height: compact ? 46 : 54)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(ThreeFPalette.border, lineWidth: 1))
                .shadow(color: ThreeFPalette.ink.opacity(0.08), radius: 16, y: 6)

                if !model.theme.quickLinks.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("바로가기")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ThreeFPalette.muted)
                        if compact {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(model.theme.quickLinks) { link in
                                        let matchingApp = installedApp(for: link)
                                        HStack(spacing: 4) {
                                            Button { navigateToQuickLink(link) } label: {
                                                Label(link.title, systemImage: "globe")
                                                    .font(.system(size: 11, weight: .medium))
                                                    .foregroundStyle(ThreeFPalette.ink)
                                                    .padding(.horizontal, 11)
                                                    .padding(.vertical, 8)
                                                    .background(ThreeFPalette.surface, in: Capsule())
                                                    .overlay(Capsule().stroke(ThreeFPalette.border, lineWidth: 1))
                                            }
                                            .buttonStyle(.plain)
                                            .help("\(link.title) · 주소를 입력하고 Enter를 누른 것처럼 바로 엽니다")
                                            .accessibilityLabel(link.title)
                                            .accessibilityHint("주소창에 입력 후 Enter를 누른 것처럼 바로 페이지를 엽니다.")
                                            .contextMenu {
                                                if !embedded {
                                                    if let app = matchingApp {
                                                        Button { openInstalledWebApp(app) } label: {
                                                            Label("\(link.title) 앱 창 열기", systemImage: "macwindow")
                                                        }
                                                    } else {
                                                        Button { installQuickLinkAsApp(link) } label: {
                                                            Label("\(link.title) 앱으로 설치", systemImage: "square.and.arrow.down")
                                                        }
                                                    }
                                                }
                                            }
                                            if !embedded && installedWebApp == nil {
                                                if let app = matchingApp {
                                                    Button { openInstalledWebApp(app) } label: {
                                                        Image(systemName: "macwindow")
                                                            .font(.system(size: 10, weight: .medium))
                                                            .foregroundStyle(model.theme.color)
                                                            .frame(width: 24, height: 24)
                                                    }
                                                    .buttonStyle(.plain)
                                                    .help("\(link.title) 앱 창 열기")
                                                    .accessibilityLabel("\(link.title) 앱 창 열기")
                                                } else {
                                                    Button { installQuickLinkAsApp(link) } label: {
                                                        Image(systemName: "square.and.arrow.down")
                                                            .font(.system(size: 10, weight: .medium))
                                                            .foregroundStyle(ThreeFPalette.muted)
                                                            .frame(width: 24, height: 24)
                                                    }
                                                    .buttonStyle(.plain)
                                                    .help("\(link.title) 앱으로 설치")
                                                    .accessibilityLabel("\(link.title) 앱으로 설치")
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 10)], spacing: 10) {
                                ForEach(model.theme.quickLinks) { link in
                                    let matchingApp = installedApp(for: link)
                                    VStack(alignment: .leading, spacing: 7) {
                                        Button { navigateToQuickLink(link) } label: {
                                            VStack(alignment: .leading, spacing: 7) {
                                                Image(systemName: "globe")
                                                    .font(.system(size: 15, weight: .semibold))
                                                    .foregroundStyle(model.theme.color)
                                                Text(link.title)
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundStyle(ThreeFPalette.ink)
                                                    .lineLimit(1)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .buttonStyle(.plain)
                                        .help("\(link.title) · 주소를 입력하고 Enter를 누른 것처럼 바로 엽니다")
                                        .accessibilityLabel(link.title)
                                        .accessibilityHint("주소창에 입력 후 Enter를 누른 것처럼 바로 페이지를 엽니다.")
                                        .contextMenu {
                                            if !embedded {
                                                if let app = matchingApp {
                                                    Button { openInstalledWebApp(app) } label: {
                                                        Label("\(link.title) 앱 창 열기", systemImage: "macwindow")
                                                    }
                                                } else {
                                                    Button { installQuickLinkAsApp(link) } label: {
                                                        Label("\(link.title) 앱으로 설치", systemImage: "square.and.arrow.down")
                                                    }
                                                }
                                            }
                                        }
                                        if !embedded && installedWebApp == nil {
                                            if let app = matchingApp {
                                                Button { openInstalledWebApp(app) } label: {
                                                    HStack(spacing: 4) {
                                                        Image(systemName: "macwindow")
                                                            .font(.system(size: 9, weight: .semibold))
                                                        Text("앱 열기")
                                                            .font(.system(size: 10, weight: .medium))
                                                    }
                                                    .foregroundStyle(model.theme.color)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 3)
                                                    .background(model.theme.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                                                }
                                                .buttonStyle(.plain)
                                                .help("\(link.title) 앱 창 열기")
                                                .accessibilityLabel("\(link.title) 앱 창 열기")
                                            } else {
                                                Button { installQuickLinkAsApp(link) } label: {
                                                    HStack(spacing: 4) {
                                                        Image(systemName: "square.and.arrow.down")
                                                            .font(.system(size: 9, weight: .medium))
                                                        Text("앱 설치")
                                                            .font(.system(size: 10, weight: .medium))
                                                    }
                                                    .foregroundStyle(ThreeFPalette.muted)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 3)
                                                    .background(ThreeFPalette.border.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                                                }
                                                .buttonStyle(.plain)
                                                .help("\(link.title) 앱으로 설치")
                                                .accessibilityLabel("\(link.title) 앱으로 설치")
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(ThreeFPalette.surface, in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(ThreeFPalette.border.opacity(0.8)))
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 540, alignment: .leading)
                }

                Text("검색 엔진  ·  \(model.searchProvider.title)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ThreeFPalette.muted)
            }
                .frame(maxWidth: 540)
                .padding(compact ? 18 : 36)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var quickLinksBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.theme.quickLinks) { link in
                    let matchingApp = installedApp(for: link)
                    HStack(spacing: 4) {
                    Button { navigateToQuickLink(link) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "globe")
                                .font(.system(size: 10, weight: .semibold))
                            Text(link.title)
                                .lineLimit(1)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ThreeFPalette.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(ThreeFPalette.surface, in: Capsule())
                        .overlay(Capsule().stroke(ThreeFPalette.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("\(link.title) · 주소를 입력하고 Enter를 누른 것처럼 바로 엽니다")
                    .accessibilityLabel(link.title)
                    .accessibilityHint("주소창에 입력 후 Enter를 누른 것처럼 바로 페이지를 엽니다.")
                    .contextMenu {
                        if !embedded {
                            if let app = matchingApp {
                                Button { openInstalledWebApp(app) } label: {
                                    Label("\(link.title) 앱 창 열기", systemImage: "macwindow")
                                }
                            } else {
                                Button { installQuickLinkAsApp(link) } label: {
                                    Label("\(link.title) 앱으로 설치", systemImage: "square.and.arrow.down")
                                }
                            }
                        }
                    }
                    if !embedded && installedWebApp == nil {
                        if let app = matchingApp {
                            Button { openInstalledWebApp(app) } label: {
                                Image(systemName: "macwindow")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(model.theme.color)
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .help("\(link.title) 앱 창 열기")
                            .accessibilityLabel("\(link.title) 앱 창 열기")
                        } else {
                            Button { installQuickLinkAsApp(link) } label: {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(ThreeFPalette.muted)
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .help("\(link.title) 앱으로 설치")
                            .accessibilityLabel("\(link.title) 앱으로 설치")
                        }
                    }
                    }
                }
                ForEach(model.installedWebApps) { app in
                    Button { openInstalledWebApp(app) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "macwindow").font(.system(size: 10, weight: .semibold))
                            Text(app.title).lineLimit(1)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ThreeFPalette.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(ThreeFPalette.surface, in: Capsule())
                        .overlay(Capsule().stroke(ThreeFPalette.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("\(app.title) 앱 창 열기")
                    .contextMenu {
                        Button("설치한 앱에서 제거", role: .destructive) { model.removeInstalledWebApp(app) }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 9)
    }

    private var youtubePolicyStatus: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            YouTubeUsageDashboardView(
                summary: model.youtubeUsageSummary,
                unavailable: model.youtubeUsageUnavailable,
                playbackReason: model.youtubePlaybackReason,
                isShorts: model.isYouTubeShortsContext,
                now: context.date
            )
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if model.isLoading {
                ProgressView().controlSize(.mini)
                Text("페이지 여는 중 · \(model.currentURL?.host ?? "주소")").lineLimit(1)
            } else {
                Circle()
                    .fill(model.currentURL == nil ? ThreeFPalette.muted.opacity(0.45) : model.theme.color)
                    .frame(width: 6, height: 6)
                Text(model.currentURL?.host ?? "새 탭").lineLimit(1)
            }
            if model.shouldShowYouTubeUsage {
                Label(model.youtubeUsageStatusLabel, systemImage: "clock")
                    .lineLimit(1)
                    .help(model.youtubeUsageDetail)
                    .accessibilityLabel("YouTube 사용량 · \(model.youtubeUsageDetail)")
            }
            Spacer()
            Text("WebKit")
            Text("·")
            Text("Chrome 확장 미지원")
            if let downloadStatus = model.downloadStatus {
                Text("·")
                Text(downloadStatus).lineLimit(1)
            }
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(ThreeFPalette.muted)
        .padding(.horizontal, 16)
        .frame(height: 25)
        .background(ThreeFPalette.surface.opacity(0.8))
        .overlay(alignment: .top) { Rectangle().fill(ThreeFPalette.border.opacity(0.65)).frame(height: 1) }
    }

    private func chromeButton(
        _ symbol: String,
        help: String,
        disabled: Bool = false,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(prominent ? model.theme.color : ThreeFPalette.muted)
                .frame(width: 34, height: 34)
                .background(prominent ? ThreeFPalette.surface : .clear, in: Circle())
                .overlay(Circle().stroke(prominent ? ThreeFPalette.border : .clear, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.42 : 1)
        .help(help)
        .accessibilityLabel(help)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private enum ThreeFPalette {
    static let canvas = Color(red: 0.957, green: 0.941, blue: 0.980) // #F4F0FA
    static let surface = Color(red: 1.000, green: 0.976, blue: 0.988) // #FFF9FC
    static let raised = Color.white
    static let ink = Color(red: 0.125, green: 0.090, blue: 0.173) // #20172C
    static let muted = Color(red: 0.467, green: 0.439, blue: 0.510) // #777082
    static let border = Color(red: 0.851, green: 0.816, blue: 0.898) // #D9D0E5
}

private struct WildcardBlockSheet: View {
    let currentURL: URL?
    let onSaved: (_ pattern: String, _ hideTitle: Bool, _ blockUrl: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var patternText = ""
    @State private var hideTitleInSearch = true
    @State private var blockUrlContains = true
    @State private var focusFenceConnected: Bool?

    private var normalizedPattern: String {
        patternText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var canConfirm: Bool {
        normalizedPattern.count >= 2 && (hideTitleInSearch || blockUrlContains)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("와일드카드 차단하기")
                .font(.title3.bold())

            if let currentURL {
                Text("현재 URL: \(currentURL.absoluteString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            TextField("차단할 URL 일부 또는 키워드 (예: yandong, stripchat)", text: $patternText)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("1. 제목(Title)에 포함 시 검색 결과에서 숨기기", isOn: $hideTitleInSearch)
                    .toggleStyle(.checkbox)
                Toggle("2. URL에 포함 시 차단", isOn: $blockUrlContains)
                    .toggleStyle(.checkbox)
            }

            if !(hideTitleInSearch || blockUrlContains) {
                Text("최소 1개 이상 옵션을 선택해 주세요.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            HStack(spacing: 6) {
                Circle()
                    .fill(focusFenceConnected == true ? Color.green : Color.secondary.opacity(0.6))
                    .frame(width: 7, height: 7)
                Text(
                    focusFenceConnected == true
                        ? "Focus Fence(FF) 자동 연동됨 · 별도 로그인 없이 Detox/BlueCloud와 자동 공유"
                        : "Focus Fence(FF) 연결 확인 중 · 로컬 저장 후 FF 실행 시 자동 동기화"
                )
                .font(.caption)
                .foregroundStyle(focusFenceConnected == true ? .green : .secondary)
            }
            .task {
                focusFenceConnected = await WildcardBlockStore.shared.checkFocusFenceConnection()
            }

            HStack {
                Spacer()
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("확인") {
                    guard canConfirm else { return }
                    let p = normalizedPattern
                    _ = WildcardBlockStore.shared.addRule(
                        pattern: p,
                        hideTitle: hideTitleInSearch,
                        blockUrl: blockUrlContains
                    )
                    onSaved(p, hideTitleInSearch, blockUrlContains)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canConfirm)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
