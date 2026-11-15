import SwiftUI
import UniformTypeIdentifiers
import AppKit
import WebKit

private enum SettingsPalette {
    static let canvas = Color(red: 0.957, green: 0.941, blue: 0.980)
    static let raised = Color(red: 1.000, green: 0.976, blue: 0.988)
    static let border = Color(red: 0.886, green: 0.863, blue: 0.925)
    static let ink = Color(red: 0.153, green: 0.133, blue: 0.196)
    static let muted = Color(red: 0.455, green: 0.427, blue: 0.510)
}

private enum SettingsPage: String, CaseIterable, Identifiable {
    case general = "일반"
    case privacy = "개인정보"
    case system = "시스템"
    case diagnostics = "진단"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .privacy: "hand.raised"
        case .system: "gearshape.2"
        case .diagnostics: "ladybug"
        }
    }
}

struct BrowserSettingsView: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject private var oauthDiagnostics = GoogleOAuthHandoffDiagnostics.shared
    @StateObject private var focusFence = FocusFenceConnectionService()
    @StateObject private var defaultBrowser = DefaultBrowserService()
    @State private var selectedPage: SettingsPage = .general
    @State private var isConfirmingWebsiteDataClear = false
    @State private var isClearingWebsiteData = false
    @State private var websiteDataClearStatus: String?
    @State private var bookmarkTransferStatus: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                sidebar
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        pageTitle
                        pageContent
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .frame(width: 760, height: 580)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(model.theme.color)
        .confirmationDialog(
            "모든 사이트 데이터와 방문 기록을 지울까요?",
            isPresented: $isConfirmingWebsiteDataClear,
            titleVisibility: .visible
        ) {
            Button("사이트 데이터와 방문 기록 지우기", role: .destructive) {
                clearWebsiteData()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("쿠키, 캐시, 사이트 저장 공간과 3F 방문 기록이 삭제됩니다. 사이트에서 로그아웃될 수 있습니다. 북마크와 다운로드 파일은 유지됩니다.")
        }
        .task {
            await focusFence.refresh()
            defaultBrowser.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(model.theme.color)
                .frame(width: 34, height: 34)
                .background(model.theme.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text("설정").font(.system(size: 15, weight: .semibold))
                Text("3F Browser 환경을 관리합니다")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("완료") { model.isShowingSettings = false }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(SettingsPage.allCases) { page in
                settingsNavigationButton(page)
                .buttonStyle(.plain)
            }
            Spacer()
            Text("3F BROWSER")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.tertiary)
                .padding(.leading, 11)
                .padding(.bottom, 6)
        }
        .padding(14)
        .frame(width: 178, alignment: .leading)
        .background(SettingsPalette.canvas)
    }

    private func settingsNavigationButton(_ page: SettingsPage) -> some View {
        let foreground = selectedPage == page ? SettingsPalette.ink : SettingsPalette.muted
        let background = selectedPage == page ? model.theme.color.opacity(0.13) : Color.clear
        return Button { selectedPage = page } label: {
            HStack(spacing: 10) {
                Image(systemName: page.symbol).font(.system(size: 13, weight: .medium)).frame(width: 20)
                Text(page.rawValue).font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background(background, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private var pageTitle: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(selectedPage.rawValue)
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundStyle(SettingsPalette.ink)
            Text(pageDescription)
                .font(.system(size: 12))
                .foregroundStyle(SettingsPalette.muted)
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch selectedPage {
        case .general:
            generalPage
        case .privacy:
            privacyPage
        case .system:
            systemPage
        case .diagnostics:
            diagnosticsPage
        }
    }

    private var pageDescription: String {
        switch selectedPage {
        case .general: "검색과 자주 사용하는 사이트를 설정합니다."
        case .privacy: "브라우저 기록과 집중 차단 연결 상태를 관리합니다."
        case .system: "브라우저 엔진 및 업데이트 상태를 확인합니다."
        case .diagnostics: "3F 브라우저 오류와 재생 불가 미디어 기록을 확인합니다. 주소와 계정 정보는 저장하지 않습니다."
        }
    }

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsCard(title: "기본 브라우저", subtitle: "웹 링크를 3F Browser에서 엽니다") {
                VStack(alignment: .trailing, spacing: 9) {
                    Text(defaultBrowser.status)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                    Button("3F를 기본 브라우저로 설정") {
                        defaultBrowser.setAsDefaultBrowser()
                    }
                    .disabled(defaultBrowser.isApplying)
                }
            }
            settingsCard(title: "검색", subtitle: "주소창과 새 탭에서 사용할 검색 엔진") {
                Picker("검색 엔진", selection: $model.searchProvider) {
                    ForEach(SearchProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 190, alignment: .trailing)
            }
            settingsCard(title: "북마크", subtitle: "저장한 사이트에 빠르게 이동") {
                HStack {
                    Button("HTML에서 가져오기", action: importBookmarks)
                    Button("HTML로 내보내기", action: exportBookmarks)
                    Spacer()
                }
                .controlSize(.small)
                if let bookmarkTransferStatus {
                    Text(bookmarkTransferStatus)
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if model.bookmarks.isEmpty {
                    emptyState("star", "저장된 북마크가 없습니다.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(model.bookmarks.enumerated()), id: \.element.id) { index, bookmark in
                            HStack(spacing: 12) {
                                Image(systemName: "globe")
                                    .foregroundStyle(model.theme.color)
                                    .frame(width: 28, height: 28)
                                    .background(model.theme.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(bookmark.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    Text(bookmark.url).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                Button("열기") {
                                    if let url = bookmark.destination { model.navigate(to: url) }
                                    model.isShowingSettings = false
                                }
                                .controlSize(.small)
                                Button {
                                    model.removeBookmark(bookmark)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                                .help("북마크 삭제")
                            }
                            .padding(.vertical, 9)
                            if index < model.bookmarks.count - 1 { Divider() }
                        }
                    }
                }
            }
            themeCard
        }
    }

    private func importBookmarks() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.html]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? Int.max
            guard fileSize <= BookmarkHTML.maximumFileSize else {
                bookmarkTransferStatus = "파일이 너무 큽니다. 5MB 이하의 북마크 HTML을 선택해 주세요."
                return
            }
            let imported = BookmarkHTML.import(try Data(contentsOf: url))
            let added = model.importBookmarks(imported)
            bookmarkTransferStatus = "HTTPS 북마크 \(added)개를 가져왔습니다. 폴더 구조는 평면 목록으로 합쳐집니다."
        } catch {
            bookmarkTransferStatus = "가져오지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func exportBookmarks() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "3F-Bookmarks.html"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try BookmarkHTML.export(model.bookmarks).write(to: url, options: .atomic)
            bookmarkTransferStatus = "북마크 \(model.bookmarks.count)개를 HTML로 내보냈습니다."
        } catch {
            bookmarkTransferStatus = "내보내지 못했습니다: \(error.localizedDescription)"
        }
    }

    private var privacyPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsCard(title: "방문 기록", subtitle: "최근 방문한 페이지 최대 100개") {
                if model.history.isEmpty {
                    emptyState("clock", "방문 기록이 없습니다.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(model.history.enumerated()), id: \.element.id) { index, entry in
                            Button {
                                if let url = URL(string: entry.url) { model.navigate(to: url) }
                                model.isShowingSettings = false
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .foregroundStyle(SettingsPalette.muted)
                                        .frame(width: 28, height: 28)
                                        .background(SettingsPalette.canvas, in: RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(entry.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                        Text(entry.url).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 4)
                                    Text(entry.visitedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 9)).foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                                .padding(.vertical, 9)
                            }
                            .buttonStyle(.plain)
                            if index < model.history.count - 1 { Divider() }
                        }
                    }
                    Divider().padding(.top, 4)
                    HStack {
                        Text("이 기기에 저장된 방문 기록입니다.")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        Spacer()
                        Button("기록 지우기", role: .destructive, action: model.clearHistory)
                            .controlSize(.small)
                    }
                    .padding(.top, 10)
                }
            }
            settingsCard(title: "사이트 데이터", subtitle: "모든 기간의 사이트 쿠키, 캐시, 저장 공간을 삭제") {
                Text("사이트 데이터와 3F 방문 기록을 함께 지웁니다. 로그인 상태가 초기화될 수 있습니다.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                HStack {
                    if let websiteDataClearStatus {
                        Text(websiteDataClearStatus)
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(isClearingWebsiteData ? "삭제 중…" : "사이트 데이터 지우기", role: .destructive) {
                        isConfirmingWebsiteDataClear = true
                    }
                    .disabled(isClearingWebsiteData)
                    .controlSize(.small)
                }
            }
            settingsCard(title: "Focus Fence", subtitle: "집중 중 방해 사이트 차단 연결") {
                featureStatus("사이트 차단 규칙 적용", enabled: OptionalFeatureAvailability.focusFenceEnforcement)
                featureStatus("YouTube 시청 시간 집계", enabled: OptionalFeatureAvailability.youtubeUsageReporting)
                featureStatus("YouTube 미리보기 재생 차단", enabled: OptionalFeatureAvailability.youtubePreviewBlocking)
                Text("꺼진 기능은 브라우저 사용을 막지 않습니다. 연결 검증과 동작 확인 후 코드 업데이트로 활성화할 예정입니다.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    statusRow("브라우저 인식", value: focusFence.recognitionStatus, symbol: "macwindow")
                    Divider()
                    statusRow("차단 규칙", value: focusFence.rulesStatus, symbol: "list.bullet.rectangle")
                    Divider()
                    statusRow("네트워크 필터", value: focusFence.filterStatus, symbol: "network")
                }
                HStack(alignment: .top) {
                    Text(focusFence.detail).font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Button("새로고침") { Task { await focusFence.refresh() } }
                        .controlSize(.small)
                }
                .padding(.top, 10)
            }
        }
    }

    private func clearWebsiteData() {
        isClearingWebsiteData = true
        websiteDataClearStatus = nil
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) {
            model.clearHistory()
            isClearingWebsiteData = false
            websiteDataClearStatus = "사이트 데이터와 방문 기록을 지웠습니다."
        }
    }

    private var systemPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsCard(title: "브라우저 엔진", subtitle: "현재 웹 페이지를 표시하는 기반 기술") {
                VStack(spacing: 0) {
                    statusRow("엔진", value: ExtensionCompatibility.currentEngine.rawValue, symbol: "globe")
                    Divider()
                    statusRow("확장 지원", value: ExtensionCompatibility.supportLevel.rawValue, symbol: "puzzlepiece.extension")
                    Divider()
                    Text(ExtensionCompatibility.status)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
                    ForEach(BrowserPolicyPlugin.allCases) { plugin in
                        Divider()
                        statusRow("Focus Fence 플러그인", value: plugin.status, symbol: "puzzlepiece.extension")
                    }
                    Text(ExtensionCompatibility.limitation + " " + ExtensionCompatibility.chromiumProfileRequirement)
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            themeCard
        }
    }

    private var diagnosticsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsCard(title: "실시간 브라우저 상태", subtitle: "현재 호스트와 정책 연결 상태를 표시합니다. 전체 URL이나 페이지 내용은 로그에 저장하지 않습니다.") {
                VStack(spacing: 0) {
                    statusRow("엔진", value: ExtensionCompatibility.currentEngine.rawValue, symbol: "globe")
                    Divider()
                    statusRow("현재 호스트", value: model.currentURL?.host ?? "열린 페이지 없음", symbol: "link")
                    Divider()
                    statusRow("페이지 상태", value: model.isLoading ? "불러오는 중" : model.currentURL == nil ? "새 탭" : "대기 중", symbol: model.isLoading ? "arrow.clockwise" : "checkmark.circle")
                    Divider()
                    statusRow("Focus Fence 인식", value: focusFence.recognitionStatus, symbol: "macwindow")
                    Divider()
                    statusRow("차단 규칙", value: focusFence.rulesStatus, symbol: "list.bullet.rectangle")
                    Divider()
                    statusRow("네트워크 필터", value: focusFence.filterStatus, symbol: "network")
                    if let challenge = oauthDiagnostics.events.first(where: {
                        $0.outcome == .cloudflareChallengeAllowed || $0.outcome == .cloudflareChallengeRejected
                    }) {
                        Divider()
                        statusRow("최근 Cloudflare 프레임", value: challenge.outcome.rawValue, symbol: "checkmark.shield")
                    }
                    if let response = oauthDiagnostics.events.first(where: { $0.outcome == .httpResponse }) {
                        Divider()
                        statusRow("최근 HTTP 응답", value: response.detail ?? response.outcome.rawValue, symbol: "network")
                    }
                    if let failure = oauthDiagnostics.events.first(where: { $0.outcome == .navigationFailed }) {
                        Divider()
                        statusRow("최근 이동 오류", value: failure.detail ?? failure.outcome.rawValue, symbol: "exclamationmark.triangle")
                    }
                }
                HStack {
                    Text("\(ProcessInfo.processInfo.operatingSystemVersionString) · 3F \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "버전 미상")")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Focus Fence 상태 새로 확인") { Task { await focusFence.refresh() } }
                        .controlSize(.small)
                }
                .padding(.top, 8)
            }

            settingsCard(title: "상세 이벤트 로그", subtitle: "최근 100건 · 로컬에 자동 저장 · URL, 쿼리, 계정, 쿠키, 토큰, 페이지 내용은 기록하지 않습니다") {
                HStack {
                    Text("\(oauthDiagnostics.events.count)건 · \(oauthDiagnostics.saveStatus)")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button("로그 폴더") { oauthDiagnostics.openLogFolder() }
                        .controlSize(.small)
                    Button("로그 지우기") { oauthDiagnostics.clear() }
                        .controlSize(.small)
                        .disabled(oauthDiagnostics.events.isEmpty)
                }
                if oauthDiagnostics.events.isEmpty {
                    emptyState("ladybug", "아직 브라우저 진단 이벤트가 없습니다.")
                } else {
                    ForEach(oauthDiagnostics.events) { event in
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(event.date.formatted(date: .abbreviated, time: .standard))
                                Text("이벤트 ID · \(event.id.uuidString)")
                                Text("상세 · \(event.detail ?? "추가 정보 없음")")
                            }
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 5)
                        } label: {
                            HStack(spacing: 10) {
                                Text(event.date, style: .time)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(event.outcome.rawValue)
                                    .font(.system(size: 11, weight: .medium))
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
    }

    private var themeCard: some View {
        settingsCard(title: "새 탭 테마", subtitle: "색상과 빠른 링크 설정을 앱 재빌드 없이 반영") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(model.theme.color)
                    Text("데이터 전용 핫 업데이트")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text("JSON")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(SettingsPalette.canvas, in: Capsule())
                }
                Text("파일 무결성을 확인하고 이전 설정으로 되돌릴 수 있습니다. 코드, 네이티브 기능, 엔진 변경에는 앱 업데이트가 필요합니다.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Text(model.themeModuleStatus)
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("JSON 불러오기") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.json]
                        panel.allowsMultipleSelection = false
                        panel.canChooseDirectories = false
                        if panel.runModal() == .OK, let url = panel.url {
                            model.importThemeModule(from: url)
                        }
                    }
                    Button("이전 설정 복원", action: model.rollbackThemeModule)
                    Button("다시 읽기", action: model.reloadThemeModule)
                }
                .controlSize(.small)
                Text(##"예: {"accentHex":"#22AAFF","quickLinks":[{"title":"문서","url":"https://example.com/docs"}]}"##)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }
    }

    private func settingsCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(SettingsPalette.ink)
                Text(subtitle).font(.system(size: 10)).foregroundStyle(SettingsPalette.muted)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsPalette.raised, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(SettingsPalette.border, lineWidth: 1))
    }

    private func statusRow(_ title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(SettingsPalette.muted).frame(width: 16)
            Text(title).font(.system(size: 11)).foregroundStyle(SettingsPalette.ink)
            Spacer()
            Text(value).font(.system(size: 10, weight: .medium)).foregroundStyle(SettingsPalette.muted)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 9)
    }

    private func featureStatus(_ title: String, enabled: Bool) -> some View {
        HStack {
            Text(title).font(.system(size: 11)).foregroundStyle(SettingsPalette.ink)
            Spacer()
            Text(enabled ? "사용 가능" : "비활성 · TODO")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(enabled ? .green : .orange)
        }
        .padding(.vertical, 4)
    }

    private func emptyState(_ symbol: String, _ message: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).foregroundStyle(SettingsPalette.muted)
            Text(message).font(.system(size: 11)).foregroundStyle(SettingsPalette.muted)
            Spacer()
        }
        .padding(.vertical, 8)
    }
}
