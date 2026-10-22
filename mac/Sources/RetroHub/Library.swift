import Foundation

struct Game: Identifiable, Hashable {
    let system: GameSystem
    let title: String
    /// The file handed to the emulator: the ROM/ISO itself, or a PS3 or PS4 game's EBOOT.BIN.
    let bootURL: URL
    /// Images that override downloaded cover art, in order of preference.
    let localCovers: [URL]

    var id: URL { bootURL }
    fileprivate var key: String { bootURL.path }

    /// The title without dump tags like "(USA)" or "[!]", and with "Legend of Zelda, The"
    /// turned back into "The Legend of Zelda".
    var displayTitle: String {
        var name = title.strippingTags
        for article in ["The", "A", "An"] where name.hasSuffix(", \(article)") {
            name = "\(article) " + name.dropLast(article.count + 2)
        }
        return name.isEmpty ? title : name
    }
}

extension String {
    /// Removes parenthesized and bracketed tags, e.g. "Contra (USA) [!]" → "Contra".
    var strippingTags: String {
        replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}

enum SidebarItem: Hashable {
    case favorites, recent, setup
    case system(GameSystem)

    /// The game lists, in the order the controller cycles through them.
    static let all: [SidebarItem] = [.favorites, .recent] + GameSystem.allCases.map(SidebarItem.system)

    var title: String {
        switch self {
        case .favorites: "Favorites"
        case .recent: "Recently Played"
        case .setup: "Setup"
        case .system(let system): system.displayName
        }
    }

    var symbol: String {
        switch self {
        case .favorites: "star.fill"
        case .recent: "clock.fill"
        case .setup: "wrench.and.screwdriver.fill"
        case .system(let system): system.symbol
        }
    }
}

@MainActor
final class Library: ObservableObject {
    private static let rootKey = "libraryRoot"
    private static let favoritesKey = "favorites"
    private static let lastPlayedKey = "lastPlayed"
    private static let recentLimit = 24
    /// The bundle ID RetroHub used to have; its settings are copied over once.
    private static let legacyDomain = "local.retrohub"

    @Published private(set) var root: URL
    @Published private(set) var games: [GameSystem: [Game]] = [:]
    @Published private(set) var favorites: Set<String>
    @Published private(set) var lastPlayed: [String: Date]
    @Published var launchError: String?

    init() {
        let defaults = UserDefaults.standard
        Self.migrateLegacySettings(into: defaults)
        if let path = defaults.string(forKey: Self.rootKey) {
            root = URL(filePath: path)
        } else {
            root = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Games")
        }
        favorites = Set(defaults.stringArray(forKey: Self.favoritesKey) ?? [])
        lastPlayed = defaults.dictionary(forKey: Self.lastPlayedKey) as? [String: Date] ?? [:]
        createFolders()
        rescan()
    }

    private static func migrateLegacySettings(into defaults: UserDefaults) {
        guard Bundle.main.bundleIdentifier != legacyDomain,
              let legacy = UserDefaults.standard.persistentDomain(forName: legacyDomain) else { return }
        for key in [rootKey, favoritesKey, lastPlayedKey] where defaults.object(forKey: key) == nil {
            if let value = legacy[key] {
                defaults.set(value, forKey: key)
            }
        }
    }

    func folder(for system: GameSystem) -> URL {
        system == .vita ? Self.vita3KAppsDir : root.appending(path: system.folderName)
    }

    /// Where Vita3K keeps installed games, one folder per title ID (its default storage location).
    static let vita3KAppsDir = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/Vita3K/Vita3K/ux0/app")

    func setRoot(_ url: URL) {
        root = url
        UserDefaults.standard.set(url.path, forKey: Self.rootKey)
        createFolders()
        rescan()
    }

    func createFolders() {
        for system in GameSystem.allCases where system != .vita {
            try? FileManager.default.createDirectory(at: folder(for: system), withIntermediateDirectories: true)
        }
    }

    func rescan() {
        games = Dictionary(uniqueKeysWithValues: GameSystem.allCases.map { system in
            (system, Self.scan(system, in: folder(for: system)))
        })
    }

    func games(for item: SidebarItem) -> [Game] {
        switch item {
        case .system(let system):
            return games[system] ?? []
        case .setup:
            return []
        case .favorites:
            return GameSystem.allCases.flatMap { games[$0] ?? [] }.filter { favorites.contains($0.key) }
        case .recent:
            let played = GameSystem.allCases.flatMap { games[$0] ?? [] }.filter { lastPlayed[$0.key] != nil }
            return Array(played.sorted { lastPlayed[$0.key]! > lastPlayed[$1.key]! }.prefix(Self.recentLimit))
        }
    }

    func isFavorite(_ game: Game) -> Bool {
        favorites.contains(game.key)
    }

    func toggleFavorite(_ game: Game) {
        if favorites.remove(game.key) == nil {
            favorites.insert(game.key)
        }
        UserDefaults.standard.set(Array(favorites), forKey: Self.favoritesKey)
    }

