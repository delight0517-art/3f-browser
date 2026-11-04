import Foundation

enum OptionalFeatureAvailability {
    // The live Focus Fence rules contract matches the browser consumer; end-to-end UI proof remains tracked separately.
    static let focusFenceEnforcement = true
    static let youtubeUsageReporting = true
    static let youtubePreviewBlocking = false
}
