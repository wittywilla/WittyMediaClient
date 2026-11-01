import Foundation

// The rules of playing something that don't need a player, so they can be tested without
// one. docs/CLIENT-API.md in the server's repository is where they come from.

/// Where the viewer is in the film, and when that needs saving. The player's clock only means
/// something once the stream it is playing is ready: from asking for a new stream until then,
/// the last good position stands.
public struct PlaybackClock: Equatable {
    public static let saveEverySeconds = 10.0
    public static let notBeforeSeconds = 5.0

    public private(set) var filmSeconds = 0.0
    private var lastSaved: Double?
    private var settled = false
    private var everSettled = false

    public init() {}

    /// A new stream was asked for. The old one's clock is no use from here.
    public mutating func switching() { settled = false }

    /// The new stream is ready and has been seeked to where it should start.
    public mutating func ready() {
        settled = true
        everSettled = true
    }

    /// The player's time, about once a second. True means: save now.
    @discardableResult
    public mutating func tick(playerSeconds: Double, offset: Double, playing: Bool) -> Bool {
        guard settled, playerSeconds.isFinite, offset.isFinite else { return false }
        filmSeconds = max(0, playerSeconds + offset)
        guard playing, filmSeconds >= Self.notBeforeSeconds else { return false }
        if let lastSaved, abs(filmSeconds - lastSaved) < Self.saveEverySeconds { return false }
        lastSaved = filmSeconds
        return true
    }

    /// What may be saved right now: nothing before it started, or in the first five seconds.
    public var saveable: Double? {
        everSettled && filmSeconds >= Self.notBeforeSeconds ? filmSeconds : nil
    }

    /// Time to offer the next episode: the last thirty seconds, once a position is known.
    public func nearEnd(duration: Double?) -> Bool {
        guard everSettled, let duration, duration > 0, filmSeconds > 0 else { return false }
        return duration - filmSeconds <= 30
    }
}

/// How often a failing stream is asked for again, so one that fails straight away can't go on
/// for ever and one that plays for a good while starts with a clean slate.
public struct RetryBudget: Equatable {
    public static let attempts = 3
    public static let goodAfterSeconds = 30.0

    private var used = 0
    private var goodSeconds = 0.0

    public init() {}

    /// How long to wait before trying again, or nil to give up.
    public mutating func next() -> Double? {
        guard used < Self.attempts else { return nil }
        used += 1
        goodSeconds = 0
        return used == 1 ? 1 : Double(used) * 2
    }

    public mutating func played(seconds: Double) {
        goodSeconds += seconds
        if goodSeconds >= Self.goodAfterSeconds { used = 0 }
    }

    public mutating func reset() { self = RetryBudget() }
}

/// What a seek has to do. A growing stream can only reach what it has so far.
public enum SeekPlan: Equatable {
    case inPlayer(Double)
    case reopen(atFilm: Double)
}

extension Playback {
    public func seekPlan(toFilm target: Double, seekableEnd: Double?) -> SeekPlan {
        let inPlayer = target - offset
        guard mustReopenToSeekFar else { return .inPlayer(max(0, inPlayer)) }
        if inPlayer >= 0, let seekableEnd, seekableEnd.isFinite, inPlayer <= seekableEnd { return .inPlayer(inPlayer) }
        return .reopen(atFilm: target)
    }
}

/// A track the player found in its stream, in plain values.
public struct TrackOption: Equatable {
    public let language: String?
    public let name: String?

    public init(language: String?, name: String?) {
        self.language = language
        self.name = name
    }
}

