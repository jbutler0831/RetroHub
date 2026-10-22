#if DEBUG
import AppKit

/// Checks that need the real window, which --self-test can't reach. A debug build launched with
/// `--ui-check <folder>` opens as usual, checks the sidebar after each step below, saves a picture
/// of the window to the folder for each step and quits with 0 if every check passed:
///
///     scripts/dev-ui-check.sh
///
/// The app draws the pictures itself, so no Screen Recording permission is needed.
@MainActor
enum UIChecks {
    private static var failures = 0
    private static var checks = 0

    static func startIfRequested() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--ui-check") else { return }
        let folder = arguments.indices.contains(flag + 1) ? URL(filePath: arguments[flag + 1]) : nil
        Task { exit(await run(picturesIn: folder)) }
    }

    private static func run(picturesIn folder: URL?) async -> Int32 {
        setvbuf(stdout, nil, _IONBF, 0)
        await pause(2)
        guard let window = NSApp.windows.first(where: \.isVisible),
              let sidebar = window.contentView.flatMap(outlineView) else {
            print("FAIL: no window with a sidebar")
            return 1
        }

        let steps: [(name: String, action: () async -> Void)] = [
            ("launch", {}),
            ("next item", {
                let title = window.title
                window.makeFirstResponder(sidebar)
                sidebar.keyDown(with: downArrow(in: window))
                await pause(1)
                expect(window.title != title, "down arrow moved from \(title) to \(window.title)")
            }),
            ("scrolled to the end", {
                sidebar.scrollRowToVisible(sidebar.numberOfRows - 1)
                await pause(0.5)
            }),
            ("hidden and shown", {
                for _ in 0..<2 {
                    NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
                    await pause(1)
                }
            }),
        ]
        for (index, step) in steps.enumerated() {
            print("- \(step.name)")
            await step.action()
            checkRows(sidebar)
            savePicture(of: window, to: folder?.appending(path: "\(index + 1) \(step.name).png"))
        }

        print(failures == 0 ? "PASS: \(checks) checks" : "FAIL: \(failures) of \(checks) checks failed")
        return failures == 0 ? 0 : 1
    }

    private static func expect(_ passed: Bool, _ label: String) {
        checks += 1
        if !passed { failures += 1 }
        print("  \(passed ? "ok" : "FAIL") \(label)")
    }

    /// Each row has to span the sidebar, less its insets, or its name is cut off after the icon.
    private static func checkRows(_ sidebar: NSTableView) {
        let width = sidebar.enclosingScrollView?.frame.width ?? sidebar.frame.width
        let rows = (0..<sidebar.numberOfRows).compactMap { sidebar.view(atColumn: 0, row: $0, makeIfNecessary: false) }
        let narrowest = rows.map(\.frame.width).min() ?? 0
        expect(!rows.isEmpty && narrowest >= width - 40,
               "\(rows.count) rows, narrowest \(Int(narrowest))pt, in a \(Int(width))pt sidebar")
    }

    private static func outlineView(in view: NSView) -> NSOutlineView? {
        view as? NSOutlineView ?? view.subviews.lazy.compactMap(outlineView).first
    }

    private static func downArrow(in window: NSWindow) -> NSEvent {
        let key = String(Character(UnicodeScalar(UInt32(NSDownArrowFunctionKey))!))
        return NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                windowNumber: window.windowNumber, context: nil, characters: key,
                                charactersIgnoringModifiers: key, isARepeat: false, keyCode: 125)!
    }

    private static func savePicture(of window: NSWindow, to url: URL?) {
        guard let url, let frame = window.contentView?.superview,
              let picture = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return }
        frame.cacheDisplay(in: frame.bounds, to: picture)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? picture.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}
#endif
