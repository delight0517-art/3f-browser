import SwiftUI
import WebKit

struct BrowserWebView: NSViewRepresentable {
    @Binding var url: URL?
    @Binding var requestID: Int
    @Binding var webView: WKWebView?
    let onNavigation: (URL?) -> Void
    let onNavigationState: (Bool, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        YouTubePreviewUsageMonitor.shared.attach(view)
        context.coordinator.parent = self
        view.navigationDelegate = context.coordinator
        DispatchQueue.main.async { webView = view }
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard let url, context.coordinator.lastRequestID != requestID else { return }
        context.coordinator.lastRequestID = requestID
        view.load(URLRequest(url: url))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: BrowserWebView
        var lastRequestID = -1

        init(parent: BrowserWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onMain {
                self.parent.onNavigation(webView.url)
                self.parent.onNavigationState(webView.canGoBack, webView.canGoForward)
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
