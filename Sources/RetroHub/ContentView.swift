import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var controller: ControllerInput
    @State private var selection: SidebarItem? = .system(.nes)
    @State private var search = ""
    @State private var couchMode = false

    /// Couch mode only shows lists with games in them, so the controller never lands on a blank screen.
    private var couchItems: [SidebarItem] {
        SidebarItem.all.filter { !library.games(for: $0).isEmpty }
    }

    var body: some View {
        Group {
            if couchMode {
                CouchView(item: selection ?? .system(.nes), items: couchItems,
                          onSelect: { selection = $0 }, onCycle: cycle, onExit: { setCouchMode(false) })
            } else {
                browser
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Picks up newly added games and newly installed emulators.
            library.rescan()
        }
        .onReceive(controller.commands) { command in
            switch command {
            case .previousSystem: cycle(-1)
            case .nextSystem: cycle(1)
            case .toggleCouchMode: setCouchMode(!couchMode)
            default: break
            }
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

    private var browser: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Library") {
                    ForEach([SidebarItem.favorites, .recent], id: \.self) { item in
                        SidebarRow(item: item, count: library.games(for: item).count).tag(item)
                    }
                }
                Section("Systems") {
                    ForEach(GameSystem.allCases) { system in
                        let item = SidebarItem.system(system)
                        SidebarRow(item: item, count: library.games(for: item).count).tag(item)
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
            if let item = selection {
                GameGridView(item: item, search: search)
                    .id(item)
            } else {
                ContentUnavailableView("Pick a system", systemImage: "gamecontroller")
            }
        }
        .searchable(text: $search, prompt: "Search games")
        .toolbar {
            ToolbarItemGroup {
                Button("Couch Mode", systemImage: "tv") { setCouchMode(true) }
                    .help("Full-screen view for playing with a controller")
                Button("Choose Games Folder", systemImage: "folder.badge.gearshape", action: chooseRoot)
                Button("Rescan", systemImage: "arrow.clockwise") { library.rescan() }
            }
        }
    }

    private func cycle(_ step: Int) {
        let items = couchMode ? couchItems : SidebarItem.all
        guard !items.isEmpty else { return }
        let current = items.firstIndex(of: selection ?? .system(.nes)) ?? (step > 0 ? -1 : 0)
        selection = items[(current + step + items.count) % items.count]
    }

    private func setCouchMode(_ on: Bool) {
        couchMode = on
        if on, let first = couchItems.first, !couchItems.contains(selection ?? .favorites) {
            selection = first
        }
        if let window = NSApp.keyWindow ?? NSApp.windows.first,
           window.styleMask.contains(.fullScreen) != on {
            window.toggleFullScreen(nil)
        }
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

private struct SidebarRow: View {
    let item: SidebarItem
    let count: Int

    var body: some View {
        HStack {
            Label(item.title, systemImage: item.symbol)
            Spacer()
            Text("\(count)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
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
                Text(emulator.covers).font(.caption).foregroundStyle(.secondary).lineLimit(2)
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
                Text(name == nil ? "Pair one in System Settings › Bluetooth" : "A: play · Y: favorite · Menu: couch mode")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct GameGridView: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var controller: ControllerInput
    let item: SidebarItem
    let search: String
    @State private var selectedID: Game.ID?
    @State private var columnCount = 1
    @FocusState private var gridFocused: Bool

    private static let cardWidth: CGFloat = 150
    private static let spacing: CGFloat = 20

    private var games: [Game] {
        let all = library.games(for: item)
        return search.isEmpty ? all : all.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    private var selectedGame: Game? {
        games.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(spacing: 0) {
            if case .system(let system) = item {
                let readiness = Launcher.readiness(for: system)
                Label(readiness.message, systemImage: readiness.ready ? "checkmark.seal" : "exclamationmark.triangle")
                    .foregroundStyle(readiness.ready ? Color.secondary : Color.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.bar)
                Divider()
            }
            if games.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .navigationTitle(item.title)
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
                            GameCard(game: game, isSelected: game.id == selectedID,
                                     isFavorite: library.isFavorite(game), showsSystem: !isSystemList)
                                .id(game.id)
                                .onTapGesture(count: 2) { play(game) }
                                .onTapGesture { selectedID = game.id }
                                .contextMenu {
                                    Button("Play") { play(game) }
                                    Button(library.isFavorite(game) ? "Remove from Favorites" : "Add to Favorites") {
                                        library.toggleFavorite(game)
                                    }
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
        .onKeyPress("f") { handle(.favorite); return .handled }
    }

    private var isSystemList: Bool {
        if case .system = item { true } else { false }
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
            } else if let game = selectedGame {
                play(game)
            }
        case .favorite:
            if let game = selectedGame { library.toggleFavorite(game) }
        case .back:
            library.launchError = nil
        case .previousSystem, .nextSystem, .toggleCouchMode:
            break
        }
    }

    private func play(_ game: Game) {
        selectedID = game.id
        library.play(game)
    }

    @ViewBuilder
    private var emptyState: some View {
        if !search.isEmpty {
            ContentUnavailableView.search(text: search)
        } else {
            switch item {
            case .favorites:
                ContentUnavailableView("No favorites yet", systemImage: "star",
                                       description: Text("Right-click a game, press F, or press Y on your controller to add it here."))
            case .recent:
                ContentUnavailableView("Nothing played yet", systemImage: "clock",
                                       description: Text("Games you play show up here."))
            case .system(let system):
                ContentUnavailableView {
                    Label("No \(system.displayName) games yet", systemImage: system.symbol)
                } description: {
                    Text("Put \(system.fileHint) in \(library.folder(for: system).path(percentEncoded: false))")
                } actions: {
                    Button("Open Folder") { NSWorkspace.shared.open(library.folder(for: system)) }
                }
            }
        }
    }
}

private struct GameCard: View {
    let game: Game
    let isSelected: Bool
    let isFavorite: Bool
    let showsSystem: Bool

    var body: some View {
        VStack(spacing: 4) {
            CoverView(game: game)
                .frame(width: 150, height: 200)
                .overlay(alignment: .topTrailing) {
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .padding(6)
                            .background(.black.opacity(0.5), in: Circle())
                            .padding(6)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                }
                .shadow(radius: isSelected ? 6 : 2)
                .scaleEffect(isSelected ? 1.05 : 1)
                .animation(.snappy(duration: 0.15), value: isSelected)
                .padding(.bottom, 2)
            Text(game.title)
                .font(.callout)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 150, alignment: .top)
            if showsSystem {
                Text(game.system.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: showsSystem ? 262 : 246, alignment: .top)
        .contentShape(Rectangle())
    }
}

struct CoverView: View {
    let game: Game
    /// Fill mode crops the art to cover its frame and shows nothing while loading; used for backdrops.
    var fill = false
    @State private var image: NSImage?

    var body: some View {
        Group {
            if fill {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Color.clear
                }
            } else {
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
            }
        }
        .task(id: game.id) {
            image = await CoverArt.data(for: game).flatMap(NSImage.init(data:))
        }
    }
}
