#if DEBUG
import Combine
import GameController
import SwiftUI

/// Debug builds only: a record of what each controller press did, for testing a controller by
/// hand. Three kinds of line, in the Controller Diagnostics window and in the app's output (the
/// log dev-run.sh writes):
///
///     input    what GameController reported: the control's name, pressed or released
///     action   the command RetroHub made of it: play, back, move…
///     result   what changed: the list shown, the picked game, favorites, couch mode, a game
///              starting or closing, the frontmost app, and where keyboard focus is
///
/// A "check" line flags a press that made more or fewer actions than it should. Only the
/// controller's name and category and the names of its controls are recorded, nothing else about
/// it. Open with `scripts/dev-run.sh --controller-diagnostics`, or Window › Controller Diagnostics.
@MainActor
final class ControllerDiagnostics: ObservableObject {
    static let shared = ControllerDiagnostics()
    static let windowID = "controller-diagnostics"
    static var requested: Bool { ProcessInfo.processInfo.arguments.contains("--controller-diagnostics") }

    struct Entry: Identifiable {
        enum Kind: String { case device, input, action, result, check }

        let id: Int
        let time: Date
        let kind: Kind
        let text: String
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var controllers: [String] = []

    private var controller: ControllerInput?
    // Read by UIChecks.swift too.
    private(set) var navigator: Navigator?
    private(set) var library: Library?
    private var recording = false
    private var subscriptions: Set<AnyCancellable> = []
    /// Directions held on each d-pad or stick, to report only when they change.
    private var held: [ObjectIdentifier: Set<String>] = [:]
    /// Presses of controls that have a command, and the commands that came of them, since the
    /// controller was last quiet.
    private var presses: [ControllerCommand: Int] = [:]
    private var actions: [ControllerCommand: Int] = [:]
    private var settle: DispatchWorkItem?
    /// 24-hour, whatever the Mac's clock setting, so log times line up with the log's file name
    /// and with notes taken during a test.
    static let timeFormat = Date.VerbatimFormatStyle(
        format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits).\(secondFraction: .fractional(3))",
        timeZone: .current, calendar: Calendar(identifier: .gregorian))

    /// Called by the main window, which has the app's controller, navigator and library.
    func attach(controller: ControllerInput, navigator: Navigator, library: Library) {
        (self.controller, self.navigator, self.library) = (controller, navigator, library)
    }

    func start() {
        guard !recording, let controller, let navigator, let library else { return }
        recording = true
        // Line by line, so the log is complete even if the app is stopped.
        setvbuf(stdout, nil, _IOLBF, 0)
        add(.device, "recording started (\(Bundle.main.bundleIdentifier ?? "?"))")

        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            NotificationCenter.default.publisher(for: name)
                .sink { [weak self] note in
                    guard let device = note.object as? GCController else { return }
                    let connected = name == .GCControllerDidConnect
                    self?.add(.device, "\(connected ? "connected" : "disconnected"): \(Self.describe(device))")
                    if connected { self?.watch(device) }
                    self?.listControllers()
                }
                .store(in: &subscriptions)
        }
        GCController.controllers().forEach { add(.device, "already connected: \(Self.describe($0))"); watch($0) }
        listControllers()

        controller.commands
            .sink { [weak self] command in self?.action(command) }
            .store(in: &subscriptions)
        // UIChecks' stand-ins for presses.
        NotificationCenter.default.publisher(for: ControllerInput.simulatedCommand)
            .compactMap { $0.object as? ControllerCommand }
            .sink { [weak self] command in self?.simulated(command) }
            .store(in: &subscriptions)

