import Foundation

struct Game: Identifiable, Hashable {
    let system: GameSystem
    let title: String
    /// The file handed to the emulator: the ROM/ISO itself, or a PS3 game's EBOOT.BIN.
    let bootURL: URL
    /// Images that override downloaded cover art, in order of preference.
    let localCovers: [URL]

    var id: URL { bootURL }
}

@MainActor
final class Library: ObservableObject {
    private static let rootKey = "libraryRoot"

    @Published private(set) var root: URL
    @Published private(set) var games: [GameSystem: [Game]] = [:]
    @Published var launchError: String?

    init() {
        if let path = UserDefaults.standard.string(forKey: Self.rootKey) {
            root = URL(filePath: path)
        } else {
            root = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Games")
        }
        createFolders()
        rescan()
    }

    func folder(for system: GameSystem) -> URL {
        root.appending(path: system.folderName)
    }

    func setRoot(_ url: URL) {
        root = url
        UserDefaults.standard.set(url.path, forKey: Self.rootKey)
        createFolders()
        rescan()
    }

    func createFolders() {
        for system in GameSystem.allCases {
            try? FileManager.default.createDirectory(at: folder(for: system), withIntermediateDirectories: true)
        }
    }

    func rescan() {
        games = Dictionary(uniqueKeysWithValues: GameSystem.allCases.map { system in
            (system, Self.scan(system, in: folder(for: system)))
        })
    }

    func play(_ game: Game) {
        do {
            try Launcher.launch(game)
        } catch {
            launchError = error.localizedDescription
        }
    }

    private static func scan(_ system: GameSystem, in folder: URL) -> [Game] {
        let games = system == .ps3 ? scanPS3(folder) : scanFiles(system, folder)
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
            let covers = ["cover.png", "cover.jpg", "PS3_GAME/ICON0.PNG", "ICON0.PNG"].map { dir.appending(path: $0) }
            return Game(system: .ps3, title: dir.lastPathComponent, bootURL: eboot, localCovers: covers)
        }
    }
}
