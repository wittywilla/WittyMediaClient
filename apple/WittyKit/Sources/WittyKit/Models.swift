// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// What the server sends, keeping only the fields these apps use. Almost
// everything is optional, because a Go nil list arrives as null and older
// servers lack newer fields. Times are in seconds and may be fractional.

public struct ServerStatus: Decodable, Equatable {
    public let name: String?
    public let version: String?
    public let setupRequired: Bool?
    public let brandName: String?
    /// Set when the owner gave the server a logo of its own: the version to ask for, see `WittyClient.brandLogoURL`.
    public let brandLogo: String?
    public let theme: String?
    public let user: User?
    /// A newer version the server's update check found, for administrators; empty or missing when there's none.
    public let update: String?

    /// Comes from a server that may not have proved anything yet, so it is cleaned before showing.
    public var displayName: String {
        if let brandName, !brandName.isEmpty { return Discovery.cleanName(brandName) }
        return Discovery.cleanName(name ?? "")
    }
}

public struct User: Decodable, Equatable {
    public let id: Int64
    /// The username: unique, and what signing in uses.
    public let name: String
    /// The profile name, which anyone may choose and share. Empty means the username.
    public let displayName: String?
    /// The person asked for their username, not their profile name, in the corner of the screen.
    public let showUsername: Bool?
    public let isAdmin: Bool?
    public let kind: String?
    public let hasPassword: Bool?
    public let twoFactor: Bool?
    /// The picture the profile chose, as "name:colour". Empty or missing means its initial: see ProfilePicture.
    public let avatar: String?

    public init(id: Int64, name: String, displayName: String? = nil, showUsername: Bool? = nil, isAdmin: Bool? = nil,
                kind: String? = nil, hasPassword: Bool? = nil, twoFactor: Bool? = nil, avatar: String? = nil) {
        self.avatar = avatar
        self.id = id
        self.name = name
        self.displayName = displayName
        self.showUsername = showUsername
        self.isAdmin = isAdmin
        self.kind = kind
        self.hasPassword = hasPassword
        self.twoFactor = twoFactor
    }

    /// What a person is called on screen, as on the web: the profile name, or the username.
    public var shownName: String { ProfileNames.shown(name: name, displayName: displayName) }
    /// Whether "@username" goes under the shown name: only when a profile name differs from it.
    public var showsUsername: Bool { ProfileNames.showsUsername(name: name, displayName: displayName) }
    /// What the corner of the screen says, which is each person's choice.
    public var cornerName: String { showUsername == true ? name : shownName }
}

public struct Profile: Decodable, Identifiable, Equatable {
    public let id: Int64
    /// The username, which signing in needs.
    public let name: String
    /// The profile name. Empty or missing means the username.
    public let displayName: String?
    public let kind: String?
    public let hasPassword: Bool?
    /// The picture the profile chose, as "name:colour". Empty or missing means its initial.
    public let avatar: String?

    public init(id: Int64, name: String, displayName: String? = nil, kind: String? = nil, hasPassword: Bool? = nil, avatar: String? = nil) {
        self.avatar = avatar
        self.id = id
        self.name = name
        self.displayName = displayName
        self.kind = kind
        self.hasPassword = hasPassword
    }

    public var shownName: String { ProfileNames.shown(name: name, displayName: displayName) }
    public var showsUsername: Bool { ProfileNames.showsUsername(name: name, displayName: displayName) }
    public var isKids: Bool { kind == "kids" }
    public var isGuest: Bool { kind == "guest" }
}

/// The two names a person has, and which to show. The same rules as the server's web pages.
public enum ProfileNames {
    public static func shown(name: String, displayName: String?) -> String {
        let profile = PlainWords.clean(displayName ?? "", limit: 60)
        return profile.isEmpty ? PlainWords.clean(name, limit: 60) : profile
    }

    /// Even when the two differ only in capitals: "Ziggy" keeps "@ziggy" under it, which is the
    /// sign-in name to type.
    public static func showsUsername(name: String, displayName: String?) -> Bool {
        let profile = PlainWords.clean(displayName ?? "", limit: 60)
        return !profile.isEmpty && profile != name
    }
}