        navigator.$selection.dropFirst().removeDuplicates()
            .sink { [weak self] in self?.add(.result, "showing \($0?.title ?? "nothing")") }
            .store(in: &subscriptions)
        navigator.$couchMode.dropFirst().removeDuplicates()
            .sink { [weak self] in self?.add(.result, "couch mode \($0 ? "on" : "off")") }
            .store(in: &subscriptions)
        navigator.$pickedGames.scan(([:], [:])) { ($0.1, $1) }.dropFirst()
            .sink { [weak self] old, new in
                for (list, id) in new where old[list] != id {
                    self?.add(.result, "picked \(self?.title(of: id) ?? "?") in \(list.title)")
                }
            }
            .store(in: &subscriptions)
        library.$favorites.scan((Set(), Set())) { ($0.1, $1) }.dropFirst()
            .sink { [weak self] old, new in
                for key in new.subtracting(old) { self?.add(.result, "favorite added: \(Self.fileName(key))") }
                for key in old.subtracting(new) { self?.add(.result, "favorite removed: \(Self.fileName(key))") }
            }
            .store(in: &subscriptions)
        library.$launchError.compactMap { $0 }
            .sink { [weak self] in self?.add(.result, "launch error: \($0)") }
            .store(in: &subscriptions)
        library.$session.scan((nil, nil)) { ($0.1, $1) }.dropFirst()
            .sink { [weak self] old, new in
                if let new {
                    self?.add(.result, "game started: \(new.game.displayTitle), process \(new.process.processIdentifier)")
                } else if let old {
                    let seconds = Date.now.timeIntervalSince(old.started)
                    self?.add(.result, String(format: "game closed: %@, exit status %d after %.1f s", old.game.displayTitle,
                                              old.process.terminationStatus, seconds))
                }
            }
            .store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .compactMap { ($0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.localizedName }
            .sink { [weak self] in self?.add(.result, "frontmost app: \($0)") }
            .store(in: &subscriptions)
    }

    func clear() {
        entries.removeAll()
    }

    // MARK: Recording

    private func add(_ kind: Entry.Kind, _ text: String) {
        let entry = Entry(id: (entries.last?.id ?? 0) + 1, time: .now, kind: kind, text: text)
        entries.append(entry)
        if entries.count > 500 { entries.removeFirst(entries.count - 500) }
        print("[controller] \(entry.time.formatted(Self.timeFormat)) \(kind.rawValue.padding(toLength: 6, withPad: " ", startingAt: 0)) \(text)")
    }

    private func watch(_ device: GCController) {
        guard let pad = device.extendedGamepad else { return }
        // A separate handler from the per-button ones ControllerInput sets, so it sees every
        // control, including the ones RetroHub doesn't use.
        pad.valueChangedHandler = { [weak self] pad, element in
            MainActor.assumeIsolated { self?.input(pad, element) }
        }
    }

    private func listControllers() {
        controllers = GCController.controllers().map(Self.describe)
    }

    private func input(_ pad: GCExtendedGamepad, _ element: GCControllerElement) {
        let bindings = ControllerInput.bindings(pad)
        func command(for button: GCControllerButtonInput) -> ControllerCommand? {
            bindings.first { $0.0 === button }?.1
        }
        let name = Self.name(of: element, in: pad)
        if let directions = element as? GCControllerDirectionPad {
            let parts = [("up", directions.up), ("down", directions.down), ("left", directions.left), ("right", directions.right)]
            let now = Set(parts.filter { $0.1.isPressed }.map(\.0))
            let before = held[ObjectIdentifier(directions)] ?? []
            guard now != before else { return }
            held[ObjectIdentifier(directions)] = now
            let pressed = parts.filter { now.contains($0.0) && !before.contains($0.0) }
            let commands = pressed.compactMap { command(for: $0.1) }
            commands.forEach { presses[$0, default: 0] += 1 }
            let state = now.isEmpty ? "released" : now.sorted().joined(separator: "+")
            add(.input, String(format: "%@ %@ (x %.2f, y %.2f)", name, state, directions.xAxis.value, directions.yAxis.value)
                + (commands.isEmpty ? "" : " → " + commands.map(Self.describe).joined(separator: ", ")))
        } else if let button = element as? GCControllerButtonInput {
            let id = ObjectIdentifier(button)
            let wasPressed = !(held[id] ?? []).isEmpty
            guard button.isPressed != wasPressed else { return }
            held[id] = button.isPressed ? ["pressed"] : []
            var text = "\(name) \(button.isPressed ? "pressed" : "released")"
            if button.isAnalog { text += String(format: " (%.2f)", button.value) }
            if button.isPressed {
                if let command = command(for: button) {
                    presses[command, default: 0] += 1
                    text += " → " + Self.describe(command)
                } else {
                    text += " → no RetroHub action"
                }
            }
            add(.input, text)
        } else {
            return
        }
        scheduleSettle()
    }

    private func simulated(_ command: ControllerCommand) {
        presses[command, default: 0] += 1
        add(.input, "simulated press → \(Self.describe(command))")
        scheduleSettle()
    }

    private func action(_ command: ControllerCommand) {
        actions[command, default: 0] += 1
        add(.action, Self.describe(command))
        scheduleSettle()
        // Focus moves after the views have handled the command.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.reportFocus() }
    }

