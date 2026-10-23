import SwiftUI

/// The two places in the browser that take keyboard focus.
enum FocusArea: Hashable {
    case sidebar, games
}

struct ContentView: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var controller: ControllerInput
    @EnvironmentObject private var navigator: Navigator
    @State private var search = ""
    @FocusState private var focus: FocusArea?
    #if DEBUG
    @Environment(\.openWindow) private var openWindow
    #endif

    /// Space under the sidebar list for the controller status.
    private static let controllerStatusHeight: CGFloat = 56

    var body: some View {
        Group {
            if navigator.couchMode {
                CouchView(item: navigator.selection ?? .system(.nes), items: navigator.couchItems(library),
                          pickedGames: $navigator.pickedGames, onSelect: { navigator.selection = $0 },
                          onCycle: { navigator.cycle($0, library: library) },
                          onExit: { navigator.setCouchMode(false, library: library) })
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
            case .previousSystem: navigator.cycle(-1, library: library)
            case .nextSystem: navigator.cycle(1, library: library)
            case .toggleCouchMode: navigator.setCouchMode(!navigator.couchMode, library: library)
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
        #if DEBUG
        .onAppear {
            ControllerDiagnostics.shared.attach(controller: controller, navigator: navigator, library: library)
            if ControllerDiagnostics.requested { openWindow(id: ControllerDiagnostics.windowID) }
        }
        #endif
    }

    private var browser: some View {
        NavigationSplitView {
            ScrollViewReader { proxy in
                List(selection: $navigator.selection) {
                    ForEach(SidebarItem.sections, id: \.title) { section in
                        if let title = section.title {
                            Section(title) { rows(section.items) }
                        } else {
                            Section { rows(section.items) }
                        }
                    }
                }
                .focused($focus, equals: .sidebar)
                // Return or → opens the selected list's games; ↑ and ↓ keep moving through the sidebar.
                .onKeyPress(keys: [.return, .rightArrow]) { _ in
                    guard navigator.selection != .setup, navigator.selection != nil else { return .ignored }
                    focus = .games
                    return .handled
                }
                // The menu bar and the controller's LB and RB can select a row that's out of view.
                .onChange(of: navigator.selection) { _, item in
                    if let item { proxy.scrollTo(item) }
                }
                // Nothing that lays out views may wrap the List (ScrollViewReader doesn't), so the
                // controller status floats over room left below it: on macOS 14, a List inside
                // .safeAreaInset or a VStack keeps a 38pt column, which cuts every row off after its icon.
                .padding(.bottom, Self.controllerStatusHeight)
                .overlay(alignment: .bottom) {
                    ControllerStatus(name: controller.controllerName)
                        .padding(10)
                        .frame(height: Self.controllerStatusHeight)
                }
            }
            // On the column's outermost view: inside the ScrollViewReader it was ignored, and the
            // sidebar opened 140pt wide.
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
        } detail: {
            switch navigator.selection {
            case .setup:
                SetupView()
            case .check:
                LibraryCheckView()
            case let item?:
                GameGridView(item: item, search: search, pickedGame: pickedGame(for: item), focus: $focus)
                    .id(item)
            case nil:
                ContentUnavailableView("Pick a system", systemImage: "gamecontroller")
            }
        }
        .searchable(text: $search, prompt: "Search games")
        // Return in the search field moves to the results, so a second Return plays the first one.
        .onSubmit(of: .search) { focus = .games }
        .toolbar {
            ToolbarItemGroup {
                Button("Couch Mode", systemImage: "tv") { navigator.setCouchMode(true, library: library) }
                    .help("Full-screen view for playing with a controller")
                Button("Rescan", systemImage: "arrow.clockwise") { library.rescan() }
                    .help("Look for new games")
            }
        }
    }

    private func rows(_ items: [SidebarItem]) -> some View {
        ForEach(items, id: \.self) { item in
            SidebarRow(item: item, count: item == .setup ? nil : library.games(for: item).count)
                .tag(item)
        }
    }

    private func pickedGame(for item: SidebarItem) -> Binding<Game.ID?> {
        Binding(get: { navigator.pickedGames[item] }, set: { navigator.pickedGames[item] = $0 })
    }
}

private struct SidebarRow: View {
    let item: SidebarItem
    /// Games in the list; nil for Setup.
    let count: Int?
    @Environment(\.sidebarRowSize) private var rowSize

    /// For a system with games, whether anything installed can play them.
    private var readiness: Launcher.Readiness? {
        guard case .system(let system) = item, let count, count > 0 else { return nil }
        return Launcher.readiness(for: system)
    }

    /// Follows System Settings › Appearance › Sidebar icon size.
    private var iconSize: CGFloat {
        switch rowSize {
        case .small: 18
        case .large: 26
        default: 22
        }
    }

    var body: some View {
        let readiness = readiness
        HStack(spacing: 10) {
            IconTile(symbol: item.symbol, color: item.color, size: iconSize)
                .accessibilityHidden(true)
            Text(item.title)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let count, count > 0 {
                CountBadge(count: count, setupNeeded: readiness?.ready == false)
            }
        }
        .padding(.vertical, 2)
        .help(help(readiness))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.title)
        .accessibilityValue(accessibilityValue(readiness))
    }

    private var gamesText: String {
        count == 1 ? "1 game" : "\(count ?? 0) games"
    }

    private func help(_ readiness: Launcher.Readiness?) -> String {
        switch item {
        case .setup: return "Emulators, games folder, graphics, controller and BIOS files"
        case .check: return "New, moved, missing and duplicate games"
        case .favorites, .recent: return "\(item.title): \(gamesText)"
        case .system(let system):
            guard let readiness else { return "\(system.displayName): no games yet" }
            return "\(system.displayName): \(gamesText). "
                + (readiness.ready ? readiness.summary : "Setup needed. " + (readiness.detail ?? ""))
        }
    }

    private func accessibilityValue(_ readiness: Launcher.Readiness?) -> String {
        guard count != nil else { return "" }
        return readiness?.ready == false ? "\(gamesText), setup needed" : gamesText
    }
}

