import Foundation

enum BrowserEngineKind: String {
    case webKit = "WebKit"
    case chromium = "Chromium"
}

struct ExtensionCompatibility {
    static let currentEngine: BrowserEngineKind = .webKit

    static var status: String {
        switch currentEngine {
        case .webKit:
            "Chrome 확장 미지원 · Chromium 엔진 교체 대기"
        case .chromium:
            "Chromium 기반 · 확장별 API 호환성 확인 필요"
        }
    }

    static let limitation = "임베디드 Chromium도 Chrome Web Store 확장 전체 호환을 보장하지 않습니다."
}
