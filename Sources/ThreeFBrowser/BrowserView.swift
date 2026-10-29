import SwiftUI
import WebKit

struct BrowserView: View {
    @StateObject private var model = BrowserModel()
    @State private var webView: WKWebView?
    @State private var canGoBack = false
    @State private var canGoForward = false

    var body: some View {
        VStack(spacing: 0) {
            addressBar
            ZStack {
                BrowserWebView(
                    url: $model.currentURL,
                    requestID: $model.navigationRequestID,
                    webView: $webView,
                    onNavigation: { model.pageDidNavigate(to: $0) },
                    onNavigationState: { canGoBack = $0; canGoForward = $1 }
                )
                .opacity(model.currentURL == nil ? 0 : 1)
                .allowsHitTesting(model.currentURL != nil)

                if model.currentURL == nil {
                    newTabPage
                }
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .sheet(isPresented: $model.isShowingSettings) {
            BrowserSettingsView(model: model)
        }
        .onOpenURL { model.openExternalURL($0) }
    }

    private var addressBar: some View {
        HStack(spacing: 10) {
            Button { webView?.goBack() } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!canGoBack || model.currentURL == nil)
            .help("뒤로")

            Button { webView?.goForward() } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!canGoForward || model.currentURL == nil)
            .help("앞으로")

            Button {
                if model.currentURL == nil {
                    model.submit(model.addressText)
                } else {
                    webView?.reload()
                }
            } label: {
                Image(systemName: model.currentURL == nil ? "magnifyingglass" : "arrow.clockwise")
            }
            .help(model.currentURL == nil ? "검색" : "새로고침")

            TextField("검색 또는 주소 입력", text: $model.addressText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.submit(model.addressText) }

            Button { model.showNewTab() } label: {
                Image(systemName: "plus")
            }
            .help("새 탭")

            Button { model.isShowingSettings = true } label: {
                Image(systemName: "gearshape")
            }
            .help("설정")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var newTabPage: some View {
        VStack(spacing: 18) {
            Text("3F")
                .font(.system(size: 54, weight: .bold, design: .rounded))
                .foregroundStyle(.tint)
            Text("검색 또는 웹 주소를 입력하세요")
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("검색어 또는 주소", text: $model.addressText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.submit(model.addressText) }
                Button("검색") { model.submit(model.addressText) }
                    .keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: 520)
            Text("검색 엔진: \(model.searchProvider.title)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
