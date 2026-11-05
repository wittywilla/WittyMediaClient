#if os(tvOS) || os(iOS) || os(visionOS)
import AVKit
import CoreMedia
import GameController
import MetalKit
import SwiftUI
import UIKit
import WittyKit

// A game on Apple TV. The server runs it and streams it over a WebSocket: this shows the picture,
// plays the sound, sends controller states, and has the game menu the server's docs ask a TV app
// for: Resume, Press Start, Press Select, Save, Load, Reset and Quit. Saves are the server's, so a
// game saved here resumes on the website, and the other way round.

// MARK: - The view the picture is drawn in

/// The picture, and while a game plays the only thing that can have focus, so the remote's presses
/// come here and not to the screens behind. It's a game controller's event view: the remote's Back
/// button and a pad's B don't go back through the app while a game is playing.
final class GameScreenView: MTKView {
    var playing = true {
        didSet { if playing != oldValue { setNeedsFocusUpdate() } }
    }
    var onPress: ((String, Bool) -> Void)?
    var onKey: ((String, Bool) -> Void)?
    var onMenu: (() -> Void)?

    override var canBecomeFocused: Bool { playing }

    private func name(_ press: UIPress) -> String? {
        switch press.type {
        case .upArrow: return "ArrowUp"
        case .downArrow: return "ArrowDown"
        case .leftArrow: return "ArrowLeft"
        case .rightArrow: return "ArrowRight"
        case .select: return "Enter"
        case .playPause: return "MediaPlayPause"
        default: break
        }
        // A keyboard's arrows and Return, as the simulator sends its remote, are the remote's.
        switch press.key?.keyCode {
        case .keyboardReturnOrEnter?: return "Enter"
        case .keyboardUpArrow?: return "ArrowUp"
        case .keyboardDownArrow?: return "ArrowDown"
        case .keyboardLeftArrow?: return "ArrowLeft"
        case .keyboardRightArrow?: return "ArrowRight"
        default: return nil
        }
    }

    private func isMenu(_ press: UIPress) -> Bool {
        press.type == .menu || press.key?.keyCode == .keyboardEscape || press.key?.keyCode == .keyboardDeleteOrBackspace
    }

