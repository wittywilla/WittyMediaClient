import Foundation

// What the server sends, keeping only the fields these apps use. Almost
// everything is optional, because a Go nil list arrives as null and older
// servers lack newer fields. Times are in seconds and may be fractional.

public struct ServerStatus: Decodable, Equatable {
    public let name: String?
    public let version: String?
    public let setupRequired: Bool?
    public let brandName: String?
    public let theme: String?
    public let user: User?

    /// Comes from a server that may not have proved anything yet, so it is cleaned before showing.
    public var displayName: String {
        if let brandName, !brandName.isEmpty { return Discovery.cleanName(brandName) }
        return Discovery.cleanName(name ?? "")
    }
}

public struct User: Decodable, Equatable {
    public let id: Int64
    public let name: String
    public let isAdmin: Bool?
    public let kind: String?
}

public struct Profile: Decodable, Identifiable, Equatable {
    public let id: Int64
    public let name: String
    public let kind: String?
    public let hasPassword: Bool?
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

    public var isShows: Bool { type == "shows" || type == "anime" }
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
    public let items: [Item]?
    public let shows: [Show]?

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

    public var id: Int { index }

    public var label: String {
        var parts: [String] = []
        let code = language ?? ""
        let name = languageName ?? ""
        parts.append(!name.isEmpty ? name : code.isEmpty ? "Unknown" : (Locale.current.localizedString(forLanguageCode: code) ?? code))
        if let title, !title.isEmpty { parts.append(title) }
        if let codec, !codec.isEmpty { parts.append(codec.uppercased()) }
        if let channels, channels > 0 { parts.append("\(channels)ch") }
        return parts.joined(separator: " · ")
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

    private enum CodingKeys: String, CodingKey {
        case decision, url, streamId, durationSec, seek, startAtSec, timeOffsetSec, audio, subtitles
        case audioIndex, subtitleIndex, subtitleDelivery, intro, nextId, explain, stereo
        case protocolName = "protocol"
    }

    public var offset: Double { timeOffsetSec ?? 0 }
    /// A growing stream has to be reopened to go past what exists so far.
    public var mustReopenToSeekFar: Bool { seek == "restart" }
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

    public init(profile: String, capabilities: DeviceCapabilities? = nil, audio: Int? = nil, subtitle: Int? = nil, startSec: Double? = nil,
                forceTranscode: Bool? = nil) {
        self.profile = profile
        self.capabilities = capabilities
        self.audio = audio
        self.subtitle = subtitle
        self.startSec = startSec
        self.forceTranscode = forceTranscode
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

    private enum CodingKeys: String, CodingKey {
        case server, version, apiVersion, apiRevision, apiVersions, setupRequired, features, minClientVersions
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
