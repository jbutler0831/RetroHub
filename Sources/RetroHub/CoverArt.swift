import Foundation

/// Finds box art for a game: a local image next to the game first, then the
/// libretro-thumbnails library, cached on disk.
enum CoverArt {
    private static let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: "RetroHub/Covers")
    private static let server = URL(string: "https://thumbnails.libretro.com")!
    private static let regions = ["USA", "World", "USA, Europe", "Europe", "Japan"]

    private enum Fetch { case found(Data), missing, offline }

    static func data(for game: Game) async -> Data? {
        let fm = FileManager.default
        if let local = game.localCovers.first(where: { fm.fileExists(atPath: $0.path) }) {
            return try? Data(contentsOf: local)
        }

        let cached = cacheDir.appending(path: game.system.rawValue).appending(path: sanitize(game.title) + ".png")
        let missMarker = cached.appendingPathExtension("none")
        if fm.fileExists(atPath: cached.path) { return try? Data(contentsOf: cached) }
        if fm.fileExists(atPath: missMarker.path) { return nil }
        try? fm.createDirectory(at: cached.deletingLastPathComponent(), withIntermediateDirectories: true)

        for name in candidateNames(for: game.title) {
            let url = server.appending(path: game.system.libretroName)
                .appending(path: "Named_Boxarts")
                .appending(path: sanitize(name) + ".png")
            switch await fetch(url) {
            case .found(let data):
                try? data.write(to: cached)
                return data
            case .missing:
                continue
            case .offline:
                return nil  // Don't remember the miss; try again when back online.
            }
        }
        fm.createFile(atPath: missMarker.path, contents: nil)
        return nil
    }

    /// libretro-thumbnails uses No-Intro names such as "Super Mario Bros. (World)",
    /// so also try the title with its tags stripped and common regions added.
    private static func candidateNames(for title: String) -> [String] {
        let base = title
            .replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        var seen = Set<String>()
        return ([title] + regions.map { "\(base) (\($0))" }).filter { seen.insert($0).inserted }
    }

    /// The thumbnail server replaces these characters with underscores.
    private static func sanitize(_ name: String) -> String {
        String(name.map { "&*/:`<>?\\|\"".contains($0) ? "_" : $0 })
    }

    private static func fetch(_ url: URL) async -> Fetch {
        guard let (data, response) = try? await URLSession.shared.data(from: url) else { return .offline }
        return (response as? HTTPURLResponse)?.statusCode == 200 ? .found(data) : .missing
    }
}

extension GameSystem {
    /// Folder name used by libretro-thumbnails.
    var libretroName: String {
        switch self {
        case .nes: "Nintendo - Nintendo Entertainment System"
        case .snes: "Nintendo - Super Nintendo Entertainment System"
        case .n64: "Nintendo - Nintendo 64"
        case .xbox: "Microsoft - Xbox"
        case .ps3: "Sony - PlayStation 3"
        }
    }
}
