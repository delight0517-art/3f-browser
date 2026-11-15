import SwiftUI
import AppKit
import WebKit

@MainActor
final class ThreeFBrowserAppDelegate: NSObject, NSApplicationDelegate {
    private let externalURLRouter: ThreeFURLRouter?
    private var controlServer: ThreeFBrowserControlServer?
    private var focusFenceContactTask: Task<Void, Never>?
    private var keyboardEventMonitor: Any?
    private var didRequestFocusFenceLaunch = false

    override init() {
        self.externalURLRouter = nil
        super.init()
    }

    init(externalURLRouter: ThreeFURLRouter? = nil) {
        self.externalURLRouter = externalURLRouter
        super.init()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        (externalURLRouter ?? ThreeFURLRouter.shared).receive(urls)
    }

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
                if !connected {
                    requestFocusFenceLaunchIfNeeded()
                }
                try? await Task.sleep(nanoseconds: connected ? 30_000_000_000 : 2_000_000_000)
            }
        }
    }

    private func requestFocusFenceLaunchIfNeeded() {
        guard !didRequestFocusFenceLaunch else { return }
        let bundleID = "com.rogan.VeliMac"
        let installedURL = URL(fileURLWithPath: "/Applications/Focus Fence.app", isDirectory: true)
        let installedBundleIsFocusFence = Bundle(url: installedURL)?.bundleIdentifier == bundleID
        guard let appURL = installedBundleIsFocusFence
            ? installedURL
            : NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return
        }
        let runningInstanceCount = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count
        let isSpaceOAgentSession = ProcessInfo.processInfo.environment["SPACEO_AGENT_SESSION"] == "1"
            || CommandLine.arguments.contains("--spaceo-agent-session")
        guard FocusFenceLaunchPolicy.shouldLaunch(
            canonicalURL: appURL,
            runningInstanceCount: runningInstanceCount,
            isSpaceOAgentSession: isSpaceOAgentSession
        ) else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.allowsRunningApplicationSubstitution = false
        didRequestFocusFenceLaunch = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            guard error != nil else { return }
            Task { @MainActor in self.didRequestFocusFenceLaunch = false }
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

enum FocusFenceLaunchPolicy {
    static func shouldLaunch(
        canonicalURL: URL,
        runningInstanceCount: Int,
        isSpaceOAgentSession: Bool = false
    ) -> Bool {
        guard !isSpaceOAgentSession, runningInstanceCount == 0 else { return false }
        return FileManager.default.fileExists(atPath: canonicalURL.path)
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
    init() {
        ThreeFBrowserTerminationProbe.installIfRequested()
    }

    @NSApplicationDelegateAdaptor(ThreeFBrowserAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("3F Browser", id: "browser") {
            BrowserView(
                authorizeNavigation: { url, completion in
                    if GoogleOAuthNavigationPolicy.requiresSystemBrowser(for: url) {
                        completion(.allowed)
                        return
                    }
                    Task {
                        guard OptionalFeatureAvailability.focusFenceEnforcement else {
                            completion(.allowed)
                            return
                        }
                        completion(ThreeFBrowserControlController.navigationAuthorizationDecision(
                            for: url,
                            rules: await ThreeFBrowserControlController.fetchFocusFenceRules()
                        ))
                    }
                },
                onWebView: { model, webView in
                    ThreeFBrowserControlController.shared.attach(model: model, webView: webView)
                }
            )
                .environmentObject(ThreeFURLRouter.shared)
        }
        WindowGroup("3F AI Mod", id: "ai-mode") {
            BrowserView(
                aiMode: true,
                authorizeNavigation: { url, completion in
                    if GoogleOAuthNavigationPolicy.requiresSystemBrowser(for: url) {
                        completion(.allowed)
                        return
                    }
                    if AIModeNavigationPolicy.isOnlyChatLocalOrigin(url) {
                        completion(.allowed)
                        return
                    }
                    Task {
                        guard OptionalFeatureAvailability.focusFenceEnforcement else {
                            completion(.allowed)
                            return
                        }
                        completion(ThreeFBrowserControlController.navigationAuthorizationDecision(
                            for: url,
                            rules: await ThreeFBrowserControlController.fetchFocusFenceRules()
                        ))
                    }
                }
            )
            .environmentObject(ThreeFURLRouter.shared)
        }
        WindowGroup("3F Web App", id: "web-app", for: InstalledWebApp.self) { installedApp in
            if let installedApp = installedApp.wrappedValue {
                BrowserView(
                    installedWebApp: installedApp,
                    authorizeNavigation: { url, completion in
                        if GoogleOAuthNavigationPolicy.requiresSystemBrowser(for: url) {
                            completion(.allowed)
                            return
                        }
                        Task {
                            guard OptionalFeatureAvailability.focusFenceEnforcement else {
                                completion(.allowed)
                                return
                            }
                            completion(ThreeFBrowserControlController.navigationAuthorizationDecision(
                                for: url,
                                rules: await ThreeFBrowserControlController.fetchFocusFenceRules()
                            ))
                        }
                    },
                    onWebView: { model, webView in
                        ThreeFBrowserControlController.shared.attach(model: model, webView: webView)
                    }
                )
                .environmentObject(ThreeFURLRouter.shared)
            } else {
                ContentUnavailableView("설치한 웹 앱을 찾을 수 없습니다", systemImage: "app.dashed")
            }
        }
    }
}
