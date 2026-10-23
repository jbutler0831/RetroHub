#if DEBUG
import AppKit

/// Checks that need the real window, which --self-test can't reach, run by a debug build launched
/// with `--ui-check <folder>`:
///
///     scripts/dev-ui-check.sh
///
/// The app opens as usual, then each step acts on it the way a person would (keys sent to the
/// window, menu shortcuts, simulated controller presses) and checks the result. A picture of the
/// window is saved to the folder after each step (the app draws it itself, so no Screen Recording
/// permission is needed), and the app quits with 0 if every check passed. `--rows-only` checks
/// just the sidebar rows, for runs at other sidebar icon sizes; `--relaunch` checks that the
/// appearance the full run ended on (Dark) was kept.
///
/// The steps expect fresh settings and the test library from scripts/make-test-library.swift.
@MainActor
enum UIChecks {
    private struct Step {
        let name: String
        var wait = 0.8
        let action: () -> Void
        var check: () -> Void = {}
    }

    private static var failures = 0
    private static var checks = 0
    private static var steps: [Step] = []
    private static var stepNumber = 0
    private static var folder: URL?
    private static var rowsOnly = false
    private static var relaunch = false
    private static var window: NSWindow!
    private static var activity: NSObjectProtocol?
    /// The sidebar's scroll position before a step, to tell whether the step scrolled it.
    private static var sidebarOrigin = NSPoint.zero
    private static var favoritesBefore: [String] = []
    /// System Settings › Appearance when the checks started; RetroHub's setting mustn't change it.
    private static var macAppearanceAtLaunch = ""

