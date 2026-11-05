import Foundation

// What arrives on a game's WebSocket (the server's docs/GAMING-API.md, WebSocket): binary
// messages whose first byte says what they are, and JSON events as text. Apple TV has no WebRTC
// of its own, so this is how it plays: H.264 into VideoToolbox, or a JPEG a frame where the server
// has no encoder, and plain PCM sound.

public enum GameStreamMessage: Equatable {
    /// One frame in Annex B, with its parameter sets before each keyframe.
    case video(keyframe: Bool, annexB: Data)
    case jpeg(Data)
    /// Signed 16-bit little-endian stereo, at any rate a console uses, such as 32040.
    case pcm(rate: Int, samples: Data)
    /// An answer on the timing channel, which this app doesn't ask for.
    case timing(Data)
    case unknown(UInt8)

    public static func parse(_ data: Data) -> GameStreamMessage? {
        guard let kind = data.first else { return nil }
        let rest = data.dropFirst()
        switch kind {
        case 1:
            guard let flag = rest.first else { return nil }
            return .video(keyframe: flag == 1, annexB: Data(rest.dropFirst()))
        case 2:
            return .jpeg(Data(rest))
        case 3:
            guard rest.count >= 4 else { return nil }
            let b = [UInt8](rest.prefix(4))
            let rate = Int(b[0]) | Int(b[1]) << 8 | Int(b[2]) << 16 | Int(b[3]) << 24
            let samples = Data(rest.dropFirst(4))
            // Whole stereo frames only: a stray byte would swap left and right from then on.
            return .pcm(rate: rate, samples: samples.prefix(samples.count - samples.count % 4))
        case 0xF2, 0xF4:
            return .timing(Data(rest))
        default:
            return .unknown(kind)
        }
    }
}

/// A message from the game, as JSON text. Types this app doesn't know are ignored.
public enum GameEvent: Equatable {
    case hello(video: String)
    /// Strength from 0 to 1.
    case rumble(port: Int, strength: Double)
    case message(String)
    case geometry(width: Int, height: Int, aspect: Double?)
    case rotation(turns: Int)
    case avinfo(aspect: Double?, fps: Double?, rate: Double?)
    /// The game ended itself: leave the player.
    case shutdown
    /// The game stopped: it crashed, stopped responding, or was stopped from elsewhere.
    case ended(String)
    case disc(index: Int, count: Int)
    /// What the core really draws changed.
    case frame(width: Int, height: Int)
    case unknown(String)

    public static func parse(_ text: String) -> GameEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let type = object["type"] as? String else { return nil }
        func int(_ key: String) -> Int { (object[key] as? NSNumber)?.intValue ?? 0 }
        func double(_ key: String) -> Double? { (object[key] as? NSNumber)?.doubleValue }
        func words(_ key: String) -> String { object[key] as? String ?? "" }
        switch type {
        case "hello": return .hello(video: words("video"))
        case "rumble": return .rumble(port: int("port"), strength: min(1, max(0, (double("strength") ?? 0) / 65535)))
        case "message": return .message(words("text"))
        case "geometry": return .geometry(width: int("width"), height: int("height"), aspect: double("aspect"))
        case "rotation": return .rotation(turns: int("turns"))
        case "avinfo": return .avinfo(aspect: double("aspect"), fps: double("fps"), rate: double("rate"))
        case "shutdown": return .shutdown
        case "ended": return .ended(words("text"))
        case "disc": return .disc(index: int("index"), count: int("count"))
        case "frame": return .frame(width: int("width"), height: int("height"))
        default: return .unknown(type)
        }
    }
}

/// H.264 as it comes, Annex B with start codes, into the length-prefixed form VideoToolbox takes.
public enum AnnexB {
    public static let sps: UInt8 = 7
    public static let pps: UInt8 = 8
    public static let idr: UInt8 = 5
    public static let aud: UInt8 = 9

    /// The NAL units, without their start codes. Three or four byte start codes both count.
    public static func units(_ data: Data) -> [Data] {
        let bytes = [UInt8](data)
        var starts: [(at: Int, code: Int)] = []
        var i = 0
        while i + 2 < bytes.count {
            if bytes[i] == 0, bytes[i + 1] == 0 {
                if bytes[i + 2] == 1 {
                    starts.append((i, 3))
                    i += 3
                    continue
                }
                if i + 3 < bytes.count, bytes[i + 2] == 0, bytes[i + 3] == 1 {
                    starts.append((i, 4))
                    i += 4
                    continue
                }
            }
            i += 1
        }
        var out: [Data] = []
        for (n, start) in starts.enumerated() {
            let from = start.at + start.code
            var to = n + 1 < starts.count ? starts[n + 1].at : bytes.count
            // Trailing zeros belong to the next start code, not to this unit.
            while to > from, bytes[to - 1] == 0, n + 1 < starts.count { to -= 1 }
            if to > from { out.append(Data(bytes[from..<to])) }
        }
        return out
    }

