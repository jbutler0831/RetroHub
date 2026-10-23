import AppKit

/// Which list the window shows, the game picked in each list, and whether couch mode is on. The
/// sidebar, the menu bar, the keyboard and the controller all change them through here, so they
/// stay in step with each other.
@MainActor
final class Navigator: ObservableObject {
    // New users land on Setup until they have an emulator.
    @Published var selection: SidebarItem? = Emulator.allCases.contains(where: \.isInstalled) ? .system(.nes) : .setup
    @Published private(set) var couchMode = false
    /// The game last picked in each list, in the browser or couch mode, so going back to a list
    /// lands on it again.
    @Published var pickedGames: [SidebarItem: Game.ID] = [:]
    /// The list shown before Library Check, where its Done button goes back to.
    private var beforeCheck: SidebarItem?

    /// Couch mode only shows lists with games in them, so the controller never lands on a blank screen.
    func couchItems(_ library: Library) -> [SidebarItem] {
        SidebarItem.all.filter { !library.games(for: $0).isEmpty }
    }

    /// Shows a list, or Setup, in the browser.
    func show(_ item: SidebarItem, library: Library) {
        if couchMode { setCouchMode(false, library: library) }
        if item == .check, selection != .check { beforeCheck = selection }
        selection = item
    }

    /// Back from Library Check to the list shown before it.
    func leaveCheck(library: Library) {
        show(beforeCheck ?? .system(.nes), library: library)
    }

    /// The next (1) or previous (-1) list: RB and LB, ⌘] and ⌘[.
    func cycle(_ step: Int, library: Library) {
        selection = SidebarItem.stepping(from: selection ?? .system(.nes), by: step,
                                         in: couchMode ? couchItems(library) : SidebarItem.all) ?? selection
    }

    func setCouchMode(_ on: Bool, library: Library) {
        couchMode = on
        let items = couchItems(library)
        if on, let first = items.first, !items.contains(selection ?? .setup) {
            selection = first
        }
        if let window = mainWindow, window.styleMask.contains(.fullScreen) != on {
            window.toggleFullScreen(nil)
        }
    }

    /// Puts the cursor in the toolbar's search field (Edit › Find Games, ⌘F).
    func findGames(library: Library) {
        if couchMode { setCouchMode(false, library: library) }
        guard let window = mainWindow,
              let item = window.toolbar?.items.first(where: { $0 is NSSearchToolbarItem || $0.view is NSSearchField })
        else { return }
        if let item = item as? NSSearchToolbarItem {
            item.beginSearchInteraction()
        } else if let field = item.view {
            window.makeFirstResponder(field)
        }
    }

    private var mainWindow: NSWindow? {
        NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible }
    }
}
