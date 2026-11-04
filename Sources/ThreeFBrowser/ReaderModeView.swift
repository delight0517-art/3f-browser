import SwiftUI

struct ReaderModeView: View {
    let article: ReaderArticle
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("읽기 모드", systemImage: "text.alignleft")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(article.siteName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button("닫기") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(article.title)
                            .font(.system(size: 30, weight: .bold, design: .serif))
                            .textSelection(.enabled)
                        if !article.byline.isEmpty {
                            Text(article.byline)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        if !article.excerpt.isEmpty {
                            Text(article.excerpt)
                                .font(.system(size: 15, design: .serif))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    Text(article.text)
                        .font(.system(size: 16, design: .serif))
                        .lineSpacing(7)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 560, minHeight: 520)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
