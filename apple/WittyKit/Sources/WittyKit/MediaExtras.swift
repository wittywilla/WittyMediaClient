// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// The server's "media extras" as the apps ask for them (docs/CLIENT-API.md, "Media extras"): where else a title
// can be watched, the routes that make something (a canvas, stems, intro markers) and the task each one starts.
// The canvas and skip rules are in MediaCanvas.swift and MediaSkips.swift; karaoke's stems in KaraokeStems.swift.

/// The server's names for what it can do here. Each thing is offered only when its name is listed.
public enum MediaFeature {
    public static let canvas = "canvas"
    public static let stems = "karaoke-stems"
    public static let markers = "skip-markers"
    public static let whereToWatch = "where-to-watch-xref"
    public static let canvasGenerate = "canvas-generate"
    public static let stemsApproximate = "stems-approximate"
    public static let stemsSeparate = "stems-separate"
    public static let introDetection = "intro-detection"
}

// MARK: - Where to watch

/// What `GET /media/{id}/where-to-watch` answers: this title here, next to the services that offer it.
public struct WhereToWatch: Decodable, Equatable {
    public struct Version: Decodable, Equatable {
        public let itemId: Int64?
        public let label: String?
        public let kind: String?
        /// 4K, 1080p, 720p, SD, DVD, Blu-ray.
        public let quality: String?
        public let container: String?
        public let videoCodec: String?
        public let sizeBytes: Double?
    }
    public struct Local: Decodable, Equatable {
        public let title: String?
        public let quality: String?
        public let versions: [Version]?
    }
    public struct Provider: Decodable, Equatable {
        public let providerId: Int?
        public let name: String
        public let logo: String?
        public let priority: Int?
    }
    public struct Group: Decodable, Equatable {
        /// stream, free, ads, rent or buy.
        public let type: String
        public let providers: [Provider]?
    }
    public let inLibrary: Bool?
    public let local: Local?
    public let region: String?
    public let link: String?
    public let groups: [Group]?
    /// Why there are no providers: no-api-key, not-matched, unavailable.
    public let reason: String?
    public let attribution: String?
}

public enum WhereToWatchLook {
    public struct Row: Equatable, Identifiable {
        public let id: String
        /// "Included with a subscription", "Free", "Free with adverts", "Rent", "Buy".
        public let heading: String
        public let providers: [WhereToWatch.Provider]
    }

    static let order = ["stream", "free", "ads", "rent", "buy"]

    public static func heading(_ type: String) -> String {
        switch type {
        case "stream": return "Included with a subscription"
        case "free": return "Free"
        case "ads": return "Free with adverts"
        case "rent": return "Rent"
        case "buy": return "Buy"
        default: return type.capitalized
        }
    }

    /// The groups in the order the server gives them meaning: what someone already pays for first, then free, then
    /// paid. Empty groups, nameless providers and a provider named twice in a group are left out.
    public static func rows(_ answer: WhereToWatch?) -> [Row] {
        let groups = (answer?.groups ?? []).sorted { (order.firstIndex(of: $0.type) ?? order.count) < (order.firstIndex(of: $1.type) ?? order.count) }
        return groups.compactMap { group in
            var seen = Set<String>()
            let providers = (group.providers ?? [])
                .map { WhereToWatch.Provider(providerId: $0.providerId, name: PlainWords.clean($0.name, limit: 60), logo: $0.logo, priority: $0.priority) }
                .filter { !$0.name.isEmpty && seen.insert($0.name.lowercased()).inserted }
                .sorted { ($0.priority ?? Int.max, $0.name) < ($1.priority ?? Int.max, $1.name) }
            return providers.isEmpty ? nil : Row(id: group.type, heading: heading(group.type), providers: providers)
        }
    }

    /// "In your library · 4K" and each copy on its own line when there's more than one: "Director's cut · 1080p · MKV · 4.2 GB".
    public static func libraryLine(_ answer: WhereToWatch?) -> String {
        guard let answer, answer.inLibrary == true else { return "" }
        let quality = answer.local?.quality ?? ""
        return quality.isEmpty ? "In your library" : "In your library · \(quality)"
    }

