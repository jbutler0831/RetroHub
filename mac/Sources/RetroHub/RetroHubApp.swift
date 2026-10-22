import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        #if DEBUG
        UIChecks.startIfRequested()
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
enum Main {
    @MainActor
    static func main() {
        #if DEBUG
        // Debug builds can run the checks in SelfTests.swift instead of the app.
        if ProcessInfo.processInfo.arguments.contains("--self-test") { exit(SelfTests.run()) }
        #endif
        RetroHubApp.main()
    }
}

struct RetroHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var library = Library()
    @StateObject private var controller = ControllerInput()
    @StateObject private var navigator = Navigator()

    var body: some Scene {
        // One window: every window's game grid acts on each controller press, so with two open,
        // one press of Y toggled a favorite on and straight back off (and A would start two games).
        Window("RetroHub", id: "main") {
            ContentView()
                .environmentObject(library)
                .environmentObject(controller)
                .environmentObject(navigator)
                .frame(minWidth: 760, minHeight: 480)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            SidebarCommands()
            BrowserCommands(navigator: navigator, library: library)
        }
    }
}

/// Menu bar equivalents of the toolbar and the controller's LB, RB and Menu buttons.
private struct BrowserCommands: Commands {
    let navigator: Navigator
    let library: Library

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Setup…") { perform { $0.show(.setup, library: $1) } }
                .keyboardShortcut(",")
        }
        CommandGroup(after: .textEditing) {
            Button("Find Games") { perform { $0.findGames(library: $1) } }
                .keyboardShortcut("f")
        }
        CommandGroup(before: .sidebar) {
            Button("Previous System") { perform { $0.cycle(-1, library: $1) } }
                .keyboardShortcut("[")
            Button("Next System") { perform { $0.cycle(1, library: $1) } }
                .keyboardShortcut("]")
            Divider()
            Button("Couch Mode") { perform { $0.setCouchMode(!$0.couchMode, library: $1) } }
            Button("Rescan Games") { perform { $1.rescan() } }
                .keyboardShortcut("r")
            Divider()
        }
    }

    /// Menu actions run on the main thread; Commands just isn't marked that way.
    private func perform(_ action: @MainActor (Navigator, Library) -> Void) {
        MainActor.assumeIsolated { action(navigator, library) }
    }
}
