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

    private var isRestricted: Bool {
        summary?.blocked == true || playbackReason != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("YouTube 사용량", systemImage: isRestricted ? "pause.circle.fill" : "play.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(YouTubeUsagePalette.ink)
                Spacer(minLength: 4)
                Text(isRestricted ? "재생 제한 중" : "시청 가능")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isRestricted ? Color.orange : YouTubeUsagePalette.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((isRestricted ? Color.orange : YouTubeUsagePalette.muted).opacity(0.12), in: Capsule())
            }

            if let summary {
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
            } else {
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
        .padding(.vertical, 11)
        .background(YouTubeUsagePalette.surface)
        .accessibilityElement(children: .combine)
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
