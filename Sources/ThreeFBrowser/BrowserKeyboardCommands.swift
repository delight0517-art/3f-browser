import Foundation

enum ThreeFBrowserKeyboardAction: Equatable {
    case reload
    case hardReload
    case closeTab
    case toggleFullScreen
    case exitFullScreen
    case zoomIn
    case zoomOut
    case resetZoom

    static func resolve(keyCode: UInt16, command: Bool, shift: Bool, isFullScreen: Bool) -> Self? {
        if command && !shift && keyCode == 13 { return .closeTab }
        if command && keyCode == 15 { return shift ? .hardReload : .reload }
        if command && (keyCode == 24 || keyCode == 69) { return .zoomIn }
        if command && (keyCode == 27 || keyCode == 78) { return .zoomOut }
        if command && !shift && (keyCode == 29 || keyCode == 82) { return .resetZoom }
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
