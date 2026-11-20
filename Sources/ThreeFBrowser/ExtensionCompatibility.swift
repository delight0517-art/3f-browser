import Foundation

enum BrowserEngineKind: String {
    case webKit = "WebKit"
    case chromium = "Chromium"
}

enum ExtensionSupportLevel: String {
    case none = "미지원"
    case chromiumAPIs = "Chromium 확장 API 일부"
    case storeVerified = "스토어 확장별 검증"
}

enum BrowserPolicyPlugin: String, CaseIterable, Identifiable {
    case focusFence

    var id: String { rawValue }

    var title: String { "Focus Fence" }

    var engine: BrowserEngineKind { .webKit }

    var status: String {
        switch self {
        case .focusFence:
            OptionalFeatureAvailability.focusFenceEnforcement
                ? "Focus Fence 정책 어댑터 사용 · 연결 상태는 브라우저 상태에서 확인"
                : "Focus Fence 정책 어댑터 비활성"
        }
    }
}

struct ExtensionCompatibility {
    static let currentEngine: BrowserEngineKind = .webKit
    static let supportLevel: ExtensionSupportLevel = .none

    static var status: String {
        switch currentEngine {
        case .webKit:
            "WebKit · Chrome 확장 미지원"
        case .chromium:
            "Chromium · 확장 API 호환성은 확장별 검증 필요"
        }
    }

    static let limitation = "Chrome Web Store의 모든 확장 호환은 보장할 수 없습니다. 지원 확장 목록과 권한을 설치 전에 확인해야 합니다."

    // A future CEF host must use an app-specific root_cache_path. CEF otherwise
    // defaults to ~/Library/Application Support/CEF/User Data, which is shared
    // by unrelated CEF apps and can corrupt or expose their browser profile.
    static let chromiumProfileRequirement = "CEF 프로필은 3F 전용 Application Support 경로로 격리해야 합니다."
}
