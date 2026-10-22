#if DEBUG
import Foundation

/// Checks for the parts of RetroHub that don't need a window: title cleanup, library scanning,
/// PARAM.SFO parsing and RetroArch options. The Command Line Tools don't include XCTest, so a
/// debug build runs these itself:
///
///     swift build && "$(swift build --show-bin-path)/RetroHub" --self-test
///
/// They only touch a temporary folder: no settings, no ~/Games, no network.
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
                                ("cover art", coverArt)] {
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
}
#endif
