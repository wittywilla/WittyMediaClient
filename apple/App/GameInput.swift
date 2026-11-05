#if os(tvOS) || os(iOS) || os(visionOS)
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
    /// A Core Haptics engine for each motor the game has used, and what each is playing.
    var engines: [RumbleMotor: CHHapticEngine] = [:]
    var playing: [RumbleMotor: CHHapticPatternPlayer] = [:]

    func stopRumble() {
        for engine in engines.values { engine.stop(completionHandler: nil) }
        engines = [:]
        playing = [:]
    }
    var last = PadState()
    /// The account's profile in use for it here, if any.
    var profile = ""
    /// When Options (Start) went down, for holding it to open the menu.
    var startDownAt: Date?
    /// The touchpad as a touch screen, for a DualSense or a DualShock 4.
    var pointer = PointerState()

    init(controller: GCController, port: UInt8, mapper: PadMapper, shortcuts: PadShortcuts) {
        self.controller = controller
        self.port = port
        self.mapper = mapper
        self.shortcuts = shortcuts
    }
}

/// A player and what they play with, for the menu.
struct GamePlayer: Equatable {
    let port: Int
    let name: String
    let profile: String
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
        /// The console has a touch screen: a touchpad stands in for it.
        var pointer = false
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
    /// Buttons held when input came back, from the press that closed the menu: not the game's
    /// until they're let go.
    private var masked: [UInt8: UInt16] = [:]
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
    /// A controller became this port's player.
    var onJoin: ((Int) -> Void)?
    /// A controller came or went: the touch controls show only while there's none.
    var onPadsChanged: (() -> Void)?
    /// Rumble for player 1 while they play by touch.
    var onTouchRumble: ((Double) -> Void)?
    /// What the touch controls hold, as player 1, and their stylus on a touch-screen console.
    private var touchState = PadState(port: 0)
    private var touchPointer = PointerState()

    var hasPads: Bool { !pads.isEmpty }

