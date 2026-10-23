import SwiftUI

extension GameSystem {
    var maker: String {
        switch self {
        case .nes, .snes, .n64, .gamecube, .wii, .wiiu, .gb, .gbc, .gba, .ds, .n3ds: "Nintendo"
        case .masterSystem, .genesis, .segaCD, .sega32x, .saturn, .dreamcast, .gameGear: "Sega"
        case .ps1, .ps2, .ps3, .ps4, .psp, .vita: "Sony"
        case .xbox: "Microsoft"
        case .pce: "NEC"
        case .neoGeo: "SNK"
        case .atari2600: "Atari"
        case .arcade: "Arcade"
        }
    }

    static let makers = ["Nintendo", "Sega", "Sony", "Microsoft", "NEC", "SNK", "Atari", "Arcade"]

    var color: Color {
        switch self {
        case .nes: .red
        case .snes: .purple
        case .n64: .green
        case .gamecube: .indigo
        case .wii: .cyan
        case .wiiu: Color(red: 0.0, green: 0.6, blue: 0.8)
        case .gb: Color(red: 0.45, green: 0.6, blue: 0.2)
        case .gbc: .teal
        case .gba: Color(red: 0.4, green: 0.3, blue: 0.85)
        case .ds: Color(red: 0.45, green: 0.5, blue: 0.6)
        case .n3ds: Color(red: 0.85, green: 0.15, blue: 0.2)
        case .masterSystem: Color(red: 0.8, green: 0.1, blue: 0.15)
        case .genesis: .blue
        case .segaCD: Color(red: 0.2, green: 0.35, blue: 0.7)
        case .sega32x: Color(red: 0.85, green: 0.45, blue: 0.1)
        case .saturn: Color(red: 0.3, green: 0.3, blue: 0.4)
        case .dreamcast: Color(red: 0.95, green: 0.45, blue: 0.1)
        case .gameGear: Color(red: 0.15, green: 0.15, blue: 0.2)
        case .ps1: Color(red: 0.55, green: 0.55, blue: 0.6)
        case .ps2: Color(red: 0.15, green: 0.3, blue: 0.75)
        case .ps3: Color(red: 0.25, green: 0.25, blue: 0.3)
        case .ps4: Color(red: 0.0, green: 0.27, blue: 0.6)
        case .psp: Color(red: 0.35, green: 0.35, blue: 0.45)
        case .vita: Color(red: 0.1, green: 0.35, blue: 0.75)
        case .xbox: Color(red: 0.2, green: 0.65, blue: 0.2)
        case .pce: Color(red: 0.9, green: 0.55, blue: 0.1)
        case .neoGeo: Color(red: 0.75, green: 0.6, blue: 0.1)
        case .atari2600: Color(red: 0.55, green: 0.3, blue: 0.15)
        case .arcade: Color(red: 0.85, green: 0.2, blue: 0.5)
        }
    }
}

extension SidebarItem {
    var color: Color {
        switch self {
        case .favorites: .yellow
        case .recent: .orange
        case .setup: .gray
        case .system(let system): system.color
        }
    }
}

extension Emulator {
    var color: Color {
        switch self {
        case .openEmu: .indigo
        case .retroArch: Color(red: 0.2, green: 0.2, blue: 0.25)
        case .dolphin: .cyan
        case .cemu: Color(red: 0.0, green: 0.6, blue: 0.8)
        case .melonDS: .pink
        case .azahar: Color(red: 0.85, green: 0.15, blue: 0.2)
        case .pcsx2: .blue
        case .rpcs3: .orange
        case .shadPS4: Color(red: 0.0, green: 0.27, blue: 0.6)
        case .ppsspp: Color(red: 0.2, green: 0.6, blue: 0.4)
        case .vita3k: Color(red: 0.1, green: 0.35, blue: 0.75)
        case .xemu: .green
        }
    }
}

/// Light, Dark, or whatever System Settings › Appearance says. It changes RetroHub's own windows,
/// menus and alerts only; the Mac's setting is left alone. Saved per bundle ID, so RetroHub Dev
/// keeps its own choice.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let key = "appearance"

    static var saved: AppAppearance {
        AppAppearance(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system
    }

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "Follow System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// For NSApp.appearance; nil follows the system.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

extension NSColor {
    /// This color for text and symbols. macOS's orange and green measure about 2:1 against a light
    /// window, and the sidebar badge's orange 4.4:1 on its own tint in Dark mode, so they're
    /// darkened in Light mode and lightened in Dark mode. The sidebar draws lighter in Dark mode on
    /// macOS 15 than on 14, where 35% toward white measured 4.22:1, so it's 55%. SelfTests checks
    /// the colors; the window checks measure the badge as drawn.
    var readable: NSColor {
        NSColor(name: nil) { appearance in
            var color = self
            appearance.performAsCurrentDrawingAppearance { color = self.usingColorSpace(.sRGB) ?? self }
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return color.blended(withFraction: dark ? 0.55 : 0.65, of: dark ? .white : .black) ?? color
        }
    }
}

extension Color {
    /// "Setup needed" orange and "ready" green, readable as text in Light and Dark mode.
    static let warning = Color(nsColor: NSColor.systemOrange.readable)
    static let success = Color(nsColor: NSColor.systemGreen.readable)
}

/// A rounded, colored square with a white symbol, like System Settings icons.
struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

/// A capsule label used for status: readable text on a light tint of the color.
struct StatusPill: View {
    let text: String
    let symbol: String
    let color: NSColor

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.callout.weight(.medium))
            .foregroundStyle(Color(nsColor: color.readable))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(nsColor: color).opacity(0.14), in: Capsule())
    }
}
