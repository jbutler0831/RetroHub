import AppKit

enum GameSystem: String, CaseIterable, Identifiable {
    case nes, snes, n64, gamecube, wii, gb, gbc, gba, ds, genesis, ps1, ps2, ps3, psp, xbox

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nes: "NES"
        case .snes: "Super Nintendo"
        case .n64: "Nintendo 64"
        case .gamecube: "GameCube"
        case .wii: "Wii"
        case .gb: "Game Boy"
        case .gbc: "Game Boy Color"
        case .gba: "Game Boy Advance"
        case .ds: "Nintendo DS"
        case .genesis: "Sega Genesis"
        case .ps1: "PlayStation"
        case .ps2: "PlayStation 2"
        case .ps3: "PlayStation 3"
        case .psp: "PSP"
        case .xbox: "Xbox"
        }
    }

    /// Subfolder of the library root that holds this system's games.
    var folderName: String {
        switch self {
        case .nes: "NES"
        case .snes: "SNES"
        case .n64: "N64"
        case .gamecube: "GameCube"
        case .wii: "Wii"
        case .gb: "GB"
        case .gbc: "GBC"
        case .gba: "GBA"
        case .ds: "DS"
        case .genesis: "Genesis"
        case .ps1: "PS1"
        case .ps2: "PS2"
        case .ps3: "PS3"
        case .psp: "PSP"
        case .xbox: "Xbox"
        }
    }

    /// PS3 games are folders rather than single files, so it has no extensions.
    var fileExtensions: Set<String> {
        switch self {
        case .nes: ["nes"]
        case .snes: ["sfc", "smc"]
        case .n64: ["z64", "n64", "v64"]
        case .gamecube: ["iso", "gcm", "rvz", "ciso"]
        case .wii: ["wbfs", "iso", "rvz", "wad"]
        case .gb: ["gb"]
        case .gbc: ["gbc"]
        case .gba: ["gba"]
        case .ds: ["nds"]
        case .genesis: ["md", "gen", "smd"]
        case .ps1: ["cue", "chd", "pbp"]
        case .ps2: ["iso", "chd", "cso"]
        case .ps3: []
        case .psp: ["iso", "cso", "pbp", "chd"]
        case .xbox: ["iso", "xiso"]
        }
    }

    var fileHint: String {
        switch self {
        case .ps1: ".cue (with its .bin files), .chd or .pbp files"
        case .xbox: "XISO-format .iso files"
        case .ps3: "game folders (each containing PS3_GAME or USRDIR)"
        default: fileExtensions.sorted().map { "." + $0 }.formatted(.list(type: .or)) + " files"
        }
    }

    var symbol: String {
        switch self {
        case .nes, .snes, .genesis: "gamecontroller"
        case .n64, .gamecube, .wii: "gamecontroller.fill"
        case .gb, .gbc, .gba: "rectangle.portrait"
        case .ds: "rectangle.split.1x2"
        case .ps1, .ps2, .ps3, .psp: "playstation.logo"
        case .xbox: "xbox.logo"
        }
    }

    /// Ways to play this system, most preferred first. The first one installed is used.
    var backends: [Backend] {
        switch self {
        case .nes: [.retroArch([Core("mesen", "Mesen"), Core("fceumm", "FCEUmm"), Core("nestopia", "Nestopia")]), .openEmu]
        case .snes: [.retroArch([Core("snes9x", "Snes9x"), Core("bsnes", "bsnes")]), .openEmu]
        case .n64: [.retroArch([Core("mupen64plus_next", "Mupen64Plus-Next"), Core("parallel_n64", "ParaLLEl N64")]), .openEmu]
        case .gamecube, .wii: [.app(.dolphin, arguments: ["-b", "-e"])]
        case .gb, .gbc: [.retroArch([Core("gambatte", "Gambatte"), Core("sameboy", "SameBoy"), Core("mgba", "mGBA")]), .openEmu]
        case .gba: [.retroArch([Core("mgba", "mGBA"), Core("vba_next", "VBA Next")]), .openEmu]
        case .ds: [.app(.melonDS, arguments: []), .retroArch([Core("melonds", "melonDS"), Core("desmume", "DeSmuME")]), .openEmu]
        case .genesis: [.retroArch([Core("genesis_plus_gx", "Genesis Plus GX"), Core("picodrive", "PicoDrive")]), .openEmu]
        case .ps1: [.retroArch([Core("swanstation", "SwanStation"), Core("pcsx_rearmed", "PCSX ReARMed"), Core("mednafen_psx", "Beetle PSX")]), .openEmu]
        case .ps2: [.app(.pcsx2, arguments: ["-batch", "--"])]
        case .ps3: [.app(.rpcs3, arguments: ["--no-gui"])]
        case .psp: [.app(.ppsspp, arguments: []), .retroArch([Core("ppsspp", "PPSSPP")]), .openEmu]
        case .xbox: [.app(.xemu, arguments: ["-dvd_path"])]
        }
    }

    /// Extra setup the emulator needs before games will boot.
    var setupNote: String? {
        switch self {
        case .ps1: "Needs a PS1 BIOS dumped from your console."
        case .ps2: "PCSX2 needs a BIOS dumped from your PS2; it asks for it on first launch."
        case .ps3: "Install the PS3 firmware in RPCS3 (File › Install Firmware) first."
        case .xbox: "Set up your BIOS, MCPX boot ROM and hard disk image in xemu's settings first."
        default: nil
        }
    }
}

