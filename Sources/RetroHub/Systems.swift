import AppKit

enum GameSystem: String, CaseIterable, Identifiable {
    case nes, snes, n64, xbox, ps3

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nes: "NES"
        case .snes: "Super Nintendo"
        case .n64: "Nintendo 64"
        case .xbox: "Xbox"
        case .ps3: "PlayStation 3"
        }
    }

    /// Subfolder of the library root that holds this system's games.
    var folderName: String {
        switch self {
        case .nes: "NES"
        case .snes: "SNES"
        case .n64: "N64"
        case .xbox: "Xbox"
        case .ps3: "PS3"
        }
    }

    /// PS3 games are folders rather than single files, so it has no extensions.
    var fileExtensions: Set<String> {
        switch self {
        case .nes: ["nes"]
        case .snes: ["sfc", "smc"]
        case .n64: ["z64", "n64", "v64"]
        case .xbox: ["iso", "xiso"]
        case .ps3: []
        }
    }

    var fileHint: String {
        switch self {
        case .nes: ".nes files"
        case .snes: ".sfc or .smc files"
        case .n64: ".z64, .n64 or .v64 files"
        case .xbox: "XISO-format .iso files"
        case .ps3: "game folders (each containing PS3_GAME or USRDIR)"
        }
    }

    var symbol: String {
        switch self {
        case .nes, .snes: "gamecontroller"
        case .n64: "gamecontroller.fill"
        case .xbox: "xbox.logo"
        case .ps3: "playstation.logo"
        }
    }

    /// The libretro core RetroArch uses for this system, if it is a RetroArch system.
    var retroArchCore: (file: String, name: String)? {
        switch self {
        case .nes: ("mesen_libretro.dylib", "Mesen")
        case .snes: ("snes9x_libretro.dylib", "Snes9x")
        case .n64: ("mupen64plus_next_libretro.dylib", "Mupen64Plus-Next")
        case .xbox, .ps3: nil
        }
    }
}

enum Emulator: String, CaseIterable, Identifiable {
    case retroArch, openEmu, xemu, rpcs3

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .retroArch: "RetroArch"
        case .openEmu: "OpenEmu"
        case .xemu: "xemu"
        case .rpcs3: "RPCS3"
        }
    }

    var covers: String {
        switch self {
        case .retroArch, .openEmu: "NES, SNES, N64"
        case .xemu: "Xbox"
        case .rpcs3: "PS3"
        }
    }

    private var appName: String { "\(displayName).app" }

    private var executableName: String {
        switch self {
        case .retroArch: "RetroArch"
        case .openEmu: "OpenEmu"
        case .xemu: "xemu"
        case .rpcs3: "rpcs3"
        }
    }

    var downloadURL: URL {
        switch self {
        case .retroArch: URL(string: "https://www.retroarch.com/?page=platforms")!
        case .openEmu: URL(string: "https://openemu.org")!
        case .xemu: URL(string: "https://xemu.app/docs/download/")!
        case .rpcs3: URL(string: "https://rpcs3.net/download")!
        }
    }

    var appURL: URL? {
        let fm = FileManager.default
        let dirs = [URL(filePath: "/Applications"), fm.homeDirectoryForCurrentUser.appending(path: "Applications")]
        return dirs.map { $0.appending(path: appName) }.first { fm.fileExists(atPath: $0.path) }
    }

    var executableURL: URL? {
        appURL?.appending(path: "Contents/MacOS/\(executableName)")
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

    private static func retroArchCoreURL(for system: GameSystem) -> URL? {
        guard let core = system.retroArchCore else { return nil }
        let url = retroArchCoresDir.appending(path: core.file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// One line describing whether games for this system can be launched, and how.
    static func readiness(for system: GameSystem) -> (ready: Bool, message: String) {
        switch system {
        case .nes, .snes, .n64:
            let coreName = system.retroArchCore!.name
            if Emulator.retroArch.isInstalled, retroArchCoreURL(for: system) != nil {
                return (true, "Plays with RetroArch (\(coreName))")
            }
            if Emulator.openEmu.isInstalled {
                return (true, "Plays with OpenEmu")
            }
            if Emulator.retroArch.isInstalled {
                return (false, "RetroArch is missing the \(coreName) core. In RetroArch open Main Menu › Online Updater › Core Downloader and install it.")
            }
            return (false, "Install OpenEmu or RetroArch to play \(system.displayName) games.")
        case .xbox:
            return Emulator.xemu.isInstalled
                ? (true, "Plays with xemu. Set up your BIOS, MCPX boot ROM and hard disk image in xemu's settings first.")
                : (false, "Install xemu to play Xbox games.")
        case .ps3:
            return Emulator.rpcs3.isInstalled
                ? (true, "Plays with RPCS3. Install the PS3 firmware in RPCS3 (File › Install Firmware) first.")
                : (false, "Install RPCS3 to play PS3 games.")
        }
    }

    static func launch(_ game: Game) throws {
        switch game.system {
        case .nes, .snes, .n64:
            if let exe = Emulator.retroArch.executableURL, let core = retroArchCoreURL(for: game.system) {
                try run(exe, ["-L", core.path, game.bootURL.path])
            } else if let app = Emulator.openEmu.appURL {
                NSWorkspace.shared.open([game.bootURL], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            } else {
                throw LaunchError.notReady(readiness(for: game.system).message)
            }
        case .xbox:
            guard let exe = Emulator.xemu.executableURL else {
                throw LaunchError.notReady(readiness(for: .xbox).message)
            }
            try run(exe, ["-dvd_path", game.bootURL.path])
        case .ps3:
            guard let exe = Emulator.rpcs3.executableURL else {
                throw LaunchError.notReady(readiness(for: .ps3).message)
            }
            try run(exe, ["--no-gui", game.bootURL.path])
        }
    }

    private static func run(_ executable: URL, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        try process.run()
    }
}