    public static func versionLines(_ answer: WhereToWatch?) -> [String] {
        let versions = answer?.local?.versions ?? []
        guard versions.count > 1 else { return [] }
        return versions.map { version in
            let size = (version.sizeBytes ?? 0) > 0 ? ActivityWords.bytes(version.sizeBytes ?? 0) : ""
            let label = (version.label ?? "").isEmpty ? "This copy" : PlainWords.clean(version.label ?? "", limit: 60)
            return [label, version.quality ?? "", (version.container ?? "").uppercased(), size].filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    /// Whether the section is worth showing at all. With no key on the server, or nothing known about the title, a
    /// page says nothing: "in your library" alone is what the page already is.
    public static func shown(_ answer: WhereToWatch?) -> Bool { !rows(answer).isEmpty }

    /// The offers page, only ever TMDB's own over HTTPS: the server checks it, and so does this.
    public static func link(_ answer: WhereToWatch?) -> URL? {
        guard let text = answer?.link, let url = URL(string: text), url.scheme == "https",
              let host = url.host?.lowercased(), host == "www.themoviedb.org" || host == "themoviedb.org" else { return nil }
        return url
    }

    /// A provider's logo, only from TMDB's picture host over HTTPS. Nothing of the sign-in ever goes with it.
    public static func logo(_ provider: WhereToWatch.Provider) -> URL? {
        guard let text = provider.logo, let url = URL(string: text), url.scheme == "https", url.host?.lowercased() == "image.tmdb.org" else { return nil }
        return url
    }

    /// "Offers in the United States" for the heading's second line.
    public static func regionWords(_ answer: WhereToWatch?) -> String {
        guard let region = answer?.region, !region.isEmpty else { return "" }
        let name = Locale(identifier: "en").localizedString(forRegionCode: region) ?? region
        return "Offers in \(name)"
    }
}

// MARK: - Things the server makes

/// What the routes that make something answer: 202 with the task to follow, or 200 when it's already there.
public struct MediaJobStart: Decodable, Equatable {
    public let task: String?
    /// The same thing was already being made: this is its task.
    public let already: Bool?
    /// There's one already (an instrumental), so nothing was started.
    public let exists: Bool?
    /// For intro detection: how many episodes and seasons it will listen to.
    public let episodes: Int?
    public let seasons: Int?
}

/// Where a task the app started has got to, read from `/system/tasks`.
public enum MediaJobState: Equatable {
    /// Queued behind another: one at a time on the whole server.
    case waiting
    case running(percent: Double?, phase: String)
    case done(result: String)
    case failed(words: String)
    case stopped
    /// Not in the lists: finished long ago, or this account can't see tasks. The thing itself says how it went.
    case unknown

    public var finished: Bool {
        switch self {
        case .done, .failed, .stopped: return true
        case .waiting, .running, .unknown: return false
        }
    }

    public static func of(task id: String, in tasks: ActivityTasks?) -> MediaJobState {
        guard !id.isEmpty, let tasks else { return .unknown }
        if let live = tasks.tasks?.first(where: { $0.id == id }) { return state(live) }
        if let past = tasks.recent?.first(where: { $0.id == id }) { return state(past) }
        return .unknown
    }

    static func state(_ task: ActivityTasks.Task) -> MediaJobState {
        switch task.state {
        case "queued": return .waiting
        case "running", "paused":
            let percent = task.percent.flatMap { $0 >= 0 ? $0 : nil }
            return .running(percent: percent, phase: PlainWords.clean(task.phase ?? "", limit: 60))
        case "done": return .done(result: PlainWords.clean(task.result ?? "", limit: 200))
        case "failed":
            let words = [task.error, task.fix].compactMap { $0 }.map { PlainWords.clean($0, limit: 300) }.filter { !$0.isEmpty }.joined(separator: " ")
            return .failed(words: words.isEmpty ? "It didn't work." : words)
        case "cancelled": return .stopped
        default: return .unknown
        }
    }

    /// "Waiting its turn…", "Making it… 40%".
    public func progressWords(_ doing: String) -> String {
        switch self {
        case .waiting: return "\(doing): waiting its turn…"
        case .running(let percent, let phase):
            let detail = [phase, percent.map { "\(Int($0.rounded()))%" } ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
            return detail.isEmpty ? "\(doing)…" : "\(doing)… \(detail)"
        case .unknown: return "\(doing)…"
        case .done, .failed, .stopped: return ""
        }
    }
}

// MARK: - The routes

/// The routes that start something take `{}`: every choice in it is optional.
private struct NoBody: Encodable {}

extension WittyClient {
    /// A read-only token for one item's media addresses, for players that can't send the sign-in.
    public func streamToken(item: Int64) async throws -> StreamToken {
        try await ask("POST", "/items/\(item)/stream-token", NoBody())
    }

    public func canvas(item: Int64) async throws -> CanvasInfo { try await get("/media/\(item)/canvas") }

    /// A canvas's address, ready for a player: the item's stream token is on it.
    public func canvasURL(_ info: CanvasInfo, item: Int64) async throws -> URL? {
        guard let path = info.url, !path.isEmpty else { return nil }
        let token = try await streamToken(item: item).token
        return mediaURL(CanvasRules.address(path: path, token: token))
    }

    /// A media address of an item (a stem, the song's own file) with a stream token on it.
    public func tokenURL(path: String, token: String) -> URL? { mediaURL(CanvasRules.address(path: path, token: token)) }

    public func markers(item: Int64) async throws -> SkipMarkers { try await get("/media/\(item)/markers") }

    public func whereToWatch(item: Int64) async throws -> WhereToWatch { try await get("/media/\(item)/where-to-watch") }

    /// Cut a canvas from a video file (an administrator's). 400 for a song or a disc, 503 with no encoder.
    public func generateCanvas(item: Int64) async throws -> MediaJobStart {
        try await ask("POST", "/media/\(item)/canvas/generate", NoBody())
    }

    /// Forget an uploaded or generated canvas (an administrator's). One beside the media stays.
    public func removeCanvas(item: Int64) async throws { _ = try await call("DELETE", "/media/\(item)/canvas") }

    /// Compare a show's episodes by ear and keep what they share as intro and credits markers (an administrator's).
    /// 409 when a run is under way or there aren't two episodes to compare.
    public func detectIntros(show: Int64) async throws -> MediaJobStart {
        try await ask("POST", "/shows/\(show)/detect-intros", NoBody())
    }
}
