import AppKit

enum GameSystem: String, CaseIterable, Identifiable {
    case nes, snes, n64, gamecube, wii, wiiu, gb, gbc, gba, ds, n3ds
    case masterSystem, genesis, segaCD, sega32x, saturn, dreamcast, gameGear
    case ps1, ps2, ps3, ps4, psp, vita, xbox, pce, neoGeo, atari2600, arcade

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nes: "NES"
        case .snes: "Super Nintendo"
        case .n64: "Nintendo 64"
        case .gamecube: "GameCube"
        case .wii: "Wii"
        case .wiiu: "Wii U"
        case .gb: "Game Boy"
        case .gbc: "Game Boy Color"
        case .gba: "Game Boy Advance"
        case .ds: "Nintendo DS"
        case .n3ds: "Nintendo 3DS"
        case .masterSystem: "Master System"
        case .genesis: "Sega Genesis"
        case .segaCD: "Sega CD"
        case .sega32x: "Sega 32X"
        case .saturn: "Sega Saturn"
        case .dreamcast: "Dreamcast"
        case .gameGear: "Game Gear"
        case .ps1: "PlayStation"
        case .ps2: "PlayStation 2"
        case .ps3: "PlayStation 3"
        case .ps4: "PlayStation 4"
        case .psp: "PSP"
        case .vita: "PS Vita"
        case .xbox: "Xbox"
        case .pce: "TurboGrafx-16"
        case .neoGeo: "Neo Geo"
        case .atari2600: "Atari 2600"
        case .arcade: "Arcade"
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
        case .wiiu: "WiiU"
        case .gb: "GB"
        case .gbc: "GBC"
        case .gba: "GBA"
        case .ds: "DS"
        case .n3ds: "3DS"
        case .masterSystem: "MasterSystem"
        case .genesis: "Genesis"
        case .segaCD: "SegaCD"
        case .sega32x: "32X"
        case .saturn: "Saturn"
        case .dreamcast: "Dreamcast"
        case .gameGear: "GameGear"
        case .ps1: "PS1"
        case .ps2: "PS2"
        case .ps3: "PS3"
        case .ps4: "PS4"
        case .psp: "PSP"
        case .vita: "Vita"
        case .xbox: "Xbox"
        case .pce: "TurboGrafx16"
        case .neoGeo: "NeoGeo"
        case .atari2600: "Atari2600"
        case .arcade: "Arcade"
        }
    }

    /// PS3 and PS4 games are folders and PS Vita games live in Vita3K, so they have no extensions.
    var fileExtensions: Set<String> {
        switch self {
        case .nes: ["nes"]
        case .snes: ["sfc", "smc"]
        case .n64: ["z64", "n64", "v64"]
        case .gamecube: ["iso", "gcm", "rvz", "ciso"]
        case .wii: ["wbfs", "iso", "rvz", "wad"]
        case .wiiu: ["wua", "wud", "wux", "rpx"]
        case .gb: ["gb"]
        case .gbc: ["gbc"]
        case .gba: ["gba"]
        case .ds: ["nds"]
        case .n3ds: ["3ds", "cci", "cxi", "3dsx"]
        case .masterSystem: ["sms"]
        case .genesis: ["md", "gen", "smd"]
        case .segaCD: ["cue", "chd"]
        case .sega32x: ["32x"]
        case .saturn: ["cue", "chd"]
        case .dreamcast: ["chd", "gdi", "cdi"]
        case .gameGear: ["gg"]
        case .ps1: ["cue", "chd", "pbp"]
        case .ps2: ["iso", "chd", "cso"]
        case .ps3, .ps4, .vita: []
        case .psp: ["iso", "cso", "pbp", "chd"]
        case .xbox: ["iso", "xiso"]
        case .pce: ["pce", "sgx"]
        case .neoGeo, .arcade: ["zip", "7z"]
        case .atari2600: ["a26", "bin"]
        }
    }

    var fileHint: String {
        switch self {
        case .ps1: ".cue (with its .bin files), .chd or .pbp files"
        case .xbox: "XISO-format .iso files"
        case .ps3: "game folders (each containing PS3_GAME or USRDIR)"
        case .ps4: "game folders (each containing eboot.bin and sce_sys)"
        case .vita: "games installed in Vita3K (File › Install .pkg or .vpk); they show up here"
        case .segaCD, .saturn: ".cue (with its .bin files) or .chd files"
        case .neoGeo, .arcade: "FinalBurn Neo ROM sets (.zip), named as the emulator expects"
        default: fileExtensions.sorted().map { "." + $0 }.formatted(.list(type: .or)) + " files"
        }
    }

    var symbol: String {
        switch self {
        case .nes, .snes, .genesis, .masterSystem, .segaCD, .sega32x, .pce, .atari2600: "gamecontroller"
        case .n64, .gamecube, .wii, .wiiu, .saturn, .dreamcast: "gamecontroller.fill"
        case .gameGear: "rectangle.portrait"
        case .n3ds: "rectangle.split.1x2"
        case .neoGeo, .arcade: "arcade.stick"
        case .gb, .gbc, .gba: "rectangle.portrait"
        case .ds: "rectangle.split.1x2"
        case .ps1, .ps2, .ps3, .ps4, .psp, .vita: "playstation.logo"
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
        case .wiiu: [.app(.cemu, arguments: ["-g"])]
        case .gb, .gbc: [.retroArch([Core("gambatte", "Gambatte"), Core("sameboy", "SameBoy"), Core("mgba", "mGBA")]), .openEmu]
        case .gba: [.retroArch([Core("mgba", "mGBA"), Core("vba_next", "VBA Next")]), .openEmu]
        case .ds: [.app(.melonDS, arguments: []), .retroArch([Core("melonds", "melonDS"), Core("desmume", "DeSmuME")]), .openEmu]
        case .n3ds: [.app(.azahar, arguments: []), .retroArch([Core("azahar", "Azahar")])]
        case .genesis, .masterSystem, .segaCD:
            [.retroArch([Core("genesis_plus_gx", "Genesis Plus GX"), Core("picodrive", "PicoDrive")]), .openEmu]
        case .sega32x: [.retroArch([Core("picodrive", "PicoDrive")]), .openEmu]
        case .gameGear: [.retroArch([Core("genesis_plus_gx", "Genesis Plus GX"), Core("gearsystem", "Gearsystem")]), .openEmu]
        case .saturn: [.retroArch([Core("mednafen_saturn", "Beetle Saturn"), Core("yabasanshiro", "YabaSanshiro")]), .openEmu]
        case .dreamcast: [.retroArch([Core("flycast", "Flycast")])]
        case .ps1: [.retroArch([Core("swanstation", "SwanStation"), Core("pcsx_rearmed", "PCSX ReARMed"), Core("mednafen_psx", "Beetle PSX")]), .openEmu]
        case .ps2: [.app(.pcsx2, arguments: ["-batch", "--"])]
        case .ps3: [.app(.rpcs3, arguments: ["--no-gui"])]
        case .ps4: [.app(.shadPS4, arguments: ["-g"])]
        case .psp: [.app(.ppsspp, arguments: []), .retroArch([Core("ppsspp", "PPSSPP")]), .openEmu]
        case .vita: [.app(.vita3k, arguments: ["-r"])]
        case .xbox: [.app(.xemu, arguments: ["-dvd_path"])]
        case .pce: [.retroArch([Core("mednafen_pce_fast", "Beetle PCE Fast"), Core("mednafen_pce", "Beetle PCE")]), .openEmu]
        case .neoGeo, .arcade: [.retroArch([Core("fbneo", "FinalBurn Neo")])]
        case .atari2600: [.retroArch([Core("stella", "Stella"), Core("stella2014", "Stella 2014")]), .openEmu]
        }
    }

    /// Extra setup the emulator needs before games will boot.
    var setupNote: String? {
        switch self {
        case .ps1: "Needs a PS1 BIOS dumped from your console."
        case .ps2: "PCSX2 needs a BIOS dumped from your PS2; it asks for it on first launch."
        case .ps3: "Install the PS3 firmware in RPCS3 (File › Install Firmware) first."
        case .ps4: "shadPS4 is early: many games don't run yet. Some need firmware modules from your own PS4."
        case .xbox: "Set up your BIOS, MCPX boot ROM and hard disk image in xemu's settings first."
        case .segaCD: "Needs a Sega CD BIOS dumped from your console."
        case .saturn: "Needs a Saturn BIOS dumped from your console."
        case .dreamcast: "Most games need Dreamcast BIOS files (dc_boot.bin, dc_flash.bin) from your console."
        case .neoGeo: "Put neogeo.zip (the Neo Geo BIOS) in the same folder as your games."
        case .n3ds: "Azahar plays decrypted games only."
        case .wiiu: "Disc dumps (.wud/.wux) need your console's keys in Cemu's keys.txt; .wua files don't."
        case .vita: "Install the PS Vita firmware in Vita3K first, then install your games there."
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
    case openEmu, retroArch, dolphin, cemu, melonDS, azahar, pcsx2, rpcs3, shadPS4, ppsspp, vita3k, xemu

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openEmu: "OpenEmu"
        case .retroArch: "RetroArch"
        case .dolphin: "Dolphin"
        case .cemu: "Cemu"
        case .melonDS: "melonDS"
        case .azahar: "Azahar"
        case .pcsx2: "PCSX2"
        case .rpcs3: "RPCS3"
        case .shadPS4: "shadPS4"
        case .ppsspp: "PPSSPP"
        case .vita3k: "Vita3K"
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
        case .cemu: URL(string: "https://cemu.info")!
        case .melonDS: URL(string: "https://melonds.kuribo64.net/downloads.php")!
        case .azahar: URL(string: "https://azahar-emu.org")!
        case .pcsx2: URL(string: "https://pcsx2.net/downloads")!
        case .rpcs3: URL(string: "https://rpcs3.net/download")!
        case .shadPS4: URL(string: "https://github.com/shadps4-emu/shadPS4/releases/latest")!
        case .ppsspp: URL(string: "https://www.ppsspp.org/download/")!
        case .vita3k: URL(string: "https://vita3k.org")!
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
        if self == .shadPS4 { return shadPS4URL }
        return appURL.flatMap { Bundle(url: $0)?.executableURL }
    }

    /// shadPS4's Mac download is a plain program with its libraries rather than an app, so it is
    /// looked for in a shadPS4 folder inside Applications.
    private var shadPS4URL: URL? {
        let fm = FileManager.default
        return [URL(filePath: "/Applications"), fm.homeDirectoryForCurrentUser.appending(path: "Applications")]
            .map { $0.appending(path: "shadPS4/shadps4") }
            .first { fm.isExecutableFile(atPath: $0.path) }
    }

    var isInstalled: Bool { executableURL != nil || appURL != nil }

    /// Extra install steps for emulators that don't come as a regular Mac app.
    var installNote: String? {
        switch self {
        case .shadPS4: "Unzip the macOS download into a folder named shadPS4 in Applications, then right-click shadps4 › Open once so macOS allows it. It's an Intel app, so Apple silicon Macs need Rosetta."
        default: nil
        }
    }
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
        /// Starts the game; returns the emulator's process, or nil when macOS opened it (OpenEmu).
        let start: (URL, @escaping @Sendable (Process) -> Void) throws -> Process?
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
                    try start(exe, ["-L", url.path] + RetroArchGraphics.arguments(for: system, core: core) + [$0.path], onExit: $1)
                }
            case .openEmu:
                guard let app = Emulator.openEmu.appURL else { continue }
                return Plan(label: "OpenEmu") { url, _ in
                    NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                    return nil
                }
            case .app(let emulator, let arguments):
                guard let exe = emulator.executableURL else { continue }
                // Vita3K runs installed games by title ID, the name of the game's folder.
                let target: (URL) -> String = emulator == .vita3k ? { $0.lastPathComponent } : { $0.path }
                return Plan(label: emulator.displayName) { try start(exe, arguments + [target($0)], onExit: $1) }
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
                         detail: (["Install \(emulators) to play \(system.displayName) games."]
                                  + system.backends.compactMap(\.emulator.installNote)).joined(separator: " "),
                         missing: system.backends.first?.emulator)
    }

    /// Starts the game and returns the emulator's process, or nil when macOS opened the emulator
    /// (OpenEmu, which stays open as a library app after the game). `onExit` runs on a background
    /// thread when the process ends.
    static func launch(_ game: Game, onExit: @escaping @Sendable (Process) -> Void) throws -> Process? {
        guard let plan = plan(for: game.system) else {
            throw LaunchError.notReady(readiness(for: game.system).detail ?? "No emulator is set up for this system.")
        }
        return try plan.start(game.bootURL, onExit)
    }

    static func start(_ executable: URL, _ arguments: [String], onExit: @escaping @Sendable (Process) -> Void) throws -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        // Set before run(), so a process that quits straight away still reports it.
        process.terminationHandler = onExit
        try process.run()
        return process
    }
}
