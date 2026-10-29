import SwiftUI
import AppKit

@MainActor
final class ThreeFBrowserAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        ThreeFURLRouter.shared.receive(urls)
    }
}

@main
struct ThreeFBrowserApp: App {
    @NSApplicationDelegateAdaptor(ThreeFBrowserAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("3F Browser") {
            BrowserView()
                .environmentObject(ThreeFURLRouter.shared)
        }
    }
}
