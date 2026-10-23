#if DEBUG
import AppKit

/// Checks for the parts of RetroHub that don't need a window: title cleanup, library scanning,
/// PARAM.SFO parsing, RetroArch options, status color contrast, emulator processes, Controller
/// Diagnostics' clock and the compatibility inventory. The Command Line Tools don't include
/// XCTest, so a debug build runs these itself:
///
///     swift build && "$(swift build --show-bin-path)/RetroHub" --self-test
///
/// They only touch a temporary folder: no settings, no ~/Games, no network. /bin/sleep and
/// /usr/bin/false stand in for an emulator.
@MainActor
enum SelfTests {
    private static var failures = 0
    private static var checks = 0

    /// Runs every check and returns the process exit code.
    static func run() -> Int32 {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "RetroHubSelfTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        // Unbuffered, so a check that crashes still shows which section it was in.
        setvbuf(stdout, nil, _IONBF, 0)

        for (name, section) in [("titles", titles), ("PARAM.SFO", { sfo(in: tmp.appending(path: "sfo")) }),
                                ("scanning", { scanning(in: tmp.appending(path: "library")) }),
                                ("systems", systems), ("sidebar", sidebar), ("RetroArch options", retroArchOptions),
                                ("cover art", coverArt), ("old settings", legacySettings),
                                ("appearance", appearance), ("game process", gameProcess),
                                ("controller diagnostics", controllerDiagnostics), ("compatibility", compatibility)] {
            print("- \(name)")
            section()
        }

        print(failures == 0 ? "PASS: \(checks) checks" : "FAIL: \(failures) of \(checks) checks failed")
        return failures == 0 ? 0 : 1
    }

    private static func expect<T: Equatable>(_ actual: T, _ expected: T, _ label: String,
                                             line: UInt = #line) {
        checks += 1
        if actual != expected {
            failures += 1
            print("  FAIL (line \(line)) \(label): got \(actual), expected \(expected)")
        }
    }

