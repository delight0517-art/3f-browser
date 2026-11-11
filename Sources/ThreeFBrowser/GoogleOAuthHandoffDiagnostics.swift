import AppKit
import Combine
import Foundation
import WebKit

struct GoogleOAuthHandoffEvent: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let outcome: Outcome
    let detail: String?

    enum Outcome: String {
        case opened = "Google 로그인 페이지 열림 · 3F 내부"
        case duplicateSuppressed = "반복 팝업 억제"
        case asideUnavailable = "로그인 화면을 3F에서 유지"
        case openFailed = "브라우저 진단 이벤트"
        case unsupportedMedia = "지원되지 않는 미디어 형식"
    }
}

final class BrowserDiagnosticsScriptMessageHandler: NSObject, WKScriptMessageHandler {
    static let name = "threeFDiagnostics"
    static let script = #"""
    (() => {
      document.addEventListener('error', event => {
        const media = event.target;
        if (!(media instanceof HTMLMediaElement)) return;
        const source = media.currentSrc || media.querySelector('source')?.src || '';
        const mime = media.querySelector('source')?.type || media.type || '';
        const ext = source.split(/[?#]/, 1)[0].split('.').pop()?.toLowerCase() || '';
        if (media.error?.code === 4 || (mime && !media.canPlayType(mime))) {
          window.webkit?.messageHandlers?.threeFDiagnostics?.postMessage({kind:'unsupportedMedia', mime:mime.slice(0,80), ext:ext.slice(0,12)});
        }
      }, true);
    })();
    """#

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.name,
              let body = message.body as? [String: String],
              body["kind"] == "unsupportedMedia" else { return }
        let mime = body["mime"]?.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber || "/-+._".contains($0)) } ?? ""
        let ext = body["ext"]?.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) } ?? ""
        let suffix = mime.isEmpty ? ext : mime
        Task { @MainActor in
            GoogleOAuthHandoffDiagnostics.shared.record(.unsupportedMedia, detail: suffix.isEmpty ? nil : suffix, key: "media-\(suffix)")
        }
    }
}

@MainActor
final class GoogleOAuthHandoffDiagnostics: ObservableObject {
    static let shared = GoogleOAuthHandoffDiagnostics()
    @Published private(set) var events: [GoogleOAuthHandoffEvent] = []
    @Published private(set) var saveStatus = "로컬 로그 저장 대기"
    private let capacity = 100
    private let maxFileBytes = 1_048_576
    private var recentKeys: [String: Date] = [:]

    private var logURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("3F Browser", isDirectory: true)
            .appendingPathComponent("diagnostics.jsonl")
    }

    private init() { load() }

    func record(_ outcome: GoogleOAuthHandoffEvent.Outcome, detail: String? = nil, key: String = "event") {
        let now = Date()
        recentKeys = recentKeys.filter { now.timeIntervalSince($0.value) < 10 }
        guard recentKeys[key] == nil else { return }
        recentKeys[key] = now
        let event = GoogleOAuthHandoffEvent(id: UUID(), date: now, outcome: outcome, detail: detail)
        events.insert(event, at: 0)
        if events.count > capacity { events.removeLast(events.count - capacity) }
        persist(event)
    }

    func handoff(_ url: URL, sourceURL: URL?) {
        // Compatibility entry point: sign-in remains in the current 3F tab.
        record(.asideUnavailable, key: "google-\(url.host ?? "unknown")")
    }

    func clear() {
        events.removeAll()
        do {
            if FileManager.default.fileExists(atPath: logURL.path) { try FileManager.default.removeItem(at: logURL) }
            let rotated = logURL.appendingPathExtension("1")
            if FileManager.default.fileExists(atPath: rotated.path) { try FileManager.default.removeItem(at: rotated) }
            saveStatus = "로컬 로그 삭제됨"
        } catch { saveStatus = "로그 삭제 실패: \(error.localizedDescription)" }
    }

    func openLogFolder() { NSWorkspace.shared.open(logURL.deletingLastPathComponent()) }

    nonisolated static func deduplicationKey(for url: URL, sourceHost: String?) -> String {
        "\(sourceHost?.lowercased() ?? "unknown")|\(url.host?.lowercased() ?? "unknown")"
    }

    private func load() {
        do {
            let data = try Data(contentsOf: logURL)
            let lines = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline)
            events = lines.suffix(capacity).compactMap { line in
                guard let row = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: String],
                      let stamp = row["date"], let date = ISO8601DateFormatter().date(from: stamp),
                      let label = row["event"], let outcome = GoogleOAuthHandoffEvent.Outcome(rawValue: label) else { return nil }
                return GoogleOAuthHandoffEvent(id: UUID(), date: date, outcome: outcome, detail: row["detail"])
            }.reversed()
            saveStatus = "로컬 로그 읽음 · \(events.count)건"
        } catch where (error as NSError).code == NSFileReadNoSuchFileError {
            saveStatus = "로컬 로그 저장 대기"
        } catch { saveStatus = "로그 읽기 실패" }
    }

    private func persist(_ event: GoogleOAuthHandoffEvent) {
        do {
            let manager = FileManager.default
            try manager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var row: [String: String] = ["date": ISO8601DateFormatter().string(from: event.date), "event": event.outcome.rawValue]
            if let detail = event.detail { row["detail"] = detail }
            var data = try JSONSerialization.data(withJSONObject: row)
            data.append(0x0A)
            if let size = try? manager.attributesOfItem(atPath: logURL.path)[.size] as? NSNumber,
               size.intValue + data.count > maxFileBytes {
                let rotated = logURL.appendingPathExtension("1")
                try? manager.removeItem(at: rotated)
                if manager.fileExists(atPath: logURL.path) { try manager.moveItem(at: logURL, to: rotated) }
            }
            if !manager.fileExists(atPath: logURL.path) { manager.createFile(atPath: logURL.path, contents: nil) }
            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
            saveStatus = "로컬 저장됨 · diagnostics.jsonl"
        } catch { saveStatus = "로컬 로그 저장 실패" }
    }
}
