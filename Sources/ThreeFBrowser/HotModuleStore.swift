import CryptoKit
import Foundation

struct HotModuleManifest: Codable, Equatable {
    let revision: Int
    let files: [String: String]
}

enum HotModuleError: Error, LocalizedError {
    case invalidRevision
    case invalidPath(String)
    case invalidHash(String)
    case missingFile(String)
    case noPreviousRevision

    var errorDescription: String? {
        switch self {
        case .invalidRevision: "모듈 revision은 현재 값보다 커야 합니다."
        case .invalidPath(let path): "허용되지 않은 모듈 경로: \(path)"
        case .invalidHash(let path): "모듈 해시가 일치하지 않습니다: \(path)"
        case .missingFile(let path): "모듈 파일이 없습니다: \(path)"
        case .noPreviousRevision: "복원할 이전 모듈 버전이 없습니다."
        }
    }
}

/// Stores reviewed, non-executable UI/theme data revisions. It never loads code.
actor HotModuleStore {
    private let root: URL
    private let fileManager = FileManager.default
    private let allowedExtensions: Set<String> = ["json", "css"]

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("3F Browser/HotModules", isDirectory: true)
    }

    func currentManifest() throws -> HotModuleManifest? {
        let url = activeDirectory.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(HotModuleManifest.self, from: Data(contentsOf: url))
    }

    func apply(revision: Int, files: [String: Data], expectedHashes: [String: String]) throws {
        let currentRevision = try currentManifest()?.revision ?? 0
        guard revision > currentRevision, !files.isEmpty, Set(files.keys) == Set(expectedHashes.keys) else {
            throw HotModuleError.invalidRevision
        }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let candidate = root.appendingPathComponent("candidate-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: candidate, withIntermediateDirectories: true)
        do {
            for (path, data) in files {
                try validate(path: path)
                guard Self.sha256(data) == expectedHashes[path]?.lowercased() else {
                    throw HotModuleError.invalidHash(path)
                }
                let destination = candidate.appendingPathComponent(path)
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: destination, options: .atomic)
            }
            let manifest = HotModuleManifest(revision: revision, files: expectedHashes.mapValues { $0.lowercased() })
            let manifestData = try JSONEncoder().encode(manifest)
            try manifestData.write(to: candidate.appendingPathComponent("manifest.json"), options: .atomic)

            let pending = root.appendingPathComponent("pending", isDirectory: true)
            try? fileManager.removeItem(at: pending)
            try fileManager.moveItem(at: candidate, to: pending)
            let previous = root.appendingPathComponent("previous", isDirectory: true)
            try? fileManager.removeItem(at: previous)
            if fileManager.fileExists(atPath: activeDirectory.path) {
                try fileManager.moveItem(at: activeDirectory, to: previous)
            }
            try fileManager.moveItem(at: pending, to: activeDirectory)
        } catch {
            try? fileManager.removeItem(at: candidate)
            throw error
        }
    }

    func rollback() throws {
        let previous = root.appendingPathComponent("previous", isDirectory: true)
        guard fileManager.fileExists(atPath: previous.path) else { throw HotModuleError.noPreviousRevision }
        let failed = root.appendingPathComponent("failed-\(UUID().uuidString)", isDirectory: true)
        if fileManager.fileExists(atPath: activeDirectory.path) {
            try fileManager.moveItem(at: activeDirectory, to: failed)
        }
        do {
            try fileManager.moveItem(at: previous, to: activeDirectory)
            try? fileManager.removeItem(at: failed)
        } catch {
            if fileManager.fileExists(atPath: failed.path) {
                try? fileManager.moveItem(at: failed, to: activeDirectory)
            }
            throw error
        }
    }

    private var activeDirectory: URL { root.appendingPathComponent("active", isDirectory: true) }

    private func validate(path: String) throws {
        let parts = path.split(separator: "/")
        guard !path.isEmpty, !path.hasPrefix("/"), !parts.contains(".."),
              parts.count == 1,
              allowedExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased()) else {
            throw HotModuleError.invalidPath(path)
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
