#if os(tvOS)
import CoreHaptics
import GameController
import UIKit
import WittyKit

// Controllers on Apple TV, into the server's controller states. MFi, Xbox and PlayStation pads come
// through GameController, read in the W3C standard layout that the server's mappings and the
// account's profiles are written in. The Siri Remote is a remote: the console's `defaults.remote`
// says what it presses, and its Back button opens the game menu, as the server's docs ask. Start and
// Select together open it from a pad.

/// One controller and what it does here.
private final class Pad {
    let controller: GCController
    var port: UInt8
    var mapper: PadMapper
    var shortcuts: PadShortcuts
    var haptics: CHHapticEngine?
    var last = PadState()

    init(controller: GCController, port: UInt8, mapper: PadMapper, shortcuts: PadShortcuts) {
        self.controller = controller
        self.port = port
        self.mapper = mapper
        self.shortcuts = shortcuts
    }
}

@MainActor
final class GameInput {
    /// Everything the game needs to know about a console's controller.
    struct Setup {
        var controls: GameControls?
        var settings: GameSettings?
        var console: String
        var game: Int64
        var consoleButtons: Set<Int>
    }

    private var setup: Setup?
    private var client: WittyClient?
    private var pads: [ObjectIdentifier: Pad] = [:]
    private var remote: KeyMapper = KeyMapper(nil)
    private var keyboard: KeyMapper = KeyMapper(nil)
    /// Remote and keyboard keys held now, by `KeyboardEvent.key` and `.code` names: from the Siri
    /// Remote through GameController, from presses that come through UIKit, and from a keyboard.
    private var remotePad: Set<String> = []
    private var remoteHeld: Set<String> = []
    private var remotes: [GCController] = []
    private var keysHeld: Set<String> = []
    private var remoteShortcuts = PadShortcuts(settings: nil, consoleButtons: [])
    private var sent: [UInt8: PadState] = [:]
    private var heartbeat: Timer?
    private var turbo: Timer?
    private var observers: [NSObjectProtocol] = []
    private(set) var enabled = false
    private let started = Date()

    var send: ((Data) -> Void)?
    var onShortcut: ((PadShortcut, Bool) -> Void)?
    var onMenu: (() -> Void)?
    /// What to show when a controller comes or goes.
    var onNotice: ((String) -> Void)?

    /// Who's on which player, for the menu.
    var players: [(port: Int, name: String)] {
        pads.values.sorted { $0.port < $1.port }.map { (Int($0.port), $0.controller.vendorName ?? $0.controller.productCategory) }
    }

