import Foundation

enum ThreeFBrowserKeyboardAction: Equatable {
    case reload
    case hardReload
    case closeTab
    case toggleFullScreen
    case exitFullScreen

    static func resolve(keyCode: UInt16, command: Bool, shift: Bool, isFullScreen: Bool) -> Self? {
        if command && !shift && keyCode == 13 { return .closeTab }
        if command && keyCode == 15 { return shift ? .hardReload : .reload }
        guard !command && !shift else { return nil }
        switch keyCode {
        case 96: return .reload
        case 103: return .toggleFullScreen
        case 53 where isFullScreen: return .exitFullScreen
        default: return nil
        }
    }
}

enum ThreeFBrowserWindowRouting {
    static func targets(_ candidate: AnyObject?, window: AnyObject?) -> Bool {
        guard let candidate, let window else { return false }
        return candidate === window
    }
}

extension Notification.Name {
    static let threeFCloseSelectedTab = Notification.Name("threef.close-selected-tab")
}
