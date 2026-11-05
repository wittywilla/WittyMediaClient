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
    /// The decoder lost its place: the next frame should be a keyframe.
    func askKeyframe()
    func close()
}

public enum GameTransportEnd: Equatable {
    /// The game has gone from the server: stopped from elsewhere, another game started on the
    /// account, or left too long. Connecting again won't find it.
    case gone
    /// The connection dropped. The game waits a minute, paused, for a new one.
    case dropped

    /// From the HTTP status the WebSocket's upgrade answered, or 0 when there was none.
    public init(upgradeStatus: Int) {
        self = [401, 403, 404, 410].contains(upgradeStatus) ? .gone : .dropped
    }
}

public enum GameTransports {
    /// A transport for one of `GameModes.supported`, for a session; nil for a mode this app
    /// can't use or an address that can't be made.
    public static func make(mode: String, session: String, client: WittyClient) -> GameTransport? {
        switch mode {
        case "ws-h264", "ws-jpeg":
            guard let request = client.gameSocketRequest(session, video: GameModes.video(for: mode)) else { return nil }
            return GameWebSocketTransport(request: request)
        default:
            return nil
        }
    }
}

/// The server's first stream: one WebSocket per viewer (`GET /play/{sid}/ws?video=h264|jpeg`),
/// binary media first-byte tagged, events as text, controller states up the same socket.
public final class GameWebSocketTransport: NSObject, GameTransport, URLSessionWebSocketDelegate, @unchecked Sendable {
    private let request: URLRequest
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private let lock = NSLock()
    private var closed = false
    public var onMessage: (@Sendable (GameStreamMessage) -> Void)?
    public var onEvent: (@Sendable (GameEvent) -> Void)?
    public var onEnd: (@Sendable (GameTransportEnd) -> Void)?

    public init(request: URLRequest) {
        self.request = request
    }

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
        receive()
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
                if let message = GameStreamMessage.parse(data) { self.onMessage?(message) }
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

    /// The server's 0xF7.
    public func askKeyframe() { sendInput(Data([0xF7])) }

    private func finish() {
        guard markClosed() else { return }
        onEnd?(GameTransportEnd(upgradeStatus: (task?.response as? HTTPURLResponse)?.statusCode ?? 0))
        session?.invalidateAndCancel()
    }

    public func close() {
        guard markClosed() else { return }
        task?.cancel(with: .normalClosure, reason: nil)
        session?.finishTasksAndInvalidate()
    }

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                           didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        finish()
    }
}
