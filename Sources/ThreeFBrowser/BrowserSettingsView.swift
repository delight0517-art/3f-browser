import SwiftUI
import UniformTypeIdentifiers
import AppKit

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
                Text("테마 JSON은 앱 재빌드 없이 적용됩니다. SHA-256과 revision을 확인하고 직전 테마로 복원할 수 있습니다. 코드·브라우저 엔진 변경은 앱 빌드와 재시작이 필요합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.themeModuleStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("테마 JSON 불러오기") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.json]
                        panel.allowsMultipleSelection = false
                        panel.canChooseDirectories = false
                        if panel.runModal() == .OK, let url = panel.url {
                            model.importThemeModule(from: url)
                        }
                    }
                    Button("이전 테마 복원", action: model.rollbackThemeModule)
                    Button("모듈 다시 읽기", action: model.reloadThemeModule)
                }
                Text(##"예: {"accentHex":"#22AAFF"}"##)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}