public struct Profiles: Decodable, Equatable {
    public let style: String?
    public let profiles: [Profile]?

    public init(style: String?, profiles: [Profile]?) {
        self.style = style
        self.profiles = profiles
    }
}

public struct LoginResult: Decodable {
    public let token: String
    public let user: User?
}

public struct Library: Decodable, Identifiable, Hashable {
    public let id: Int64
    public let name: String
    public let type: String
    public let console: String?
    public let itemCount: Int?
    /// The server is looking through its folders now.
    public let scanning: Bool?
    /// A commercials library its owner chose to show in the menus and on Home.
    public let showMain: Bool?

    public var isShows: Bool { type == "shows" || type == "anime" }
    /// Commercials stay out of the menus and Home unless switched on, as on the website.
    public var inMainMenus: Bool { type != "commercials" || showMain == true }
    /// The games on someone's own PC: see Rigs.swift.
    public var isRigGames: Bool { type == "games" && console == "rig" }
    /// Lists what these apps can open: video, and games on someone's own PC. Types are a list
    /// that grows, so anything not known here counts as not yet.
    public var opensHere: Bool { ["movies", "shows", "anime", "videos", "discs"].contains(type) || isRigGames }
    /// Sound of some kind, which goes under Music.
    public var isListening: Bool { ["music", "audiobooks", "podcasts", "radio"].contains(type) }
    /// Music, audiobooks and podcasts have these apps' own screens and player, as on Android. Radio is
    /// the server's page.
    public var hasListeningScreens: Bool { ["music", "audiobooks", "podcasts"].contains(type) }
}

public struct CouchStatus: Decodable, Equatable {
    public let allowed: Bool?
}

public struct Progress: Decodable, Equatable {
    public let positionSec: Double?
    public let durationSec: Double?
    public let watched: Bool?
    public let resumeSec: Double?
    /// When the place was last saved, in seconds since 1970: which book was left off most recently.
    public let updatedAt: Int64?
}

public struct Item: Decodable, Identifiable, Equatable {
    public let id: Int64
    public let libraryId: Int64?
    public let kind: String?
    public let title: String
    public let year: Int?
    public let overview: String?
    public let genres: [String]?
    public let contentRating: String?
    public let runtimeSec: Double?
    public let updatedAt: Int64?
    public let progress: Progress?
    public let showId: Int64?
    public let showTitle: String?
    public let season: Int?
    public let episode: Int?
    public let episodeEnd: Int?
    public let nextId: Int64?
    public let introStart: Double?
    public let introEnd: Double?
    public let console: String?
    public let tagline: String?
    public let album: String?
    public let albumArtist: String?
    public let artist: String?
    public let track: Int?
    /// Which disc of a set a track is on, and the CD image it was ripped from, if it was.
    public let discNo: Int?
    public let cdDisc: Int64?
    /// A podcast episode's date, as the server writes it.
    public let aired: String?
    /// The score out of 10 from where its details came from.
    public let rating: Double?
    /// A DVD's or a Blu-ray's own facts, for one that is.
    public let disc: DiscInfo?
    /// How a book is read in the browser (`epub`, `cbz`, `pdf`); missing when it can't be.
    public let reader: String?

    /// Video plays in these apps' own player. Anything else opens the server's page: see ServerPages.swift.
    public var isPlayable: Bool { kind == "video" }
    /// A game on someone's own PC, which plays in the Moonlight app: see Rigs.swift.
    public var isRigGame: Bool { kind == "game" && console == "rig" }

    /// The server decides where Resume goes; nil means start over.
    public var resumeSeconds: Double? {
        guard let at = progress?.resumeSec, at > 0 else { return nil }
        return at
    }

    /// How far through, from 0 to 1, for a bar on the card. Nil if not started or already finished.
    public var progressFraction: Double? {
        guard progress?.watched != true, let at = progress?.positionSec, at > 0,
              let total = progress?.durationSec ?? runtimeSec, total > 0 else { return nil }
        return min(at / total, 1)
    }

