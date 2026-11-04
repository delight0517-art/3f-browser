import SwiftUI

struct MediaSiteCandidateSheet: View {
    let candidate: MediaSiteCandidate
    let onResolved: (MediaSiteCandidate) -> Void
    let onDeferred: (MediaSiteCandidate) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var connection = FocusFenceConnectionService()
    @State private var scheduleText = ""
    @State private var statusMessage: String?
    @State private var pendingConfirmation = false
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(candidate.platformName)을 차단 대상에 추가할까요?")
                .font(.title3.weight(.semibold))
            Text("\(candidate.category.label)와 관련된 사이트를 열었습니다. 차단 규칙 추가, 시간표 등록, 그대로 두기 중에서 선택하세요.")
                .foregroundStyle(.secondary)
            Text("대상: \(candidate.domain)")
                .font(.callout.monospaced())

            Button("현재 Focus Fence 차단에 추가") { addToCurrentBlock() }
                .disabled(isWorking)

            Divider()
            Text("차단 시간표 만들기")
                .font(.headline)
            TextField("예: 매일 밤 10시부터 아침 7시까지", text: $scheduleText)
                .textFieldStyle(.roundedBorder)
                .disabled(isWorking || pendingConfirmation)
            Button(pendingConfirmation ? "미리보기 확인 완료 · 적용" : "시간표 미리보기") {
                pendingConfirmation ? confirmSchedule() : previewSchedule()
            }
            .disabled(isWorking || scheduleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let statusMessage {
                Text(statusMessage)
                    .font(.callout)
                    .textSelection(.enabled)
            }

            HStack {
                Button("추가하지 않고 허용") {
                    onResolved(candidate)
                    dismiss()
                }
                .disabled(isWorking)
                Spacer()
                Button("나중에 · 24시간 숨기기") {
                    onDeferred(candidate)
                    dismiss()
                }
                    .disabled(isWorking)
            }
            Text("‘추가하지 않고 허용’은 이 사이트를 새 차단 규칙에 넣지 않고 이 제안만 기억합니다. 다른 일반 규칙의 영향은 그대로입니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 440)
    }

    private func addToCurrentBlock() {
        run {
            let outcome = try await connection.quickAddDomain(candidate.domain)
            statusMessage = outcome.message + (outcome.scheduleName.map { " · 적용 위치: \($0)" } ?? "")
            if outcome.ok || outcome.duplicate {
                onResolved(candidate)
                dismiss()
            }
        }
    }

    private func previewSchedule() {
        run {
            let outcome = try await connection.previewSchedule(scheduleText)
            statusMessage = outcome.message + (outcome.scheduleName.map { " · 시간표: \($0)" } ?? "")
            pendingConfirmation = outcome.ok && outcome.requiresConfirm
        }
    }

    private func confirmSchedule() {
        run {
            let outcome = try await connection.confirmSchedule(scheduleText)
            statusMessage = outcome.message + (outcome.scheduleName.map { " · 시간표: \($0)" } ?? "")
            if outcome.ok {
                onResolved(candidate)
                dismiss()
            }
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        isWorking = true
        statusMessage = nil
        Task {
            defer { isWorking = false }
            do { try await action() }
            catch { statusMessage = "Focus Fence와 연결할 수 없습니다. \(error.localizedDescription)" }
        }
    }
}