    func lastPlayed(_ game: Game) -> Date? {
        lastPlayed[game.key]
    }

    func play(_ game: Game) {
        do {
            try Launcher.launch(game)
            lastPlayed[game.key] = .now
            UserDefaults.standard.set(lastPlayed, forKey: Self.lastPlayedKey)
        } catch {
            launchError = error.localizedDescription
        }
    }

    static func scan(_ system: GameSystem, in folder: URL) -> [Game] {
        let games = switch system {
        case .ps3: scanPS3(folder)
        case .ps4: scanPS4(folder)
        case .vita: scanVita(folder)
        default: scanFiles(system, folder)
        }
        return games.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private static func scanFiles(_ system: GameSystem, _ folder: URL) -> [Game] {
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil,
                                                         options: [.skipsHiddenFiles]) else { return [] }
        return files.compactMap { $0 as? URL }
            .filter { system.fileExtensions.contains($0.pathExtension.lowercased()) }
            .map { url in
                let base = url.deletingPathExtension()
                return Game(system: system, title: base.lastPathComponent, bootURL: url,
                            localCovers: ["png", "jpg", "jpeg"].map { base.appendingPathExtension($0) })
            }
    }

    /// Disc dumps keep EBOOT.BIN under PS3_GAME/USRDIR; PSN games keep it under USRDIR.
    private static func scanPS3(_ folder: URL) -> [Game] {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                options: [.skipsHiddenFiles])) ?? []
        return dirs.compactMap { dir in
            let candidates = ["PS3_GAME/USRDIR/EBOOT.BIN", "USRDIR/EBOOT.BIN"].map { dir.appending(path: $0) }
            guard let eboot = candidates.first(where: { fm.fileExists(atPath: $0.path) }) else { return nil }
            let title = ["PS3_GAME/PARAM.SFO", "PARAM.SFO"].lazy
                .compactMap { sfoTitle(at: dir.appending(path: $0)) }
                .first ?? dir.lastPathComponent
            let covers = ["cover.png", "cover.jpg", "PS3_GAME/ICON0.PNG", "ICON0.PNG"].map { dir.appending(path: $0) }
            return Game(system: .ps3, title: title, bootURL: eboot, localCovers: covers)
        }
    }

    /// PS4 game dumps keep eboot.bin at the top of the folder and their details under sce_sys.
    private static func scanPS4(_ folder: URL) -> [Game] {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                options: [.skipsHiddenFiles])) ?? []
        return dirs.compactMap { dir in
            let eboot = dir.appending(path: "eboot.bin")
            guard fm.fileExists(atPath: eboot.path) else { return nil }
            let title = sfoTitle(at: dir.appending(path: "sce_sys/param.sfo")) ?? dir.lastPathComponent
            let covers = ["cover.png", "cover.jpg", "sce_sys/icon0.png"].map { dir.appending(path: $0) }
            return Game(system: .ps4, title: title, bootURL: eboot, localCovers: covers)
        }
    }

    /// Games installed in Vita3K: one folder per title ID, with details under sce_sys.
    private static func scanVita(_ folder: URL) -> [Game] {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                options: [.skipsHiddenFiles])) ?? []
        return dirs.compactMap { dir in
            let sfo = dir.appending(path: "sce_sys/param.sfo")
            guard fm.fileExists(atPath: sfo.path) else { return nil }
            return Game(system: .vita, title: sfoTitle(at: sfo) ?? dir.lastPathComponent, bootURL: dir,
                        localCovers: [dir.appending(path: "sce_sys/icon0.png")])
        }
    }

    /// Reads the TITLE entry from a PS3, PS4 or PS Vita PARAM.SFO file (little-endian key/value table).
    static func sfoTitle(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url), data.count >= 20,
              data.prefix(4) == Data([0x00, 0x50, 0x53, 0x46]) else { return nil }
        func u16(_ offset: Int) -> Int { Int(data[offset]) | Int(data[offset + 1]) << 8 }
        func u32(_ offset: Int) -> Int { u16(offset) | u16(offset + 2) << 16 }

        let keyTable = u32(8), dataTable = u32(12), count = u32(16)
        for index in 0..<count {
            let entry = 20 + index * 16
            // Checked before reading the entry: a damaged file can claim more entries than it holds.
            guard entry + 16 <= data.count else { return nil }
            let keyStart = keyTable + u16(entry)
            guard keyStart < data.count, let keyEnd = data[keyStart...].firstIndex(of: 0) else { return nil }
            guard String(decoding: data[keyStart..<keyEnd], as: UTF8.self) == "TITLE" else { continue }

            let start = dataTable + u32(entry + 12), length = u32(entry + 4)
            guard start + length <= data.count else { return nil }
            let title = String(decoding: data[start..<start + length], as: UTF8.self)
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces.union(.controlCharacters))
            return title.isEmpty ? nil : title
        }
        return nil
    }
}
