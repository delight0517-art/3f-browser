import SwiftUI

struct BrowserSettingsView: View {
    @ObservedObject var model: BrowserModel

    var body: some View {
        Form {
            Picker("검색 엔진", selection: $model.searchProvider) {
                ForEach(SearchProvider.allCases) { provider in
                    Text(provider.title).tag(provider)
                }
            }
            Text("주소창과 새 탭 검색에 함께 적용됩니다.")
                .foregroundStyle(.secondary)
            Section("브라우저 엔진 및 확장") {
                LabeledContent("현재 엔진", value: ExtensionCompatibility.currentEngine.rawValue)
                Text(ExtensionCompatibility.status)
                    .foregroundStyle(.secondary)
                Text(ExtensionCompatibility.limitation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("신체 개조 업데이트") {
                Text("검토한 JSON/CSS UI 모듈은 SHA-256과 증가 revision을 확인해 교체하고, 직전 버전으로 복원할 수 있습니다. 코드·브라우저 엔진 변경은 앱 빌드와 재시작이 필요합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}
