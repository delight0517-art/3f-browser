import SwiftUI
import WebKit
import AppKit

struct BrowserView: View {
    @StateObject private var model: BrowserModel
    @EnvironmentObject private var externalURLs: ThreeFURLRouter
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var webView: WKWebView?
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var tabs: [BrowserSessionTab]
    @State private var selectedTabID: UUID?
    @State private var navigationFeedbackPulse = false
    @SceneStorage("threef.browser.session-window-id") private var sessionWindowID = UUID().uuidString
    @State private var didRestoreSession = false
    @State private var isWindowClosing = false
    @State private var isAppTerminating = false
    private let embedded: Bool
    private let authorizeNavigation: ((URL, @escaping (BrowserNavigationAuthorizationDecision) -> Void) -> Void)?
    private let onWebView: ((BrowserModel, WKWebView) -> Void)?
    private let onPageStateChange: ((URL?) -> Void)?
    private let onBlockedNavigation: ((URL) -> Void)?

    init(
        embedded: Bool = false,
        authorizeNavigation: ((URL, @escaping (BrowserNavigationAuthorizationDecision) -> Void) -> Void)? = nil,
        onWebView: ((BrowserModel, WKWebView) -> Void)? = nil,
        onPageStateChange: ((URL?) -> Void)? = nil,
        onBlockedNavigation: ((URL) -> Void)? = nil
    ) {
        self.embedded = embedded
        self.authorizeNavigation = authorizeNavigation
        self.onWebView = onWebView
        self.onPageStateChange = onPageStateChange
        self.onBlockedNavigation = onBlockedNavigation
        _model = StateObject(wrappedValue: BrowserModel())
        let initialTab = BrowserSessionTab(title: "새 탭")
        _tabs = State(initialValue: [initialTab])
        _selectedTabID = State(initialValue: initialTab.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            if embedded {
                tabStrip
            } else {
                VStack(spacing: 0) {
                    tabStrip
                    addressBar
                    if !model.theme.quickLinks.isEmpty { quickLinksBar }
                }
                .background(ThreeFPalette.canvas)
            }
            browserContent
            if !embedded { statusBar }
        }
        .padding(.top, embedded ? 0 : 28)
        .frame(minWidth: embedded ? 280 : 760, minHeight: embedded ? 220 : 520)
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
        .onAppear(perform: consumeExternalURLs)
        .onAppear(perform: initializeWindow)
        .onChange(of: model.currentURL) { _, url in
            updateActiveTab(url: url, title: url?.host)
            onPageStateChange?(url)
        }
        .onChange(of: model.navigationRequestID) { _, _ in
            pulseNavigationFeedback()
        }
        .onChange(of: webView) { _, _ in
            attachWebViewIfActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard ThreeFBrowserWindowRouting.targets(notification.object as? NSWindow, window: webView?.window) else { return }
            try? BrowserSessionStore.markWindowActive(sessionWindowID)
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
            guard !embedded, model.isYouTubePage else {
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
            BrowserWebView(
                url: $model.currentURL,
                requestID: $model.navigationRequestID,
                webView: $webView,
                authorizeNavigation: authorizeNavigation,
                onRejectedNavigation: { url, decision in
                    model.pageDidRejectNavigation(decision)
                    onBlockedNavigation?(url)
                },
                allowsDownloads: !embedded,
                onDownloadStatus: { model.downloadStatus = $0 },
                onWindowAttached: { attachedView in
                    let viewWindow = attachedView.window
                    let keyWindow = NSApp.keyWindow
                    guard ThreeFBrowserWindowRouting.targets(viewWindow, window: keyWindow) else { return }
                    onWebView?(model, attachedView)
                },
                onNavigationStarted: { model.pageDidStartNavigation(to: $0) },
                onLoadingChanged: { model.isLoading = $0 },
                onNavigationFailed: { model.pageDidFailToNavigate($0) },
                onOpenLinkInNewTab: addTab(for:),
                onOpenBackgroundTab: addBackgroundTab(for:),
                onOpenLinkInNewWindow: openLinkInNewWindow,
                onNavigation: { url, title in
                    model.pageDidNavigate(to: url, title: title)
                    updateActiveTab(url: url, title: title)
                },
                onNavigationState: { canGoBack = $0; canGoForward = $1 }
            )
            .opacity(model.currentURL == nil ? 0 : 1)
            .allowsHitTesting(model.currentURL != nil)

            if model.currentURL == nil { newTabPage }
        }
    }

    private func consumeExternalURLs() {
        externalURLs.takePendingURLs().forEach { model.openExternalURL($0, authorize: authorizeNavigation) }
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
                if model.currentURL == nil { model.submit(model.addressText, authorize: authorizeNavigation) }
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
                TextField("검색 또는 웹 주소 입력", text: $model.addressText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .onSubmit { model.submit(model.addressText, authorize: authorizeNavigation) }
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
            .shadow(color: ThreeFPalette.ink.opacity(0.04), radius: 3, y: 1)
            .animation(.easeInOut(duration: 0.18), value: model.isLoading)
            .animation(.easeInOut(duration: 0.14), value: navigationFeedbackPulse)
            if let notice = model.addressBlockNotice {
                Text(notice).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(1)
            }

            chromeButton("plus", help: "새 탭", prominent: true) { addTab() }
            chromeButton("star", help: "북마크 추가", disabled: model.currentURL == nil) {
                model.addBookmarkForCurrentPage()
            }
            chromeButton("gearshape", help: "설정") { model.isShowingSettings = true }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
        let tab = BrowserSessionTab(title: "새 탭")
        tabs.append(tab)
        selectedTabID = tab.id
        model.showNewTab()
        canGoBack = false
        canGoForward = false
        saveSession()
    }

    private func addTab(for url: URL) {
        guard let url = ThreeFContextMenuPolicy.safeHTTPURL(url) else { return }
        saveCurrentTab()
        let tab = BrowserSessionTab(title: url.host ?? "새 탭", url: url)
        tabs.append(tab)
        selectedTabID = BrowserTabSelectionPolicy.selectedTabID(
            currentSelection: selectedTabID,
            newlyOpenedTabID: tab.id,
            opensInBackground: false
        )
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
        canGoBack = false
        canGoForward = false
        if let url = tab.url { model.navigate(to: url, authorize: authorizeNavigation) }
        else { model.showNewTab() }
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
        guard wasSelected else { saveSession(); return }
        let replacement = tabs[min(index, tabs.count - 1)]
        selectedTabID = replacement.id
        canGoBack = false
        canGoForward = false
        if let url = replacement.url { model.navigate(to: url, authorize: authorizeNavigation) }
        else { model.showNewTab() }
        saveSession()
    }

    private func closeCurrentWindow() {
        guard !embedded, !isWindowClosing else { return }
        isWindowClosing = true
        try? BrowserSessionStore.remove(windowID: sessionWindowID)
        dismiss()
    }

    private func handleBrowserWindowWillClose(_ notification: Notification) {
        guard !embedded, !isWindowClosing,
              ThreeFBrowserWindowRouting.targets(notification.object as? NSWindow, window: webView?.window) else { return }
        if isAppTerminating {
            saveCurrentTab()
            return
        }
        isWindowClosing = true
        try? BrowserSessionStore.remove(windowID: sessionWindowID)
    }

    private func saveCurrentTab() {
        guard !isWindowClosing,
              let selectedTabID, let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        tabs[index].url = model.currentURL
        if let host = model.currentURL?.host { tabs[index].title = host }
        saveSession()
    }

    private func updateActiveTab(url: URL?, title: String?) {
        guard let selectedTabID, let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        tabs[index].url = url
        tabs[index].title = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? url?.host ?? "새 탭"
        saveSession()
    }

    private func saveSession() {
        guard !embedded, !isWindowClosing else { return }
        try? BrowserSessionStore.save(BrowserSessionSnapshot(tabs: tabs, selectedTabID: selectedTabID), windowID: sessionWindowID)
    }

    private func initializeWindow() {
        guard !embedded, !didRestoreSession else { return }
        didRestoreSession = true
        let session = try? BrowserSessionStore.restoreWindow(sessionWindowID)
        if let destination = ThreeFContextMenuWindowRoute.takeNext() {
            model.navigate(to: destination, authorize: authorizeNavigation)
            return
        }
        guard let session else { return }
        tabs = session.tabs
        selectedTabID = session.selectedTabID ?? session.tabs.first?.id
        if let selectedTabID,
           let restoredURL = tabs.first(where: { $0.id == selectedTabID })?.url {
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
                    TextField("검색 또는 웹 주소 입력", text: $model.addressText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .onSubmit { model.submit(model.addressText, authorize: authorizeNavigation) }
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
                                        Button { model.openQuickLink(link, authorize: authorizeNavigation) } label: {
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
                                    }
                                }
                            }
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 10)], spacing: 10) {
                                ForEach(model.theme.quickLinks) { link in
                                    Button { model.openQuickLink(link, authorize: authorizeNavigation) } label: {
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
                                        .padding(12)
                                        .background(ThreeFPalette.surface, in: RoundedRectangle(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ThreeFPalette.border.opacity(0.8)))
                                    }
                                    .buttonStyle(.plain)
                                    .help("\(link.title) · 주소를 입력하고 Enter를 누른 것처럼 바로 엽니다")
                                    .accessibilityLabel(link.title)
                                    .accessibilityHint("주소창에 입력 후 Enter를 누른 것처럼 바로 페이지를 엽니다.")
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
        HStack(spacing: 8) {
            ForEach(model.theme.quickLinks) { link in
                Button { model.openQuickLink(link, authorize: authorizeNavigation) } label: {
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
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 9)
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
            if model.isYouTubePage {
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
