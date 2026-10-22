import Combine
import GameController

enum ControllerCommand: Equatable {
    case move(dx: Int, dy: Int)
    case play
    case favorite
    case back
    case previousSystem
    case nextSystem
    case toggleCouchMode
}

/// Turns gamepad presses into library navigation commands. macOS only delivers
/// controller input to the frontmost app, so this goes quiet while an emulator is playing.
@MainActor
final class ControllerInput: ObservableObject {
    @Published private(set) var controllerName: String?
    let commands = PassthroughSubject<ControllerCommand, Never>()

    init() {
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        refresh()
        #if DEBUG
        NotificationCenter.default.addObserver(forName: Self.simulatedCommand, object: nil, queue: .main) { [weak self] note in
            guard let command = note.object as? ControllerCommand else { return }
            MainActor.assumeIsolated { self?.commands.send(command) }
        }
        #endif
    }

    #if DEBUG
    /// UIChecks.swift posts commands under this name, as if they came from a controller.
    static let simulatedCommand = Notification.Name("RetroHubSimulatedControllerCommand")
    #endif

    private func refresh() {
        let controllers = GCController.controllers()
        controllers.forEach(configure)
        controllerName = controllers.first.map { $0.vendorName ?? "Controller" }
    }

    private func configure(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        for directions in [pad.dpad, pad.leftThumbstick] {
            bind(directions.up, .move(dx: 0, dy: -1))
            bind(directions.down, .move(dx: 0, dy: 1))
            bind(directions.left, .move(dx: -1, dy: 0))
            bind(directions.right, .move(dx: 1, dy: 0))
        }
        bind(pad.buttonA, .play)
        bind(pad.buttonB, .back)
        bind(pad.buttonY, .favorite)
        bind(pad.buttonMenu, .toggleCouchMode)
        bind(pad.leftShoulder, .previousSystem)
        bind(pad.rightShoulder, .nextSystem)
    }

    /// Handlers run on the main queue, GameController's default.
    private func bind(_ button: GCControllerButtonInput, _ command: ControllerCommand) {
        button.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated { self?.commands.send(command) }
        }
    }
}
