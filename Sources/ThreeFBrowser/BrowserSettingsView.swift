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
                LabeledContent("확장 지원", value: ExtensionCompatibility.supportLevel.rawValue)
                Text(ExtensionCompatibility.status)
                    .foregroundStyle(.secondary)
                Text(ExtensionCompatibility.limitation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(ExtensionCompatibility.chromiumProfileRequirement)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("신체 개조 업데이트") {
                LabeledContent("현재 핫 업데이트 범위", value: "새 탭 테마 · HTTPS 빠른 링크")
                LabeledContent("모듈 형식", value: "서명되지 않은 데이터 JSON")
                Text("이 범위의 설정 데이터는 앱 재빌드 없이 반영되며 SHA-256과 revision을 확인하고 직전 설정으로 복원합니다. 임의 코드·네이티브 기능·Chromium 엔진·확장 런타임 변경은 앱 빌드와 재검증이 필요합니다.")
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
                Text(##"예: {"accentHex":"#22AAFF","quickLinks":[{"title":"문서","url":"https://example.com/docs"}]}"##)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}