    private func handle(_ presses: Set<UIPress>, down: Bool) -> Set<UIPress> {
        guard playing else { return presses }
        var rest = Set<UIPress>()
        for press in presses {
            if press.key != nil, GCKeyboard.coalesced != nil {
                // A keyboard GameController reads already: once is enough. Kept from the app's screens.
                continue
            }
            if isMenu(press) {
                if down { onMenu?() }
            } else if let name = name(press) {
                onPress?(name, down)
            } else if let code = press.key.flatMap({ GameInput.codeName(hid: $0.keyCode) }) {
                // Any other key, by the console's keyboard layout.
                onKey?(code, down)
            } else {
                rest.insert(press)
            }
        }
        return rest
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let rest = handle(presses, down: true)
        if !rest.isEmpty { super.pressesBegan(rest, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let rest = handle(presses, down: false)
        if !rest.isEmpty { super.pressesEnded(rest, with: event) }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let rest = handle(presses, down: false)
        if !rest.isEmpty { super.pressesCancelled(rest, with: event) }
    }
}

/// While the game plays, controllers go to the game and not to the app's screens.
final class GameHostController: GCEventViewController {
    let screen = GameScreenView(frame: .zero, device: MTLCreateSystemDefaultDevice())

    override func loadView() {
        screen.isOpaque = false
        screen.backgroundColor = .clear
        screen.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        screen.colorPixelFormat = .bgra8Unorm
        // Drawn when a frame comes, not on a clock of its own.
        screen.isPaused = true
        screen.enableSetNeedsDisplay = false
        screen.autoResizeDrawable = true
        view = screen
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] { [screen] }

    func setPlaying(_ on: Bool) {
        guard screen.playing != on || controllerUserInteractionEnabled == on else { return }
        // Off while the menu is open, so the remote moves through it.
        controllerUserInteractionEnabled = !on
        screen.playing = on
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
    }
}

private struct GameScreen: UIViewControllerRepresentable {
    let host: GameHostController
    let playing: Bool

    func makeUIViewController(context: Context) -> GameHostController { host }
    func updateUIViewController(_ host: GameHostController, context: Context) { host.setPlaying(playing) }
}

// MARK: - The stream

/// From the transport to the screen and the speakers, on the transport's own thread.
private final class GamePipeline: @unchecked Sendable {
    let renderer: GamePictureRenderer?
    let sound = GameSound()
    /// For the second stream's Opus, where this device can decode it.
    let opus = GameOpusDecoder()
    private var decoder: GameVideoDecoder!
    private weak var view: MTKView?
    private let lock = NSLock()
    private var drawWaiting = false
    var askKeyframe: (@Sendable () -> Void)?

    init(view: MTKView) {
        self.view = view
        renderer = GamePictureRenderer(view: view)
        decoder = GameVideoDecoder(output: { [weak self] pixels in
            self?.renderer?.show(pixels)
            self?.draw()
        }, needKeyframe: { [weak self] in self?.askKeyframe?() })
    }

    var frames: Int { renderer?.frames ?? 0 }

    /// Decoding happens here and nowhere else, whichever connection a message came on.
    private let queue = DispatchQueue(label: "wittyplay.stream", qos: .userInteractive)
    private var connection = 0

    /// A new connection: what's left of the last one is dropped, and the decoder starts afresh.
    func restart() -> Int {
        lock.lock()
        connection += 1
        let id = connection
        lock.unlock()
        queue.async { [self] in
            decoder.reset()
            opus?.reset()
            sound.flush()
        }
        return id
    }

    func take(_ message: GameStreamMessage, from id: Int) {
        queue.async { [self] in
            lock.lock()
            let current = connection
            lock.unlock()
            guard id == current else { return }
            switch message {
            case .video(let keyframe, let data):
                decoder.decode(data, keyframe: keyframe)
            case .jpeg(let data):
                if let image = decodeGameJPEG(data) {
                    renderer?.show(image)
                    draw()
                }
            case .pcm(let rate, let samples):
                sound.play(samples, rate: rate)
            case .opus(_, let packet):
                if let samples = opus?.decode(packet) { sound.play(samples, rate: GameOpusDecoder.rate) }
            case .picture(let pixels):
                // Decoded by the transport itself, as WebRTC does.
                renderer?.show(pixels)
                draw()
            case .timing, .unknown:
                break
            }
        }
    }

    /// One draw at a time: frames that come while one waits are drawn by it.
    func draw() {
        lock.lock()
        if drawWaiting {
            lock.unlock()
            return
        }
        drawWaiting = true
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.drawWaiting = false
            self.lock.unlock()
            self.view?.draw()
        }
    }
}

// MARK: - The game

@MainActor
final class GamePlayerModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case preparing(Double?)
        case starting
        case connecting
        case playing
        case failed(String)
    }

    enum MenuPage: Equatable {
        case main, save, load, controllers, reset, quit
    }

    @Published var phase: Phase = .loading
    @Published var menuOpen = false
    @Published var page: MenuPage = .main
    @Published var notice = ""
    @Published private(set) var session: GameSession?
    @Published private(set) var saves: [GameSave] = []
    @Published private(set) var settings = GameSettings(values: [:])
    @Published private(set) var disc = 0
    @Published private(set) var discs = 1
    @Published private(set) var busy = false
    @Published private(set) var players: [GamePlayer] = []
    /// What each player has plugged in, where the console's emulator offers a choice.
    @Published private(set) var devices: [GamePortDevices] = []
    @Published private(set) var plugged: [Int: Int] = [:]
    @Published var leave = false
    /// The console's controls, for drawing them on a touch screen.
    @Published private(set) var controlsData: GameControls?
    @Published private(set) var padsConnected = false
    /// Whether this person wants touch controls on this device; they show only with no controller.
    @Published var touchWanted: Bool = GamePlayerModel.touchByDefault {
        didSet { UserDefaults.standard.set(touchWanted, forKey: "wittyplay.touch") }
    }

    let host = GameHostController()
    private let input = GameInput()
    private var pipeline: GamePipeline?
    private var transport: GameTransport?
    private var client = WittyClient(base: "")
    private var gameId: Int64 = 0
    private var start: GameStart = .fresh
    private var modes: [String] = GameModes.supported
    private var modeAt = 0
    private var watchdog: Timer?
    private var framesSeen = 0
    private var framesAt = Date()
    private var connectedAt = Date()
    private var aspect = 4.0 / 3.0
    private var frame: (width: Double, height: Double) = (0, 0)
    private var turns = 0
    private var stopped = false
    private var noticeTask: Task<Void, Never>?
    private var loadAfterStart: Int?
    private var consoleButtons: Set<Int> = []
    private var menuClosedAt = Date.distantPast
    private var menuOpenedAt = Date.distantPast
    private var hadPicture = false
    /// Actions reach the server in the order they're made: each waits for the one before.
    private var lastAction: Task<Void, Never>?

    var quickSlot: Int { max(1, min(99, Int(settings.number("states.quickSlot", 1)))) }
    var confirms: Bool { settings.flag("states.confirm", true) }

    /// Touch layouts are saved per device, as the website saves them: an id of this device's own.
    static var deviceId: String {
        let key = "wittyplay.device"
        if let saved = UserDefaults.standard.string(forKey: key) { return saved }
        #if os(tvOS)
        let kind = "appletv"
        #elseif os(visionOS)
        let kind = "vision"
        #else
        let kind = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        #endif
        let made = kind + "-" + UUID().uuidString.prefix(12).lowercased()
        UserDefaults.standard.set(made, forKey: key)
        return made
    }

    func begin(id: Int64, start: GameStart, client: WittyClient) async {
        guard pipeline == nil else { return }
        // The second stream over WebRTC, first where the server has it.
        GameTransports.webRTC = { offer, hello in GameWebRTCTransport(offer: offer, hello: hello) }
        self.client = client
        gameId = id
        self.start = start
        loadAfterStart = start.slotToLoad
        pipeline = GamePipeline(view: host.screen)
        if pipeline?.renderer == nil {
            phase = .failed("This Apple TV couldn't set up its graphics for the game.")
            return
        }
        input.send = { [weak self] data in self?.transport?.sendInput(data) }
        input.onMenu = { [weak self] in self?.openMenu() }
        input.onShortcut = { [weak self] shortcut, down in self?.shortcut(shortcut, down) }
        input.onNotice = { [weak self] words in self?.say(words) }
        input.onJoin = { [weak self] port in self?.joined(port: port) }
        input.onPadsChanged = { [weak self] in
            guard let self else { return }
            self.padsConnected = self.input.hasPads
            self.players = self.input.players
            // On the second stream, the server is told which players this device now holds.
            self.transport?.sendEvent(GameHello.seatsText(self.input.ports))
        }
        input.onTouchRumble = { strength in Self.touchRumble(strength) }
        host.screen.onPress = { [weak self] name, down in self?.input.press(name, down: down) }
        host.screen.onKey = { [weak self] code, down in self?.input.typed(code, down: down) }
        host.screen.onMenu = { [weak self] in self?.openMenu() }
        pipeline?.askKeyframe = { @Sendable [weak self] in
            // The stack has no way of its own to ask: the server's 0xF7.
            Task { @MainActor in self?.transport?.askKeyframe() }
        }
        settings = (try? await client.gameSettings(item: id)) ?? GameSettings(values: [:])
        guard live else { return }
        applySettings()
        // A game in an archive is unpacked first, which can take a while on a small server.
        do {
            while !Task.isCancelled {
                let state = try await client.prepareGame(id)
                if state.ready { break }
                phase = .preparing(state.fraction)
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        } catch {
            fail(error)
            return
        }
        guard live else { return }
        phase = .starting
        let session: GameSession
        do {
            session = try await client.playGame(id, resume: start.resumes, safeMode: start.safeMode)
        } catch {
            fail(error)
            return
        }
        guard live else {
            // Left while it started: it still has to be stopped, from a task that isn't cancelled.
            Task.detached { [client] in try? await client.stopGame(session.id) }
            return
        }
        self.session = session
        aspect = session.aspect ?? (Double(session.width ?? 4) / Double(max(1, session.height ?? 3)))
        frame = (Double(session.width ?? 0), Double(session.height ?? 0))
        turns = session.turns ?? 0
        disc = session.disc ?? 0
        discs = max(1, session.discs ?? 1)
        modes = GameModes.order(session.modes)
        devices = (session.devices ?? []).filter { ($0.types ?? []).count > 1 }
        input.playerPorts = GamePorts.players(count: nil, devices: session.devices)
        plugged = Dictionary(devices.compactMap { d in d.current.map { (d.port, $0) } }, uniquingKeysWith: { a, _ in a })
        for words in session.notices ?? [] where !words.isEmpty { say(words) }
        updateLayout()
        let console = session.console ?? ""
        let controls = try? await client.gameControls(console: console, device: Self.deviceId, game: id)
        guard live else {
            Task.detached { [client] in try? await client.stopGame(session.id) }
            return
        }
        controlsData = controls
        consoleButtons = Set((controls?.pad?.buttons ?? []).map(\.id)).union([RetroPad.up, RetroPad.down, RetroPad.left, RetroPad.right])
        input.start(client: client, setup: GameInput.Setup(controls: controls, settings: settings, console: console, game: id, consoleButtons: consoleButtons,
                                                           pointer: controls?.pad?.pointer == true))
        players = input.players
        padsConnected = input.hasPads
        connect()
        watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.watch() }
        }
    }

    /// Still on screen, and not stopped.
    private var live: Bool { !stopped && !Task.isCancelled }

    private func fail(_ error: Error) {
        if error is CancellationError { return }
        let words = (error as? APIError)?.message ?? plainWords(Problem.of(error))
        phase = .failed(words.isEmpty ? "This game couldn't start." : words)
    }

    private func applySettings() {
        guard let renderer = pipeline?.renderer else { return }
        renderer.look = PictureLook(settings)
        pipeline?.sound.latency = GameSoundLatency.seconds(settings.text("audio.latency", "lowest"))
        pipeline?.sound.setVolume(settings.number("audio.volume", 1), muted: settings.flag("audio.mute", false))
        transport?.setVolume(settings.number("audio.volume", 1), muted: settings.flag("audio.mute", false))
    }

    private func updateLayout() {
        let bezel = settings.text("display.bezel", "none")
        pipeline?.renderer?.layout = (settings, aspect, frame, turns, bezel == "none" ? 0 : settings.number("display.bezelInset", 0))
        pipeline?.draw()
    }

    // MARK: Touch controls

    /// On by default where the screen is touched; a Vision Pro is played with a controller.
    static var touchByDefault: Bool {
        #if os(iOS)
        return UserDefaults.standard.object(forKey: "wittyplay.touch") as? Bool ?? true
        #else
        return UserDefaults.standard.object(forKey: "wittyplay.touch") as? Bool ?? false
        #endif
    }

    var touchShown: Bool {
        #if os(tvOS)
        return false
        #else
        return touchWanted && !padsConnected && !(controlsData?.controls ?? []).isEmpty
        #endif
    }

    /// A DS or 3DS: a finger on the picture is the stylus.
    var touchScreenConsole: Bool { controlsData?.pad?.pointer == true }

    #if DEBUG
    /// What the fingers last held, and each press since, for the touch preview.
    @Published private(set) var lastTouch = TouchOutput()
    @Published private(set) var touchLog: [String] = []

    /// The touch controls with no game: a console's controls, as if playing.
    func previewTouch(_ controls: GameControls) {
        controlsData = controls
        touchWanted = true
        phase = .playing
    }
    #endif

    /// What the fingers hold, from the touch controls over a screen of `size` points.
    func touched(_ out: TouchOutput, size: CGSize) {
        #if DEBUG
        let pressed = out.buttons & ~lastTouch.buttons
        let names = RetroPad.names.filter { pressed & RetroPad.bit($0.value) != 0 }.sorted { $0.value < $1.value }.map(\.key)
        if !names.isEmpty { touchLog = Array((touchLog + [names.joined(separator: "+")]).suffix(12)) }
        if out.leftX != 0 || out.leftY != 0 { touchLog = Array((touchLog + [String(format: "stick %.2f,%.2f", out.leftX, out.leftY)]).suffix(12)) }
        if let at = out.stylus, lastTouch.stylus == nil { touchLog = Array((touchLog + [String(format: "stylus %.0f,%.0f", at.x, at.y)]).suffix(12)) }
        lastTouch = out
        #endif
        input.touch(out.padState(port: 0))
        guard touchScreenConsole else { return }
        if let at = out.stylus, let drawn = pipeline?.renderer?.drawnPicture {
            let picture = (x: drawn.x * size.width, y: drawn.y * size.height, width: drawn.width * size.width, height: drawn.height * size.height)
            let pointer = touchPointer(x: at.x, y: at.y, picture: picture, turns: drawn.turns, pressed: true)
            lastStylus = pointer
            input.touchStylus(pointer)
        } else if lastStylus.pressed {
            // Lifted where it last was.
            lastStylus.pressed = false
            input.touchStylus(lastStylus)
        }
    }
    private var lastStylus = PointerState()

    /// In portrait the picture moves up above the controls; otherwise it has the whole screen.
    func placePicture(aboveControls: Bool) {
        let area: (x: Double, y: Double, width: Double, height: Double) = aboveControls ? (0, 0, 1, 0.52) : (0, 0, 1, 1)
        guard let renderer = pipeline?.renderer, renderer.area != area else { return }
        renderer.area = area
        pipeline?.draw()
    }

    private static func touchRumble(_ strength: Double) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: strength > 0.5 ? .heavy : .medium).impactOccurred()
        #endif
    }

    // MARK: The connection

    private func connect() {
        guard let session, !stopped else { return }
        transport?.close()
        let id = pipeline?.restart() ?? 0
        let mode = modes[min(modeAt, modes.count - 1)]
        guard let transport = GameTransports.make(mode: mode, session: session.id, client: client, hello: hello()) else {
            phase = .failed("This server's address can't be used for a game.")
            return
        }
        phase = .connecting
        let pipeline = self.pipeline
        transport.onMessage = { @Sendable message in pipeline?.take(message, from: id) }
        transport.onEvent = { @Sendable [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        transport.onEnd = { @Sendable [weak self] end in
            Task { @MainActor in self?.connectionLost(end) }
        }
        self.transport = transport
        transport.setVolume(settings.number("audio.volume", 1), muted: settings.flag("audio.mute", false))
        connectedAt = Date()
        framesAt = Date()
        framesSeen = pipeline?.frames ?? 0
        transport.open()
    }

    private func connectionLost(_ end: GameTransportEnd) {
        guard !stopped else { return }
        // This way didn't get through before any picture: the next way, at once.
        if end == .unreachable, !hadPicture, modeAt + 1 < modes.count {
            modeAt += 1
            say("Trying another way of sending the picture")
            connect()
            return
        }
        // Gone from the server: stopped from elsewhere, another game started, or left too long.
        if end == .gone {
            finish(saying: "This game has stopped. It may have been started on another device, or left for more than a minute.")
            return
        }
        // The game waits, paused, for a minute: a new connection picks it up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, !self.stopped else { return }
            if case .failed = self.phase { return }
            self.connect()
        }
    }

    /// No first picture in 12 seconds: the next way of sending. No new picture for 4 seconds while
    /// it's playing: connect again.
    private func watch() {
        guard !stopped, let pipeline else { return }
        let frames = pipeline.frames
        if frames != framesSeen {
            framesSeen = frames
            framesAt = Date()
            if phase != .playing { firstPicture() }
            return
        }
        guard !menuOpen else {
            framesAt = Date()
            return
        }
        if Date().timeIntervalSince(framesAt) > 60 {
            // The server keeps a game for a minute with nobody connected: past that, it's gone.
            finish(saying: "The game's picture stopped coming. Check the network, then start the game again: it saved where you were.")
        } else if phase == .connecting, Date().timeIntervalSince(connectedAt) > GameModes.firstPictureWait(modes[min(modeAt, modes.count - 1)]) {
            // No first picture: the next way of sending. A picture that stopped: the same way again.
            if !hadPicture, modeAt + 1 < modes.count {
                modeAt += 1
                say("Trying another way of sending the picture")
            }
            connect()
        } else if phase == .playing, Date().timeIntervalSince(framesAt) > 4 {
            connect()
        }
    }

    /// Ports whose new player may need something plugged in, once the game is running.
    private var joinedPorts: Set<Int> = []
    private var autoPlugged: Set<Int> = []

    private func joined(port: Int) {
        joinedPorts.insert(port)
        if hadPicture { plugForNewPlayers() }
    }

    /// An NES's players 3 and 4 play through a Four Score only once a gamepad is in their ports:
    /// a controller that joins as one of them plugs one in, once, where the port is on "Auto".
    private func plugForNewPlayers() {
        for port in joinedPorts.sorted() where !autoPlugged.contains(port) {
            autoPlugged.insert(port)
            if let d = devices.first(where: { $0.port == port }), let pad = d.padForNewPlayer(plugged: plugged[port]) {
                plug(port: port, device: pad)
            }
        }
        joinedPorts = []
    }

    private func firstPicture() {
        phase = .playing
        hadPicture = true
        plugForNewPlayers()
        players = input.players
        if let slot = loadAfterStart {
            loadAfterStart = nil
            Task { await act(.load(slot), done: "Loaded \(GameWords.slotName(slot).lowercased())") }
        }
    }

    private func handle(_ event: GameEvent) {
        switch event {
        case .rumble(let port, let strength, let motor, let ms): input.rumble(port: port, strength: strength, motor: motor, ms: ms)
        case .motion(let want): input.setMotion(want)
        case .message(let text): say(text)
        case .geometry(let width, let height, let shape):
            if let shape, shape > 0 { aspect = shape }
            if frame.width == 0 { frame = (Double(width), Double(height)) }
            updateLayout()
        case .rotation(let t):
            turns = t
            updateLayout()
        case .avinfo(let shape, _, _):
            if let shape, shape > 0 { aspect = shape }
            updateLayout()
        case .frame(let width, let height):
            frame = (Double(width), Double(height))
            updateLayout()
        case .disc(let index, let count):
            disc = index
            discs = max(1, count)
        case .shutdown:
            finish(saying: "")
        case .ended(let text):
            finish(saying: text.isEmpty ? "The game stopped." : text)
        case .stream(let s):
            // The second stream says the shape and turns as the session does, how many players the
            // game takes, and whose motion it reads.
            matchRefresh(fps: s.fps, width: s.width, height: s.height)
            if let shape = s.aspect, shape > 0 { aspect = shape }
            turns = s.turns
            if s.ports > 0 { input.playerPorts = GamePorts.players(count: s.ports, devices: session?.devices) }
            for want in s.motionOn { input.setMotion(want) }
            updateLayout()
        case .refused(let code, let text, _):
            say(text.isEmpty ? "The game refused that (\(code))." : text)
        // A core's lights: libretro has no light bar, so each pad keeps its player's colour.
        case .hello, .seats, .led, .unknown:
            break
        }
    }

    /// What this device says about itself on the second stream.
    private func hello() -> GameHello {
        #if os(tvOS)
        let platform = "tvOS"
        #elseif os(visionOS)
        let platform = "visionOS"
        #else
        let platform = "iOS"
        #endif
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        #if os(visionOS)
        let display = GameHello.Display(hz: 90, width: 0, height: 0)
        #else
        let screen = UIScreen.main
        let display = GameHello.Display(hz: Double(screen.maximumFramesPerSecond), width: Int(screen.nativeBounds.width), height: Int(screen.nativeBounds.height))
        #endif
        return GameHello(app: "WittyMedia \(platform) \(version)", device: Self.deviceId, name: UIDevice.current.name,
                         audio: GameOpusDecoder.available ? ["opus", "pcm"] : ["pcm"], seats: input.ports,
                         display: display, latency: settings.text("emulation.latency", "auto"))
    }

    // MARK: The TV's refresh rate

    #if os(tvOS)
    private var matchedDisplay = false
    #endif

    /// Where the person lets apps switch the TV to what they show (Settings, Video and Audio, Match
    /// Content), the TV switches to the game's rate: 50 Hz for a PAL game, so no frame is dropped or
    /// shown twice. Once it has, the server is told, and paces the game to it.
    private func matchRefresh(fps: Double?, width: Int, height: Int) {
        #if os(tvOS)
        guard let fps, fps > 0, !matchedDisplay,
              let manager = host.view.window?.avDisplayManager, manager.isDisplayCriteriaMatchingEnabled else { return }
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreate(allocator: nil, codecType: kCMVideoCodecType_H264, width: Int32(max(1, width)),
                                       height: Int32(max(1, height)), extensions: nil, formatDescriptionOut: &format)
        guard let format else { return }
        manager.preferredDisplayCriteria = AVDisplayCriteria(refreshRate: Float(fps), formatDescription: format)
        matchedDisplay = true
        reportRefresh(after: 1, tries: 8)
        #endif
    }

    #if os(tvOS)
    /// Once the switch is done, the screen's rate as it is now.
    private func reportRefresh(after seconds: Double, tries: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, !self.stopped else { return }
            if host.view.window?.avDisplayManager.isDisplayModeSwitchInProgress == true, tries > 0 {
                self.reportRefresh(after: 0.5, tries: tries - 1)
                return
            }
            let hz = Double(host.view.window?.screen.maximumFramesPerSecond ?? 0)
            if hz > 0 { self.transport?.sendEvent(GameHello.reportText(hz: hz)) }
        }
    }
    #endif

    /// The TV goes back to what the rest of the app shows.
    private func unmatchRefresh() {
        #if os(tvOS)
        guard matchedDisplay else { return }
        matchedDisplay = false
        host.view.window?.avDisplayManager.preferredDisplayCriteria = nil
        #endif
    }

    private func finish(saying words: String) {
        unmatchRefresh()
        stopped = true
        transport?.close()
        input.stop()
        pipeline?.sound.stop()
        watchdog?.invalidate()
        if words.isEmpty { leave = true } else { phase = .failed(words) }
    }

    // MARK: The menu

    func openMenu() {
        // The remote's Back closes the menu through the screen, and reaches the controller too: not again at once.
        guard phase == .playing || phase == .connecting, !menuOpen, Date().timeIntervalSince(menuClosedAt) > 0.6 else { return }
        page = .main
        menuOpen = true
        menuOpenedAt = Date()
        input.setEnabled(false)
        pipeline?.sound.flush()
        players = input.players
        Task {
            try? await ordered(.pause(true))
            await refreshSaves()
        }
    }

    func closeMenu() {
        guard menuOpen else { return }
        menuClosedAt = Date()
        menuOpen = false
        page = .main
        input.setEnabled(true)
        framesAt = Date()
        Task { try? await ordered(.pause(false)) }
    }

    func back() {
        // The press that opened the menu can come back as Back as it's let go.
        guard Date().timeIntervalSince(menuOpenedAt) > 0.4 else { return }
        if page == .main { closeMenu() } else { page = .main }
    }

    func refreshSaves() async {
        saves = ((try? await client.gameSaves(gameId)) ?? []).sorted { $0.slot < $1.slot }
    }

    /// Sends an action after every one before it has been answered.
    private func ordered(_ action: GameAction) async throws {
        guard let session else { return }
        let previous = lastAction
        let client = self.client
        let mine = Task { () -> Error? in
            await previous?.value
            do {
                try await client.gameAction(session.id, action)
                return nil
            } catch {
                return error
            }
        }
        lastAction = Task { _ = await mine.value }
        if let error = await mine.value { throw error }
    }

    private func act(_ action: GameAction, done: String) async -> Bool {
        guard session != nil else { return false }
        busy = true
        defer { busy = false }
        do {
            try await ordered(action)
            if !done.isEmpty { say(done) }
            return true
        } catch {
            say((error as? APIError)?.message ?? "That didn't work.")
            return false
        }
    }

    func save(_ slot: Int) {
        Task {
            if await act(.save(slot), done: "Saved to \(GameWords.slotName(slot).lowercased())") {
                await refreshSaves()
                closeMenu()
            }
        }
    }

    func load(_ slot: Int) {
        Task {
            if await act(.load(slot), done: "Loaded \(GameWords.slotName(slot).lowercased())") { closeMenu() }
        }
    }

    func reset() {
        Task { if await act(.reset, done: "The game was reset") { closeMenu() } }
    }

    /// Plugs another kind of controller into a player's port, as the emulator offers.
    func plug(port: Int, device: GameDeviceType) {
        Task {
            if await act(.device(port: port, device: device.id), done: "Player \(port + 1): \(device.name)") { plugged[port] = device.id }
        }
    }

    func changeDisc(_ to: Int) {
        Task { if await act(.disc(to), done: "Disc \(to + 1) is in") { closeMenu() } }
    }

    /// Start or Select for a moment, for a remote that can't reach them.
    func press(_ button: Int) {
        closeMenu()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.input.tap(button) }
    }

    private func shortcut(_ shortcut: PadShortcut, _ down: Bool) {
        guard let session else { return }
        Task {
            switch shortcut {
            case .menu: openMenu()
            case .quickSave: _ = await act(.save(quickSlot), done: "Saved to slot \(quickSlot)")
            case .quickLoad: _ = await act(.load(quickSlot), done: "Loaded slot \(quickSlot)")
            case .fastForward:
                try? await ordered(.speed(down ? min(session.maxSpeed ?? 4, settings.number("emulation.ffSpeed", 4)) : 1))
            case .slow:
                try? await ordered(.speed(down ? settings.number("emulation.slowSpeed", 0.5) : 1))
            case .rewind:
                try? await ordered(.rewind(down))
            case .pause:
                openMenu()
            case .advance:
                try? await ordered(.advance(1))
            case .screenshot:
                break
            }
        }
    }

    func say(_ words: String) {
        notice = words
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { notice = "" }
        }
    }

    /// Saves and stops: the answer comes once everything's written, so the game's page shows it.
    func quit() async {
        guard !stopped else {
            leave = true
            return
        }
        busy = true
        stopped = true
        input.stop()
        transport?.close()
        pipeline?.sound.stop()
        watchdog?.invalidate()
        if let session { try? await client.stopGame(session.id) }
        busy = false
        leave = true
    }

    /// Leaving any other way still saves and stops it, without waiting.
    func abandon() {
        unmatchRefresh()
        guard !stopped else { return }
        stopped = true
        input.stop()
        transport?.close()
        pipeline?.sound.stop()
        watchdog?.invalidate()
        if let session { Task.detached { [client] in try? await client.stopGame(session.id) } }
    }

    /// The app going to the background lets go of everything; the game waits for a minute.
    func scene(_ phase: ScenePhase) {
        guard !stopped, session != nil else { return }
        switch phase {
        case .active:
            if transport == nil || self.phase == .connecting { connect() }
            input.setEnabled(!menuOpen)
        case .background:
            input.setEnabled(false)
            transport?.close()
            transport = nil
        default:
            input.setEnabled(false)
        }
    }

    var bezelColour: Color {
        switch settings.text("display.bezel", "none") {
        case "color": return Color(hex: settings.text("display.bezelColor", "#14161e"))
        default: return .black
        }
    }

    var bezelImage: Int64? {
        guard settings.text("display.bezel", "none") == "image" else { return nil }
        let id = Int64(settings.number("display.bezelImage", 0))
        return id > 0 ? id : nil
    }
}