/// Which of the player's tracks is the one the server chose. Servers say `eng`; a player may
/// say `en` or `en-US`. If it can't be matched, nothing is picked: the wrong language
/// silently is worse than a viewer choosing again.
public enum TrackMatch {
    private static let twoLetter: [String: String] = [
        "eng": "en", "fre": "fr", "fra": "fr", "ger": "de", "deu": "de", "spa": "es", "ita": "it", "por": "pt", "dut": "nl", "nld": "nl",
        "rus": "ru", "jpn": "ja", "kor": "ko", "chi": "zh", "zho": "zh", "ara": "ar", "hin": "hi", "pol": "pl", "tur": "tr", "swe": "sv",
        "nor": "no", "nob": "no", "nno": "no", "dan": "da", "fin": "fi", "gre": "el", "ell": "el", "heb": "he", "hun": "hu", "cze": "cs",
        "ces": "cs", "rum": "ro", "ron": "ro", "tha": "th", "vie": "vi", "ind": "id", "ukr": "uk", "bul": "bg", "hrv": "hr", "slo": "sk", "slk": "sk",
    ]

    /// "eng", "en" and "en-US" all come out as "en". Empty for unknown.
    public static func base(_ language: String?) -> String {
        let text = (language ?? "").lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? ""
        if text == "und" || text == "unknown" { return "" }
        return twoLetter[text] ?? text
    }

    public static func pick(wanted: Track, among tracks: [Track], options: [TrackOption]) -> Int? {
        let language = base(wanted.language)
        if language.isEmpty {
            // No language to go on. Only the same list in the same order is safe to count along.
            guard options.count == tracks.count, let at = tracks.firstIndex(of: wanted) else { return nil }
            return at
        }
        let matching = options.indices.filter { base(options[$0].language) == language }
        guard !matching.isEmpty else { return nil }
        // Two English tracks: the second English one in the server's list is the second here.
        let peers = tracks.filter { base($0.language) == language }
        let place = peers.firstIndex(of: wanted) ?? 0
        return place < matching.count ? matching[place] : matching[0]
    }
}

/// What this device told the app it can do. Fields are named as the server's
/// playback.Capabilities has them. Left out, a field keeps the profile's value.
public struct DeviceCapabilities: Encodable, Equatable {
    public var videoCodecs: [String]?
    public var hdr: [String]?
    public var tenBit: Bool?
    public var maxHeight: Int?
    public var maxBitrateKbps: Int?
    public var maxAudioChannels: Int?
    public var hlsVideo: [String]?

    public init() {}
}

/// The plain facts the app reads from the system, on any Apple device.
public struct DeviceFacts: Equatable {
    public enum Kind: Equatable { case tv, phone, tablet, computer }

    public var kind: Kind
    public var hevc: Bool
    public var av1: Bool
    public var hdr: [String]
    /// Nil where the system doesn't say, as on a Mac.
    public var audioChannels: Int?
    /// A metered connection, or the person's Low Data setting.
    public var costlyNetwork: Bool

    public init(kind: Kind, hevc: Bool, av1: Bool, hdr: [String], audioChannels: Int?, costlyNetwork: Bool = false) {
        self.kind = kind
        self.hevc = hevc
        self.av1 = av1
        self.hdr = hdr
        self.audioChannels = audioChannels
        self.costlyNetwork = costlyNetwork
    }

    /// Each Apple profile is a safe floor. There's no profile for a phone, so a phone or tablet
    /// names a TV's and replaces every limit with what it found here.
    public var profile: String { hevc ? "appletv" : "appletv-hd" }

    public var capabilities: DeviceCapabilities {
        var out = DeviceCapabilities()
        out.videoCodecs = ["h264"] + (hevc ? ["hevc"] : []) + (av1 ? ["av1"] : [])
        // HLS here is H.264 in TS and HEVC in fMP4: no AV1, whatever the decoder can do.
        out.hlsVideo = ["h264"] + (hevc ? ["hevc"] : [])
        out.hdr = hevc ? hdr : []
        out.tenBit = hevc
        // What limits the picture is the decoder, not the size of the screen: a conversion to fit a
        // phone's screen would cost the server far more than the phone scaling it.
        out.maxHeight = hevc ? 2160 : 1080
        if let audioChannels, audioChannels >= 1 { out.maxAudioChannels = min(audioChannels, 16) }
        // Nothing else stops a phone on a metered connection drawing a whole remux down it.
        if costlyNetwork, kind == .phone || kind == .tablet { out.maxBitrateKbps = 8000 }
        return out
    }
}
