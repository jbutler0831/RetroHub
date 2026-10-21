import SwiftUI

/// Everything needed before playing: emulators, the games folder, controllers and BIOS files.
struct SetupView: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var controller: ControllerInput

    private var installedCount: Int {
        Emulator.allCases.filter(\.isInstalled).count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                section("Emulators", subtitle: "RetroHub opens your games in these free emulators. Install the ones for the systems you want to play.") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                        ForEach(Emulator.allCases) { EmulatorCard(emulator: $0) }
                    }
                }

                section("Games Folder", subtitle: "Each system has its own folder inside this one.") {
                    card {
                        HStack(spacing: 14) {
                            IconTile(symbol: "folder.fill", color: .blue, size: 36)
                            Text(library.root.path(percentEncoded: false))
                                .font(.body.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button("Open") { NSWorkspace.shared.open(library.root) }
                            Button("Change…", action: chooseRoot)
                        }
                    }
                }

                section("Graphics", subtitle: "Applied when RetroHub starts a game in RetroArch. RetroArch's own settings stay as they are.") {
                    GraphicsCard()
                }

                section("Controller", subtitle: "PS5 DualSense and Xbox Wireless controllers work over Bluetooth.") {
                    card {
                        HStack(spacing: 14) {
                            IconTile(symbol: "gamecontroller.fill", color: controller.controllerName == nil ? .gray : .green, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(controller.controllerName ?? "No controller connected").font(.headline)
                                Text(controller.controllerName == nil
                                     ? "PS5: hold PS + Create. Xbox: hold the pair button. Then pick it in Bluetooth settings."
                                     : "A to play · Y to favorite · LB/RB to switch · Menu for couch mode")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if controller.controllerName == nil {
                                Button("Bluetooth Settings") {
                                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
                                }
                            }
                        }
                    }
                }

                section("BIOS & Firmware", subtitle: "Some systems need files from your own console. These can't be included.") {
                    card {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(GameSystem.allCases.filter { $0.setupNote != nil }) { system in
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    IconTile(symbol: system.symbol, color: system.color, size: 22)
                                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 5 }
                                    Text(system.displayName).font(.headline).frame(width: 120, alignment: .leading)
                                    Text(system.setupNote!).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .navigationTitle("Setup")
    }

    private var header: some View {
        HStack(spacing: 16) {
            IconTile(symbol: "wrench.and.screwdriver.fill", color: .gray, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text("Setup").font(.largeTitle.weight(.bold))
                Text(installedCount == 0
                     ? "Welcome! Install an emulator below to get started."
                     : "\(installedCount) of \(Emulator.allCases.count) emulators installed")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func section<Content: View>(_ title: String, subtitle: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.semibold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            content()
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.quaternary))
    }

    private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = library.root
        panel.prompt = "Use Folder"
        panel.message = "RetroHub will create a folder for each system inside it."
        if panel.runModal() == .OK, let url = panel.url {
            library.setRoot(url)
        }
    }
}

private struct GraphicsCard: View {
    @AppStorage(Graphics.filterKey) private var filter = ScreenFilter.off
    @AppStorage(Graphics.scaleKey) private var scale = 1
    @AppStorage(Graphics.widescreenKey) private var widescreen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            row("Screen filter", detail: "NES, SNES, Game Boy, GBA and Genesis. CRT adds scanlines and a curved screen; Smooth HD rounds off pixel edges.") {
                Picker("Screen filter", selection: $filter) {
                    ForEach(ScreenFilter.allCases) { Text($0.label).tag($0) }
                }
            }
            if filter != .off, RetroArchGraphics.shaderURL(filter) == nil {
                Label("Download RetroArch's shaders first: Main Menu › Online Updater › Update Slang Shaders.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            Divider()
            row("3D resolution", detail: "N64 and PlayStation. Higher looks sharper but needs a faster Mac.") {
                Picker("3D resolution", selection: $scale) {
                    ForEach(Graphics.scales, id: \.self) { Text($0 == 1 ? "Native" : "\($0)×").tag($0) }
                }
            }
            Divider()
            row("Widescreen hack", detail: "N64 and PlayStation. Shows more of the 3D world in 16:9; some games glitch at the edges.") {
                Toggle("Widescreen hack", isOn: $widescreen)
                    .toggleStyle(.switch)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.quaternary))
    }

    private func row<Control: View>(_ title: String, detail: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            control()
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
        }
    }
}

private struct EmulatorCard: View {
    let emulator: Emulator

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(emulator.color.gradient)
                .frame(width: 40, height: 40)
                .overlay {
                    Text(emulator.displayName.prefix(1).uppercased())
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(emulator.displayName).font(.headline)
                Text(emulator.covers)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if emulator.isInstalled {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.green)
                } else {
                    Button("Download") { NSWorkspace.shared.open(emulator.downloadURL) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.quaternary))
    }
}
