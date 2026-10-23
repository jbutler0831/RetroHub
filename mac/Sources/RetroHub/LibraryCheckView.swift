import SwiftUI

/// Library Check: what the Smart Game Scanner found (Scanner.swift) since the changes were last
/// reviewed. Nothing changes without one of its buttons: a renamed game takes its favorite and
/// play history along only when confirmed, and a missing game is kept until it's removed.
struct LibraryCheckView: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var navigator: Navigator
    @State private var confirmingRemoveAll = false

    private var summary: Scanner.Summary { library.check.summary }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 16) {
                    IconTile(symbol: SidebarItem.check.symbol, color: SidebarItem.check.color, size: 52)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Library Check").font(.largeTitle.weight(.bold))
                        Text(library.check.news.isEmpty ? "No changes since you last checked." : "Since you last checked: \(library.check.news)")
                            .foregroundStyle(.secondary)
                    }
                }

                section("Moved or renamed", count: summary.renamed.count,
                        subtitle: "Files that turned up under a new name. Their favorite and play history move with them only when you confirm.") {
                    Button("Same game for all") {
                        for rename in summary.renamed { library.applyRename(from: rename.from, to: rename.to) }
                    }
                } rows: {
                    ForEach(summary.renamed, id: \.from) { rename in
                        row(rename.system, rename.title, "Now: \(name(rename.to)) · \(carries(rename.from))", "Was: \(name(rename.from))") {
                            Button("Same game") { library.applyRename(from: rename.from, to: rename.to) }
                                .buttonStyle(.borderedProminent)
                            Button("Not the same") { library.notRenamed(from: rename.from) }
                        }
                    }
                }

                section("Missing", count: summary.missing.count,
                        subtitle: "Games whose files are gone. They're kept, with their favorites and play history, until you remove them, so nothing is lost if the files come back (from an external drive, say).") {
                    Button("Remove All…") { confirmingRemoveAll = true }
                } rows: {
                    ForEach(summary.missing, id: \.path) { missing in
                        let since = Date(timeIntervalSince1970: missing.since / 1000).formatted(.relative(presentation: .named))
                        row(missing.system, missing.title, "\(name(missing.path)) · missing since \(since) · \(carries(missing.path))") {
                            Button("Remove") { library.removeMissing([missing.path]) }
                        }
                    }
                }

                section("New", count: summary.added.count, subtitle: "Games added since you last checked. They are already in your library.") {
                    EmptyView()
                } rows: {
                    ForEach(summary.added, id: \.path) { added in
                        row(added.system, added.title, "\(GameSystem(rawValue: added.system)?.displayName ?? added.system) · \(name(added.path))") { EmptyView() }
                    }
                }

                section("Duplicates", count: summary.duplicates.count, subtitle: "The same file in more than one place.") {
                    EmptyView()
                } rows: {
                    ForEach(summary.duplicates, id: \.paths) { duplicate in
                        row(duplicate.system, duplicate.title, duplicate.paths.map(name).joined(separator: " · ")) {
                            ForEach(Array(duplicate.paths.enumerated()), id: \.element) { number, path in
                                Button("Show Copy \(number + 1)") { library.showInFinder(path: path) }
                                    .help(path)
                            }
                        }
                    }
                }

                section("No cover art found", count: library.check.noArt.count,
                        subtitle: "RetroHub looked for these covers and found none. Put an image with the same name next to the game, or look again.") {
                    Button("Look Again") { library.lookAgainForCovers() }
                } rows: {
                    ForEach(library.check.noArt) { game in
                        row(game.system.rawValue, game.displayTitle, game.system.displayName) { EmptyView() }
                    }
                }

                Button("Done") {
                    library.markReviewed()
                    navigator.leaveCheck(library: library)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .navigationTitle("Library Check")
        .confirmationDialog(summary.missing.count == 1 ? "Remove the missing game?" : "Remove all \(summary.missing.count) missing games?",
                            isPresented: $confirmingRemoveAll) {
            Button("Remove", role: .destructive) { library.removeMissing(summary.missing.map(\.path)) }
        } message: {
            Text("Their favorites and play history are forgotten.")
        }
    }

    private func name(_ path: String) -> String { URL(filePath: path).lastPathComponent }

    /// What confirming or removing would affect: "favorite · played 3 days ago".
    private func carries(_ path: String) -> String {
        var parts: [String] = []
        if library.isFavorite(path: path) { parts.append("favorite") }
        if let played = library.lastPlayed(path: path) { parts.append("played \(played.formatted(.relative(presentation: .named)))") }
        return parts.isEmpty ? "no favorite or play history" : parts.joined(separator: " · ")
    }

    private func section<Actions: View, Rows: View>(_ title: String, count: Int, subtitle: String,
                                                   @ViewBuilder actions: () -> Actions,
                                                   @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.title3.weight(.semibold))
                Text("\(count)").font(.title3).foregroundStyle(.secondary)
                Spacer()
                if count > 0 { actions() }
            }
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
            if count == 0 {
                Text("None.").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) { rows() }
                    .padding(.horizontal, 16)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.quaternary))
            }
        }
    }

    /// A game's row: its system's icon, its title, one or two lines of detail, and its buttons.
    private func row<Buttons: View>(_ system: String, _ title: String, _ detail: String, _ more: String? = nil,
                                    @ViewBuilder buttons: () -> Buttons) -> some View {
        let system = GameSystem(rawValue: system)
        return HStack(spacing: 12) {
            IconTile(symbol: system?.symbol ?? "gamecontroller.fill", color: system?.color ?? .gray, size: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                ForEach([detail] + (more.map { [$0] } ?? []), id: \.self) { line in
                    Text(line).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            buttons()
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// "Library changed: 2 new · 1 moved or renamed · 1 missing", above the game lists.
struct LibraryBanner: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var navigator: Navigator
    let news: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: SidebarItem.check.symbol)
            Text("Library changed: \(news)")
            Spacer()
            Button("Review") { navigator.show(.check, library: library) }
        }
        .font(.callout)
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(SidebarItem.check.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 28)
        .padding(.top, 16)
    }
}