    /// Half a second after the last press, compares presses with actions: each press of a control
    /// that has a command must make exactly one.
    private func scheduleSettle() {
        settle?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.compareCounts() }
        }
        settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func compareCounts() {
        for command in Set(presses.keys).union(actions.keys) where presses[command] != actions[command] {
            add(.check, "\(Self.describe(command)): \(presses[command] ?? 0) press(es) made \(actions[command] ?? 0) action(s)")
        }
        presses.removeAll()
        actions.removeAll()
    }

    private func reportFocus() {
        // SwiftUI names a scene's window after its id: "main-AppWindow-1".
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) else { return }
        let responder = window.firstResponder
        let place = switch responder {
        case is NSOutlineView: "sidebar"
        case is NSText: "search field"
        case is NSWindow, nil: "nothing"
        default: navigator?.couchMode == true ? "couch mode" : "games"
        }
        add(.result, "keyboard focus: \(place); RetroHub \(NSApp.isActive ? "is" : "isn't") the active app")
    }

    // MARK: Names

    private func title(of id: Game.ID) -> String {
        library?.games.values.joined().first { $0.id == id }?.displayTitle ?? id.lastPathComponent
    }

    private static func fileName(_ key: String) -> String {
        URL(filePath: key).lastPathComponent
    }

    private static func describe(_ device: GCController) -> String {
        "\(device.vendorName ?? "unnamed controller") (\(device.productCategory)\(device.extendedGamepad == nil ? ", not a full gamepad: RetroHub can't use it" : ""))"
    }

    private static func describe(_ command: ControllerCommand) -> String {
        switch command {
        case .move(let dx, let dy):
            "move " + (dy < 0 ? "up" : dy > 0 ? "down" : dx < 0 ? "left" : "right")
        case .play: "play"
        case .favorite: "favorite"
        case .back: "back"
        case .previousSystem: "previous system"
        case .nextSystem: "next system"
        case .toggleCouchMode: "couch mode"
        }
    }

    /// GameController's name for the control, and the gamepad property it is, which is what
    /// RetroHub's bindings use: "Cross Button (buttonA)".
    private static func name(of element: GCControllerElement, in pad: GCExtendedGamepad) -> String {
        var roles: [(GCControllerElement?, String)] = [
            (pad.dpad, "dpad"), (pad.leftThumbstick, "leftThumbstick"), (pad.rightThumbstick, "rightThumbstick"),
            (pad.buttonA, "buttonA"), (pad.buttonB, "buttonB"), (pad.buttonX, "buttonX"), (pad.buttonY, "buttonY"),
            (pad.leftShoulder, "leftShoulder"), (pad.rightShoulder, "rightShoulder"),
            (pad.leftTrigger, "leftTrigger"), (pad.rightTrigger, "rightTrigger"),
            (pad.buttonMenu, "buttonMenu"), (pad.buttonOptions, "buttonOptions"), (pad.buttonHome, "buttonHome"),
            (pad.leftThumbstickButton, "leftThumbstickButton"), (pad.rightThumbstickButton, "rightThumbstickButton"),
        ]
        if let dualSense = pad as? GCDualSenseGamepad {
            roles += [(dualSense.touchpadButton, "touchpadButton"), (dualSense.touchpadPrimary, "touchpadPrimary"),
                      (dualSense.touchpadSecondary, "touchpadSecondary")]
        }
        let role = roles.first { $0.0 === element }?.1 ?? "unknown control"
        return "\(element.localizedName ?? role) (\(role))"
    }
}

struct ControllerDiagnosticsView: View {
    @ObservedObject private var diagnostics = ControllerDiagnostics.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Controllers").font(.headline)
                if diagnostics.controllers.isEmpty {
                    Text("None connected").foregroundStyle(.secondary)
                }
                ForEach(diagnostics.controllers, id: \.self) { Text($0) }
            }
            .padding(12)
            Divider()
            ScrollViewReader { proxy in
                List(diagnostics.entries) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(entry.time, format: ControllerDiagnostics.timeFormat)
                            .foregroundStyle(.secondary)
                        Text(entry.kind.rawValue)
                            .foregroundStyle(entry.kind == .check ? Color.warning : .secondary)
                            .frame(width: 52, alignment: .leading)
                        Text(entry.text)
                            .textSelection(.enabled)
                    }
                    .font(.callout.monospaced())
                    .id(entry.id)
                }
                .onChange(of: diagnostics.entries.last?.id) { _, id in
                    if let id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            Divider()
            HStack {
                Text("Also written to the app's output (mac/build/dev/logs with dev-run.sh)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { diagnostics.clear() }
            }
            .padding(10)
        }
        .frame(minWidth: 560, minHeight: 360)
        .onAppear { diagnostics.start() }
    }
}
#endif