    /// "S2 · E15–16", or "" for anything that isn't an episode.
    public var episodeLabel: String {
        guard let season, let episode, episode >= 0 else { return "" }
        var label = "E\(episode)"
        if let episodeEnd, episodeEnd != 0 { label += "–\(episodeEnd)" }
        return season == 0 ? "Special · \(label)" : "S\(season) · \(label)"
    }
}

/// An album, a book or a podcast. The server groups them from their tracks, so they have no ID of
/// their own: they're asked for by name. `coverItem` is a track whose poster is the cover.
public struct Album: Decodable, Equatable, Hashable {
    public let artist: String?
    public let title: String?
    public let year: Int?
    public let genre: String?
    public let tracks: Int?
    public let durationSec: Double?
    public let coverItem: Int64?

    /// One album to a name and an artist, as a list shows each once.
    public var key: String { "\(artist ?? "")|\(title ?? "")" }
}

/// An artist or an author, and how many of their albums or books the library has.
public struct Artist: Decodable, Equatable, Hashable {
    public let name: String?
    public let albums: Int?
    public let tracks: Int?
    public let coverItem: Int64?
}

public struct Show: Decodable, Identifiable, Equatable {
    public let id: Int64
    public let title: String
    public let year: Int?
    public let overview: String?
    public let updatedAt: Int64?
    public let episodeCount: Int?
    public let seasonCount: Int?
    public let unwatched: Int?
}

public struct Season: Decodable, Identifiable, Equatable {
    public let number: Int
    public let title: String?
    public let episodeCount: Int?
    public let unwatched: Int?

    public var id: Int { number }
    public var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return number == 0 ? "Specials" : "Season \(number)"
    }
}

public struct ShowDetail: Decodable, Equatable {
    public let show: Show
    public let seasons: [Season]?
    public let episodes: [Item]?
    public let nextUpId: Int64?
}

public struct Hub: Decodable, Identifiable, Equatable {
    public let key: String
    public let title: String
    public let libraryId: Int64?
    /// For a saved view: what its library's address takes after "?" to show the view whole.
    public let query: String?
    public let items: [Item]?
    public let shows: [Show]?

    public init(key: String, title: String, libraryId: Int64?, query: String? = nil, items: [Item]?, shows: [Show]?) {
        self.key = key
        self.title = title
        self.libraryId = libraryId
        self.query = query
        self.items = items
        self.shows = shows
    }

    public var id: String { key }
    public var isEmpty: Bool { (items ?? []).isEmpty && (shows ?? []).isEmpty }
}

public struct Home: Decodable, Equatable {
    public let hubs: [Hub]?
    public let featured: [Item]?
    public let libraries: [Library]?

    /// The one big picture at the top: the first featured thing this app can play, or failing that
    /// whatever someone is in the middle of.
    public var hero: Item? {
        if let first = (featured ?? []).first(where: \.isPlayable) { return first }
        return (hubs ?? []).lazy.compactMap { $0.items?.first(where: \.isPlayable) }.first
    }
}

public struct ItemPage: Decodable {
    public let items: [Item]?
    public let total: Int?
}

public struct ShowPage: Decodable {
    public let shows: [Show]?
    public let total: Int?
}

public struct SearchResults: Equatable {
    public let items: [Item]
    public let shows: [Show]

    public init(items: [Item], shows: [Show]) {
        self.items = items
        self.shows = shows
    }

    public var isEmpty: Bool { items.isEmpty && shows.isEmpty }
}

public struct Track: Decodable, Identifiable, Equatable {
    public let index: Int
    public let language: String?
    public let languageName: String?
    public let title: String?
    public let codec: String?
    public let channels: Int?
    public let delivery: String?
    public let url: String?
    /// What the file marks the track as: the one to play by default, only the foreign lines (forced), for the deaf
    /// and hard of hearing (sdh), or someone talking over the film (commentary). See docs/CLIENT-API.md, Playback.
    public var isDefault: Bool? = nil
    public var forced: Bool? = nil
    public var sdh: Bool? = nil
    public var commentary: Bool? = nil

