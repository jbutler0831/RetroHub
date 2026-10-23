// Makes a small games folder for trying RetroHub without real games.
// Usage (from the mac folder): swift scripts/make-test-library.swift <folder>
//
// It holds one playable file, "RetroHub Test Pattern.nes": a tiny NES program written for
// RetroHub (no copyrighted code) that fills the screen with a color that changes about once a
// second. Everything else is an empty placeholder that shows how the library is scanned; those
// show up in RetroHub but won't boot in an emulator.
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("Usage: swift scripts/make-test-library.swift <folder>\n".data(using: .utf8)!)
    exit(1)
}
let root = URL(filePath: CommandLine.arguments[1], directoryHint: .isDirectory)
let fm = FileManager.default

func write(_ path: String, _ data: Data = Data()) throws {
    let url = root.appending(path: path)
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

/// NROM (mapper 0) image: 16 KB of program at $C000 and 8 KB of blank tiles, so the screen
/// shows only the backdrop color. NMI bumps a frame counter and every 64 frames picks the next
/// of eight bright colors.
func testPatternROM() -> Data {
    let code: [UInt8] = [
        // reset, $C000
        0x78,                   // sei
        0xD8,                   // cld
        0xA2, 0x40,             // ldx #$40
        0x8E, 0x17, 0x40,       // stx $4017      ; no APU frame IRQ
        0xA2, 0xFF,             // ldx #$ff
        0x9A,                   // txs
        0xE8,                   // inx            ; x = 0
        0x8E, 0x00, 0x20,       // stx $2000      ; NMI off
        0x8E, 0x01, 0x20,       // stx $2001      ; rendering off
        0x8E, 0x10, 0x40,       // stx $4010      ; no DMC IRQ
        0x86, 0x00,             // stx $00        ; frame counter
        0x86, 0x01,             // stx $01        ; color index
        0x2C, 0x02, 0x20,       // bit $2002
        0x2C, 0x02, 0x20,       // vbl1: bit $2002 ($C01B)
        0x10, 0xFB,             // bpl vbl1
        0x2C, 0x02, 0x20,       // vbl2: bit $2002 ($C020)
        0x10, 0xFB,             // bpl vbl2
        0x20, 0x45, 0xC0,       // jsr setpal
        0xA9, 0x80,             // lda #$80
        0x8D, 0x00, 0x20,       // sta $2000      ; NMI on
        0xA9, 0x0A,             // lda #$0a
        0x8D, 0x01, 0x20,       // sta $2001      ; show background
        0x4C, 0x32, 0xC0,       // loop: jmp loop ($C032)
        // nmi, $C035
        0x48,                   // pha
        0xE6, 0x00,             // inc $00
        0xA5, 0x00,             // lda $00
        0x29, 0x3F,             // and #$3f
        0xD0, 0x05,             // bne done
        0xE6, 0x01,             // inc $01
        0x20, 0x45, 0xC0,       // jsr setpal
        0x68,                   // done: pla ($C043)
        0x40,                   // irq: rti ($C044)
        // setpal, $C045: backdrop = $21 + (color index & 7), then scroll back to 0,0
        0xA9, 0x3F,             // lda #$3f
        0x8D, 0x06, 0x20,       // sta $2006
        0xA9, 0x00,             // lda #$00
        0x8D, 0x06, 0x20,       // sta $2006
        0xA5, 0x01,             // lda $01
        0x29, 0x07,             // and #$07
        0x18,                   // clc
        0x69, 0x21,             // adc #$21
        0x8D, 0x07, 0x20,       // sta $2007
        0xA9, 0x00,             // lda #$00
        0x8D, 0x06, 0x20,       // sta $2006
        0x8D, 0x06, 0x20,       // sta $2006
        0x8D, 0x05, 0x20,       // sta $2005
        0x8D, 0x05, 0x20,       // sta $2005
        0x60,                   // rts
    ]
    precondition(code.count == 0x68, "code moved; fix the jump targets")
    var prg = [UInt8](repeating: 0xFF, count: 0x4000)
    prg.replaceSubrange(0..<code.count, with: code)
    prg.replaceSubrange(0x3FFA..<0x4000, with: [0x35, 0xC0, 0x00, 0xC0, 0x44, 0xC0])  // NMI, reset, IRQ
    let header: [UInt8] = [0x4E, 0x45, 0x53, 0x1A, 1, 1] + [UInt8](repeating: 0, count: 10)
    return Data(header + prg + [UInt8](repeating: 0, count: 0x2000))
}

/// A PARAM.SFO with just a TITLE entry, the way PS3, PS4 and PS Vita games describe themselves.
func paramSFO(title: String) -> Data {
    func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
    func le32(_ v: Int) -> [UInt8] { le16(v & 0xFFFF) + le16(v >> 16) }
    let value = Array(title.utf8) + [0]
    let keys: [UInt8] = Array("TITLE".utf8) + [0, 0, 0]  // padded to 4 bytes
    let keyTable = 20 + 16, dataTable = keyTable + keys.count
    let header = [0x00, 0x50, 0x53, 0x46, 0x01, 0x01, 0x00, 0x00] + le32(keyTable) + le32(dataTable) + le32(1)
    let entry = le16(0) + le16(0x0204) + le32(value.count) + le32(value.count) + le32(0)
    return Data(header + entry + keys + value)
}

do {
    try write("NES/RetroHub Test Pattern.nes", testPatternROM())
    // Placeholders: tags and trailing articles are tidied in titles; extensions match in any case;
    // games in subfolders are found; hidden files and other extensions are skipped.
    try write("NES/Legend of Placeholder, The (USA) [!].nes")
    try write("NES/notes.txt")
    try write("NES/.hidden.nes")
    try write("SNES/UPPERCASE EXTENSION.SFC")
    try write("Genesis/Subfolder/Nested Game.md")
    // Only the .cue of a disc image is listed, not its tracks.
    try write("PS1/Disc Placeholder (USA).cue")
    try write("PS1/Disc Placeholder (USA) (Track 1).bin")
    // PS3 and PS4 games are folders; their titles come from PARAM.SFO.
    try write("PS3/BLUS00000/PS3_GAME/USRDIR/EBOOT.BIN")
    try write("PS3/BLUS00000/PS3_GAME/PARAM.SFO", paramSFO(title: "PS3 Folder Placeholder"))
    try write("PS3/Not A Game/readme.txt")
    try write("PS4/CUSA00000/eboot.bin")
    try write("PS4/CUSA00000/sce_sys/param.sfo", paramSFO(title: "PS4 Folder Placeholder"))
    print("Made a test library in \(root.path(percentEncoded: false))")
} catch {
    FileHandle.standardError.write("\(error.localizedDescription)\n".data(using: .utf8)!)
    exit(1)
}
