import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
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
