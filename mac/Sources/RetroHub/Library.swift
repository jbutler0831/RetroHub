import AppKit

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
    /// `check` is Library Check, shown from the banner and Setup; it isn't a sidebar row.
    case favorites, recent, setup, check
    case system(GameSystem)

    /// The sidebar, top to bottom: the lists and Setup, then each maker's systems under its name.
    static let sections: [(title: String?, items: [SidebarItem])] = [(nil, [.favorites, .recent, .setup])]
        + GameSystem.makers.map { maker in (maker, GameSystem.allCases.filter { $0.maker == maker }.map(SidebarItem.system)) }

    /// The game lists in sidebar order: what LB/RB and Next/Previous System step through.
    static let all: [SidebarItem] = sections.flatMap(\.items).filter { $0 != .setup }

    /// The item `step` places away in `items`, wrapping around at either end. From an item that
    /// isn't in `items`, such as Setup, a step forward lands on the first item and back on the last.
    static func stepping(from item: SidebarItem, by step: Int, in items: [SidebarItem]) -> SidebarItem? {
        guard !items.isEmpty else { return nil }
        let current = items.firstIndex(of: item) ?? (step > 0 ? -1 : 0)
        return items[((current + step) % items.count + items.count) % items.count]
    }

    var title: String {
        switch self {
        case .favorites: "Favorites"
        case .recent: "Recently Played"
        case .setup: "Setup"
        case .check: "Library Check"
        case .system(let system): system.displayName
        }
    }

    var symbol: String {
        switch self {
        case .favorites: "star.fill"
        case .recent: "clock.fill"
        case .setup: "wrench.and.screwdriver.fill"
        case .check: "arrow.triangle.2.circlepath"
        case .system(let system): system.symbol
        }
    }
}

/// What Library Check shows: the scanner's summary (Scanner.swift) and the games whose cover
/// was looked up and not found.
struct LibraryCheck {
    var summary = Scanner.Summary()
    var noArt: [Game] = []
    /// News since the last review, for the banner. Games still missing from before (an unplugged
    /// drive, say) stay listed without bringing the banner back.
    var newCount = 0, renamedCount = 0, newlyMissingCount = 0

    /// "2 new · 1 moved or renamed · 1 missing", or "" when nothing changed since the last review.
    var news: String {
        [newCount > 0 ? "\(newCount) new" : nil, renamedCount > 0 ? "\(renamedCount) moved or renamed" : nil,
         newlyMissingCount > 0 ? "\(newlyMissingCount) missing" : nil].compactMap { $0 }.joined(separator: " · ")
    }
}

/// A game started from RetroHub, and its emulator's process.
struct GameSession {
    let game: Game
    let process: Process
    let started: Date

    /// How soon an emulator closing counts as "straight away".
    static let quickExit: TimeInterval = 10

    enum Ending: Equatable {
        /// Closed after a while: the game was played.
        case played
        /// Closed straight away with an error or a crash: a missing BIOS, core or setting.
        case failed
        /// Closed straight away without one: usually handed the game to a copy already open.
        case handedOff
    }

    /// The same rule as the desktop app's endOfGame (desktop/src/emulators.js).
    static func ending(seconds: TimeInterval, status: Int32, crashed: Bool) -> Ending {
        guard seconds < quickExit else { return .played }
        return status == 0 && !crashed ? .handedOff : .failed
    }

    /// What RetroHub says when an emulator closes straight away with an error.
    static func failedMessage(label: String, status: Int32?, note: String?) -> String {
        "\(label) closed straight away\(status.map { " (exit code \($0))" } ?? ""). Open it on its own and load the game to see what it says."
            + (note.map { " \($0)" } ?? "")
    }
}