    private static func write(_ url: URL, _ data: Data = Data()) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url)
    }

    private static func titles() {
        expect("Contra (USA) [!]".strippingTags, "Contra", "tags stripped")
        expect("Super Mario Bros. (World)".strippingTags, "Super Mario Bros.", "region stripped")
        let zelda = Game(system: .nes, title: "Legend of Zelda, The (USA)", bootURL: URL(filePath: "/z.nes"), localCovers: [])
        expect(zelda.displayTitle, "The Legend of Zelda", "trailing article moved to the front")
        let tagsOnly = Game(system: .nes, title: "(Proto)", bootURL: URL(filePath: "/p.nes"), localCovers: [])
        expect(tagsOnly.displayTitle, "(Proto)", "a title that is all tags is kept")
    }

    /// PARAM.SFO with the given entries; `count` overrides the entry count in the header.
    private static func sfoData(_ entries: [(key: String, value: String)], count: Int? = nil) -> Data {
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
        func le32(_ v: Int) -> [UInt8] { le16(v & 0xFFFF) + le16(v >> 16) }
        var keys: [UInt8] = [], values: [UInt8] = [], index: [UInt8] = []
        for entry in entries {
            let value = Array(entry.value.utf8) + [0]
            index += le16(keys.count) + le16(0x0204) + le32(value.count) + le32(value.count) + le32(values.count)
            keys += Array(entry.key.utf8) + [0]
            values += value
        }
        while keys.count % 4 != 0 { keys.append(0) }
        let keyTable = 20 + index.count, dataTable = keyTable + keys.count
        let header: [UInt8] = [0x00, 0x50, 0x53, 0x46, 0x01, 0x01, 0x00, 0x00]
            + le32(keyTable) + le32(dataTable) + le32(count ?? entries.count)
        return Data(header + index + keys + values)
    }

    private static func sfo(in dir: URL) {
        func title(_ data: Data, _ name: String) -> String? {
            let url = dir.appending(path: name)
            write(url, data)
            return Library.sfoTitle(at: url)
        }
        expect(title(sfoData([("TITLE", "Test Game")]), "plain.sfo"), "Test Game", "TITLE read")
        expect(title(sfoData([("CATEGORY", "DG"), ("TITLE", "Second Entry")]), "second.sfo"), "Second Entry",
               "TITLE found after another key")
        expect(title(sfoData([("TITLE", "Two\nLines")]), "newline.sfo"), "Two Lines", "newline becomes a space")
        expect(title(sfoData([("CATEGORY", "DG")]), "untitled.sfo"), nil, "no TITLE entry")
        expect(title(Data("not an sfo file at all".utf8), "garbage.sfo"), nil, "wrong magic")
        expect(title(Data(), "empty.sfo"), nil, "empty file")
        // A header that promises more entries than the file holds (a truncated or damaged
        // PARAM.SFO) must give up, not read past the end of the data.
        expect(title(sfoData([], count: 3), "truncated.sfo"), nil, "truncated index")
        expect(title(sfoData([("CATEGORY", "DG")], count: 2), "short.sfo"), nil, "index shorter than its count")
    }

    private static func scanning(in root: URL) {
        let nes = root.appending(path: "NES")
        for name in ["b game.nes", "A Game.NES", ".hidden.nes", "notes.txt", "Sub/c nested.nes"] {
            write(nes.appending(path: name))
        }
        expect(Library.scan(.nes, in: nes).map(\.title), ["A Game", "b game", "c nested"],
               "NES: any-case extensions, subfolders, sorted; hidden and other files skipped")
        expect(Library.scan(.nes, in: nes).first?.localCovers.map(\.lastPathComponent),
               ["A Game.png", "A Game.jpg", "A Game.jpeg"], "local cover candidates")

        let ps1 = root.appending(path: "PS1")
        write(ps1.appending(path: "Disc (USA).cue"))
        write(ps1.appending(path: "Disc (USA) (Track 1).bin"))
        expect(Library.scan(.ps1, in: ps1).map(\.bootURL.lastPathComponent), ["Disc (USA).cue"], "PS1: only the .cue")

        let ps3 = root.appending(path: "PS3")
        write(ps3.appending(path: "BLUS1/PS3_GAME/USRDIR/EBOOT.BIN"))
        write(ps3.appending(path: "BLUS1/PS3_GAME/PARAM.SFO"), sfoData([("TITLE", "Disc Dump")]))
        write(ps3.appending(path: "NPUB2/USRDIR/EBOOT.BIN"))
        write(ps3.appending(path: "Not a game/readme.txt"))
        let ps3Games = Library.scan(.ps3, in: ps3)
        expect(ps3Games.map(\.title), ["Disc Dump", "NPUB2"], "PS3: disc and PSN layouts, title from PARAM.SFO")
        expect(ps3Games.first?.bootURL.lastPathComponent, "EBOOT.BIN", "PS3 boots EBOOT.BIN")

        let ps4 = root.appending(path: "PS4")
        write(ps4.appending(path: "CUSA1/eboot.bin"))
        write(ps4.appending(path: "CUSA1/sce_sys/param.sfo"), sfoData([("TITLE", "PS4 Game")]))
        write(ps4.appending(path: "CUSA2/sce_sys/param.sfo"))
        expect(Library.scan(.ps4, in: ps4).map(\.title), ["PS4 Game"], "PS4: needs eboot.bin")

        // A damaged PARAM.SFO inside a game folder must not stop the scan.
        write(ps4.appending(path: "CUSA3/eboot.bin"))
        write(ps4.appending(path: "CUSA3/sce_sys/param.sfo"), sfoData([], count: 40))
        expect(Library.scan(.ps4, in: ps4).map(\.title), ["CUSA3", "PS4 Game"], "PS4: damaged PARAM.SFO falls back to folder name")

        expect(Library.scan(.snes, in: root.appending(path: "Missing")).count, 0, "missing folder is empty")
    }

    private static func systems() {
        // APFS is case-insensitive by default, so folder names must differ in more than case.
        let folders = GameSystem.allCases.map { $0.folderName.lowercased() }
        expect(Set(folders).count, folders.count, "system folder names are unique")
        for system in GameSystem.allCases {
            expect(system.backends.isEmpty, false, "\(system) has an emulator")
            expect(system.fileExtensions.isEmpty, [.ps3, .ps4, .vita].contains(system), "\(system) extensions")
        }
        expect(SidebarItem.all.count, GameSystem.allCases.count + 2, "controller cycles favorites, recent and every system")
    }

    private static func sidebar() {
        let listed = SidebarItem.sections.flatMap(\.items)
        expect(Set(listed).count, listed.count, "each sidebar row appears once")
        expect(SidebarItem.sections.first?.items, [.favorites, .recent, .setup], "Favorites, Recently Played and Setup come first")
        expect(SidebarItem.sections.dropFirst().map(\.title), GameSystem.makers.map(Optional.some), "a section per maker, in order")
        for (title, items) in SidebarItem.sections.dropFirst() {
            let own = items.allSatisfy { if case .system(let system) = $0 { system.maker == title } else { false } }
            expect(own, true, "\(title ?? "") lists only its own systems")
        }
        expect(listed.filter { if case .system = $0 { true } else { false } }.count, GameSystem.allCases.count,
               "every system has a row")
        expect(Set(listed.map(\.title)).count, listed.count, "every row has its own name")
        expect(listed.allSatisfy { !$0.title.isEmpty && !$0.symbol.isEmpty }, true, "every row has a name and an icon")
        expect(SidebarItem.all, listed.filter { $0 != .setup }, "LB/RB go through the lists in sidebar order, skipping Setup")

        let items: [SidebarItem] = [.favorites, .recent, .system(.nes)]
        expect(SidebarItem.stepping(from: .favorites, by: 1, in: items), .recent, "next")
        expect(SidebarItem.stepping(from: .system(.nes), by: 1, in: items), .favorites, "next wraps to the first")
        expect(SidebarItem.stepping(from: .favorites, by: -1, in: items), .system(.nes), "previous wraps to the last")
        expect(SidebarItem.stepping(from: .setup, by: 1, in: items), .favorites, "from Setup, next is the first list")
        expect(SidebarItem.stepping(from: .setup, by: -1, in: items), .system(.nes), "from Setup, previous is the last list")
        expect(SidebarItem.stepping(from: .favorites, by: 1, in: []), nil, "no lists to step through")
    }

    private static func retroArchOptions() {
        expect(RetroArchGraphics.coreOptions("flycast", scale: 2, widescreen: false),
               ["reicast_internal_resolution": "1280x960"], "Dreamcast 2x")
        expect(RetroArchGraphics.coreOptions("mupen64plus_next", scale: 3, widescreen: false),
               ["mupen64plus-EnableNativeResFactor": "3", "mupen64plus-parallel-rdp-upscaling": "2x"],
               "N64 3x rounds the ParaLLEl-RDP factor down to a power of two")
        expect(RetroArchGraphics.coreOptions("swanstation", scale: 1, widescreen: false), [:], "native, no hacks")
        expect(RetroArchGraphics.coreOptions("snes9x", scale: 4, widescreen: true), [:], "2D cores get no 3D options")
    }

    private static func coverArt() {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        expect(CoverArt.result(status: 200, data: png), .found(png), "200 is art")
        expect(CoverArt.result(status: 404, data: Data()), .missing, "404 is remembered as no art")
        // Server trouble must not be cached as "no art", or the cover never loads again.
        for status in [429, 500, 502, 503] {
            expect(CoverArt.result(status: status, data: Data()), .offline, "\(status) is retried later")
        }
        expect(CoverArt.result(status: nil, data: Data()), .offline, "no HTTP status is retried later")
    }

    /// Only the installed RetroHub takes over the settings saved under the old bundle ID; the
    /// development copies must never see the Mac's real favorites, recents or games folder.
    private static func legacySettings() {
        expect(Library.takesLegacySettings(bundleID: "io.github.jbutler0831.retrohub"), true, "the installed RetroHub")
        for id in ["io.github.jbutler0831.retrohub.dev", "io.github.jbutler0831.retrohub.devcheck", "local.retrohub"] {
            expect(Library.takesLegacySettings(bundleID: id), false, "not \(id)")
        }
        expect(Library.takesLegacySettings(bundleID: nil), false, "not the bare debug binary")
    }

    /// Launcher reports when the emulator's process ends, with its exit status, also when it
    /// fails straight away; Library uses it to allow one game at a time.
    private static func gameProcess() {
        final class Exits: @unchecked Sendable {
            private let lock = NSLock()
            private var statuses: [Int32] = []
            func add(_ status: Int32) { lock.withLock { statuses.append(status) } }
            var all: [Int32] { lock.withLock { statuses } }
        }
        let exits = Exits()
        let game = try? Launcher.start(URL(filePath: "/bin/sleep"), ["0.5"]) { exits.add($0.terminationStatus) }
        expect(game?.isRunning, true, "the emulator is running after it starts")
        _ = try? Launcher.start(URL(filePath: "/usr/bin/false"), []) { exits.add($0.terminationStatus) }
        let deadline = Date.now + 5
        while exits.all.count < 2, Date.now < deadline { Thread.sleep(forTimeInterval: 0.05) }
        expect(exits.all.sorted(), [0, 1], "both ends are reported, with their exit status")
        expect(game?.isRunning, false, "and the process has ended")
        expect((try? Launcher.start(URL(filePath: "/nonexistent/emulator"), []) { _ in }) == nil, true,
               "a missing emulator is an error, not a silent failure")
    }

    /// Controller Diagnostics times are compared with notes taken during a hardware test, so they
    /// must be 24-hour: a 12-hour clock without AM/PM logged 8:12 PM as 08:12.
    private static func controllerDiagnostics() {
        func at(_ hour: Int, _ minute: Int, _ second: Int, _ milliseconds: Int) -> Date {
            Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: hour, minute: minute,
                                                       second: second, nanosecond: milliseconds * 1_000_000))!
        }
        let format = ControllerDiagnostics.timeFormat
        expect(at(20, 12, 17, 250).formatted(format), "20:12:17.250", "evening is 20, not 08")
        expect(at(8, 5, 9, 500).formatted(format), "08:05:09.500", "morning keeps its leading zero")
        expect(at(0, 0, 0, 0).formatted(format), "00:00:00.000", "midnight is 00, not 12")
        expect(at(12, 30, 0, 0).formatted(format), "12:30:00.000", "noon is 12")
    }

    private static func compatibility() {
        let x86 = Data([0xCF, 0xFA, 0xED, 0xFE, 0x07, 0x00, 0x00, 0x01])
        let arm = Data([0xCF, 0xFA, 0xED, 0xFE, 0x0C, 0x00, 0x00, 0x01])
        let universal = Data([0xCA, 0xFE, 0xBA, 0xBE, 0, 0, 0, 2, 0x01, 0, 0, 0x07] + Array(repeating: 0, count: 16)
                             + [0x01, 0, 0, 0x0C] + Array(repeating: 0, count: 16))
        expect(Compatibility.architectures(header: x86), ["x86_64"], "an Intel program")
        expect(Compatibility.architectures(header: arm), ["arm64"], "an Apple silicon program")
        expect(Compatibility.architectures(header: universal), ["x86_64", "arm64"], "a universal program")
        expect(Compatibility.architectures(header: Data("#!/bin/sh\n".utf8)), [], "a script is no Mach-O")
        expect(Compatibility.architectures(header: Data([0xCA, 0xFE])), [], "a cut-off header")

        // From libretro-core-info's mednafen_psx_libretro.info.
        let info = """
            firmware_count = 3
            firmware0_desc = "scph5500.bin (PS1 JP BIOS)"
            firmware0_path = "scph5500.bin"
            firmware0_opt = "false"
            firmware1_desc = "scph5501.bin (PS1 US BIOS)"
            firmware1_path = "scph5501.bin"
            firmware1_opt = "false"
            firmware2_desc = "psxonpsp660.bin (PSP PS1 BIOS)"
            firmware2_path = "psxonpsp660.bin"
            firmware2_opt = "true"
            """
        let firmware = Compatibility.firmware(info: info)
        expect(firmware.map(\.path), ["scph5500.bin", "scph5501.bin", "psxonpsp660.bin"], "firmware files from a core's .info")
        expect(firmware.map(\.optional), [false, false, true], "and which are optional")
        expect(Compatibility.firmware(info: "display_name = \"Nestopia\"").isEmpty, true, "a core without firmware")

        typealias Installed = Compatibility.Installed
        let retroArch = Compatibility.InstalledEmulator(path: "/Applications/RetroArch.app", version: "1.22.2", architectures: ["x86_64", "arm64"])
        func core(_ architectures: [String], _ firmware: [Compatibility.Firmware]? = []) -> Compatibility.InstalledCore {
            Compatibility.InstalledCore(architectures: architectures, firmware: firmware)
        }
        func status(_ system: GameSystem, _ installed: Installed) -> Compatibility.Status {
            Compatibility.evaluate(system, installed).status
        }
        var mac = Installed(architecture: "x86_64")
        mac.retroArch.configFound = true
        expect(status(.nes, mac), .setupRequired, "nothing installed")
        mac.emulators["retroArch"] = retroArch
        expect(status(.nes, mac), .setupRequired, "RetroArch without an NES core")
        expect(Compatibility.evaluate(.nes, mac).evidence.joined().contains("mesen_libretro.dylib"), true, "names the cores it looked for")
        mac.cores["fceumm"] = core(["x86_64"])
        let nes = Compatibility.evaluate(.nes, mac)
        expect(nes.status, .ready, "RetroArch and an Intel NES core on an Intel Mac")
        expect(nes.backend, "RetroArch (FCEUmm)", "using the first core RetroHub would pick")
        expect(nes.confidence, .high, "from files on disk")
        mac.cores["mesen"] = core(["arm64"])
        expect(status(.nes, mac), .unsupported, "an Apple silicon core, which RetroHub would pick first, on an Intel Mac")
        mac.retroArch.configFound = false
        mac.cores["mesen"] = core(["x86_64", "arm64"])
        expect(Compatibility.evaluate(.nes, mac).confidence, .medium, "less sure with RetroArch's default folders assumed")

        let bios = firmware.map { item -> Compatibility.Firmware in var item = item; item.present = false; return item }
        mac.cores["swanstation"] = core(["x86_64"], bios)
        expect(status(.ps1, mac), .setupRequired, "PlayStation without the BIOS the core needs")
        mac.cores["swanstation"] = core(["x86_64"], bios.enumerated().map { var item = $1; item.present = $0 == 1; return item })
        expect(status(.ps1, mac), .unknown, "with one region's BIOS of two")
        mac.cores["swanstation"] = core(["x86_64"], bios.map { var item = $0; item.present = !item.optional; return item })
        expect(status(.ps1, mac), .ready, "with every required BIOS")
        mac.retroArch.systemNotRead = true
        mac.cores["swanstation"] = core(["x86_64"], firmware)
        expect(status(.ps1, mac), .unknown, "firmware folder in Documents, not read")
        mac.cores["swanstation"] = core(["x86_64"], nil)
        expect(status(.ps1, mac), .unknown, "no .info file, and the system needs a BIOS")

        mac.emulators["dolphin"] = Compatibility.InstalledEmulator(path: "/Applications/Dolphin.app", version: "2509", architectures: ["x86_64", "arm64"])
        expect(status(.gamecube, mac), .ready, "a standalone emulator for a system that needs no firmware")
        mac.emulators["pcsx2"] = Compatibility.InstalledEmulator(path: "/Applications/PCSX2.app", version: nil, architectures: ["x86_64"])
        expect(status(.ps2, mac), .unknown, "PCSX2 keeps the BIOS it needs itself")
        var appleSilicon = Installed(architecture: "arm64")
        appleSilicon.emulators["pcsx2"] = mac.emulators["pcsx2"]
        appleSilicon.emulators["dolphin"] = Compatibility.InstalledEmulator(path: "/Applications/Dolphin.app", version: nil, architectures: ["x86_64"])
        expect(status(.gamecube, appleSilicon), .unsupported, "an Intel-only emulator on Apple silicon without Rosetta")
        appleSilicon.rosetta = true
        expect(status(.gamecube, appleSilicon), .ready, "and with Rosetta")

        // On this Mac, RetroHub's launcher and the inventory pick the same way.
        let here = Installed.current()
        for system in GameSystem.allCases {
            expect(Compatibility.evaluate(system, here).backend != nil, Launcher.readiness(for: system).ready,
                   "\(system.displayName): the inventory and the launcher agree")
        }
    }

    private static func appearance() {
        expect(AppAppearance.allCases.map(\.label), ["Follow System", "Light", "Dark"], "the appearance choices")
        expect(AppAppearance.system.nsAppearance == nil, true, "Follow System leaves the appearance to macOS")
        expect(AppAppearance.light.nsAppearance?.name, .aqua, "Light")
        expect(AppAppearance.dark.nsAppearance?.name, .darkAqua, "Dark")

        // Status text needs 4.5:1 wherever it's drawn: on the window, on its own 14% tint in the
        // status pill, and (orange only) on an 18% tint in the sidebar's count badge. The sidebar's
        // material, as drawn on macOS 14.4, is darker than the window in Light mode and lighter in Dark.
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let sidebar = name == .aqua ? NSColor(srgbRed: 227 / 255, green: 228 / 255, blue: 237 / 255, alpha: 1)
                                        : NSColor(srgbRed: 56 / 255, green: 59 / 255, blue: 65 / 255, alpha: 1)
            var window = sidebar
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                window = NSColor.windowBackgroundColor.usingColorSpace(.sRGB)!
            }
            let places = [(window, 0.0, "window"), (window, 0.14, "pill"), (sidebar, 0.18, "badge")]
            for (color, colorName, drawnOn) in [(NSColor.systemOrange, "orange", places), (.systemGreen, "green", Array(places.prefix(2)))] {
                var text = color, tint = color
                NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                    text = color.readable.usingColorSpace(.sRGB)!
                    tint = color.usingColorSpace(.sRGB)!
                }
                for (backdrop, opacity, place) in drawnOn {
                    let ratio = text.contrast(with: backdrop.blended(withFraction: opacity, of: tint)!)
                    expect(ratio >= 4.5, true, String(format: "%@ text on the %@ in %@: %.2f:1", colorName, place,
                                                      name == .aqua ? "Light" : "Dark", ratio))
                }
            }
        }
    }
}

extension NSColor {
    /// WCAG relative luminance, of the color in sRGB.
    var luminance: Double {
        guard let rgb = usingColorSpace(.sRGB) else { return 0 }
        func channel(_ value: CGFloat) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb.redComponent) + 0.7152 * channel(rgb.greenComponent) + 0.0722 * channel(rgb.blueComponent)
    }

    /// WCAG contrast ratio, from 1 (none) to 21 (black on white).
    func contrast(with other: NSColor) -> Double {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
#endif
