import AppKit
import CoreImage

/// Finds box art for a game: a local image next to the game first, then the
/// libretro-thumbnails library, cached on disk.
enum CoverArt {
    /// Named after the app, so a development build ("RetroHub Dev") keeps its own cache.
    private static let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "RetroHub")
        .appending(path: "Covers")
    private static let server = URL(string: "https://thumbnails.libretro.com")!
    private static let regions = ["USA", "World", "USA, Europe", "Europe", "Japan"]

    enum Fetch: Equatable { case found(Data), missing, offline }

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

    /// A small, heavily blurred copy of the art, for full-screen backdrops.
    static func blurred(_ data: Data) async -> CGImage? {
        guard let input = CIImage(data: data) else { return nil }
        let scale = 240 / max(input.extent.width, 1)
        let small = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let blurred = small.clampedToExtent().applyingGaussianBlur(sigma: 14).cropped(to: small.extent)
        return CIContext().createCGImage(blurred, from: small.extent)
    }

    /// libretro-thumbnails uses No-Intro names such as "Super Mario Bros. (World)" and
    /// "Legend of Zelda, The (USA)", so also try the bare title with common regions added.
    private static func candidateNames(for title: String) -> [String] {
        let base = title.strippingTags
        var bases = [base]
        if base.hasPrefix("The ") { bases.append(String(base.dropFirst(4)) + ", The") }
        var seen = Set<String>()
        return ([title] + bases.flatMap { base in regions.map { "\(base) (\($0))" } })
            .filter { seen.insert($0).inserted }
    }

    /// The thumbnail server replaces these characters with underscores.
    private static func sanitize(_ name: String) -> String {
        String(name.map { "&*/:`<>?\\|\"".contains($0) ? "_" : $0 })
    }

    private static func fetch(_ url: URL) async -> Fetch {
        guard let (data, response) = try? await URLSession.shared.data(from: url) else { return .offline }
        return result(status: (response as? HTTPURLResponse)?.statusCode, data: data)
    }

    /// Only a 404 means there's no art under that name. Anything else that isn't a 200 (rate
    /// limiting, a server outage) is treated like being offline, so the miss isn't remembered.
    static func result(status: Int?, data: Data) -> Fetch {
        switch status {
        case 200: .found(data)
        case 404: .missing
        default: .offline
        }
    }
}

extension GameSystem {
    /// Folder name used by libretro-thumbnails.
    var libretroName: String {
        switch self {
        case .nes: "Nintendo - Nintendo Entertainment System"
        case .snes: "Nintendo - Super Nintendo Entertainment System"
        case .n64: "Nintendo - Nintendo 64"
        case .gamecube: "Nintendo - GameCube"
        case .wii: "Nintendo - Wii"
        case .wiiu: "Nintendo - Wii U"
        case .gb: "Nintendo - Game Boy"
        case .gbc: "Nintendo - Game Boy Color"
        case .gba: "Nintendo - Game Boy Advance"
        case .ds: "Nintendo - Nintendo DS"
        case .n3ds: "Nintendo - Nintendo 3DS"
        case .masterSystem: "Sega - Master System - Mark III"
        case .genesis: "Sega - Mega Drive - Genesis"
        case .segaCD: "Sega - Mega-CD - Sega CD"
        case .sega32x: "Sega - 32X"
        case .saturn: "Sega - Saturn"
        case .dreamcast: "Sega - Dreamcast"
        case .gameGear: "Sega - Game Gear"
        case .ps1: "Sony - PlayStation"
        case .ps2: "Sony - PlayStation 2"
        case .ps3: "Sony - PlayStation 3"
        case .ps4: "Sony - PlayStation 4"
        case .psp: "Sony - PlayStation Portable"
        case .vita: "Sony - PlayStation Vita"
        case .xbox: "Microsoft - Xbox"
        case .pce: "NEC - PC Engine - TurboGrafx 16"
        case .neoGeo: "SNK - Neo Geo"
        case .atari2600: "Atari - 2600"
        case .arcade: "FBNeo - Arcade Games"
        }
    }
}
