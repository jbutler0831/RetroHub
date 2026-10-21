import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var controller: ControllerInput
    @State private var selection: GameSystem? = .nes
    @State private var search = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Systems") {
                    ForEach(GameSystem.allCases) { system in
                        HStack {
                            Label(system.displayName, systemImage: system.symbol)
                            Spacer()
                            Text("\(library.games[system]?.count ?? 0)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .tag(system)
                    }
                }
                Section("Emulators") {
                    ForEach(Emulator.allCases) { EmulatorRow(emulator: $0) }
                }
                Section("Controller") {
                    ControllerRow(name: controller.controllerName)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
        } detail: {
            if let system = selection {
                GameGridView(system: system, search: search)
                    .id(system)
            } else {
                ContentUnavailableView("Pick a system", systemImage: "gamecontroller")
            }
        }
        .searchable(text: $search, prompt: "Search games")
        .toolbar {
            ToolbarItemGroup {
                Button("Choose Games Folder", systemImage: "folder.badge.gearshape", action: chooseRoot)
                Button("Rescan", systemImage: "arrow.clockwise") { library.rescan() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Picks up newly added games and newly installed emulators.
            library.rescan()
        }
        .onReceive(controller.commands) { command in
            let step = command == .nextSystem ? 1 : command == .previousSystem ? -1 : 0
            guard step != 0 else { return }
            let systems = GameSystem.allCases
            let current = systems.firstIndex(of: selection ?? .nes) ?? 0
            selection = systems[(current + step + systems.count) % systems.count]
        }
        .alert("Couldn't start the game", isPresented: Binding(
            get: { library.launchError != nil },
            set: { if !$0 { library.launchError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(library.launchError ?? "")
        }
    }

    private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = library.root
        panel.prompt = "Use Folder"
        panel.message = "RetroHub will create NES, SNES, N64, Xbox and PS3 folders inside it."
        if panel.runModal() == .OK, let url = panel.url {
            library.setRoot(url)
        }
    }
}

private struct EmulatorRow: View {
    let emulator: Emulator

    var body: some View {
        HStack {
            Image(systemName: emulator.isInstalled ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(emulator.isInstalled ? .green : .secondary)
            VStack(alignment: .leading) {
                Text(emulator.displayName)
                Text(emulator.covers).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !emulator.isInstalled {
                Button("Get") { NSWorkspace.shared.open(emulator.downloadURL) }
                    .controlSize(.small)
            }
        }
    }
}

private struct ControllerRow: View {
    let name: String?

    var body: some View {
        HStack {
            Image(systemName: name == nil ? "gamecontroller" : "gamecontroller.fill")
                .foregroundStyle(name == nil ? Color.secondary : Color.green)
            VStack(alignment: .leading) {
                Text(name ?? "None connected")
                Text(name == nil ? "Pair one in System Settings › Bluetooth" : "A: play · LB/RB: switch system")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct GameGridView: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var controller: ControllerInput
    let system: GameSystem
    let search: String
    @State private var selectedID: Game.ID?
    @State private var columnCount = 1
    @FocusState private var gridFocused: Bool

    private static let cardWidth: CGFloat = 150
    private static let spacing: CGFloat = 20

    private var games: [Game] {
        let all = library.games[system] ?? []
        return search.isEmpty ? all : all.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        let readiness = Launcher.readiness(for: system)
        VStack(spacing: 0) {
            Label(readiness.message, systemImage: readiness.ready ? "checkmark.seal" : "exclamationmark.triangle")
                .foregroundStyle(readiness.ready ? Color.secondary : Color.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.bar)
            Divider()
            if games.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .navigationTitle(system.displayName)
        .onReceive(controller.commands, perform: handle)
    }

    private var grid: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.cardWidth), spacing: Self.spacing),
                                             count: columnCount),
                              spacing: Self.spacing) {
                        ForEach(games) { game in
                            GameCard(game: game, isSelected: game.id == selectedID)
                                .id(game.id)
                                .onTapGesture(count: 2) { play(game) }
                                .onTapGesture { selectedID = game.id }
                                .contextMenu {
                                    Button("Play") { play(game) }
                                    Button("Show in Finder") {
                                        NSWorkspace.shared.activateFileViewerSelecting([game.bootURL])
                                    }
                                }
                        }
                    }
                    .padding(Self.spacing)
                }
                .onChange(of: selectedID) { _, id in
                    if let id { withAnimation { proxy.scrollTo(id) } }
                }
            }
            .onChange(of: geometry.size.width, initial: true) { _, width in
                columnCount = max(1, Int((width - Self.spacing) / (Self.cardWidth + Self.spacing)))
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($gridFocused)
        .onAppear {
            gridFocused = true
            if selectedID == nil { selectedID = games.first?.id }
        }
        .onKeyPress(.upArrow) { handle(.move(dx: 0, dy: -1)); return .handled }
        .onKeyPress(.downArrow) { handle(.move(dx: 0, dy: 1)); return .handled }
        .onKeyPress(.leftArrow) { handle(.move(dx: -1, dy: 0)); return .handled }
        .onKeyPress(.rightArrow) { handle(.move(dx: 1, dy: 0)); return .handled }
        .onKeyPress(.return) { handle(.play); return .handled }
    }

    private func handle(_ command: ControllerCommand) {
        switch command {
        case .move(let dx, let dy):
            guard !games.isEmpty else { return }
            guard let current = games.firstIndex(where: { $0.id == selectedID }) else {
                selectedID = games[0].id
                return
            }
            let next = min(max(current + dx + dy * columnCount, 0), games.count - 1)
            selectedID = games[next].id
        case .play:
            // With an error showing, A dismisses it instead of retrying the launch.
            if library.launchError != nil {
                library.launchError = nil
            } else if let game = games.first(where: { $0.id == selectedID }) {
                play(game)
            }
        case .previousSystem, .nextSystem:
            break
        }
    }

    private func play(_ game: Game) {
        selectedID = game.id
        library.play(game)
    }

    @ViewBuilder
    private var emptyState: some View {
        if search.isEmpty {
            ContentUnavailableView {
                Label("No \(system.displayName) games yet", systemImage: system.symbol)
            } description: {
                Text("Put \(system.fileHint) in \(library.folder(for: system).path(percentEncoded: false))")
            } actions: {
                Button("Open Folder") { NSWorkspace.shared.open(library.folder(for: system)) }
            }
        } else {
            ContentUnavailableView.search(text: search)
        }
    }
}

private struct GameCard: View {
    let game: Game
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            CoverView(game: game)
                .frame(width: 150, height: 200)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                }
                .shadow(radius: isSelected ? 6 : 2)
                .scaleEffect(isSelected ? 1.05 : 1)
                .animation(.snappy(duration: 0.15), value: isSelected)
            Text(game.title)
                .font(.callout)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 150, height: 36, alignment: .top)
        }
        .contentShape(Rectangle())
    }
}

private struct CoverView: View {
    let game: Game
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(.quaternary)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: game.system.symbol).font(.largeTitle)
                    Text(game.title).font(.caption).multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .padding()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: game.id) {
            image = await CoverArt.data(for: game).flatMap(NSImage.init(data:))
        }
    }
}