struct Core {
    let id: String
    let file: String
    let name: String

    init(_ id: String, _ name: String) {
        self.id = id
        file = "\(id)_libretro.dylib"
        self.name = name
    }
}

enum Backend {
    case retroArch([Core])
    case openEmu
    /// A standalone emulator; the game path is appended after `arguments`.
    case app(Emulator, arguments: [String])

    var emulator: Emulator {
        switch self {
        case .retroArch: .retroArch
        case .openEmu: .openEmu
        case .app(let emulator, _): emulator
        }
    }
}

enum Emulator: String, CaseIterable, Identifiable {
    case openEmu, retroArch, dolphin, melonDS, pcsx2, rpcs3, ppsspp, xemu

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openEmu: "OpenEmu"
        case .retroArch: "RetroArch"
        case .dolphin: "Dolphin"
        case .melonDS: "melonDS"
        case .pcsx2: "PCSX2"
        case .rpcs3: "RPCS3"
        case .ppsspp: "PPSSPP"
        case .xemu: "xemu"
        }
    }

    var covers: String {
        GameSystem.allCases
            .filter { $0.backends.contains { $0.emulator == self } }
            .map(\.folderName)
            .joined(separator: ", ")
    }

    private var appNames: [String] {
        switch self {
        case .ppsspp: ["PPSSPPSDL.app", "PPSSPP.app"]
        default: ["\(displayName).app"]
        }
    }

    var downloadURL: URL {
        switch self {
        case .openEmu: URL(string: "https://openemu.org")!
        case .retroArch: URL(string: "https://www.retroarch.com/?page=platforms")!
        case .dolphin: URL(string: "https://dolphin-emu.org/download/")!
        case .melonDS: URL(string: "https://melonds.kuribo64.net/downloads.php")!
        case .pcsx2: URL(string: "https://pcsx2.net/downloads")!
        case .rpcs3: URL(string: "https://rpcs3.net/download")!
        case .ppsspp: URL(string: "https://www.ppsspp.org/download/")!
        case .xemu: URL(string: "https://xemu.app/docs/download/")!
        }
    }

    var appURL: URL? {
        let fm = FileManager.default
        let dirs = [URL(filePath: "/Applications"), fm.homeDirectoryForCurrentUser.appending(path: "Applications")]
        return dirs.flatMap { dir in appNames.map { dir.appending(path: $0) } }
            .first { fm.fileExists(atPath: $0.path) }
    }

    var executableURL: URL? {
        appURL.flatMap { Bundle(url: $0)?.executableURL }
    }

    var isInstalled: Bool { appURL != nil }
}

enum LaunchError: LocalizedError {
    case notReady(String)

    var errorDescription: String? {
        switch self {
        case .notReady(let message): message
        }
    }
}

enum Launcher {
    static let retroArchCoresDir = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/RetroArch/cores")

    private struct Plan {
        let label: String
        let start: (URL) throws -> Void
    }

    /// The first installed backend for this system, ready to start a game.
    private static func plan(for system: GameSystem) -> Plan? {
        for backend in system.backends {
            switch backend {
            case .retroArch(let cores):
                guard let exe = Emulator.retroArch.executableURL,
                      let core = cores.first(where: { coreURL($0) != nil }),
                      let url = coreURL(core) else { continue }
                return Plan(label: "RetroArch (\(core.name))") {
                    try run(exe, ["-L", url.path] + RetroArchGraphics.arguments(for: system, core: core) + [$0.path])
                }
            case .openEmu:
                guard let app = Emulator.openEmu.appURL else { continue }
                return Plan(label: "OpenEmu") {
                    NSWorkspace.shared.open([$0], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                }
            case .app(let emulator, let arguments):
                guard let exe = emulator.executableURL else { continue }
                return Plan(label: emulator.displayName) { try run(exe, arguments + [$0.path]) }
            }
        }
        return nil
    }

    private static func coreURL(_ core: Core) -> URL? {
        let url = retroArchCoresDir.appending(path: core.file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    struct Readiness {
        let ready: Bool
        /// Short status, e.g. "Plays with Dolphin" or "Setup needed".
        let summary: String
        let detail: String?
        /// The emulator to download when nothing that plays this system is installed.
        let missing: Emulator?
    }

    static func readiness(for system: GameSystem) -> Readiness {
        if let plan = plan(for: system) {
            return Readiness(ready: true, summary: "Plays with \(plan.label)", detail: system.setupNote, missing: nil)
        }
        for case .retroArch(let cores) in system.backends where Emulator.retroArch.isInstalled {
            let names = cores.map(\.name).formatted(.list(type: .or))
            return Readiness(ready: false, summary: "Setup needed",
                             detail: "RetroArch needs the \(names) core. In RetroArch open Main Menu › Online Updater › Core Downloader and install it.",
                             missing: nil)
        }
        let emulators = system.backends.map(\.emulator.displayName).formatted(.list(type: .or))
        return Readiness(ready: false, summary: "Setup needed",
                         detail: "Install \(emulators) to play \(system.displayName) games.",
                         missing: system.backends.first?.emulator)
    }

    static func launch(_ game: Game) throws {
        guard let plan = plan(for: game.system) else {
            throw LaunchError.notReady(readiness(for: game.system).detail ?? "No emulator is set up for this system.")
        }
        try plan.start(game.bootURL)
    }

    private static func run(_ executable: URL, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        try process.run()
    }
}
