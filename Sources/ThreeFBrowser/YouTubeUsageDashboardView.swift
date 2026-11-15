import SwiftUI

private enum YouTubeUsagePalette {
    static let surface = Color(red: 1.000, green: 0.976, blue: 0.988)
    static let ink = Color(red: 0.125, green: 0.090, blue: 0.173)
    static let muted = Color(red: 0.467, green: 0.439, blue: 0.510)
}

struct YouTubeUsageDashboardView: View {
    let summary: FocusFenceYouTubeUsageSummary?
    let unavailable: Bool
    let playbackReason: String?
    let isShorts: Bool
    let now: Date

    @State private var isExpanded = false

    private var isRestricted: Bool {
        summary?.blocked == true || playbackReason != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Label("YouTube 한도", systemImage: isRestricted ? "pause.circle.fill" : "play.circle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(YouTubeUsagePalette.ink)
                    Text(compactUsageText)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(YouTubeUsagePalette.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 2)
                    Text(statusLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(statusColor.opacity(0.12), in: Capsule())
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(YouTubeUsagePalette.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "YouTube 사용량 상세 접기" : "YouTube 사용량 상세 보기")
            .accessibilityHint("상세 사용량과 제한 상태를 펼치거나 접습니다.")

            if isExpanded, let summary {
                HStack(alignment: .top, spacing: 18) {
                    usageMeter(
                        title: "오늘",
                        usedSeconds: summary.todaySeconds,
                        capSeconds: summary.dailyCapMinutes * 60,
                        capLabel: summary.dailyCapMinutes > 0 ? "한도 \(summary.dailyCapMinutes)분" : "한도 없음",
                        remainingSeconds: summary.dailyCapMinutes > 0 ? max(0, summary.dailyCapMinutes * 60 - summary.todaySeconds) : nil
                    )
                    usageMeter(
                        title: "최근 1시간",
                        usedSeconds: summary.hourlyUsedSeconds,
                        capSeconds: (summary.hourlyCapMinutes ?? 0) * 60,
                        capLabel: (summary.hourlyCapMinutes ?? 0) > 0
                            ? "한도 \(summary.hourlyCapMinutes ?? 0)분"
                            : (summary.hourlyCapMinutes == 0 ? "한도 없음" : "사용량 확인 불가"),
                        remainingSeconds: summary.hourlyRemainingSeconds
                    )
                }

                if let playbackReason {
                    Text(playbackReason)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(YouTubeUsagePalette.ink)
                } else if let resume = summary.resumeStatus(at: now, isShorts: isShorts) {
                    Text(resume)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(YouTubeUsagePalette.ink)
                        .monospacedDigit()
                }

                if unavailable {
                    Label("FF 연결 끊김 · 마지막 정상 사용량과 설정을 표시 중", systemImage: "wifi.slash")
                        .font(.system(size: 10))
                        .foregroundStyle(YouTubeUsagePalette.muted)
                        .lineLimit(1)
                }

                if let sync = summary.synchronizationExplanation {
                    Label(sync, systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10))
                        .foregroundStyle(YouTubeUsagePalette.muted)
                        .lineLimit(1)
                }
            } else if isExpanded {
                Label(
                    unavailable ? "사용량을 불러오지 못했습니다. FF 연결 상태를 확인해 주세요." : "사용량 정보를 기다리는 중입니다.",
                    systemImage: unavailable ? "exclamationmark.triangle" : "clock"
                )
                .font(.system(size: 11))
                .foregroundStyle(YouTubeUsagePalette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(YouTubeUsagePalette.ink)
        .padding(.horizontal, 18)
        .padding(.vertical, isExpanded ? 9 : 6)
        .background(YouTubeUsagePalette.surface)
        .accessibilityElement(children: .contain)
    }

    private var compactUsageText: String {
        guard let summary else {
            return unavailable ? "FF 연결 확인 필요" : "사용량 확인 중"
        }
        let dailyCap = summary.dailyCapMinutes > 0 ? "\(summary.dailyCapMinutes)분" : "제한 없음"
        let hourlyCap: String
        if let cap = summary.hourlyCapMinutes {
            hourlyCap = cap > 0 ? "\(cap)분" : "제한 없음"
        } else {
            hourlyCap = "확인 불가"
        }
        let hourlyUsed = summary.hourlyUsedSeconds.map(FocusFenceYouTubeUsageSummary.duration) ?? "확인 불가"
        return "오늘 \(FocusFenceYouTubeUsageSummary.duration(summary.todaySeconds))/\(dailyCap) · 1시간 \(hourlyUsed)/\(hourlyCap)"
    }

    private var statusLabel: String {
        if unavailable { return "FF 연결 확인" }
        guard summary != nil else { return "확인 중" }
        return isRestricted ? "재생 제한 중" : "시청 가능"
    }

    private var statusColor: Color {
        if unavailable || summary == nil { return YouTubeUsagePalette.muted }
        return isRestricted ? .orange : YouTubeUsagePalette.muted
    }

    @ViewBuilder
    private func usageMeter(title: String, usedSeconds: Int?, capSeconds: Int, capLabel: String, remainingSeconds: Int?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(YouTubeUsagePalette.muted)
            if let usedSeconds {
                Text(FocusFenceYouTubeUsageSummary.duration(usedSeconds))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                if capSeconds > 0 {
                    ProgressView(value: min(1, Double(max(0, usedSeconds)) / Double(capSeconds)))
                        .tint(isRestricted ? .orange : .purple)
                        .accessibilityLabel("\(title) 사용량")
                    HStack(spacing: 4) {
                        Text(capLabel)
                        Spacer(minLength: 0)
                        if let remainingSeconds {
                            Text("남음 \(FocusFenceYouTubeUsageSummary.duration(remainingSeconds))")
                                .monospacedDigit()
                        }
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(YouTubeUsagePalette.muted)
                    .lineLimit(1)
                } else {
                    Text(capLabel)
                        .font(.system(size: 9))
                        .foregroundStyle(YouTubeUsagePalette.muted)
                }
            } else {
                Text("확인 불가")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(YouTubeUsagePalette.muted)
                Text(capLabel)
                    .font(.system(size: 9))
                    .foregroundStyle(YouTubeUsagePalette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