    private enum CodingKeys: String, CodingKey {
        case index, language, languageName, title, codec, channels, delivery, url, forced, sdh, commentary
        case isDefault = "default"
    }

    public var id: Int { index }

    /// One line for a list with no room for more: the language, the track's own name and marks, then the format.
    public var label: String {
        (channels ?? 0) > 0 ? TrackWords.audio(self, number: index + 1).line : TrackWords.subtitle(self, number: index + 1).line
    }
}

public struct Intro: Decodable, Equatable {
    public let startSec: Double
    public let endSec: Double
}

public struct Explanation: Decodable, Equatable {
    public let summary: String?
    public let source: String?
    public let picture: String?
    public let sound: String?
    public let subtitles: String?
    public let reasons: [String]?
    /// How hard the server works: none, light or heavy.
    public let load: String?
    public let streaming: String?
}

/// A chapter of a video, where it starts in the film's time.
public struct Chapter: Decodable, Equatable {
    public let start: Double
    public let title: String?
}

/// What POST /items/{id}/playback answers: see docs/CLIENT-API.md. The film's
/// position is always the player's time plus timeOffsetSec.
public struct Playback: Decodable, Equatable {
    public let decision: String?
    public let protocolName: String?
    public let url: String
    public let streamId: String?
    public let durationSec: Double?
    public let seek: String?
    public let startAtSec: Double?
    public let timeOffsetSec: Double?
    public let audio: [Track]?
    public let subtitles: [Track]?
    public let audioIndex: Int?
    public let subtitleIndex: Int?
    public let subtitleDelivery: String?
    public let intro: Intro?
    public let nextId: Int64?
    /// Why it plays this way, in plain words to show as they are.
    public let explain: Explanation?
    /// A 3D picture stored in the frame: sbs or tab. Asking with `flatten3d` shows one eye.
    public let stereo: String?
    /// The film's chapters, for the marks on the seek bar and the Scenes panel.
    public let chapters: [Chapter]?
    /// The quality menu, for a video the server can offer one for: docs/CLIENT-API.md, Quality.
    public var quality: QualityMenu? = nil
    /// The stream as it reaches the player: its size, for stepping down when the server can't keep up.
    public var output: StreamOutput? = nil

    private enum CodingKeys: String, CodingKey {
        case decision, url, streamId, durationSec, seek, startAtSec, timeOffsetSec, audio, subtitles
        case audioIndex, subtitleIndex, subtitleDelivery, intro, nextId, explain, stereo, chapters, quality, output
        case protocolName = "protocol"
    }

    public var offset: Double { timeOffsetSec ?? 0 }
    /// A growing stream has to be reopened to go past what exists so far.
    public var mustReopenToSeekFar: Bool { seek == "restart" }
}

/// The quality menu's easy sizes, from a video's /playback answer: at or below the picture's own, within the
/// profile's limits.
public struct QualityPreset: Decodable, Equatable {
    public let name: String
    public let height: Int
    public let kbps: Int

    /// What a request asks for to get this size: at most this many lines and this rate.
    public var choice: String { "h\(height)-b\(kbps)" }
}

public struct QualityMenu: Decodable, Equatable {
    /// What streams are made to now, in the form of a request's quality: "" or "auto", "original", "h720-b4000".
    public let choice: String?
    public let presets: [QualityPreset]?
    public let sourceHeight: Int?
    public let sourceKbps: Int?

    public struct Row: Equatable, Identifiable {
        public let choice: String
        public let name: String
        public let detail: String
        public let active: Bool
        public var id: String { choice }
    }