// MARK: - The screen

/// The game player on any Apple device: the screen to show for a server game, given its item id.
/// Present it full screen (a navigation destination, or a full-screen cover on iPhone and iPad);
/// it leaves by `leave`, or by stepping back from the navigation path when there's none.
struct GamePlayerView: View {
    let gameId: Int64
    var start: GameStart = .resume
    var leave: (() -> Void)?

    init(gameId: Int64, start: GameStart = .resume, leave: (() -> Void)? = nil) {
        self.gameId = gameId
        self.start = start
        self.leave = leave
    }

    var body: some View { GamePlayerScreen(id: gameId, start: start, leave: leave) }
}

struct GamePlayerScreen: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var game = GamePlayerModel()
    let id: Int64
    let start: GameStart
    var leave: (() -> Void)?

    private func goBack() {
        if let leave { leave(); return }
        if case .playGame? = app.path.last { app.path.removeLast() }
    }

    var body: some View {
        ZStack {
            game.bezelColour.ignoresSafeArea()
            if let bezel = game.bezelImage {
                ArtImage(url: client.gameBezelURL(bezel), width: 1920, blank: true).ignoresSafeArea()
            }
            // Only a game being shown takes the remote; before that, Back leaves as it does anywhere.
            GameScreen(host: game.host, playing: !game.menuOpen && (game.phase == .playing || game.phase == .connecting))
                .ignoresSafeArea()
                .accessibilityLabel(game.session?.title ?? "Game")
            #if !os(tvOS)
            // The touch controls, or on a DS or 3DS with a controller, just the stylus.
            if !game.menuOpen, game.phase == .playing || game.phase == .connecting, game.touchShown || game.touchScreenConsole {
                TouchControlsOverlay(game: game, drawn: game.touchShown)
            }
            #endif
            status
            if !game.notice.isEmpty, !game.menuOpen {
                VStack {
                    Text(game.notice)
                        .font(.headline)
                        .foregroundStyle(palette.text)
                        .padding(.horizontal, Tokens.Space.s6)
                        .padding(.vertical, Tokens.Space.s3)
                        .background(Capsule().fill(palette.panel.opacity(0.94)))
                        .accessibilityAddTraits(.updatesFrequently)
                    Spacer()
                }
                .padding(.top, Tokens.edge)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
            #if !os(tvOS)
            // No remote here: the menu has a button of its own, top right as on the website, and
            // the touch controls one to hide them beside it.
            if !game.menuOpen, game.phase == .playing || game.phase == .connecting {
                VStack {
                    HStack(spacing: 16) {
                        Spacer()
                        if game.touchShown {
                            cornerButton("eye.slash", label: "Hide touch controls") { game.touchWanted = false }
                                .opacity(0.75)
                        }
                        cornerButton("line.3.horizontal", label: "Game menu") { game.openMenu() }
                            .opacity(game.padsConnected ? 0.45 : 1)
                    }
                    Spacer()
                }
                .padding(8)
            }
            #endif
            if game.menuOpen {
                GameMenu(game: game, gameId: id)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        #if os(iOS)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        #endif
        .onChange(of: game.leave) { leave in if leave { goBack() } }
        .onChange(of: scenePhase) { game.scene($0) }
        .task {
            // A game stops the music, as a film does.
            app.listening.pauseForVideo()
            await game.begin(id: id, start: start, client: client)
        }
        .onDisappear { game.abandon() }
        #if !os(tvOS)
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { placePicture(geo.size) }
                .onChange(of: geo.size) { placePicture($0) }
                .onChange(of: game.touchShown) { _ in placePicture(geo.size) }
        })
        #endif
    }

    #if !os(tvOS)
    /// Held upright with the controls showing, the picture goes above them.
    private func placePicture(_ size: CGSize) {
        game.placePicture(aboveControls: game.touchShown && TouchOrientation(width: size.width, height: size.height) == .portrait)
    }

    private func cornerButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(red: 20 / 255, green: 22 / 255, blue: 30 / 255).opacity(0.55)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
    #endif

    @ViewBuilder private var status: some View {
        switch game.phase {
        case .loading, .starting:
            Waiting(words: game.session == nil ? "Starting the console, and your save…" : "Starting…")
        case .preparing(let fraction):
            Waiting(words: "Getting the game ready…", fraction: fraction)
        case .connecting:
            Waiting(words: "Connecting…")
        case .playing:
            EmptyView()
        case .failed(let words):
            GameProblem(words: words, back: goBack)
        }
    }
}