    public static func type(_ unit: Data) -> UInt8 { (unit.first ?? 0) & 0x1f }

    /// Each unit with its length in four big-endian bytes before it.
    public static func lengthPrefixed(_ units: [Data]) -> Data {
        var out = Data(capacity: units.reduce(0) { $0 + $1.count + 4 })
        for unit in units {
            let n = UInt32(unit.count)
            out.append(contentsOf: [UInt8(n >> 24), UInt8((n >> 16) & 0xff), UInt8((n >> 8) & 0xff), UInt8(n & 0xff)])
            out.append(unit)
        }
        return out
    }

    /// A frame split into its parameter sets and the units to decode.
    public struct Frame: Equatable {
        public var sps: Data?
        public var pps: Data?
        public var picture: [Data]
    }

    public static func frame(_ data: Data) -> Frame {
        var frame = Frame(sps: nil, pps: nil, picture: [])
        for unit in units(data) {
            switch type(unit) {
            case sps: frame.sps = unit
            case pps: frame.pps = unit
            case aud: continue
            default: frame.picture.append(unit)
            }
        }
        return frame
    }
}

/// Which of the server's ways of sending a game this app tries, in order. Apple TV has no WebRTC
/// stack of its own, so it's the WebSocket with H.264, then with a JPEG a frame.
public enum GameModes {
    public static let supported = ["ws-h264", "ws-jpeg"]

    /// The server's order, best first, of what this app can use. Ids it doesn't know are ignored.
    public static func order(_ offered: [GameMode]?) -> [String] {
        let ids = (offered ?? []).map(\.id).filter { supported.contains($0) }
        return ids.isEmpty ? supported : ids
    }

    /// `h264` or `jpeg`, for the WebSocket's address.
    public static func video(for mode: String) -> String { mode == "ws-jpeg" ? "jpeg" : "h264" }
}

/// Where the picture goes on the screen, by the person's `display.*` settings.
public struct PictureLayout: Equatable {
    public var width: Double
    public var height: Double
    /// Quarter turns clockwise.
    public var turns: Int

    /// - aspect: the session's, width over height, as the game says.
    /// - frame: what the core really draws, in pixels, for square pixels and whole multiples.
    /// - box: the space there is, in pixels.
    public static func fit(settings: GameSettings, aspect: Double, frame: (width: Double, height: Double), turns sessionTurns: Int,
                           box: (width: Double, height: Double)) -> PictureLayout {
        let rotate = Int(settings.text("display.rotate", "0")) ?? 0
        let turns = ((sessionTurns + rotate / 90) % 4 + 4) % 4
        let cropX = min(0.2, max(0, settings.number("display.cropX", 0) / 100))
        let cropY = min(0.2, max(0, settings.number("display.cropY", 0) / 100))
        var shape: Double
        switch settings.text("display.aspect", "original") {
        case "4:3": shape = 4.0 / 3.0
        case "16:9": shape = 16.0 / 9.0
        case "square": shape = frame.height > 0 ? frame.width / frame.height : aspect
        case "custom": shape = min(3, max(0.5, settings.number("display.aspectCustom", 1.33)))
        case "stretch": shape = 0
        default: shape = aspect
        }
        if shape <= 0 || !shape.isFinite {
            // Fill the screen: whatever shape it has, turned or not.
            return PictureLayout(width: box.width, height: box.height, turns: turns)
        }
        shape *= (1 - 2 * cropX) / (1 - 2 * cropY)
        // Turned a quarter, the picture is as tall as it was wide.
        let shown = turns % 2 == 1 ? 1 / shape : shape
        var h = min(box.height, box.width / shown)
        let sourceHeight = (turns % 2 == 1 ? frame.width : frame.height) * (1 - 2 * (turns % 2 == 1 ? cropX : cropY))
        if settings.flag("display.integer", false), sourceHeight > 0, h >= sourceHeight {
            h = (h / sourceHeight).rounded(.down) * sourceHeight
        }
        return PictureLayout(width: h * shown, height: h, turns: turns)
    }
}

/// How sound keeps up: the most that may wait to be played before some is dropped to catch up.
public enum GameSoundLatency {
    public static func seconds(_ setting: String) -> Double {
        switch setting {
        case "smooth": return 0.16
        case "balanced": return 0.09
        default: return 0.05
        }
    }
}
