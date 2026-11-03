import Foundation

enum OptionalFeatureAvailability {
    // Keep unfinished cross-app integrations inert until their runtime contract is verified.
    static let focusFenceEnforcement = false
    static let youtubeUsageReporting = true
    static let youtubePreviewBlocking = false
}
