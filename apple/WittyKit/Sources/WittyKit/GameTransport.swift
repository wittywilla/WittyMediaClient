import Foundation

// How a game reaches the player: its picture, sound and events come in, and controller states
// go out. The player knows only this, so another way of streaming (the server's second stream,
// WebRTC with the same messages over a WebSocket behind it) is another transport, not another player.

public protocol GameTransport: AnyObject {
    /// Picture and sound, on the transport's own thread.
    var onMessage: (@Sendable (GameStreamMessage) -> Void)? { get set }
    /// The game's JSON events, on the transport's own thread.
    var onEvent: (@Sendable (GameEvent) -> Void)? { get set }
    /// Once, when it ends other than by `close()`.
    var onEnd: (@Sendable (GameTransportEnd) -> Void)? { get set }

    func open()
    /// A controller state or a pointer message. A newer one always follows, so one may be lost.
    func sendInput(_ data: Data)
    /// A JSON event to the game, such as which players this device holds. Only the second stream has them.
    func sendEvent(_ text: String)
    /// The decoder lost its place: the next frame should be a keyframe.
    func askKeyframe()
    /// For a transport that plays the sound itself, as WebRTC does: the person's volume, 0 to 1.
    func setVolume(_ level: Double, muted: Bool)
    func close()
}

public extension GameTransport {
    func sendEvent(_ text: String) {}
    func setVolume(_ level: Double, muted: Bool) {}
}

public enum GameTransportEnd: Equatable {
    /// The game has gone from the server: stopped from elsewhere, another game started on the
    /// account, or left too long. Connecting again won't find it.
    case gone
    /// The connection dropped. The game waits a minute, paused, for a new one.
    case dropped
    /// This way of connecting didn't get through (no ICE in 5 seconds, or the server refused it):
    /// the next way should be tried.
    case unreachable

    /// From the HTTP status the WebSocket's upgrade answered, or 0 when there was none.
    public init(upgradeStatus: Int) {
        self = [401, 403, 404, 410].contains(upgradeStatus) ? .gone : .dropped
    }
}

public enum GameTransports {
    /// The app's WebRTC transport, where it has one: given the `POST /play/{sid}/stream` request and
    /// the device's hello. WittyKit has no WebRTC stack of its own.
    nonisolated(unsafe) public static var webRTC: ((_ offer: URLRequest, _ hello: GameHello) -> GameTransport?)?

    /// A transport for one of `GameModes.supported`, for a session; nil for a mode this app
    /// can't use or an address that can't be made. The second stream needs the device's hello.
    public static func make(mode: String, session: String, client: WittyClient, hello: GameHello? = nil) -> GameTransport? {
        switch mode {
        case GameModes.streamWebRTC:
            guard let hello, let request = client.gameStreamOfferRequest(session) else { return nil }
            return webRTC?(request, hello)
        case GameModes.streamWebSocket:
            guard let hello, let request = client.gameStreamRequest(session) else { return nil }
            return GameWebSocketTransport(request: request, hello: hello)
        case "ws-h264", "ws-jpeg":
            guard let request = client.gameSocketRequest(session, video: GameModes.video(for: mode)) else { return nil }
            return GameWebSocketTransport(request: request)
        default:
            return nil
        }
    }
}

/// A game over a WebSocket: binary media first-byte tagged, events as text, controller states up
/// the same socket. Without a hello, the first stream (`GET /play/{sid}/ws?video=h264|jpeg`). With
/// one, the second (`GET /play/{sid}/stream`): the hello goes first, frames carry timestamps, and
/// how late they arrive goes back twice a second.
public final class GameWebSocketTransport: NSObject, GameTransport, URLSessionWebSocketDelegate, @unchecked Sendable {
    private let request: URLRequest
    private let hello: GameHello?
    private let queue = DispatchQueue(label: "wittyplay.socket")
    private var delay = ArrivalDelay()
    private var reports: DispatchSourceTimer?
    private let clock = Date()
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private let lock = NSLock()
    private var closed = false
    public var onMessage: (@Sendable (GameStreamMessage) -> Void)?
    public var onEvent: (@Sendable (GameEvent) -> Void)?
    public var onEnd: (@Sendable (GameTransportEnd) -> Void)?

    public init(request: URLRequest, hello: GameHello? = nil) {
        self.request = request
        self.hello = hello
    }

    public var isSecondStream: Bool { hello != nil }

    public func open() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: request)
        // A keyframe of a big game is more than the usual megabyte.
        task.maximumMessageSize = 32 << 20
        self.session = session
        self.task = task
        task.resume()
        if let hello {
            task.send(.string(hello.text())) { _ in }
            startReports()
        }
        receive()
    }

    /// Twice a second, the worst lateness since the last report.
    private func startReports() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
        timer.setEventHandler { [weak self] in
            guard let self, !self.isClosed, let ms = self.delay.report() else { return }
            self.task?.send(.string(ArrivalDelay.reportText(ms))) { _ in }
        }
        reports = timer
        timer.resume()
    }

    private func take(_ data: Data) {
        guard hello != nil else {
            if let message = GameStreamMessage.parse(data) { onMessage?(message) }
            return
        }
        guard let parsed = GameStreamV2.parse(data) else { return }
        let message = parsed.message
        if let timing = parsed.timing {
            let now = Date().timeIntervalSince(clock) * 1000
            queue.async { self.delay.arrived(timestamp: timing.timestamp, now: now) }
        }
        onMessage?(message)
    }

    private var isClosed: Bool {
        lock.lock(); defer { lock.unlock() }
        return closed
    }

    /// True the first time only.
    private func markClosed() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if closed { return false }
        closed = true
        return true
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self, !self.isClosed else { return }
            switch result {
            case .success(.data(let data)):
                self.take(data)
                self.receive()
            case .success(.string(let text)):
                if let event = GameEvent.parse(text) { self.onEvent?(event) }
                self.receive()
            case .success:
                self.receive()
            case .failure:
                self.finish()
            }
        }
    }

    public func sendInput(_ data: Data) {
        guard !isClosed else { return }
        task?.send(.data(data)) { _ in }
    }

    public func sendEvent(_ text: String) {
        guard hello != nil, !isClosed else { return }
        task?.send(.string(text)) { _ in }
    }

    /// The server's 0xF7.
    public func askKeyframe() { sendInput(Data([0xF7])) }

    private func finish() {
        guard markClosed() else { return }
        reports?.cancel()
        onEnd?(GameTransportEnd(upgradeStatus: (task?.response as? HTTPURLResponse)?.statusCode ?? 0))
        session?.invalidateAndCancel()
    }

    public func close() {
        guard markClosed() else { return }
        reports?.cancel()
        task?.cancel(with: .normalClosure, reason: nil)
        session?.finishTasksAndInvalidate()
    }

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                           didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        finish()
    }
}
