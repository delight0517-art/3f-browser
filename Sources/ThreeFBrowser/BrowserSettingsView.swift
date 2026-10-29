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
        }
        .padding(20)
        .frame(width: 340)
    }
}