private struct Waiting: View {
    @Environment(\.palette) private var palette
    let words: String
    var fraction: Double?

    var body: some View {
        VStack(spacing: Tokens.Space.s4) {
            if let fraction {
                ProgressView(value: fraction).frame(maxWidth: 480)
            } else {
                ProgressView()
            }
            Text(words).font(.headline).foregroundStyle(palette.text)
        }
        .padding(Tokens.Space.s8)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.xl).fill(palette.panel.opacity(0.9)))
        .accessibilityElement(children: .combine)
    }
}

private struct GameProblem: View {
    @Environment(\.palette) private var palette
    let words: String
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s4) {
            Text("This game stopped").font(.wmPage).foregroundStyle(palette.text)
            Text(words).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            Button("Back to the game", action: back).mainAction()
        }
        .padding(Tokens.Space.s10)
        .frame(maxWidth: 900, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.xl).fill(palette.panel))
        .onTVBack(back)
    }
}

private extension View {
    /// The remote's Back on Apple TV. Elsewhere the screen has buttons for it.
    @ViewBuilder func onTVBack(_ action: @escaping () -> Void) -> some View {
        #if os(tvOS)
        onExitCommand(perform: action)
        #else
        self
        #endif
    }

    @ViewBuilder func tvFocusSection() -> some View {
        #if os(tvOS)
        focusSection()
        #else
        self
        #endif
    }