    func start(client: WittyClient, setup: Setup) {
        self.client = client
        self.setup = setup
        remote = KeyMapper(setup.controls?.defaults?.remote)
        keyboard = KeyMapper(setup.controls?.defaults?.keyboard)
        remoteShortcuts = PadShortcuts(settings: setup.settings, consoleButtons: setup.consoleButtons)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            guard let controller = note.object as? GCController else { return }
            Task { @MainActor in self?.attach(controller, announce: true) }
        })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] note in
            guard let controller = note.object as? GCController else { return }
            Task { @MainActor in self?.detach(controller) }
        })
        observers.append(center.addObserver(forName: .GCKeyboardDidConnect, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.watchKeyboard() }
        })
        for controller in GCController.controllers() { attach(controller, announce: false) }
        watchKeyboard()
        GCController.startWirelessControllerDiscovery {}
        // Again every 250 ms, so a lost state corrects itself. Repeats don't count as playing.
        heartbeat = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.beat() }
        }
        enabled = true
    }

    func stop() {
        releaseAll()
        enabled = false
        heartbeat?.invalidate()
        turbo?.invalidate()
        heartbeat = nil
        turbo = nil
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers = []
        GCController.stopWirelessControllerDiscovery()
        for pad in pads.values {
            pad.controller.extendedGamepad?.valueChangedHandler = nil
            pad.haptics?.stop()
        }
        pads = [:]
        // The rest of the app has the remote back as it was.
        for remote in remotes {
            remote.microGamepad?.valueChangedHandler = nil
            remote.microGamepad?.buttonMenu.pressedChangedHandler = nil
            remote.microGamepad?.reportsAbsoluteDpadValues = false
        }
        remotes = []
        GCKeyboard.coalesced?.keyboardInput?.keyChangedHandler = nil
    }

    /// While the menu is open nothing reaches the game; everything held is let go.
    func setEnabled(_ on: Bool) {
        enabled = on
        if !on { releaseAll() } else { refreshAll() }
    }

    // MARK: Controllers

    private func freePort() -> UInt8 {
        let taken = Set(pads.values.map(\.port))
        return (0...3).map(UInt8.init).first { !taken.contains($0) } ?? 3
    }

    private func attach(_ controller: GCController, announce: Bool) {
        let id = ObjectIdentifier(controller)
        guard pads[id] == nil else { return }
        if controller.extendedGamepad == nil, let micro = controller.microGamepad {
            guard !remotes.contains(where: { $0 === controller }) else { return }
            remotes.append(controller)
            // The Siri Remote: absolute positions, so a click at the edge of the clickpad is a direction.
            micro.reportsAbsoluteDpadValues = true
            micro.allowsRotation = false
            micro.valueChangedHandler = { [weak self] pad, _ in
                Task { @MainActor in self?.remoteChanged(pad) }
            }
            micro.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                Task { @MainActor in self?.onMenu?() }
            }
            return
        }
        guard let extended = controller.extendedGamepad, let setup else { return }
        let port = freePort()
        controller.playerIndex = GCControllerPlayerIndex(rawValue: Int(port)) ?? .indexUnset
        let shortcuts = PadShortcuts(settings: setup.settings, consoleButtons: setup.consoleButtons)
        let mapper = PadMapper(defaults: setup.controls?.defaults?.gamepad, options: nil, defaultOptions: setup.controls?.defaults?.options)
        let pad = Pad(controller: controller, port: port, mapper: mapper, shortcuts: shortcuts)
        pads[id] = pad
        extended.valueChangedHandler = { [weak self] _, _ in
            Task { @MainActor in self?.padChanged(id) }
        }
        // The Home button is the system's; Start and Select together open the menu.
        if announce { onNotice?("\(controller.vendorName ?? "A controller") is player \(port + 1)") }
        Task { await loadProfile(for: id) }
        updateTurboTimer()
    }

    private func detach(_ controller: GCController) {
        let id = ObjectIdentifier(controller)
        guard let pad = pads.removeValue(forKey: id) else { return }
        pad.haptics?.stop()
        // Disconnecting lets go of everything it held at once.
        let released = PadState(port: pad.port)
        send?(released.encoded())
        sent[pad.port] = released
        onNotice?("Player \(pad.port + 1)'s controller disconnected")
    }

    /// The account's profile for this controller, console and game, over the console's defaults.
    private func loadProfile(for id: ObjectIdentifier) async {
        guard let pad = pads[id], let client, let setup else { return }
        let key = PadIdentity.key(productCategory: pad.controller.productCategory, vendorName: pad.controller.vendorName)
        let saved = setup.controls?.saved?.gamepad?[pad.controller.vendorName ?? ""]
        let resolved = try? await client.resolvePad(controller: key, console: setup.console, game: setup.game)
        guard let pad = pads[id] else { return }
        pad.mapper = PadMapper(defaults: setup.controls?.defaults?.gamepad, layers: [saved, resolved?.map],
                               options: resolved?.options, defaultOptions: setup.controls?.defaults?.options)
        if let name = resolved?.profile?.name, !name.isEmpty { onNotice?("Player \(pad.port + 1): \(name)") }
        updateTurboTimer()
        padChanged(id)
    }

    private func updateTurboTimer() {
        let wanted = pads.values.contains { !($0.mapper.options.turbo ?? []).isEmpty }
        if wanted, turbo == nil {
            turbo = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refreshAll() }
            }
        } else if !wanted {
            turbo?.invalidate()
            turbo = nil
        }
    }

    private static func reading(_ g: GCExtendedGamepad) -> StandardPadReading {
        var r = StandardPadReading()
        func v(_ b: GCControllerButtonInput?) -> Double { Double(b?.value ?? 0) }
        r[button: StandardPadReading.south] = v(g.buttonA)
        r[button: StandardPadReading.east] = v(g.buttonB)
        r[button: StandardPadReading.west] = v(g.buttonX)
        r[button: StandardPadReading.north] = v(g.buttonY)
        r[button: StandardPadReading.l1] = v(g.leftShoulder)
        r[button: StandardPadReading.r1] = v(g.rightShoulder)
        r[button: StandardPadReading.l2] = v(g.leftTrigger)
        r[button: StandardPadReading.r2] = v(g.rightTrigger)
        r[button: StandardPadReading.select] = v(g.buttonOptions)
        r[button: StandardPadReading.start] = v(g.buttonMenu)
        r[button: StandardPadReading.l3] = v(g.leftThumbstickButton)
        r[button: StandardPadReading.r3] = v(g.rightThumbstickButton)
        r[button: StandardPadReading.up] = v(g.dpad.up)
        r[button: StandardPadReading.down] = v(g.dpad.down)
        r[button: StandardPadReading.left] = v(g.dpad.left)
        r[button: StandardPadReading.right] = v(g.dpad.right)
        r[button: StandardPadReading.home] = v(g.buttonHome)
        // The standard gamepad has down positive; GameController has up positive.
        r.axes = [Double(g.leftThumbstick.xAxis.value), Double(-g.leftThumbstick.yAxis.value),
                  Double(g.rightThumbstick.xAxis.value), Double(-g.rightThumbstick.yAxis.value)]
        return r
    }

    private func padChanged(_ id: ObjectIdentifier) {
        guard let pad = pads[id], let g = pad.controller.extendedGamepad else { return }
        var state = pad.mapper.state(Self.reading(g), port: pad.port, applyTurbo: false)
        let filtered = pad.shortcuts.filter(state.buttons)
        state.buttons = filtered.buttons
        for s in filtered.started {
            if s == .menu { onMenu?() } else { onShortcut?(s, true) }
        }
        for s in filtered.ended { onShortcut?(s, false) }
        // The guide button, where the system lets an app have it, opens the menu too.
        if g.buttonHome?.isPressed == true { onMenu?() }
        pad.last = state
        flush(port: pad.port)
    }

    // MARK: The remote and keyboards

    private func remoteChanged(_ micro: GCMicroGamepad) {
        var held: Set<String> = []
        if micro.buttonA.isPressed {
            // A click on the clickpad: its edge is a direction, its middle is select.
            let x = micro.dpad.xAxis.value, y = micro.dpad.yAxis.value
            if max(abs(x), abs(y)) > 0.5 {
                if abs(x) > abs(y) { held.insert(x > 0 ? "ArrowRight" : "ArrowLeft") } else { held.insert(y > 0 ? "ArrowUp" : "ArrowDown") }
            } else {
                held.insert("Enter")
            }
        }
        if micro.buttonX.isPressed { held.insert("MediaPlayPause") }
        remotePad = held
        flush(port: 0)
    }

    /// Presses that come through UIKit: a keyboard, or the simulator's remote.
    func press(_ name: String, down: Bool) {
        if down { remoteHeld.insert(name) } else { remoteHeld.remove(name) }
        flush(port: 0)
    }

    /// Start or Select for a moment, from the menu, as a remote can't reach them.
    func tap(_ button: Int) {
        guard (0...15).contains(button) else { return }
        var state = merged(port: 0)
        state.buttons |= RetroPad.bit(button)
        send?(state.encoded())
        sent[0] = state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.flush(port: 0, force: true) }
    }

    private func watchKeyboard() {
        GCKeyboard.coalesced?.keyboardInput?.keyChangedHandler = { [weak self] _, _, code, pressed in
            Task { @MainActor in self?.key(code, pressed) }
        }
    }

    private func key(_ code: GCKeyCode, _ pressed: Bool) {
        guard let name = Self.codeName(code) else { return }
        if name == "Escape" {
            if pressed { onMenu?() }
            return
        }
        if pressed { keysHeld.insert(name) } else { keysHeld.remove(name) }
        flush(port: 0)
    }

    /// `KeyboardEvent.code` names, as the server's keyboard layouts use them.
    static func codeName(_ code: GCKeyCode) -> String? {
        let letters: [GCKeyCode] = [.keyA, .keyB, .keyC, .keyD, .keyE, .keyF, .keyG, .keyH, .keyI, .keyJ, .keyK, .keyL, .keyM,
                                    .keyN, .keyO, .keyP, .keyQ, .keyR, .keyS, .keyT, .keyU, .keyV, .keyW, .keyX, .keyY, .keyZ]
        if let i = letters.firstIndex(of: code) { return "Key" + String(UnicodeScalar(UInt8(65 + i))) }
        let digits: [GCKeyCode] = [.zero, .one, .two, .three, .four, .five, .six, .seven, .eight, .nine]
        if let i = digits.firstIndex(of: code) { return "Digit\(i)" }
        let named: [GCKeyCode: String] = [
            .upArrow: "ArrowUp", .downArrow: "ArrowDown", .leftArrow: "ArrowLeft", .rightArrow: "ArrowRight",
            .returnOrEnter: "Enter", .spacebar: "Space", .escape: "Escape", .tab: "Tab", .deleteOrBackspace: "Backspace",
            .leftShift: "ShiftLeft", .rightShift: "ShiftRight", .leftControl: "ControlLeft", .rightControl: "ControlRight",
            .leftAlt: "AltLeft", .rightAlt: "AltRight", .comma: "Comma", .period: "Period", .slash: "Slash", .semicolon: "Semicolon",
            .quote: "Quote", .openBracket: "BracketLeft", .closeBracket: "BracketRight", .backslash: "Backslash", .hyphen: "Minus",
            .equalSign: "Equal", .graveAccentAndTilde: "Backquote",
        ]
        return named[code]
    }

    // MARK: Sending

    /// Everything on one player: their pad, and on player 1 the remote and keyboard too.
    private func merged(port: UInt8) -> PadState {
        var state = PadState(port: port)
        let now = Date().timeIntervalSince(started)
        for pad in pads.values where pad.port == port {
            var held = pad.last
            held.buttons = PadMapper.turbo(held.buttons, ids: pad.mapper.options.turbo ?? [], hz: pad.mapper.turboHz, now: now)
            state = state.merged(held)
        }
        if port == 0 {
            var keys = remote.state(held: remoteHeld.union(remotePad))
            let typed = keyboard.state(held: keysHeld)
            keys = keys.merged(typed)
            let filtered = remoteShortcuts.filter(keys.buttons)
            keys.buttons = filtered.buttons
            for s in filtered.started { if s == .menu { onMenu?() } else { onShortcut?(s, true) } }
            for s in filtered.ended { onShortcut?(s, false) }
            state = state.merged(keys)
        }
        state.port = port
        return state
    }

    private var activePorts: Set<UInt8> { Set(pads.values.map(\.port)).union([0]) }

    private func flush(port: UInt8, force: Bool = false) {
        guard enabled else { return }
        let state = merged(port: port)
        if force || sent[port] != state {
            send?(state.encoded())
            sent[port] = state
        }
    }

    /// Turbo buttons beat by the clock, so their states are sent again as it ticks.
    private func refreshAll() {
        for port in activePorts { flush(port: port) }
    }

    private func beat() {
        guard enabled else { return }
        for port in activePorts {
            let state = sent[port] ?? PadState(port: port)
            send?(state.encoded())
        }
    }

    /// Lets go of everything, on every player: for the menu, and for leaving.
    func releaseAll() {
        remoteHeld = []
        remotePad = []
        keysHeld = []
        for port in activePorts {
            let released = PadState(port: port)
            send?(released.encoded())
            sent[port] = released
        }
        for pad in pads.values { pad.haptics?.stop(completionHandler: nil); pad.haptics = nil }
    }

    // MARK: Rumble

    func rumble(port: Int, strength: Double) {
        guard let pad = pads.values.first(where: { Int($0.port) == port }), pad.mapper.options.noRumble != true else { return }
        if pad.haptics == nil {
            pad.haptics = pad.controller.haptics?.createEngine(withLocality: .default)
            try? pad.haptics?.start()
        }
        guard let engine = pad.haptics, strength > 0 else { return }
        let event = CHHapticEvent(eventType: .hapticContinuous,
                                  parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(strength))],
                                  relativeTime: 0, duration: 0.12)
        if let pattern = try? CHHapticPattern(events: [event], parameters: []), let player = try? engine.makePlayer(with: pattern) {
            try? player.start(atTime: CHHapticTimeImmediate)
        }
    }
}
#endif
