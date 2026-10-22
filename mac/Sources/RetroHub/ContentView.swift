import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var controller: ControllerInput
    // New users land on Setup until they have an emulator.
    @State private var selection: SidebarItem? = Emulator.allCases.contains(where: \.isInstalled) ? .system(.nes) : .setup
    @State private var search = ""
    @State private var couchMode = false

    /// Space under the sidebar list for the controller status.
    private static let controllerStatusHeight: CGFloat = 56

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
                Section {
                    ForEach([SidebarItem.favorites, .recent], id: \.self) { item in
                        SidebarRow(item: item, count: library.games(for: item).count).tag(item)
                    }
                    SidebarRow(item: .setup, count: nil).tag(SidebarItem.setup)
                }
                ForEach(GameSystem.makers, id: \.self) { maker in
                    Section(maker) {
                        ForEach(GameSystem.allCases.filter { $0.maker == maker }) { system in
                            let item = SidebarItem.system(system)
                            SidebarRow(item: item, count: library.games(for: item).count).tag(item)
                        }
                    }
                }
            }
            // The List must stay the sidebar's root view, so the controller status floats over
            // room left below it: on macOS 14, a List inside .safeAreaInset or a VStack keeps a
            // 38pt column, which cuts every row off after its icon.
            .padding(.bottom, Self.controllerStatusHeight)
            .overlay(alignment: .bottom) {
                ControllerStatus(name: controller.controllerName)
                    .padding(10)
                    .frame(height: Self.controllerStatusHeight)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
        } detail: {
            switch selection {
            case .setup:
                SetupView()
            case let item?:
                GameGridView(item: item, search: search)
                    .id(item)
            case nil:
                ContentUnavailableView("Pick a system", systemImage: "gamecontroller")
            }
        }
        .searchable(text: $search, prompt: "Search games")
        .toolbar {
            ToolbarItemGroup {
                Button("Couch Mode", systemImage: "tv") { setCouchMode(true) }
                    .help("Full-screen view for playing with a controller")
                Button("Rescan", systemImage: "arrow.clockwise") { library.rescan() }
                    .help("Look for new games")
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
        if on, let first = couchItems.first, !couchItems.contains(selection ?? .setup) {
            selection = first
        }
        if let window = NSApp.keyWindow ?? NSApp.windows.first,
           window.styleMask.contains(.fullScreen) != on {
            window.toggleFullScreen(nil)
        }
    }
}

private struct SidebarRow: View {
    let item: SidebarItem
    let count: Int?