/// The number of games in a sidebar row; orange with a warning sign when no emulator can play them.
private struct CountBadge: View {
    let count: Int
    let setupNeeded: Bool
    /// Increased in a selected row with the accent-colored highlight.
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        HStack(spacing: 3) {
            if setupNeeded {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            Text("\(count)")
                .monospacedDigit()
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(foreground)
        .padding(.horizontal, 7)
        .padding(.vertical, 1)
        .background(setupNeeded ? AnyShapeStyle(.orange.opacity(0.18)) : AnyShapeStyle(.quaternary), in: Capsule())
    }

    private var foreground: AnyShapeStyle {
        if prominence == .increased { return AnyShapeStyle(.white) }
        return setupNeeded ? AnyShapeStyle(Color.warning) : AnyShapeStyle(.secondary)
    }
}

private struct ControllerStatus: View {
    let name: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: name == nil ? "gamecontroller" : "gamecontroller.fill")
                .foregroundStyle(name == nil ? Color.secondary : Color.success)
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
    /// The selected game, kept by ContentView for each list.
    @Binding var pickedGame: Game.ID?
    var focus: FocusState<FocusArea?>.Binding
    @State private var columnCount = 1

    private var selectedID: Game.ID? {
        get { pickedGame }
        nonmutating set { pickedGame = newValue }
    }

    private var gridFocused: Bool { focus.wrappedValue == .games }

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
            if !library.check.news.isEmpty {
                LibraryBanner(news: library.check.news)
            }
            GridHeader(item: item, count: library.games(for: item).count, shown: search.isEmpty ? nil : games.count)
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
                            GameCard(game: game, isSelected: game.id == selectedID, isFocused: gridFocused,
                                     isFavorite: library.isFavorite(game), showsSystem: !isSystemList,
                                     onPlay: { play(game) })
                                .id(game.id)
                                .onTapGesture(count: 2) { play(game) }
                                .onTapGesture {
                                    selectedID = game.id
                                    focus.wrappedValue = .games
                                }
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
        .focused(focus, equals: .games)
        .onAppear {
            // When a list is picked in the sidebar, focus stays there so ↑ and ↓ keep moving
            // through the lists; otherwise the games take it. Asked of AppKit: the List doesn't
            // update `focus` when a click or the keyboard puts it in charge.
            if !(NSApp.keyWindow?.firstResponder is NSOutlineView) { focus.wrappedValue = .games }
            if selectedGame == nil { selectedID = games.first?.id }
        }
        .onKeyPress(.upArrow) { handle(.move(dx: 0, dy: -1)); return .handled }
        .onKeyPress(.downArrow) { handle(.move(dx: 0, dy: 1)); return .handled }
        .onKeyPress(.leftArrow) { handle(.move(dx: -1, dy: 0)); return .handled }
        .onKeyPress(.rightArrow) { handle(.move(dx: 1, dy: 0)); return .handled }
        .onKeyPress(.return) { handle(.play); return .handled }
        .onKeyPress("f") { handle(.favorite); return .handled }
        .onKeyPress(.escape) { focus.wrappedValue = .sidebar; return .handled }
    }

    private func handle(_ command: ControllerCommand) {
        // Controller input works wherever keyboard focus is; moving focus to the games shows
        // the selected game as active.
        if command != .back { focus.wrappedValue = .games }
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
            case .setup, .check:
                EmptyView()
            }
        }
    }
}

private struct GridHeader: View {
    let item: SidebarItem
    let count: Int
    /// How many games match the search, while searching.
    let shown: Int?

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            IconTile(symbol: item.symbol, color: item.color, size: 52)
                .shadow(color: item.color.opacity(0.35), radius: 8, y: 3)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title).font(.largeTitle.weight(.bold))
                HStack(spacing: 10) {
                    Text(shown.map { "\($0) of \(count) games" } ?? (count == 1 ? "1 game" : "\(count) games"))
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
                       color: readiness.ready ? .systemGreen : .systemOrange)
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
    /// Whether the games have keyboard focus: the selected game is outlined in the accent color
    /// then, and in gray while focus is in the sidebar or the search field.
    let isFocused: Bool
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
                        .strokeBorder(isSelected ? (isFocused ? Color.accentColor : Color.secondary) : .clear, lineWidth: 3)
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
