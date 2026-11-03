import Foundation

enum OptionalFeatureAvailability {
    // Keep unfinished cross-app integrations inert until their runtime contract is verified.
    static let focusFenceEnforcement = false
    static let youtubeUsageReporting = false
    static let youtubePreviewBlocking = false
}