    /// Who's on which player, for the menu: the controller and the profile it plays by.
    var players: [GamePlayer] {
        pads.values.sorted { $0.port < $1.port }.map {
            GamePlayer(port: Int($0.port), name: $0.controller.vendorName ?? $0.controller.productCategory, profile: $0.profile)
        }
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
        motionWants = [:]
        updateMotion()
        for pad in pads.values {
            pad.controller.extendedGamepad?.valueChangedHandler = nil
            pad.controller.microGamepad?.valueChangedHandler = nil
            pad.stopRumble()
            Self.keepButtons(pad.controller, forGame: false)
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
        if !on {
            releaseAll()
        } else {
            for port in activePorts { masked[port] = 0xFFFF }
            refreshAll()
        }
    }

    // MARK: Controllers

    /// How many players the game takes: 4, or up to 8 where the second stream says its core has a multitap.
    var maxPorts = 4 {
        didSet { maxPorts = min(8, max(1, maxPorts)) }
    }

    private func freePort() -> UInt8 {
        let taken = Set(pads.values.map(\.port))
        return (0..<UInt8(maxPorts)).first { !taken.contains($0) } ?? UInt8(maxPorts - 1)
    }

    private func attach(_ controller: GCController, announce: Bool) {
        let id = ObjectIdentifier(controller)
        guard pads[id] == nil else { return }
        if controller.extendedGamepad == nil, let micro = controller.microGamepad, PadIdentity.isRemote(productCategory: controller.productCategory) {
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
        guard let setup, controller.extendedGamepad != nil || controller.microGamepad != nil else { return }
        let port = freePort()
        controller.playerIndex = GCControllerPlayerIndex(rawValue: Int(port)) ?? .indexUnset
        Self.keepButtons(controller, forGame: true)
        // A PlayStation pad's light in its player's colour, as a console does: blue, red, green, pink.
        let colours: [(Float, Float, Float)] = [(0, 0.25, 1), (1, 0, 0.1), (0, 0.9, 0.2), (1, 0.2, 0.7)]
        let c = colours[Int(port) % colours.count]
        controller.light?.color = GCColor(red: c.0, green: c.1, blue: c.2)
        let shortcuts = PadShortcuts(settings: setup.settings, consoleButtons: setup.consoleButtons)
        let mapper = PadMapper(defaults: setup.controls?.defaults?.gamepad, options: nil, defaultOptions: setup.controls?.defaults?.options)
        let pad = Pad(controller: controller, port: port, mapper: mapper, shortcuts: shortcuts)
        pads[id] = pad
        let changed: () -> Void = { [weak self] in Task { @MainActor in self?.padChanged(id) } }
        if let extended = controller.extendedGamepad {
            extended.valueChangedHandler = { _, _ in changed() }
        } else if let micro = controller.microGamepad {
            // One Joy-Con on its side, or another small pad: its stick is the D-pad.
            micro.reportsAbsoluteDpadValues = true
            micro.allowsRotation = true
            micro.valueChangedHandler = { _, _ in changed() }
        }
        // Home, where the system lets it through, opens the menu, and so do Start and Select together.
        if announce { onNotice?("\(controller.vendorName ?? "A controller") is player \(port + 1)") }
        onJoin?(Int(port))
        onPadsChanged?()
        updateMotion()
        Task { await loadProfile(for: id) }
        updateTurboTimer()
    }

    private func detach(_ controller: GCController) {
        let id = ObjectIdentifier(controller)
        guard let pad = pads.removeValue(forKey: id) else { return }
        pad.stopRumble()
        if let motion = controller.motion, motion.sensorsRequireManualActivation { motion.sensorsActive = false }
        Self.keepButtons(controller, forGame: false)
        if pad.pointer.pressed { sendPointer(PointerState(pressed: false, x: pad.pointer.x, y: pad.pointer.y), times: 3) }
        // Fast-forward or rewind held on it stops with it.
        for s in pad.shortcuts.endAll() { onShortcut?(s, false) }
        updateTurboTimer()
        // Disconnecting lets go of everything it held at once.
        let released = PadState(port: pad.port)
        send?(released.encoded())
        sent[pad.port] = released
        onNotice?("Player \(pad.port + 1)'s controller disconnected")
        onPadsChanged?()
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
        pad.profile = resolved?.profile?.name ?? ""
        if !pad.profile.isEmpty { onNotice?("Player \(pad.port + 1): \(pad.profile)") }
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

    /// While a game plays, tvOS doesn't act on a controller's buttons itself: Home, Options and
    /// Share are the game's, or the menu's. Given back when the game ends.
    static func keepButtons(_ controller: GCController, forGame: Bool) {
        for element in controller.physicalInputProfile.allElements {
            element.preferredSystemGestureState = forGame ? .disabled : .enabled
        }
    }

    /// A pad with only a D-pad and a few buttons, in the standard layout.
    private static func reading(_ m: GCMicroGamepad) -> StandardPadReading {
        var r = StandardPadReading()
        r[button: StandardPadReading.south] = Double(m.buttonA.value)
        r[button: StandardPadReading.west] = Double(m.buttonX.value)
        r[button: StandardPadReading.start] = Double(m.buttonMenu.value)
        r[button: StandardPadReading.up] = m.dpad.yAxis.value > 0.5 ? 1 : 0
        r[button: StandardPadReading.down] = m.dpad.yAxis.value < -0.5 ? 1 : 0
        r[button: StandardPadReading.left] = m.dpad.xAxis.value < -0.5 ? 1 : 0
        r[button: StandardPadReading.right] = m.dpad.xAxis.value > 0.5 ? 1 : 0
        r.axes = [Double(m.dpad.xAxis.value), Double(-m.dpad.yAxis.value), 0, 0]
        return r
    }

    private func padChanged(_ id: ObjectIdentifier) {
        guard let pad = pads[id] else { return }
        guard let g = pad.controller.extendedGamepad else {
            if let m = pad.controller.microGamepad { apply(pad, Self.reading(m), home: false) }
            return
        }
        touchpad(pad)
        apply(pad, Self.reading(g), home: g.buttonHome?.isPressed == true)
    }

    /// A DualSense's or a DualShock 4's touchpad, as the console's touch screen: a click is a press.
    private func touchpad(_ pad: Pad) {
        guard setup?.pointer == true else { return }
        let profile = pad.controller.physicalInputProfile
        guard let surface = profile.dpads[GCInputDualShockTouchpadOne], let click = profile.buttons[GCInputDualShockTouchpadButton] else { return }
        let state = PointerState.touchpad(x: Double(surface.xAxis.value), y: Double(surface.yAxis.value), pressed: click.isPressed)
        guard state != pad.pointer else { return }
        let released = pad.pointer.pressed && !state.pressed
        pad.pointer = state
        // A lost release would hold the stylus down: it goes more than once.
        sendPointer(state, times: released ? 3 : 1)
    }

    private func sendPointer(_ state: PointerState, times: Int) {
        guard enabled else { return }
        for _ in 0..<times { send?(state.encoded()) }
    }

    private func apply(_ pad: Pad, _ reading: StandardPadReading, home: Bool) {
        // Holding Options (Start) for a second opens the menu; a press is still Start for the game.
        if reading[button: StandardPadReading.start] > 0.5 {
            if pad.startDownAt == nil { pad.startDownAt = Date() }
        } else {
            pad.startDownAt = nil
        }
        var state = pad.mapper.state(reading, port: pad.port, applyTurbo: false)
        let filtered = pad.shortcuts.filter(state.buttons)
        state.buttons = filtered.buttons
        for s in filtered.started {
            if s == .menu { onMenu?() } else { onShortcut?(s, true) }
        }
        for s in filtered.ended { onShortcut?(s, false) }
        // The guide button, where the system lets an app have it, opens the menu too.
        if home { onMenu?() }
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
        // Escape opens the menu, as on the website; on a TV, Backspace too, unless the layout uses it.
        if name == "Escape" || (name == "Backspace" && !keyboard.knows("Backspace")) {
            if pressed { onMenu?() }
            return
        }
        if pressed { keysHeld.insert(name) } else { keysHeld.remove(name) }
        flush(port: 0)
    }

    /// A key that came through UIKit rather than GameController, by its code name.
    func typed(_ code: String, down: Bool) {
        if down { keysHeld.insert(code) } else { keysHeld.remove(code) }
        flush(port: 0)
    }

    /// The same names from UIKit's key codes.
    static func codeName(hid: UIKeyboardHIDUsage) -> String? {
        codeName(GCKeyCode(rawValue: CFIndex(hid.rawValue)))
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

    // MARK: Touch controls

    func touch(_ state: PadState) {
        var state = state
        state.port = 0
        guard state != touchState else { return }
        touchState = state
        flush(port: 0)
    }

    /// The stylus on a DS's or 3DS's lower screen. A lost release would hold it down: it goes more than once.
    func touchStylus(_ state: PointerState) {
        guard state != touchPointer else { return }
        let released = touchPointer.pressed && !state.pressed
        touchPointer = state
        sendPointer(state, times: released ? 5 : 1)
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
            keys = keys.merged(typed).merged(touchState)
            let filtered = remoteShortcuts.filter(keys.buttons)
            keys.buttons = filtered.buttons
            for s in filtered.started { if s == .menu { onMenu?() } else { onShortcut?(s, true) } }
            for s in filtered.ended { onShortcut?(s, false) }
            state = state.merged(keys)
        }
        state.port = port
        let held = (masked[port] ?? 0) & state.buttons
        masked[port] = held
        state.buttons &= ~held
        return state
    }

    private var activePorts: Set<UInt8> { Set(pads.values.map(\.port)).union([0]) }

    /// The players this device plays: player 1 always (the remote, the keyboard or touch), and each pad's.
    var ports: [Int] { activePorts.map(Int.init).sorted() }

    private func flush(port: UInt8, force: Bool = false) {
        guard enabled else { return }
        var state = merged(port: port)
        state.buttons |= heldLongEnough(port: port, state.buttons)
        if force || sent[port] != state {
            send?(state.encoded())
            sent[port] = state
        }
    }

    /// A press as short as a click is still seen: a game reads its buttons once a frame, so a
    /// button let go within three frames of being pressed is held until then. Turbo is left alone.
    private static let shortestPress: TimeInterval = 0.05
    private var pressedAt: [UInt8: [Int: Date]] = [:]

    private func heldLongEnough(port: UInt8, _ buttons: UInt16) -> UInt16 {
        let now = Date()
        let before = sent[port]?.buttons ?? 0
        var turbo: UInt16 = 0
        for pad in pads.values where pad.port == port { for id in pad.mapper.options.turbo ?? [] { turbo |= RetroPad.bit(id) } }
        var keep: UInt16 = 0
        var wait: TimeInterval = 0
        for id in 0...15 {
            let bit = RetroPad.bit(id)
            if buttons & bit != 0 {
                if before & bit == 0 { pressedAt[port, default: [:]][id] = now }
            } else if before & bit != 0, turbo & bit == 0, let at = pressedAt[port]?[id] {
                let held = now.timeIntervalSince(at)
                if held < Self.shortestPress {
                    keep |= bit
                    wait = max(wait, Self.shortestPress - held)
                }
            }
        }
        if keep != 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + wait + 0.005) { [weak self] in self?.flush(port: port) }
        }
        return keep
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
        if touchPointer.pressed { send?(touchPointer.encoded()) }
        for pad in pads.values {
            if pad.pointer.pressed { send?(pad.pointer.encoded()) }
            if let at = pad.startDownAt, Date().timeIntervalSince(at) >= 1 {
                pad.startDownAt = nil
                onMenu?()
            }
        }
    }

    /// Lets go of everything, on every player: for the menu, and for leaving.
    func releaseAll() {
        remoteHeld = []
        remotePad = []
        for pad in pads.values { for s in pad.shortcuts.endAll() { onShortcut?(s, false) } }
        for s in remoteShortcuts.endAll() { onShortcut?(s, false) }
        keysHeld = []
        touchState = PadState(port: 0)
        if touchPointer.pressed {
            touchPointer.pressed = false
            for _ in 0..<5 { send?(touchPointer.encoded()) }
        }
        for port in activePorts {
            let released = PadState(port: port)
            send?(released.encoded())
            sent[port] = released
        }
        for pad in pads.values { pad.stopRumble() }
    }

    // MARK: Rumble

    /// A motor at a strength for `ms` (the server renews it while it's on), replacing what that
    /// motor was doing; 0 stops it at once. The strong motor is the left handle's, the weak the right's.
    func rumble(port: Int, strength: Double, motor: RumbleMotor = .either, ms: Int? = nil) {
        guard let pad = pads.values.first(where: { Int($0.port) == port }) else {
            if port == 0, strength > 0 { onTouchRumble?(strength) }
            return
        }
        guard pad.mapper.options.noRumble != true else { return }
        try? pad.playing[motor]?.stop(atTime: CHHapticTimeImmediate)
        pad.playing[motor] = nil
        guard strength > 0, let engine = engine(pad, motor) else { return }
        let seconds = ms.map { max(0.02, Double($0) / 1000) } ?? 0.12
        let event = CHHapticEvent(eventType: .hapticContinuous,
                                  parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(strength)),
                                               CHHapticEventParameter(parameterID: .hapticSharpness, value: motor == .weak ? 0.8 : 0.2)],
                                  relativeTime: 0, duration: seconds)
        if let pattern = try? CHHapticPattern(events: [event], parameters: []), let player = try? engine.makePlayer(with: pattern) {
            try? player.start(atTime: CHHapticTimeImmediate)
            pad.playing[motor] = player
        }
    }

    private func engine(_ pad: Pad, _ motor: RumbleMotor) -> CHHapticEngine? {
        if let engine = pad.engines[motor] { return engine }
        guard let haptics = pad.controller.haptics else { return nil }
        let wanted: GCHapticsLocality = motor == .strong ? .leftHandle : motor == .weak ? .rightHandle : .default
        let locality = haptics.supportedLocalities.contains(wanted) ? wanted : .default
        guard let engine = haptics.createEngine(withLocality: locality) else { return nil }
        try? engine.start()
        pad.engines[motor] = engine
        return engine
    }

    // MARK: Motion

    /// The players whose motion the game reads, and how.
    private var motionWants: [UInt8: GameMotionWant] = [:]
    private var motionTimer: Timer?

    /// What the game said it wants of one player's motion.
    func setMotion(_ want: GameMotionWant) {
        guard let port = want.port, (0...7).contains(port) else { return }
        motionWants[UInt8(port)] = want.wanted ? want : nil
        updateMotion()
    }

    /// Sensors on only for the players wanted, and sent as often as the game asks, up to 60 a second.
    private func updateMotion() {
        for pad in pads.values {
            if let motion = pad.controller.motion, motion.sensorsRequireManualActivation {
                motion.sensorsActive = motionWants[pad.port] != nil
            }
        }
        motionTimer?.invalidate()
        motionTimer = nil
        guard let hz = motionWants.values.map(\.hz).max(), hz > 0 else { return }
        motionTimer = Timer.scheduledTimer(withTimeInterval: 1 / min(60, hz), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sendMotion() }
        }
    }

    private func sendMotion() {
        guard enabled else { return }
        for pad in pads.values {
            guard let want = motionWants[pad.port], let m = pad.controller.motion else { continue }
            var accel = (x: 0.0, y: 0.0, z: 0.0), gyro = (x: 0.0, y: 0.0, z: 0.0)
            if want.accel {
                if m.hasGravityAndUserAcceleration {
                    accel = (m.gravity.x + m.userAcceleration.x, m.gravity.y + m.userAcceleration.y, m.gravity.z + m.userAcceleration.z)
                } else {
                    accel = (m.acceleration.x, m.acceleration.y, m.acceleration.z)
                }
            }
            if want.gyro, m.hasRotationRate {
                gyro = (m.rotationRate.x, m.rotationRate.y, m.rotationRate.z)
            }
            send?(GameMotion.encoded(port: pad.port, accel: accel, gyro: gyro))
        }
    }
}
#endif
