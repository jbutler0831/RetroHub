import CryptoKit
import Foundation

/// The Smart Game Scanner: compares each scan with the games RetroHub saw before, so it can say
/// what's new, what was moved or renamed, what's missing and what's there twice. Nothing is changed
/// until the user approves it in Library Check: a missing game keeps its favorite and play history,
/// and a renamed one only takes them over once confirmed. The same rules as the desktop app's
/// desktop/src/scanner.js; SelfTests checks the same cases as its tests.
enum Scanner {
    /// A game RetroHub has seen, by its path. `fp` is a fingerprint of the file's first 64 KB,
    /// worked out after the scan, in the background, only for files that don't have one yet.
    struct Entry: Codable, Equatable {
        var system: String
        var title: String
        var size: Int64?
        var mtime: Double?
        var firstSeen: Double
        var fp: String?
        var missingSince: Double?
        var notRenamed: Bool?
    }

    typealias Index = [String: Entry]

    struct FileInfo: Equatable {
        let size: Int64
        let mtime: Double
    }

    struct Added: Equatable { let path: String, system: String, title: String }
    struct Renamed: Equatable { let from: String, to: String, system: String, title: String }
    struct Missing: Equatable { let path: String, system: String, title: String, since: Double }
    struct Duplicate: Equatable { let system: String, title: String, paths: [String] }

    struct Summary: Equatable {
        var added: [Added] = []
        var renamed: [Renamed] = []
        var missing: [Missing] = []
        var duplicates: [Duplicate] = []
    }

    private static let fingerprintBytes = 64 * 1024

    /// Size and modification time (milliseconds), or nil for a folder (PS Vita games), which isn't
    /// matched on moves.
    static func statFile(_ path: String) -> FileInfo? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber,
              let date = attributes[.modificationDate] as? Date else { return nil }
        return FileInfo(size: size.int64Value, mtime: date.timeIntervalSince1970 * 1000)
    }

    /// SHA-256 of the file's size and first 64 KB, shortened.
    static func fingerprint(_ path: String) throws -> String {
        let handle = try FileHandle(forReadingFrom: URL(filePath: path))
        defer { try? handle.close() }
        let data = try handle.read(upToCount: fingerprintBytes) ?? Data()
        let size = try handle.seekToEnd()
        var hash = SHA256()
        hash.update(data: Data(String(size).utf8))
        hash.update(data: data)
        return String(hash.finalize().map { String(format: "%02x", $0) }.joined().prefix(24))
    }

    /// The index after a scan. `previous` nil means RetroHub has never scanned: everything found is
    /// the baseline, not news. Games that disappeared stay in the index, marked missing since `now`.
    static func updateIndex(_ previous: Index?, games: [Game], now: Double,
                            stat: (String) -> FileInfo? = statFile) -> Index {
        var index: Index = [:]
        for game in games {
            let path = game.bootURL.path
            let old = previous?[path]
            let info = stat(path)
            let unchanged = old != nil && info != nil && old?.size == info?.size && old?.mtime == info?.mtime
            index[path] = Entry(system: game.system.rawValue, title: game.displayTitle, size: info?.size, mtime: info?.mtime,
                                firstSeen: old?.firstSeen ?? (previous == nil ? 0 : now), fp: unchanged ? old?.fp : nil)
        }
        for (path, old) in previous ?? [:] where index[path] == nil {
            var entry = old
            entry.missingSince = old.missingSince ?? now
            index[path] = entry
        }
        return index
    }

    /// Present files that still need a fingerprint.
    static func needsFingerprint(_ index: Index) -> [String] {
        index.filter { $0.value.missingSince == nil && $0.value.fp == nil && $0.value.size != nil }.map(\.key).sorted()
    }

    private static func sameKind(_ a: Entry, _ b: Entry, _ pathA: String, _ pathB: String) -> Bool {
        a.system == b.system && a.size != nil && a.size == b.size
            && URL(filePath: pathA).pathExtension.lowercased() == URL(filePath: pathB).pathExtension.lowercased()
    }

    /// What Library Check shows. `reviewedAt` is when the user last reviewed the changes: games
    /// first seen since then are new.
    static func summarize(_ index: Index, reviewedAt: Double = 0) -> Summary {
        let entries = index.sorted { $0.key < $1.key }
        let present = entries.filter { $0.value.missingSince == nil }
        var summary = Summary()
        var claimed = Set<String>()
        for (from, old) in entries where old.missingSince != nil && old.notRenamed != true {
            // Same system, size and file type, and first seen when (or after) the old one went
            // missing: a file that was already there is a different game.
            let candidates = present.filter { to, entry in
                !claimed.contains(to) && sameKind(old, entry, from, to) && entry.firstSeen >= old.missingSince!
            }
            // Fingerprints, where both are known, must agree; one not worked out yet doesn't rule it out.
            let possible = candidates.filter { old.fp == nil || $0.value.fp == nil || $0.value.fp == old.fp }
            guard possible.count == 1, let match = possible.first else { continue }
            claimed.insert(match.key)
            summary.renamed.append(Renamed(from: from, to: match.key, system: old.system, title: old.title))
        }
        let renamedFrom = Set(summary.renamed.map(\.from))
        summary.added = present.filter { $0.value.firstSeen > reviewedAt && !claimed.contains($0.key) }
            .map { Added(path: $0.key, system: $0.value.system, title: $0.value.title) }
        summary.missing = entries.filter { $0.value.missingSince != nil && !renamedFrom.contains($0.key) }
            .map { Missing(path: $0.key, system: $0.value.system, title: $0.value.title, since: $0.value.missingSince!) }
        var groups: [String: [String]] = [:]
        for (path, entry) in present {
            guard let fp = entry.fp else { continue }
            groups["\(entry.system):\(fp)", default: []].append(path)
        }
        summary.duplicates = groups.values.filter { $0.count > 1 }.map { $0.sorted() }
            .sorted { $0[0] < $1[0] }
            .map { Duplicate(system: index[$0[0]]!.system, title: index[$0[0]]!.title, paths: $0) }
        return summary
    }
}