    /// Text the remote can stop on, so it can be read.
    @ViewBuilder func tvFocusable() -> some View {
        #if os(tvOS)
        focusable(true)
        #else
        self
        #endif
    }

    @ViewBuilder func slotButtonStyle() -> some View {
        #if os(tvOS)
        buttonStyle(.card)
        #else
        buttonStyle(.plain)
        #endif
    }
}

/// Words that differ by what the device is held with.
private enum MenuWords {
    #if os(tvOS)
    static let opens = "Start and Select together, or the remote's Back button, open this menu."
    static let noPads = "The Siri Remote"
    static let alone = "The Siri Remote is player 1: its clickpad is the D-pad, a click in the middle is A, and Play/Pause is B. Connect a game controller in Settings, Remotes and Devices for games that need more buttons."
    static let alongside = "The Siri Remote plays as player 1 too."
    #else
    static let opens = "Start and Select together, or the pause button, open this menu."
    static let noPads = "Touch controls"
    static let alone = "The touch controls are player 1. Connect a game controller in Settings, Bluetooth for games that need more buttons."
    static let alongside = "The touch controls hide while a controller is connected."
    #endif
}

// MARK: - The game menu

private struct GameMenu: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @ObservedObject var game: GamePlayerModel
    let gameId: Int64
    @FocusState private var focused: String?

    private var title: String {
        switch game.page {
        case .main: return game.session?.title ?? "Game menu"
        case .save: return "Save state"
        case .load: return "Load state"
        case .reset: return "Reset the game?"
        case .quit: return "Save and quit?"
        case .controllers: return "Controllers"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                    Text(title).font(.wmPage).foregroundStyle(palette.text).lineLimit(2).accessibilityAddTraits(.isHeader)
                    #if !os(tvOS)
                    if game.page != .main {
                        Button { game.back() } label: { Label("Back", systemImage: "chevron.left") }.action(pill: true)
                    }
                    #endif
                    switch game.page {
                    case .main: main
                    case .save: slots(saving: true)
                    case .load: slots(saving: false)
                    case .controllers: controllers
                    case .reset: confirm("Everything since your last save is lost.", yes: "Reset") { game.reset() }
                    case .quit: confirm("The game saves where you are, and you can resume it here or on any other device.", yes: "Save and quit") {
                            Task { await game.quit() }
                        }
                    }
                }
                .padding(Tokens.Space.s10)
            }
            .frame(maxWidth: game.page == .main || game.page == .reset || game.page == .quit ? 640 : 1100)
            .background(palette.background.opacity(0.96))
            Spacer(minLength: 0)
        }
        .ignoresSafeArea()
        .background(Color.black.opacity(0.35).ignoresSafeArea())
        .onTVBack { game.back() }
        .onAppear { DispatchQueue.main.async { focused = "resume" } }
        .onChange(of: game.page) { _ in DispatchQueue.main.async { focused = game.page == .main ? "resume" : "first" } }
    }

    private func row(_ words: String, _ icon: String, key: String, sub: String = "", action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Tokens.Space.s4) {
                Image(systemName: icon).frame(width: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(words)
                    if !sub.isEmpty { Text(sub).font(.caption).foregroundStyle(palette.textSecondary) }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .action(wide: true)
        .focused($focused, equals: key)
        .disabled(game.busy)
    }

    @ViewBuilder private var main: some View {
        row("Resume", "play.fill", key: "resume") { game.closeMenu() }
        row("Save state", "square.and.arrow.down", key: "save", sub: "Choose a slot") { game.page = .save }
        row("Load state", "square.and.arrow.up", key: "load", sub: game.saves.isEmpty ? "No saved states yet" : "Choose a save") { game.page = .load }
        row("Quick save", "bolt", key: "qsave", sub: "Slot \(game.quickSlot)") { game.save(game.quickSlot) }
        if game.saves.contains(where: { $0.slot == game.quickSlot }) {
            row("Quick load", "bolt.horizontal", key: "qload", sub: "Slot \(game.quickSlot)") { game.load(game.quickSlot) }
        }
        row("Press Start", "playpause", key: "start") { game.press(RetroPad.start) }
        row("Press Select", "square.grid.2x2", key: "select") { game.press(RetroPad.select) }
        if game.discs > 1 {
            ForEach(0..<game.discs, id: \.self) { n in
                if n != game.disc { row("Change to disc \(n + 1)", "opticaldisc", key: "disc\(n)", sub: "Disc \(game.disc + 1) is in") { game.changeDisc(n) } }
            }
        }
        #if !os(tvOS)
        row(game.touchWanted ? "Hide touch controls" : "Show touch controls", "hand.tap", key: "touch",
            sub: game.padsConnected ? "They show while no controller is connected" : "") {
            game.touchWanted.toggle()
            game.closeMenu()
        }
        #endif
        row("Controllers", "gamecontroller", key: "pads", sub: game.players.isEmpty ? MenuWords.noPads : "\(game.players.count) connected") { game.page = .controllers }
        row("Reset", "arrow.counterclockwise", key: "reset") { if game.confirms { game.page = .reset } else { game.reset() } }
        row("Save and quit", "xmark", key: "quit") { if game.confirms { game.page = .quit } else { Task { await game.quit() } } }
        Secondary(MenuWords.opens)
            .padding(.top, Tokens.Space.s4)
    }

    /// Who's on which player and what they play by, and what each player has plugged in.
    @ViewBuilder private var controllers: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            if game.players.isEmpty {
                Secondary(MenuWords.alone)
            } else {
                ForEach(game.players, id: \.port) { p in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Player \(p.port + 1): \(p.name)").foregroundStyle(palette.text)
                        Secondary(p.profile.isEmpty ? "The console's own layout" : "Your profile \u{201C}\(p.profile)\u{201D}")
                    }
                }
                Secondary(MenuWords.alongside)
            }
            Secondary("Profiles are made on the website, under Controllers, and follow you here.")
        }
        .tvFocusable()
        .accessibilityElement(children: .combine)
        ForEach(Array(game.devices.enumerated()), id: \.element.port) { n, port in
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                Text("Player \(port.port + 1) has plugged in").font(.wmSection).foregroundStyle(palette.text)
                FlowLayout(spacing: Tokens.Space.s2) {
                    ForEach(port.types ?? [], id: \.id) { type in
                        Button { game.plug(port: port.port, device: type) } label: {
                            ChipLabel(title: type.name, selected: game.plugged[port.port] == type.id)
                        }
                        .buttonStyle(SurfaceStyle(radius: 999))
                        .focused($focused, equals: n == 0 && type.id == port.types?.first?.id ? "first" : "dev\(port.port)-\(type.id)")
                        .disabled(game.busy)
                        .accessibilityAddTraits(game.plugged[port.port] == type.id ? [.isSelected] : [])
                    }
                }
            }
            .padding(.top, Tokens.Space.s2)
            .tvFocusSection()
        }
    }

    private func thumb(_ save: GameSave?) -> some View {
        Group {
            if let save, save.hasThumb == true {
                ArtImage(url: client.gameSaveThumbURL(gameId, slot: save.slot, version: save.updatedAt), width: 300, fit: true)
            } else {
                Rectangle().fill(palette.card)
            }
        }
        .frame(width: 240, height: 160)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous))
    }

    @ViewBuilder private func slots(saving: Bool) -> some View {
        let bySlot = Dictionary(uniqueKeysWithValues: game.saves.map { ($0.slot, $0) })
        let shown: [Int] = saving ? Array(1...max(9, (game.saves.map(\.slot).filter(GameWords.canSave).max() ?? 0) + 1)).filter(GameWords.canSave)
                                  : game.saves.map(\.slot)
        if shown.isEmpty {
            Secondary("No saved states yet. Choose Save state to make one.")
        }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: Tokens.Space.s4)], alignment: .leading, spacing: Tokens.Space.s4) {
            ForEach(Array(shown.enumerated()), id: \.element) { n, slot in
                let save = bySlot[slot]
                Button {
                    if saving { game.save(slot) } else { game.load(slot) }
                } label: {
                    VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                        thumb(save)
                        Text(GameWords.slotName(slot)).font(.wmCard).foregroundStyle(palette.text)
                        Text(save.map { GameWords.ago($0.updatedAt) } ?? "Empty").font(.wmCardSub).foregroundStyle(palette.textSecondary)
                    }
                    .padding(Tokens.Space.s2)
                }
                .slotButtonStyle()
                .focused($focused, equals: n == 0 ? "first" : "slot\(slot)")
                .disabled(game.busy)
                .accessibilityLabel(saving ? "Save to \(GameWords.slotName(slot))\(save == nil ? "" : ", replacing a save")" : "Load \(GameWords.slotName(slot))")
            }
        }
        if saving { Secondary("Saving to a slot that has a save replaces it.") }
    }

    @ViewBuilder private func confirm(_ words: String, yes: String, action: @escaping () -> Void) -> some View {
        Secondary(words)
        Button(yes, action: action).mainAction().focused($focused, equals: "first").disabled(game.busy)
        Button("Cancel") { game.page = .main }.action(pill: true)
    }
}
#endif
