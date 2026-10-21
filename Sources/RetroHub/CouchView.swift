import SwiftUI

/// Full-screen, controller-first view: a carousel of covers over a blurred backdrop.
struct CouchView: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var controller: ControllerInput
    let item: SidebarItem
    /// The tabs across the top; only lists that have games.
    let items: [SidebarItem]
    let onSelect: (SidebarItem) -> Void
    let onCycle: (Int) -> Void
    let onExit: () -> Void
    @State private var index = 0
    @FocusState private var focused: Bool

    private static let coverSize = CGSize(width: 220, height: 300)

    private var games: [Game] { library.games(for: item) }

    private var current: Game? {
        games.indices.contains(index) ? games[index] : nil
    }

    var body: some View {
        ZStack {
            Color.black
            if let current {
                Color.clear
                    .overlay { CoverView(game: current, fill: true) }
                    .clipped()
                    .blur(radius: 50)
                    .opacity(0.45)
                    .id(current.id)
                    .transition(.opacity)
            }
            VStack(spacing: 0) {
                tabs.padding(.top, 50)
                Spacer()
                if let current {
                    carousel
                    details(for: current)
                } else {
                    emptyMessage
                }
                Spacer()
                hints.padding(.bottom, 40)
            }
        }
        .ignoresSafeArea()
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .overlay(alignment: .topTrailing) {
            Button(action: onExit) {
                Image(systemName: "xmark.circle.fill").font(.title)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.6))
            .padding(24)
            .help("Exit couch mode (Esc)")
        }
        .animation(.easeOut(duration: 0.25), value: current?.id)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onChange(of: item) { index = 0 }
        .onChange(of: games.count) { _, count in index = min(index, max(0, count - 1)) }
        .onReceive(controller.commands, perform: handle)
        .onKeyPress(.leftArrow) { handle(.move(dx: -1, dy: 0)); return .handled }
        .onKeyPress(.rightArrow) { handle(.move(dx: 1, dy: 0)); return .handled }
        .onKeyPress(.upArrow) { handle(.move(dx: 0, dy: -1)); return .handled }
        .onKeyPress(.downArrow) { handle(.move(dx: 0, dy: 1)); return .handled }
        .onKeyPress(.return) { handle(.play); return .handled }
        .onKeyPress(.escape) { handle(.back); return .handled }
        .onKeyPress("f") { handle(.favorite); return .handled }
    }

    private var tabs: some View {
        HStack(spacing: 20) {
            buttonBadge("LB")
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 32) {
                        ForEach(items, id: \.self) { tab in
                            Text(tab.title)
                                .font(.title2.weight(tab == item ? .bold : .regular))
                                .opacity(tab == item ? 1 : 0.45)
                                .id(tab)
                                .onTapGesture { onSelect(tab) }
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .onChange(of: item, initial: true) { _, tab in
                    withAnimation { proxy.scrollTo(tab, anchor: .center) }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            buttonBadge("RB")
        }
        .padding(.horizontal, 60)
    }

    private var carousel: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 36) {
                        ForEach(Array(games.enumerated()), id: \.element.id) { offset, game in
                            CoverView(game: game)
                                .frame(width: Self.coverSize.width, height: Self.coverSize.height)
                                .scaleEffect(offset == index ? 1.15 : 0.9)
                                .opacity(offset == index ? 1 : 0.5)
                                .shadow(color: .black.opacity(0.6), radius: offset == index ? 24 : 4)
                                .id(game.id)
                                .onTapGesture(count: 2) { index = offset; play() }
                                .onTapGesture { index = offset }
                        }
                    }
                    // Lets the first and last covers sit in the middle of the screen.
                    .padding(.horizontal, max(0, (geometry.size.width - Self.coverSize.width) / 2))
                    .frame(height: geometry.size.height)
                }
                .onChange(of: index, initial: true) {
                    if let id = current?.id {
                        withAnimation(.snappy(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
        .frame(height: Self.coverSize.height * 1.4)
        .id(item)
    }

    private func details(for game: Game) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Text(game.title).font(.system(size: 34, weight: .bold))
                if library.isFavorite(game) {
                    Image(systemName: "star.fill").font(.title).foregroundStyle(.yellow)
                }
            }
            Text(([game.system.displayName] + [library.lastPlayed(game).map {
                "Last played " + $0.formatted(.relative(presentation: .named))
            }].compactMap { $0 }).joined(separator: "  ·  "))
                .font(.title3)
                .opacity(0.7)
        }
        .lineLimit(1)
        .padding(.horizontal, 60)
    }

    private var emptyMessage: some View {
        VStack(spacing: 12) {
            Image(systemName: "gamecontroller").font(.system(size: 60))
            Text("No games yet").font(.largeTitle.bold())
            Text("Add games to \(library.root.path(percentEncoded: false)) to see them here.")
                .font(.title3)
                .opacity(0.7)
        }
    }

    private var hints: some View {
        HStack(spacing: 36) {
            hint("A", "Play")
            hint("Y", "Favorite")
            hint("LB  RB", "Switch")
            hint("B", "Exit")
        }
        .font(.headline)
    }

    private func hint(_ button: String, _ label: String) -> some View {
        HStack(spacing: 10) {
            buttonBadge(button)
            Text(label).opacity(0.8)
        }
    }

    private func buttonBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.white.opacity(0.2), in: Capsule())
    }

    private func handle(_ command: ControllerCommand) {
        switch command {
        case .move(let dx, let dy):
            if dy != 0 {
                onCycle(dy)
            } else if !games.isEmpty {
                index = min(max(index + dx, 0), games.count - 1)
            }
        case .play:
            // With an error showing, A dismisses it instead of retrying the launch.
            if library.launchError != nil {
                library.launchError = nil
            } else {
                play()
            }
        case .favorite:
            if let current { library.toggleFavorite(current) }
        case .back:
            if library.launchError != nil {
                library.launchError = nil
            } else {
                onExit()
            }
        case .previousSystem, .nextSystem, .toggleCouchMode:
            break
        }
    }

    private func play() {
        guard let current else { return }
        library.play(current)
        // The game just moved to the front of Recently Played.
        if item == .recent { index = 0 }
    }
}