    var body: some View {
        HStack(spacing: 10) {
            IconTile(symbol: item.symbol, color: item.color)
            Text(item.title)
            Spacer()
            if let count, count > 0 {
                Text("\(count)")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ControllerStatus: View {
    let name: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: name == nil ? "gamecontroller" : "gamecontroller.fill")
                .foregroundStyle(name == nil ? Color.secondary : Color.green)
            Text(name ?? "No controller")
                .font(.callout)
                .foregroundStyle(name == nil ? .secondary : .primary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help(name == nil ? "Pair a controller in System Settings › Bluetooth"
                          : "A: play · Y: favorite · LB/RB: switch · Menu: couch mode")
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

    private static let cardWidth: CGFloat = 160
    private static let spacing: CGFloat = 24

    private var games: [Game] {
        let all = library.games(for: item)
        return search.isEmpty ? all : all.filter { $0.displayTitle.localizedCaseInsensitiveContains(search) }
    }

    private var selectedGame: Game? {
        games.first { $0.id == selectedID }
    }

    private var isSystemList: Bool {
        if case .system = item { true } else { false }
    }

    var body: some View {
        VStack(spacing: 0) {
            GridHeader(item: item, count: library.games(for: item).count)
            if games.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                grid
            }
        }
        .background(alignment: .top) {
            LinearGradient(colors: [item.color.opacity(0.16), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 220)
                .ignoresSafeArea()
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
                                     isFavorite: library.isFavorite(game), showsSystem: !isSystemList,
                                     onPlay: { play(game) })
                                .id(game.id)
                                .onTapGesture(count: 2) { play(game) }
                                .onTapGesture { selectedID = game.id }
                                .contextMenu {
                                    Button("Play", systemImage: "play.fill") { play(game) }
                                    Button(library.isFavorite(game) ? "Remove from Favorites" : "Add to Favorites",
                                           systemImage: library.isFavorite(game) ? "star.slash" : "star") {
                                        library.toggleFavorite(game)
                                    }
                                    Divider()
                                    Button("Show in Finder", systemImage: "folder") {
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
                FriendlyEmptyState(item: item, title: "No favorites yet",
                                   message: "Right-click a game and choose Add to Favorites, press F, or press Y on your controller.")
            case .recent:
                FriendlyEmptyState(item: item, title: "Nothing played yet",
                                   message: "The games you play will show up here so you can jump right back in.")
            case .system(let system):
                SystemEmptyState(system: system)
            case .setup:
                EmptyView()
            }
        }
    }
}

private struct GridHeader: View {
    let item: SidebarItem
    let count: Int

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            IconTile(symbol: item.symbol, color: item.color, size: 52)
                .shadow(color: item.color.opacity(0.35), radius: 8, y: 3)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title).font(.largeTitle.weight(.bold))
                HStack(spacing: 10) {
                    Text(count == 1 ? "1 game" : "\(count) games")
                        .foregroundStyle(.secondary)
                    if case .system(let system) = item {
                        SystemStatus(system: system)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }
}

/// Green "Plays with…" or orange "Setup needed" pill, with details on hover and a download button.
private struct SystemStatus: View {
    let system: GameSystem

    var body: some View {
        let readiness = Launcher.readiness(for: system)
        HStack(spacing: 8) {
            StatusPill(text: readiness.summary,
                       symbol: readiness.ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                       color: readiness.ready ? .green : .orange)
                .help(readiness.detail ?? "")
            if let missing = readiness.missing {
                Button("Get \(missing.displayName)") { NSWorkspace.shared.open(missing.downloadURL) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }
}

private struct FriendlyEmptyState: View {
    let item: SidebarItem
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            IconTile(symbol: item.symbol, color: item.color, size: 72)
                .shadow(color: item.color.opacity(0.35), radius: 12, y: 4)
            Text(title).font(.title2.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(40)
    }
}

/// Two-step checklist: get an emulator, then add games.
private struct SystemEmptyState: View {
    @EnvironmentObject private var library: Library
    let system: GameSystem

    var body: some View {
        let readiness = Launcher.readiness(for: system)
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                IconTile(symbol: system.symbol, color: system.color, size: 72)
                    .shadow(color: system.color.opacity(0.35), radius: 12, y: 4)
                Text("Let's add some \(system.displayName) games")
                    .font(.title2.weight(.semibold))
            }
            VStack(alignment: .leading, spacing: 0) {
                StepRow(number: 1, done: readiness.ready, title: readiness.ready ? readiness.summary : "Get an emulator",
                        detail: readiness.detail) {
                    if let missing = readiness.missing {
                        Button("Get \(missing.displayName)") { NSWorkspace.shared.open(missing.downloadURL) }
                            .buttonStyle(.borderedProminent)
                    }
                }
                Divider().padding(.leading, 52)
                StepRow(number: 2, done: false, title: "Add your games",
                        detail: system == .vita
                            ? "Install them in Vita3K (File › Install .pkg or .vpk); they show up here."
                            : "Put \(system.fileHint) in the \(system.folderName) folder.") {
                    Button("Open Folder") { NSWorkspace.shared.open(library.folder(for: system)) }
                        .buttonStyle(.bordered)
                }
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.quaternary))
            .frame(maxWidth: 520)
        }
        .padding(40)
    }
}

private struct StepRow<Action: View>: View {
    let number: Int
    let done: Bool
    let title: String
    let detail: String?
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle().fill(done ? Color.green : Color.accentColor.opacity(0.15))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.callout.weight(.semibold)).foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                if let detail {
                    Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            Spacer(minLength: 12)
            action()
        }
        .padding(16)
    }
}

private struct GameCard: View {
    let game: Game
    let isSelected: Bool
    let isFavorite: Bool
    let showsSystem: Bool
    let onPlay: () -> Void
    @State private var isHovering = false

    private var isRaised: Bool { isSelected || isHovering }

    var body: some View {
        VStack(spacing: 8) {
            CoverView(game: game)
                .frame(width: 160, height: 214)
                .overlay(alignment: .topTrailing) {
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.yellow)
                            .padding(6)
                            .background(.black.opacity(0.55), in: Circle())
                            .padding(8)
                    }
                }
                .overlay {
                    if isHovering {
                        Button(action: onPlay) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 54, height: 54)
                                .background(.black.opacity(0.45), in: Circle())
                                .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                }
                .shadow(color: .black.opacity(isRaised ? 0.3 : 0.12), radius: isRaised ? 12 : 4, y: isRaised ? 6 : 2)
                .scaleEffect(isSelected ? 1.04 : isHovering ? 1.02 : 1)
            VStack(spacing: 2) {
                Text(game.displayTitle)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if showsSystem {
                    Text(game.system.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 160)
        }
        .frame(height: showsSystem ? 282 : 266, alignment: .top)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.snappy(duration: 0.18)) { isHovering = hovering }
        }
        .animation(.snappy(duration: 0.18), value: isSelected)
    }
}

struct CoverView: View {
    let game: Game
    /// Fill mode shows a blurred copy cropped to cover its frame, and nothing while loading; used for backdrops.
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
                    if let image {
                        Rectangle().fill(.black.opacity(0.85))
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                    } else {
                        placeholder
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .task(id: game.id) {
            guard let data = await CoverArt.data(for: game) else { return }
            if fill {
                image = await CoverArt.blurred(data).map { NSImage(cgImage: $0, size: .zero) }
            } else {
                image = NSImage(data: data)
            }
        }
    }

    /// Shown while art loads, or when none was found: a box in the system's color.
    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [game.system.color, game.system.color.opacity(0.6)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 10) {
                Image(systemName: game.system.symbol)
                    .font(.system(size: 34, weight: .semibold))
                    .opacity(0.9)
                Text(game.displayTitle)
                    .font(.callout.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
            }
            .foregroundStyle(.white)
            .padding(14)
        }
    }
}
