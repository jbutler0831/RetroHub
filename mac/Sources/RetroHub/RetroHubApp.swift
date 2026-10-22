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

    var body: some Scene {
        WindowGroup("RetroHub") {
            ContentView()
                .environmentObject(library)
                .environmentObject(controller)
                .frame(minWidth: 760, minHeight: 480)
        }
    }
}
