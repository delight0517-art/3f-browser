import SwiftUI
import AppKit
import WebKit

@MainActor
final class ThreeFBrowserAppDelegate: NSObject, NSApplicationDelegate {
    private var controlServer: ThreeFBrowserControlServer?
    private var focusFenceContactTask: Task<Void, Never>?
    private var keyboardEventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        keyboardEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let window = NSApp.keyWindow else { return event }
            let isFullScreen = window.styleMask.contains(.fullScreen)
            let action = ThreeFBrowserKeyboardAction.resolve(
                keyCode: event.keyCode,
                command: event.modifierFlags.contains(.command),
                shift: event.modifierFlags.contains(.shift),
                isFullScreen: isFullScreen
            )
            guard let action else { return event }
            switch action {
            case .closeTab:
                guard window.threeFBrowserWebView != nil else { return event }
                NotificationCenter.default.post(name: .threeFCloseSelectedTab, object: window)
            case .reload:
                window.threeFBrowserWebView?.reload()
            case .hardReload:
                window.threeFBrowserWebView?.reloadFromOrigin()
            case .toggleFullScreen, .exitFullScreen:
                window.toggleFullScreen(nil)
            }
            return nil
        }
        let descriptorURL = ProcessInfo.processInfo.environment["THREEF_BROWSER_CONTROL_DESCRIPTOR"]
            .map { URL(fileURLWithPath: $0) }
        let server = ThreeFBrowserControlServer(descriptorURL: descriptorURL)
        controlServer = server
        server.start()
        focusFenceContactTask = Task {
            while !Task.isCancelled {
                guard OptionalFeatureAvailability.focusFenceEnforcement else { return }
                let connected = await ThreeFBrowserControlController.refreshFocusFencePolicyContact()
                try? await Task.sleep(nanoseconds: connected ? 30_000_000_000 : 2_000_000_000)
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        controlServer?.publishForActiveInstance()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyboardEventMonitor {
            NSEvent.removeMonitor(keyboardEventMonitor)
            self.keyboardEventMonitor = nil
        }
        focusFenceContactTask?.cancel()
        focusFenceContactTask = nil
        controlServer?.stop()
        controlServer = nil
    }

}

private extension NSWindow {
    var threeFBrowserWebView: WKWebView? {
        if let webView = firstResponder as? WKWebView { return webView }
        func find(in view: NSView) -> WKWebView? {
            if let webView = view as? WKWebView { return webView }
            for child in view.subviews.reversed() {
                if let webView = find(in: child) { return webView }
            }
            return nil
        }
        guard let contentView else { return nil }
        return find(in: contentView)
    }
}

@main
struct ThreeFBrowserApp: App {
    @NSApplicationDelegateAdaptor(ThreeFBrowserAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("3F Browser", id: "browser") {
            BrowserView(
                authorizeNavigation: { url, completion in
                    Task {
                        guard OptionalFeatureAvailability.focusFenceEnforcement else {
                            completion(.allowed)
                            return
                        }
                        guard let rules = await ThreeFBrowserControlController.fetchFocusFenceRules() else {
                            completion(.unavailable)
                            return
                        }
                        completion(ThreeFBrowserControlController.navigationAuthorizationDecision(
                            for: url,
                            rules: rules
                        ))
                    }
                },
                onWebView: { model, webView in
                    ThreeFBrowserControlController.shared.attach(model: model, webView: webView)
                }
            )
                .environmentObject(ThreeFURLRouter.shared)
                .onOpenURL { url in
                    ThreeFURLRouter.shared.receive([url])
                }
        }
    }
}
