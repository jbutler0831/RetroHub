import SwiftUI

extension GameSystem {
    var maker: String {
        switch self {
        case .nes, .snes, .n64, .gamecube, .wii, .gb, .gbc, .gba, .ds: "Nintendo"
        case .genesis: "Sega"
        case .ps1, .ps2, .ps3, .psp: "Sony"
        case .xbox: "Microsoft"
        }
    }

    static let makers = ["Nintendo", "Sega", "Sony", "Microsoft"]

    var color: Color {
        switch self {
        case .nes: .red
        case .snes: .purple
        case .n64: .green
        case .gamecube: .indigo
        case .wii: .cyan
        case .gb: Color(red: 0.45, green: 0.6, blue: 0.2)
        case .gbc: .teal
        case .gba: Color(red: 0.4, green: 0.3, blue: 0.85)
        case .ds: Color(red: 0.45, green: 0.5, blue: 0.6)
        case .genesis: .blue
        case .ps1: Color(red: 0.55, green: 0.55, blue: 0.6)
        case .ps2: Color(red: 0.15, green: 0.3, blue: 0.75)
        case .ps3: Color(red: 0.25, green: 0.25, blue: 0.3)
        case .psp: Color(red: 0.35, green: 0.35, blue: 0.45)
        case .xbox: Color(red: 0.2, green: 0.65, blue: 0.2)
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
        case .melonDS: .pink
        case .pcsx2: .blue
        case .rpcs3: .orange
        case .ppsspp: Color(red: 0.2, green: 0.6, blue: 0.4)
        case .xemu: .green
        }
    }
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

/// A capsule label used for status.
struct StatusPill: View {
    let text: String
    let symbol: String
    let color: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.callout.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.14), in: Capsule())
    }
}
