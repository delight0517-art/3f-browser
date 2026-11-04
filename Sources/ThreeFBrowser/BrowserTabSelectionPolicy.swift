import Foundation

enum BrowserTabSelectionPolicy {
    static func selectedTabID(
        currentSelection: UUID?,
        newlyOpenedTabID: UUID,
        opensInBackground: Bool
    ) -> UUID {
        if opensInBackground, let currentSelection {
            return currentSelection
        }
        return newlyOpenedTabID
    }
}
