import Foundation

/// How long a game has been played, from the sessions RetroHub started and saw end. The same
/// rules as the desktop app's desktop/src/renderer/playtime.js; SelfTests checks the same cases.
struct Playtime: Codable, Equatable {
    var seconds: Int
    var sessions: Int

    /// Sessions shorter than this don't count: usually an emulator that couldn't start the game.
    static let minimumSession: TimeInterval = 10

    /// The record with one more session added, or unchanged if the session was too short.
    static func adding(_ record: [String: Playtime], _ id: String, seconds: TimeInterval) -> [String: Playtime] {
        guard seconds >= minimumSession else { return record }
        var record = record
        let old = record[id] ?? Playtime(seconds: 0, sessions: 0)
        record[id] = Playtime(seconds: old.seconds + Int(seconds.rounded()), sessions: old.sessions + 1)
        return record
    }

    /// A renamed game's play time moves to its new path, added to any it already has.
    static func moving(_ record: [String: Playtime], from: String, to: String) -> [String: Playtime] {
        guard let moved = record[from] else { return record }
        var record = record
        record[from] = nil
        let old = record[to] ?? Playtime(seconds: 0, sessions: 0)
        record[to] = Playtime(seconds: old.seconds + moved.seconds, sessions: old.sessions + moved.sessions)
        return record
    }

    static func total(_ record: [String: Playtime]) -> Int {
        record.values.reduce(0) { $0 + $1.seconds }
    }

    /// "under a minute", "12 min", "3 h 12 min", "40 h".
    static func format(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes < 1 { return "under a minute" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60, rest = minutes % 60
        return hours >= 10 || rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}