    static func startIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "--ui-check") else { return }
        folder = arguments.indices.contains(flag + 1) ? URL(filePath: arguments[flag + 1]) : nil
        rowsOnly = arguments.contains("--rows-only")
        relaunch = arguments.contains("--relaunch")
        macAppearanceAtLaunch = macAppearance
        // App Nap would hold back the timers below while the window isn't in front.
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "RetroHub UI checks")
        setvbuf(stdout, nil, _IONBF, 0)
        // Main-queue timers rather than Task.sleep: in an async Task here, a step sometimes
        // never resumed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard let main = NSApp.windows.first(where: { $0.isVisible }) else {
                print("FAIL: no window")
                exit(1)
            }
            window = main
            window.setContentSize(NSSize(width: 1100, height: 680))
            if rowsOnly || relaunch {
                steps = rowsOnly ? rowSteps() : relaunchSteps()
                runNextStep()
            } else {
                steps = allSteps()
                activateThenRun(attempts: 90)
            }
        }
    }

    /// Keyboard focus and menu commands only behave normally in the active window, and macOS
    /// declines to bring an app forward while someone is using another one, so this keeps asking.
    private static func activateThenRun(attempts: Int) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if window.isKeyWindow || attempts == 0 {
            if !window.isKeyWindow { print("(the window never became active: keyboard and menu checks may fail)") }
            return runNextStep()
        }
        if attempts == 90 { print("(waiting up to 90 seconds for the window to become active: click it, or leave other apps alone)") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { activateThenRun(attempts: attempts - 1) }
    }

    private static func runNextStep() {
        guard !steps.isEmpty else {
            print(failures == 0 ? "PASS: \(checks) checks" : "FAIL: \(failures) of \(checks) checks failed")
            exit(failures == 0 ? 0 : 1)
        }
        let step = steps.removeFirst()
        stepNumber += 1
        print("- \(step.name)")
        if !window.isKeyWindow && !rowsOnly && !relaunch {
            print("  (the window isn't active, so keyboard and menu checks may fail)")
        }
        sidebarOrigin = sidebar?.visibleRect.origin ?? .zero
        step.action()
        DispatchQueue.main.asyncAfter(deadline: .now() + step.wait) {
            step.check()
            savePicture(String(format: "%02d %@.png", stepNumber, step.name))
            runNextStep()
        }
    }

    // MARK: Steps

    private static func rowSteps() -> [Step] {
        [Step(name: "rows at this sidebar size", action: {}, check: checkRows)]
    }

    private static func relaunchSteps() -> [Step] {
        [Step(name: "relaunch keeps Dark", action: {}, check: {
            expect(UserDefaults.standard.string(forKey: AppAppearance.key) == "dark", "Dark is still saved")
            expect(NSApp.appearance?.name == .darkAqua, "and applied at launch")
            expect(isDark(window.effectiveAppearance), "the window draws dark")
            expect(macAppearance == macAppearanceAtLaunch, "the Mac's own appearance is unchanged: \(macAppearance)")
        })]
    }

    private static func allSteps() -> [Step] {
        [
            Step(name: "launch", action: {}, check: {
                checkRows()
                expect(window.title == "Setup", "opens on Setup (no emulators): \(window.title)")
                expect(menuItem(key: "n", title: "Window") == nil, "no New Window command, so one controller press acts once")
                expect(menuItem(key: ",", title: "Setup") != nil, "Setup… (⌘,) is in the app menu")
                expect(UserDefaults.standard.string(forKey: AppAppearance.key) == nil && NSApp.appearance == nil,
                       "follows the system appearance by default")
            }),
            Step(name: "down arrow in the sidebar", action: {
                if let sidebar { window.makeFirstResponder(sidebar) }
                sidebarOrigin = sidebar?.visibleRect.origin ?? .zero
                press(.down)
            }, check: {
                expect(window.title == "NES", "↓ selects NES: \(window.title)")
                expect(sidebarFocused, "the sidebar keeps keyboard focus")
                expect(sidebar?.visibleRect.origin == sidebarOrigin, "the sidebar doesn't scroll for a row already in view")
                checkSelectionVisible()
            }),
            Step(name: "down arrow again", action: { press(.down) }, check: {
                expect(window.title == "Super Nintendo", "a second ↓ selects Super Nintendo: \(window.title)")
            }),
            Step(name: "up arrow", action: { press(.up) }, check: {
                expect(window.title == "NES", "↑ goes back to NES: \(window.title)")
            }),
            // Rows: an empty header, Favorites, Recently Played, Setup, the Nintendo header, NES, Super Nintendo.
            Step(name: "click Super Nintendo", action: { click(row: 6) }, check: {
                expect(window.title == "Super Nintendo", "a click selects Super Nintendo: \(window.title)")
                expect(sidebarFocused, "the sidebar keeps keyboard focus after a click")
            }),
            Step(name: "down arrow after the click", action: { press(.down) }, check: {
                expect(window.title == "Nintendo 64", "↓ after the click selects Nintendo 64: \(window.title)")
            }),
            Step(name: "up twice", action: {
                press(.up)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { press(.up) }
            }, check: {
                expect(window.title == "NES", "back on NES: \(window.title)")
            }),
            Step(name: "return opens the games", action: { press(.return) }, check: {
                expect(gamesFocused, "Return moves keyboard focus to the games")
                expect(window.title == "NES", "and NES stays selected: \(window.title)")
            }),
            Step(name: "F favorites the first game", action: { press(.f) }, check: {
                expect(favorites == ["Legend of Placeholder, The (USA) [!].nes"], "F adds the selected game: \(favorites)")
            }),
            Step(name: "right arrow in the games", action: { press(.right) }),
            Step(name: "F favorites the second game", action: { press(.f) }, check: {
                expect(favorites.count == 2, "→ then F adds the second game: \(favorites)")
            }),
            Step(name: "escape returns to the sidebar", action: { press(.escape) }, check: {
                expect(sidebarFocused, "Esc moves keyboard focus back to the sidebar")
            }),
            Step(name: "down to Super Nintendo", action: { press(.down) }),
            Step(name: "back up to NES", action: { press(.up) }, check: {
                expect(window.title == "NES", "back on NES: \(window.title)")
            }),
            Step(name: "the second game is still picked", action: { press(.return) }),
            Step(name: "F removes the picked game", action: { press(.f) }, check: {
                expect(favorites == ["Legend of Placeholder, The (USA) [!].nes"],
                       "F acts on the game picked before leaving NES, not the first one: \(favorites)")
            }),
            Step(name: "setup shortcut", action: { shortcut(",") }, check: {
                expect(window.title == "Setup", "⌘, shows Setup: \(window.title)")
            }),
            Step(name: "LB from Setup", action: { controller(.previousSystem) }, check: {
                expect(window.title == "Arcade", "LB from Setup wraps to the last list, Arcade: \(window.title)")
                checkSelectionVisible()
            }),
            Step(name: "RB wraps to Favorites", action: { controller(.nextSystem) }, check: {
                expect(window.title == "Favorites", "RB from Arcade wraps to Favorites: \(window.title)")
                checkSelectionVisible()
            }),
            Step(name: "Y on Favorites", action: { controller(.favorite) }, check: {
                expect(favorites.isEmpty, "Y removes the one favorite, exactly once: \(favorites)")
                expect(gamesFocused, "controller input moves keyboard focus to the games")
            }),
            Step(name: "next system shortcut", action: { shortcut("]") }, check: {
                expect(window.title == "Recently Played", "⌘] selects Recently Played: \(window.title)")
            }),
            Step(name: "previous system shortcut", action: { shortcut("["); shortcut("]"); shortcut("]") }, check: {
                expect(window.title == "NES", "⌘[ and ⌘] step through the lists: \(window.title)")
            }),
            Step(name: "find shortcut", action: { shortcut("f") }, check: {
                expect(searchFocused, "⌘F puts the cursor in the search field")
            }),
            Step(name: "search for pattern", wait: 1, action: {
                (window.firstResponder as? NSTextView)?.insertText("pattern", replacementRange: NSRange(location: NSNotFound, length: 0))
            }),
            Step(name: "return in the search field", action: { press(.return) }, check: {
                expect(gamesFocused, "Return in the search field moves to the results")
            }),
            Step(name: "F on the only result", action: { press(.f) }, check: {
                expect(favorites == ["RetroHub Test Pattern.nes"], "F adds the one game matching \"pattern\": \(favorites)")
            }),
            Step(name: "clear the search", action: {
                shortcut("f")
                (window.firstResponder as? NSTextView).map { $0.selectAll(nil); $0.deleteBackward(nil) }
                if let sidebar { window.makeFirstResponder(sidebar) }
            }),
            Step(name: "sidebar scrolled to the end", action: {
                sidebar.map { $0.scrollRowToVisible($0.numberOfRows - 1) }
            }, check: checkRows),
            Step(name: "sidebar hidden and shown", wait: 1.2, action: {
                NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
                }
            }, check: checkRows),
            Step(name: "smallest window", action: { window.setContentSize(window.contentMinSize) }, check: {
                checkRows()
                expect(window.contentMinSize.width >= 760, "the window can't be made narrower than 760pt: \(Int(window.contentMinSize.width))")
            }),
            Step(name: "sidebar dragged narrow", action: { splitView?.setPosition(120, ofDividerAt: 0) }, check: {
                checkRows()
                expect((sidebar?.enclosingScrollView?.frame.width ?? 0) >= 220, "the sidebar stops at 220pt: \(Int(sidebar?.enclosingScrollView?.frame.width ?? 0))")
            }),
            Step(name: "sidebar dragged wide", action: { splitView?.setPosition(420, ofDividerAt: 0) }, check: checkRows),
            Step(name: "large window", action: {
                splitView?.setPosition(240, ofDividerAt: 0)
                window.setContentSize(NSSize(width: 1500, height: 900))
            }, check: checkRows),
            // NES is selected; Super Nintendo (row 6) shows an unselected orange badge.
            Step(name: "View menu Appearance Dark", wait: 1.2, action: {
                sidebar?.scrollRowToVisible(6)
                chooseInMenu(.dark)
            }, check: {
                checkAppearance(.dark, "View › Appearance › Dark")
                checkRows()
                checkBadgeContrast()
            }),
            Step(name: "Setup in Dark", wait: 1.2, action: {
                shortcut(",")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { scrollPageToEnd() }
            }, check: {
                expect(window.title == "Setup", "⌘, shows Setup: \(window.title)")
                expect(appearanceControl.map { $0.label(forSegment: $0.selectedSegment) } == AppAppearance.dark.label,
                       "Setup's Appearance control shows Dark")
            }),
            Step(name: "Setup Appearance Light", wait: 1.2, action: { chooseInSetup(.light) }, check: {
                checkAppearance(.light, "Setup › Appearance › Light")
            }),
            Step(name: "NES in Light", wait: 1.2, action: {
                shortcut("]"); shortcut("]"); shortcut("]")
                sidebar?.scrollRowToVisible(6)
            }, check: {
                expect(window.title == "NES", "⌘] from Setup three times reaches NES: \(window.title)")
                checkBadgeContrast()
            }),
            Step(name: "couch mode", wait: 2.5, action: {
                window.setContentSize(NSSize(width: 1100, height: 680))
                controller(.toggleCouchMode)
            }, check: {
                expect(window.styleMask.contains(.fullScreen), "Menu opens couch mode full screen")
                let luminance = averageLuminance()
                expect(luminance < 0.2, String(format: "couch mode stays dark with RetroHub set to Light (average luminance %.2f)", luminance))
            }),
            Step(name: "back out of couch mode", wait: 2.5, action: { controller(.back) }, check: {
                expect(!window.styleMask.contains(.fullScreen), "B leaves couch mode")
                expect(window.title == "NES", "still on NES: \(window.title)")
                expect(!isDark(window.effectiveAppearance), "the browser is Light again")
                checkRows()
            }),
            Step(name: "View menu Appearance Follow System", wait: 1.2, action: { chooseInMenu(.system) }, check: {
                checkAppearance(.system, "View › Appearance › Follow System")
            }),
            Step(name: "second window", wait: 1.5, action: openSecondWindow, check: {}),
            Step(name: "Y with every window on NES", action: {
                favoritesBefore = favorites
                controller(.favorite)
            }, check: {
                let changed = Set(favorites).symmetricDifference(favoritesBefore)
                expect(changed.count == 1, "one press of Y toggles one game, once: \(favoritesBefore) → \(favorites)")
            }),
            Step(name: "controller diagnostics", wait: 1.5, action: {
                if let item = menuItem(titled: "Controller Diagnostics"), let menu = item.menu {
                    menu.performActionForItem(at: menu.index(of: item))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { controller(.nextSystem) }
            }, check: {
                let entries = ControllerDiagnostics.shared.entries
                expect(diagnosticsWindow != nil, "Window › Controller Diagnostics opens it")
                expect(entries.contains { $0.kind == .input && $0.text.hasSuffix("next system") }, "it records the press")
                expect(entries.contains { $0.kind == .action && $0.text == "next system" }, "the action it made")
                expect(entries.contains { $0.kind == .result && $0.text == "showing Super Nintendo" },
                       "and what that did: \(entries.last { $0.kind == .result }?.text ?? "nothing")")
                expect(!entries.contains { $0.kind == .check }, "one press made one action")
                if let diagnosticsWindow { savePicture(String(format: "%02d diagnostics window.png", stepNumber), of: diagnosticsWindow) }
            }),
            Step(name: "diagnostics closed", action: {
                diagnosticsWindow?.performClose(nil)
                window.makeKeyAndOrderFront(nil)
            }, check: {
                expect(diagnosticsWindow == nil && window.isKeyWindow, "closing it leaves the main window active")
            }),
            Step(name: "Dark again for the relaunch run", action: { chooseInMenu(.dark) }, check: {
                expect(UserDefaults.standard.string(forKey: AppAppearance.key) == "dark", "Dark is saved")
            }),
        ]
    }

    /// Before Shift 02 the app could open more windows (File › New Window). Opens one if it can and
    /// puts NES in both, so the last step shows whether a controller press acts once per window.
    private static func openSecondWindow() {
        guard let item = menuItem(key: "n", title: "Window"), let menu = item.menu else {
            print("  (no New Window command: one window only)")
            return
        }
        menu.performActionForItem(at: menu.index(of: item))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            for other in NSApp.windows where other.isVisible && other !== window {
                if let list = outlineView(in: other.contentView) {
                    other.makeFirstResponder(list)
                    other.sendEvent(Key.down.event(in: other))
                }
            }
        }
    }

    // MARK: Checks

    private static func expect(_ passed: Bool, _ label: String) {
        checks += 1
        if !passed { failures += 1 }
        print("  \(passed ? "ok" : "FAIL") \(label)")
    }

    /// Each row has to span the sidebar, less its insets, or its name is cut off after the icon.
    private static func checkRows() {
        guard let sidebar else { return expect(false, "no sidebar") }
        let width = sidebar.enclosingScrollView?.frame.width ?? sidebar.frame.width
        let rows = (0..<sidebar.numberOfRows).compactMap { sidebar.view(atColumn: 0, row: $0, makeIfNecessary: false) }
        let narrowest = rows.map(\.frame.width).min() ?? 0
        expect(!rows.isEmpty && narrowest >= width - 40,
               "\(rows.count) rows, narrowest \(Int(narrowest))pt, in a \(Int(width))pt sidebar")
    }

    /// The setting is saved, applied to RetroHub, shown in View › Appearance, and leaves the Mac's
    /// own appearance alone.
    private static func checkAppearance(_ appearance: AppAppearance, _ label: String) {
        expect(UserDefaults.standard.string(forKey: AppAppearance.key) == appearance.rawValue, "\(label) is saved")
        expect(NSApp.appearance?.name == appearance.nsAppearance?.name, "and applied to RetroHub")
        let dark = appearance == .system ? macAppearance == "Dark" : appearance == .dark
        expect(isDark(window.effectiveAppearance) == dark, "the window draws \(dark ? "dark" : "light")")
        expect(appearanceItem(appearance)?.state == .on, "the View menu shows \(appearance.label) checked")
        expect(macAppearance == macAppearanceAtLaunch, "the Mac's own appearance is unchanged: \(macAppearance)")
    }

    /// Text contrast of Super Nintendo's count badge (orange, with a warning sign: there's no
    /// emulator for it) as drawn in the window: the most common pale orange pixel, the badge's
    /// tint, against the strongest orange pixel, its text and sign. Needs 4.5:1.
    private static func checkBadgeContrast() {
        guard let sidebar, let frame = window.contentView?.superview else { return expect(false, "no sidebar") }
        var rect = sidebar.rect(ofRow: 6)
        rect.size.width /= 2
        rect.origin.x += rect.width
        let area = sidebar.convert(rect, to: frame)
        guard let picture = frame.bitmapImageRepForCachingDisplay(in: area) else { return expect(false, "no picture of the badge") }
        frame.cacheDisplay(in: area, to: picture)
        var tints: [NSColor: Int] = [:]
        var marks: [NSColor] = []
        for x in 0..<picture.pixelsWide {
            for y in 0..<picture.pixelsHigh {
                guard let pixel = picture.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let warmth = pixel.redComponent - pixel.blueComponent
                if warmth > 0.3 {
                    marks.append(pixel)
                } else if warmth > 0.06 {
                    tints[pixel, default: 0] += 1
                }
            }
        }
        guard let tint = tints.max(by: { $0.value < $1.value })?.key, !marks.isEmpty else {
            return expect(false, "found the orange badge next to Super Nintendo")
        }
        let ratio = marks.map { $0.contrast(with: tint) }.max() ?? 0
        expect(ratio >= 4.5, String(format: "the orange badge's text is readable in %@: %.2f:1",
                                    isDark(window.effectiveAppearance) ? "Dark" : "Light", ratio))
    }

    /// The selected row is in view, below the toolbar.
    private static func checkSelectionVisible() {
        guard let sidebar, let scroll = sidebar.enclosingScrollView, sidebar.selectedRow >= 0 else {
            return expect(false, "a sidebar row is selected")
        }
        // The clip view's insets cover whatever it lets show through from under the toolbar.
        let clip = scroll.contentView
        var visible = clip.bounds
        visible.origin.y += clip.contentInsets.top
        visible.size.height -= clip.contentInsets.top + clip.contentInsets.bottom
        expect(visible.contains(sidebar.rect(ofRow: sidebar.selectedRow)), "the selected row (\(sidebar.selectedRow)) is in view")
    }

    // MARK: Reading the window

    private static var sidebar: NSOutlineView? { outlineView(in: window.contentView) }

    private static var splitView: NSSplitView? { sidebar.flatMap { enclosing(NSSplitView.self, of: $0) } }

    private static var sidebarFocused: Bool { sidebar != nil && window.firstResponder === sidebar }

    private static var searchFocused: Bool { ((window.firstResponder as? NSText)?.delegate as? NSSearchField) != nil }

    /// Keyboard focus is in the game grid: not the sidebar and not a text field.
    private static var gamesFocused: Bool {
        !sidebarFocused && !(window.firstResponder is NSText) && window.firstResponder is NSView
    }

    private static var macAppearance: String {
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleInterfaceStyle"] as? String ?? "Light"
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private static var diagnosticsWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.identifier?.rawValue.hasPrefix(ControllerDiagnostics.windowID) == true }
    }

    private static func menuItem(titled title: String) -> NSMenuItem? {
        func search(_ menu: NSMenu?) -> NSMenuItem? {
            for item in menu?.items ?? [] {
                if item.title == title { return item }
                if let found = search(item.submenu) { return found }
            }
            return nil
        }
        return search(NSApp.mainMenu)
    }

    /// An item in View › Appearance.
    private static func appearanceItem(_ appearance: AppAppearance) -> NSMenuItem? {
        func search(_ menu: NSMenu?) -> NSMenuItem? {
            for item in menu?.items ?? [] {
                if item.title == "Appearance", let found = item.submenu?.items.first(where: { $0.title == appearance.label }) {
                    return found
                }
                if let found = search(item.submenu) { return found }
            }
            return nil
        }
        return search(NSApp.mainMenu)
    }

    /// The Appearance control on the Setup page.
    private static var appearanceControl: NSSegmentedControl? {
        func search(_ view: NSView) -> NSSegmentedControl? {
            if let control = view as? NSSegmentedControl,
               (0..<control.segmentCount).contains(where: { control.label(forSegment: $0) == AppAppearance.system.label }) {
                return control
            }
            return view.subviews.lazy.compactMap(search).first
        }
        return window.contentView.flatMap(search)
    }

    /// Average luminance of the window as drawn, from 0 (black) to 1 (white).
    private static func averageLuminance() -> Double {
        guard let frame = window.contentView?.superview,
              let picture = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return 1 }
        frame.cacheDisplay(in: frame.bounds, to: picture)
        let pixels = stride(from: 0, to: picture.pixelsWide, by: 16).flatMap { x in
            stride(from: 0, to: picture.pixelsHigh, by: 16).compactMap { picture.colorAt(x: x, y: $0) }
        }
        return pixels.isEmpty ? 1 : pixels.map(\.luminance).reduce(0, +) / Double(pixels.count)
    }

    private static var favorites: [String] {
        (UserDefaults.standard.stringArray(forKey: "favorites") ?? []).map { URL(filePath: $0).lastPathComponent }.sorted()
    }

    private static func outlineView(in view: NSView?) -> NSOutlineView? {
        guard let view else { return nil }
        return view as? NSOutlineView ?? view.subviews.lazy.compactMap { outlineView(in: $0) }.first
    }

    private static func enclosing<T: NSView>(_ type: T.Type, of view: NSView) -> T? {
        var current = view.superview
        while let view = current, !(view is T) { current = view.superview }
        return current as? T
    }

    /// The menu bar item with this ⌘ shortcut and a title containing `title`.
    private static func menuItem(key: String, title: String) -> NSMenuItem? {
        func search(_ menu: NSMenu?) -> NSMenuItem? {
            for item in menu?.items ?? [] {
                if item.keyEquivalent == key, item.keyEquivalentModifierMask == .command, item.title.contains(title) {
                    return item
                }
                if let found = search(item.submenu) { return found }
            }
            return nil
        }
        return search(NSApp.mainMenu)
    }

    // MARK: Acting on the window

    private enum Key {
        case up, down, right, `return`, escape, f

        @MainActor
        func event(in window: NSWindow, modifiers: NSEvent.ModifierFlags = [], characters: String? = nil) -> NSEvent {
            let (code, text): (UInt16, String) = switch self {
            case .up: (126, String(Character(UnicodeScalar(UInt32(NSUpArrowFunctionKey))!)))
            case .down: (125, String(Character(UnicodeScalar(UInt32(NSDownArrowFunctionKey))!)))
            case .right: (124, String(Character(UnicodeScalar(UInt32(NSRightArrowFunctionKey))!)))
            case .return: (36, "\r")
            case .escape: (53, "\u{1b}")
            case .f: (3, "f")
            }
            return NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                                    windowNumber: window.windowNumber, context: nil, characters: characters ?? text,
                                    charactersIgnoringModifiers: characters ?? text, isARepeat: false, keyCode: code)!
        }
    }

    private static func press(_ key: Key) {
        window.sendEvent(key.event(in: window))
    }

    /// A click in the middle of a sidebar row. The mouse-up goes in the queue first, for the
    /// table's mouse tracking to pick up.
    private static func click(row: Int) {
        guard let sidebar else { return }
        let rect = sidebar.rect(ofRow: row)
        let point = sidebar.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
        func event(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        NSApp.postEvent(event(.leftMouseUp), atStart: false)
        window.sendEvent(event(.leftMouseDown))
    }

    /// A ⌘ shortcut, handled by the menu bar as a real key press would be.
    private static func shortcut(_ character: String) {
        let event = Key.f.event(in: window, modifiers: .command, characters: character)
        if NSApp.mainMenu?.performKeyEquivalent(with: event) != true {
            print("  (no menu item for ⌘\(character))")
        }
    }

    private static func chooseInMenu(_ appearance: AppAppearance) {
        guard let item = appearanceItem(appearance), let menu = item.menu else {
            return print("  (no View › Appearance › \(appearance.label))")
        }
        menu.performActionForItem(at: menu.index(of: item))
    }

    private static func chooseInSetup(_ appearance: AppAppearance) {
        guard let control = appearanceControl,
              let segment = (0..<control.segmentCount).first(where: { control.label(forSegment: $0) == appearance.label })
        else { return print("  (no Appearance control on the page)") }
        control.selectedSegment = segment
        control.sendAction(control.action, to: control.target)
    }

    /// Scrolls the page beside the sidebar to its end.
    private static func scrollPageToEnd() {
        func scrollViews(in view: NSView) -> [NSScrollView] {
            ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap { scrollViews(in: $0) }
        }
        guard let scroll = window.contentView.map({ scrollViews(in: $0) })?
            .filter({ $0.documentView !== sidebar })
            .max(by: { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }),
              let page = scroll.documentView else { return }
        let clip = scroll.contentView
        clip.scroll(to: NSPoint(x: 0, y: page.isFlipped ? max(0, page.frame.height - clip.bounds.height) : 0))
        scroll.reflectScrolledClipView(clip)
    }

    private static func controller(_ command: ControllerCommand) {
        NotificationCenter.default.post(name: ControllerInput.simulatedCommand, object: command)
    }

    private static func savePicture(_ name: String, of target: NSWindow? = nil) {
        guard let folder, let frame = (target ?? window).contentView?.superview,
              let picture = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return }
        frame.cacheDisplay(in: frame.bounds, to: picture)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? picture.representation(using: .png, properties: [:])?.write(to: folder.appending(path: name))
    }
}
#endif