    /// The menu's rows: Auto, Original, then each size, with the one in use marked.
    public var rows: [Row] {
        let now = choice ?? ""
        let auto = now.isEmpty || now == "auto"
        var rows = [
            Row(choice: "", name: "Auto", detail: "", active: auto),
            Row(choice: "original", name: "Original", detail: (sourceHeight ?? 0) > 0 ? "\(sourceHeight ?? 0)p" : "", active: now == "original"),
        ]
        for preset in presets ?? [] where !rows.contains(where: { $0.choice == preset.choice }) {
            rows.append(Row(choice: preset.choice, name: preset.name, detail: Self.rate(preset.kbps), active: now == preset.choice))
        }
        return rows
    }

    /// The button's words: what the viewer chose, or Auto.
    public var shortName: String {
        let now = choice ?? ""
        if now.isEmpty || now == "auto" { return "Auto" }
        if now == "original" { return "Original" }
        return presets?.first { $0.choice == now }?.name ?? "Quality"
    }

    public static func rate(_ kbps: Int) -> String {
        guard kbps >= 1000 else { return "\(kbps) kbit/s" }
        return kbps % 1000 == 0 ? "\(kbps / 1000) Mbit/s" : String(format: "%.1f Mbit/s", Double(kbps) / 1000)
    }
}

/// Left out, a field lets the server decide: which tracks, and where to resume.
public struct PlaybackRequest: Encodable {
    public let profile: String
    public var capabilities: DeviceCapabilities?
    public var audio: Int?
    public var subtitle: Int?
    public var startSec: Double?
    /// This device couldn't decode what it was sent: ask for a conversion instead.
    public var forceTranscode: Bool?
    /// This device's streaming choice ("standard", "robust"), and what its connection carries, for robust streams.
    public var streaming: String?
    public var measuredKbps: Double?
    /// The viewer's choice of size and rate ("", "original", "h720-b4000"): docs/CLIENT-API.md, Quality.
    public var quality: String?
    /// The player's speed (2 for 2×), so the stream is made far enough ahead from its start. Nil at 1×.
    public var rate: Double?

    public init(profile: String, capabilities: DeviceCapabilities? = nil, audio: Int? = nil, subtitle: Int? = nil, startSec: Double? = nil,
                forceTranscode: Bool? = nil, streaming: String? = nil, measuredKbps: Double? = nil, quality: String? = nil, rate: Double? = nil) {
        self.quality = quality
        self.rate = rate
        self.profile = profile
        self.capabilities = capabilities
        self.audio = audio
        self.subtitle = subtitle
        self.startSec = startSec
        self.forceTranscode = forceTranscode
        self.streaming = streaming
        self.measuredKbps = measuredKbps
    }
}

public struct Capabilities: Decodable, Equatable {
    public let server: String?
    public let version: String?
    public let apiVersion: Int?
    /// Counts additions within the version. `features` names them.
    public let apiRevision: Int?
    public let apiVersions: [Int]?
    public let setupRequired: Bool?
    public let features: [String]?
    /// The lowest version of each kind of client (`android`, `apple`, `desktop`) this server works
    /// with. An older server doesn't send it, and a platform not listed means fine.
    public let minClientVersions: [String: String]?
    /// How the server sends viewers away from home their video: "standard" or "robust".
    public let remoteStreaming: String?

    private struct PlaybackFacts: Decodable { let remoteStreaming: String? }

    private enum CodingKeys: String, CodingKey {
        case server, version, apiVersion, apiRevision, apiVersions, setupRequired, features, minClientVersions, playback
    }

    /// An optional field that can't be read counts as absent, so it can't stop anyone connecting.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        server = try values.decodeIfPresent(String.self, forKey: .server)
        version = try values.decodeIfPresent(String.self, forKey: .version)
        apiVersion = try? values.decodeIfPresent(Int.self, forKey: .apiVersion)
        apiRevision = try? values.decodeIfPresent(Int.self, forKey: .apiRevision)
        apiVersions = try? values.decodeIfPresent([Int].self, forKey: .apiVersions)
        setupRequired = try? values.decodeIfPresent(Bool.self, forKey: .setupRequired)
        features = try? values.decodeIfPresent([String].self, forKey: .features)
        minClientVersions = try? values.decodeIfPresent([String: String].self, forKey: .minClientVersions)
        remoteStreaming = (try? values.decodeIfPresent(PlaybackFacts.self, forKey: .playback))??.remoteStreaming
    }

    /// Optional abilities go by name, never by comparing server versions.
    public func has(_ feature: String) -> Bool { features?.contains(feature) == true }
}