@MainActor
final class Library: ObservableObject {
    private static let rootKey = "libraryRoot"
    private static let favoritesKey = "favorites"
    private static let lastPlayedKey = "lastPlayed"
    private static let playtimeKey = "playtime"
    private static let recentLimit = 24
    /// The bundle ID RetroHub used to have; its settings are copied over once.
    private static let legacyDomain = "local.retrohub"
    /// The installed RetroHub's bundle ID, the only one that takes over the old settings.
    private static let releaseBundleID = "io.github.jbutler0831.retrohub"

    @Published private(set) var root: URL
    @Published private(set) var games: [GameSystem: [Game]] = [:]
    @Published private(set) var favorites: Set<String>
    @Published private(set) var lastPlayed: [String: Date]
    /// Time played per game path (Playtime.swift).
    @Published private(set) var playtime: [String: Playtime] = [:]
    private var terminationObserver: NSObjectProtocol?
    @Published var launchError: String?
    /// The game RetroHub started, while its emulator runs. Not set for OpenEmu, which macOS opens
    /// and which stays open after the game.
    @Published private(set) var session: GameSession?
    /// What the Smart Game Scanner found, for the banner and Library Check.
    @Published private(set) var check = LibraryCheck()

    /// What the scanner has seen and when the changes were last reviewed, in Application Support,
    /// named after the app like the cover cache, so RetroHub Dev keeps its own.
    private struct ScannerState: Codable {
        var index: Scanner.Index?
        var reviewedAt: Double = 0
    }
    private static let scannerFile = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "RetroHub")
        .appending(path: "library.json")
    private var scanner = ScannerState()
    private var savedScanner: Data?
    private var fingerprinting = false

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
        if let data = defaults.data(forKey: Self.playtimeKey), let saved = try? JSONDecoder().decode([String: Playtime].self, from: data) {
            playtime = saved
        }
        if let data = try? Data(contentsOf: Self.scannerFile), let saved = try? JSONDecoder().decode(ScannerState.self, from: data) {
            scanner = saved
            savedScanner = data
        }
        createFolders()
        rescan()
        // Quitting RetroHub mid-game keeps the time played so far (the emulator keeps running).
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                                                     object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let session = self.session else { return }
                self.recordPlaytime(session)
                self.session = nil
            }
        }
    }

    /// Development copies (RetroHub Dev, RetroHub Dev Check) keep their own settings: given the old
    /// ones, they showed the Mac's real favorites and recents, and the window checks failed.
    static func takesLegacySettings(bundleID: String?) -> Bool {
        bundleID == releaseBundleID
    }

    private static func migrateLegacySettings(into defaults: UserDefaults) {
        guard takesLegacySettings(bundleID: Bundle.main.bundleIdentifier),
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

    /// Counts rescans, so the results of an older one that finishes late are dropped.
    private var scanGeneration = 0

    /// Looks for games off the main thread, so a large library (or a network drive) doesn't stall
    /// the window; RetroHub rescans each time it comes forward. The results arrive a moment later.
    func rescan() {
        scanGeneration += 1
        let generation = scanGeneration
        let folders = GameSystem.allCases.map { ($0, folder(for: $0)) }
        Task.detached(priority: .userInitiated) {
            let found = Dictionary(uniqueKeysWithValues: folders.map { system, folder in (system, Library.scan(system, in: folder)) })
            // Each game's size and date for the scanner, and whether its cover was looked for and not
            // found: file checks too, so they're done here as well.
            let all = found.values.flatMap { $0 }
            let stats = Dictionary(uniqueKeysWithValues: all.compactMap { game in
                Scanner.statFile(game.bootURL.path).map { (game.bootURL.path, $0) }
            })
            let noArt = Set(all.filter(CoverArt.knownMissing).map(\.bootURL.path))
            await self.scanned(found, stats: stats, noArt: noArt, generation: generation)
        }
    }

    /// Paths of the games whose cover was looked for and not found, from the last scan.
    private var noArtPaths: Set<String> = []

    private func scanned(_ found: [GameSystem: [Game]], stats: [String: Scanner.FileInfo], noArt: Set<String>, generation: Int) {
        guard generation == scanGeneration else { return }
        games = found
        noArtPaths = noArt
        let now = Date.now.timeIntervalSince1970 * 1000
        // The first scan is the baseline: what's there already isn't news.
        if scanner.index == nil { scanner.reviewedAt = now }
        scanner.index = Scanner.updateIndex(scanner.index, games: GameSystem.allCases.flatMap { games[$0] ?? [] }, now: now,
                                            stat: { stats[$0] })
        saveScanner()
        refreshCheck()
        fingerprintInBackground()
    }

    // MARK: Smart Game Scanner

    /// Saves the index; RetroHub rescans each time it comes forward, so only when it changed.
    private func saveScanner() {
        guard let data = try? JSONEncoder().encode(scanner), data != savedScanner else { return }
        try? FileManager.default.createDirectory(at: Self.scannerFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.scannerFile, options: .atomic)
        savedScanner = data
    }

    private func refreshCheck() {
        let summary = Scanner.summarize(scanner.index ?? [:], reviewedAt: scanner.reviewedAt)
        check = LibraryCheck(summary: summary,
                             noArt: GameSystem.allCases.flatMap { games[$0] ?? [] }.filter { noArtPaths.contains($0.key) },
                             newCount: summary.added.count, renamedCount: summary.renamed.count,
                             newlyMissingCount: summary.missing.filter { $0.since > scanner.reviewedAt }.count)
    }

    /// Fingerprints new and changed files off the main thread after a scan, then updates Library Check.
    private func fingerprintInBackground() {
        guard !fingerprinting, let index = scanner.index else { return }
        let paths = Scanner.needsFingerprint(index)
        guard !paths.isEmpty else { return }
        fingerprinting = true
        Task.detached(priority: .utility) {
            var found: [String: String] = [:]
            for path in paths {
                if let fp = try? Scanner.fingerprint(path) { found[path] = fp }
            }
            await self.fingerprinted(found, as: index)
        }
    }

    private func fingerprinted(_ found: [String: String], as before: Scanner.Index) {
        fingerprinting = false
        for (path, fp) in found {
            // Only if the file is still the one fingerprinted: a rescan may have replaced the entry.
            guard let entry = scanner.index?[path], entry.size == before[path]?.size, entry.mtime == before[path]?.mtime else { continue }
            scanner.index?[path]?.fp = fp
        }
        saveScanner()
        refreshCheck()
        fingerprintInBackground()
    }

    func isFavorite(path: String) -> Bool { favorites.contains(path) }
    func lastPlayed(path: String) -> Date? { lastPlayed[path] }

    /// Confirms a rename: the game's favorite and play history move to its new path.
    func applyRename(from: String, to: String) {
        guard scanner.index?[from]?.missingSince != nil, let target = scanner.index?[to], target.missingSince == nil else { return }
        if favorites.remove(from) != nil { favorites.insert(to) }
        if let played = lastPlayed.removeValue(forKey: from) { lastPlayed[to] = max(lastPlayed[to] ?? played, played) }
        playtime = Playtime.moving(playtime, from: from, to: to)
        scanner.index?[from] = nil
        saveGameState()
    }

    /// "Not the same game": the old one stays missing.
    func notRenamed(from: String) {
        guard scanner.index?[from]?.missingSince != nil else { return }
        scanner.index?[from]?.notRenamed = true
        saveScanner()
        refreshCheck()
    }

    /// Forgets missing games: their index entries, favorites and play history.
    func removeMissing(_ paths: [String]) {
        for path in paths where scanner.index?[path]?.missingSince != nil {
            scanner.index?[path] = nil
            favorites.remove(path)
            lastPlayed[path] = nil
            playtime[path] = nil
        }
        saveGameState()
    }

    func markReviewed() {
        scanner.reviewedAt = Date.now.timeIntervalSince1970 * 1000
        saveScanner()
        refreshCheck()
    }

    /// Looks for the covers that weren't found again, next time they're shown.
    func lookAgainForCovers() {
        check.noArt.forEach(CoverArt.forgetMiss)
        noArtPaths.removeAll()
        refreshCheck()
    }

    /// Shows a file in the Finder: only one RetroHub knows about, such as a duplicate.
    func showInFinder(path: String) {
        guard let entry = scanner.index?[path], entry.missingSince == nil else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
    }

    private func saveGameState() {
        UserDefaults.standard.set(Array(favorites), forKey: Self.favoritesKey)
        UserDefaults.standard.set(lastPlayed, forKey: Self.lastPlayedKey)
        savePlaytime()
        saveScanner()
        refreshCheck()
    }

    func games(for item: SidebarItem) -> [Game] {
        switch item {
        case .system(let system):
            return games[system] ?? []
        case .setup, .check:
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
        // One game at a time: A pressed again while the emulator starts, or while it's open behind
        // RetroHub, brings it forward instead of starting a second copy.
        if let session, session.process.isRunning {
            NSRunningApplication(processIdentifier: session.process.processIdentifier)?.activate()
            return
        }
        do {
            let process = try Launcher.launch(game) { process in
                DispatchQueue.main.async { MainActor.assumeIsolated { self.ended(process) } }
            }
            if let process, process.isRunning {
                session = GameSession(game: game, process: process, started: .now)
            }
            lastPlayed[game.key] = .now
            UserDefaults.standard.set(lastPlayed, forKey: Self.lastPlayedKey)
        } catch {
            launchError = error.localizedDescription
        }
    }

    /// RetroHub comes back to the front when the game is closed, including from another Space
    /// while couch mode is full screen. macOS doesn't allow it if you've moved on to another app.
    /// When the emulator closes, RetroHub comes back to the front, and says why if it closed
    /// straight away with an error. If it closed straight away without one, it most likely handed
    /// the game to a copy that was already open, so RetroHub stays out of the way.
    private func ended(_ process: Process) {
        guard let session, session.process === process else { return }
        recordPlaytime(session)
        self.session = nil
        let crashed = process.terminationReason == .uncaughtSignal
        switch GameSession.ending(seconds: Date.now.timeIntervalSince(session.started), status: process.terminationStatus, crashed: crashed) {
        case .handedOff:
            return
        case .played:
            NSApp.activate()
        case .failed:
            NSApp.activate()
            launchError = GameSession.failedMessage(label: Launcher.label(for: session.game.system) ?? "The emulator",
                                                    status: crashed ? nil : process.terminationStatus, note: session.game.system.setupNote)
        }
    }

    /// Adds a session's time to its game's play time (sessions under 10 seconds don't count).
    private func recordPlaytime(_ session: GameSession) {
        playtime = Playtime.adding(playtime, session.game.key, seconds: Date.now.timeIntervalSince(session.started))
        savePlaytime()
    }

    private func savePlaytime() {
        UserDefaults.standard.set(try? JSONEncoder().encode(playtime), forKey: Self.playtimeKey)
    }

    func playtime(_ game: Game) -> Int { playtime[game.key]?.seconds ?? 0 }
    func playtime(path: String) -> Int { playtime[path]?.seconds ?? 0 }

    nonisolated static func scan(_ system: GameSystem, in folder: URL) -> [Game] {
        let games = switch system {
        case .ps3: scanPS3(folder)
        case .ps4: scanPS4(folder)
        case .vita: scanVita(folder)
        default: scanFiles(system, folder)
        }
        return games.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    nonisolated private static func scanFiles(_ system: GameSystem, _ folder: URL) -> [Game] {
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
    nonisolated private static func scanPS3(_ folder: URL) -> [Game] {
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
    nonisolated private static func scanPS4(_ folder: URL) -> [Game] {
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
    nonisolated private static func scanVita(_ folder: URL) -> [Game] {
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
    nonisolated static func sfoTitle(at url: URL) -> String? {
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
