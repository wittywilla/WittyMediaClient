import Foundation

// The server's second stream (WittyMediaServer docs/GAMING-STREAM.md): one route,
// `/play/{sid}/stream`, for WebRTC and for the same messages over a WebSocket. This is what both
// share: the hello a device opens with, the binary messages over the WebSocket, and the reports of
// how late frames arrive, without which a slow network fills with seconds of video.

/// What a device says about itself, first thing on a connection.
public struct GameHello: Encodable, Equatable {
    public struct Display: Encodable, Equatable {
        public var hz: Double
        public var width: Int
        public var height: Int

        public init(hz: Double, width: Int, height: Int) {
            self.hz = hz
            self.width = width
            self.height = height
        }
    }

    public var v = 2
    /// The app and its version, for the server's log.
    public var app: String
    /// The id touch layouts are saved under.
    public var device: String
    /// What other players see this device as.
    public var name: String
    public var watch = true
    public var video: [String]
    public var audio: [String]
    /// The players this device holds, 0 to 3.
    public var seats: [Int]
    public var display: Display
    /// `auto`, `fastest`, `balanced` or `steady`.
    public var latency: String
    public var maxKbps = 0

    public init(app: String, device: String, name: String, video: [String] = ["h264"], audio: [String] = ["pcm"], seats: [Int],
                display: Display, latency: String = "auto") {
        self.app = String(app.prefix(64))
        self.device = device
        self.name = String(name.prefix(40))
        self.video = video
        self.audio = audio
        self.seats = seats
        self.display = display
        self.latency = latency
    }

    /// As the WebSocket's first message: the hello with `"type": "hello"`.
    public func text() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(self),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "{}" }
        object["type"] = "hello"
        guard let out = try? JSONSerialization.data(withJSONObject: object, options: .sortedKeys) else { return "{}" }
        return String(decoding: out, as: UTF8.self)
    }

    /// The screen's refresh rate now, after a TV switched to the game's: the server paces the game to it.
    public static func reportText(hz: Double) -> String {
        // To a thousandth, as written by hand: JSON's own writer gives 59.94 as 59.939999999999998.
        var number = String(format: "%.3f", max(0, hz))
        while number.hasSuffix("0") { number.removeLast() }
        if number.hasSuffix(".") { number.removeLast() }
        return #"{"hz":\#(number),"type":"report"}"#
    }

    /// Changing which players this device holds, once connected.
    public static func seatsText(_ ports: [Int], take: Bool = false) -> String {
        let object: [String: Any] = ["type": "seats", "ports": ports.sorted(), "take": take]
        guard let out = try? JSONSerialization.data(withJSONObject: object, options: .sortedKeys) else { return "{}" }
        return String(decoding: out, as: UTF8.self)
    }
}

/// One binary message of the second stream's WebSocket.
public enum GameStreamV2 {
    public struct VideoTiming: Equatable {
        public let frame: UInt32
        /// 90 kHz.
        public let timestamp: UInt32
    }

    /// The message for the player, and for a frame of video, its number and timestamp.
    public static func parse(_ data: Data) -> (message: GameStreamMessage, timing: VideoTiming?)? {
        guard let kind = data.first else { return nil }
        let rest = [UInt8](data.dropFirst())
        func u32(_ at: Int) -> UInt32 {
            UInt32(rest[at]) | UInt32(rest[at + 1]) << 8 | UInt32(rest[at + 2]) << 16 | UInt32(rest[at + 3]) << 24
        }
        switch kind {
        case 0x11:
            guard rest.count >= 9 else { return nil }
            let timing = VideoTiming(frame: u32(1), timestamp: u32(5))
            return (.video(keyframe: rest[0] & 1 == 1, annexB: Data(rest[9...])), timing)
        case 0x12:
            guard rest.count >= 4 else { return nil }
            return (.opus(timestamp: u32(0), packet: Data(rest[4...])), nil)
        default:
            // PCM (0x03), JPEG (0x02) and the timing answers are as in the first stream.
            return GameStreamMessage.parse(data).map { ($0, nil) }
        }
    }
}

/// How much later than the quickest lately frames are arriving, from each frame's timestamp
/// against when it came: the worst of each half second, as `{"type": "report", "delayMs": N}`.
/// TCP's buffers hide a full link from the server; these reports are how it learns to send less.
/// (WittyPlay's `web/arrival.ts` is the browser's version.)
public struct ArrivalDelay {
    /// How far back the quickest is looked for.
    public static let window: Double = 10_000
    private var recent: [(at: Double, lateness: Double)] = []
    private var worst: Double?

    public init() {}

    /// A frame with its 90 kHz timestamp arrived at `now`, in milliseconds of any steady clock.
    public mutating func arrived(timestamp: UInt32, now: Double) {
        let lateness = now - Double(timestamp) / 90
        // A timestamp that went back (a new connection, or the counter wrapping) starts again.
        if let last = recent.last, lateness - last.lateness > 3_600_000 || last.lateness - lateness > 3_600_000 {
            recent.removeAll()
        }
        recent.append((now, lateness))
        while let first = recent.first, now - first.at > Self.window { recent.removeFirst() }
        let quickest = recent.map(\.lateness).min() ?? lateness
        let delay = lateness - quickest
        worst = max(worst ?? 0, delay)
    }

    /// The worst delay since the last report, in whole milliseconds, or nil with no frame since.
    public mutating func report() -> Int? {
        defer { worst = nil }
        return worst.map { Int($0.rounded()) }
    }

    public static func reportText(_ delayMs: Int) -> String { #"{"delayMs":\#(delayMs),"type":"report"}"# }
}

/// A controller's motion, for a game that reads it: 14 bytes, `0xE1`, the player, then the
/// accelerometer and the gyroscope as the controller is held: X right, Y up, Z towards the player.
public enum GameMotion {
    /// - accel: in g, gravity included. Sent in 1/4096 g, up to 8 g either way.
    /// - gyro: in radians a second, anticlockwise positive. Sent in 1/16 degree a second.
    public static func encoded(port: UInt8, accel: (x: Double, y: Double, z: Double), gyro: (x: Double, y: Double, z: Double)) -> Data {
        func i16(_ v: Double) -> Int16 { Int16(max(-32767, min(32767, v.rounded()))) }
        let perDegree = 180 / Double.pi * 16
        let values = [accel.x * 4096, accel.y * 4096, accel.z * 4096, gyro.x * perDegree, gyro.y * perDegree, gyro.z * perDegree].map(i16)
        var out = Data([0xE1, port])
        for v in values {
            let u = UInt16(bitPattern: v)
            out.append(UInt8(u & 0xff))
            out.append(UInt8(u >> 8))
        }
        return out
    }
}