public struct PairStart: Decodable, Equatable {
    public let code: String
    public let deviceSecret: String
    public let expiresInSec: Int?
    public let intervalSec: Int?
    public let approvePath: String?
    public let approveUrl: String?

    /// The full address for a phone. `approveUrl` carries the code, so it goes first. The page still
    /// asks before doing anything. Whatever the server said, this only ever points back at it.
    public func approveAddress(base: String) -> String? {
        for path in [approveUrl, approvePath, "/pair"] {
            if let path, let url = Origin.join(base: base, path: path) { return url.absoluteString }
        }
        return nil
    }
}

public struct PairPoll: Decodable, Equatable {
    public let status: String
    public let token: String?
    public let intervalSec: Int?
}

/// The stream as it reaches the player: /playback's `output`.
public struct StreamOutput: Decodable, Equatable {
    public var width: Int?
    public var height: Int?
}

/// How a stream's conversion keeps up with its player: GET /hls/{id}/work's `pace` (docs/CLIENT-API.md, Playback speed).
public struct StreamPace: Decodable, Equatable {
    /// Seconds of the film made per second; 0 before it has been measured.
    public var speed: Double
    public var rate: Double
    public var keepingUp: Bool
    /// The server's faster setting is already in use: only a lower quality or speed would help.
    public var fastest: Bool
}

/// Playing faster than the server converts: the next size down, and the words for the viewer (as the
/// website's pace.ts and the Android app's PlaybackRules.kt).
public enum PaceRules {
    /// A change of speed big enough to line the sound and picture up again after (the website's speed.ts).
    public static func realignNeeded(from: Float, to: Float) -> Bool {
        from > 0 && to > 0 && abs(to - from) >= 0.5
    }

    static let steps = [2160, 1440, 1080, 720, 480, 360]

    /// The next size down from what plays now, or 0 when there's none to go to.
    public static func lowerHeight(_ height: Int) -> Int {
        guard height > steps.last! else { return 0 }
        return steps.first { $0 < height - 8 } ?? 0
    }

    public static func times(_ n: Double) -> String {
        let r = (n * 100).rounded() / 100
        return (r == r.rounded() ? String(Int(r)) : String(r)) + "×"
    }

    public static func steppedDown(speed: Double, rate: Double, height: Int) -> String {
        "This server converts this video at \(times(speed)), slower than the \(times(rate)) it plays at, so it goes on at \(height)p."
    }

    public enum Step: Equatable { case lower, slower, tell }

    /// What to do when the conversion falls behind (the website's tooSlow): faster than 1×, a size down once,
    /// to 720p at most; then the fastest speed it keeps up with; and only then words.
    public static func step(speed: Double, rate: Double, height: Int, viewerChose: Bool) -> Step {
        let fast = rate > 1
        if viewerChose || lowerHeight(height) == 0 || (fast && height <= 720) {
            return fast && sustainableRate(speed: speed, rate: rate) < rate ? .slower : .tell
        }
        return .lower
    }

    /// The fastest of the menu's speeds, 1× or more and below the one asked for, the server converts with a tenth to spare.
    public static func sustainableRate(speed: Double, rate: Double) -> Double {
        PlayerSpeeds.all.filter { $0 >= 1 && $0 <= rate && $0 * 1.1 <= speed }.max() ?? 1
    }

    public static func slower(rate: Double, to: Double) -> String {
        "This server can’t keep up at \(times(rate)) for this video, so it plays at \(times(to))."
    }

    public static func tooSlow(speed: Double, rate: Double) -> String {
        "This server converts this video at \(times(speed)), slower than the \(times(rate)) it plays at, so it will stop now and then to catch up. A lower speed or quality plays smoothly."
    }
}
