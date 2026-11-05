import Foundation

// The website's music, audiobook and podcast library pages at phone size, as rules the phone and tablet apps
// share: web/src/pages/AudioLibrary.tsx, music/parts.tsx, music/ArtistPage.tsx, music/CoverFlow.tsx. Music videos
// are MusicVideos.swift.

/// A listening library's front page in one answer: `/music/home`.
public struct MusicHome: Decodable, Equatable {
    public struct Counts: Decodable, Equatable {
        public let albums: Int?
        public let artists: Int?
        public let songs: Int?
        public let liked: Int?
    }
    public let hero: [Album]
    public let albums: [Album]
    public let artists: [Artist]
    public let songs: [Item]
    public let recent: [Item]
    public let `continue`: [Item]
    public let genres: [String]?
    public let counts: Counts?

    private enum CodingKeys: String, CodingKey { case hero, albums, artists, songs, recent, `continue`, genres, counts }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hero = (try? c.decodeIfPresent([Album].self, forKey: .hero)) ?? []
        albums = (try? c.decodeIfPresent([Album].self, forKey: .albums)) ?? []
        artists = (try? c.decodeIfPresent([Artist].self, forKey: .artists)) ?? []
        songs = (try? c.decodeIfPresent([Item].self, forKey: .songs)) ?? []
        recent = (try? c.decodeIfPresent([Item].self, forKey: .recent)) ?? []
        `continue` = (try? c.decodeIfPresent([Item].self, forKey: .continue)) ?? []
        genres = try? c.decodeIfPresent([String].self, forKey: .genres)
        counts = try? c.decodeIfPresent(Counts.self, forKey: .counts)
    }
}

/// An artist's or author's page: `/music/artist`.
public struct ArtistPageInfo: Decodable, Equatable {
    public let name: String
    public let albums: [Album]
    public let tracks: [Item]
    public let top: [Item]
    public let genres: [String]
    public let online: Bool?
    public let bio: String?
    public let bioUrl: String?

    private enum CodingKeys: String, CodingKey { case name, albums, tracks, top, genres, online, bio, bioUrl }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        albums = (try? c.decodeIfPresent([Album].self, forKey: .albums)) ?? []
        tracks = (try? c.decodeIfPresent([Item].self, forKey: .tracks)) ?? []
        top = (try? c.decodeIfPresent([Item].self, forKey: .top)) ?? []
        genres = (try? c.decodeIfPresent([String].self, forKey: .genres)) ?? []
        online = try? c.decodeIfPresent(Bool.self, forKey: .online)
        bio = try? c.decodeIfPresent(String.self, forKey: .bio)
        bioUrl = try? c.decodeIfPresent(String.self, forKey: .bioUrl)
    }

    /// Albums of seven tracks or more, then the singles and EPs under them; a book is a book whatever its length.
    public func discography(newestFirst: Bool, books: Bool) -> (full: [Album], small: [Album]) {
        let sorted = newestFirst ? albums.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
                                 : albums.sorted { ($0.title ?? "").localizedCompare($1.title ?? "") == .orderedAscending }
        return (sorted.filter { books || ($0.tracks ?? 0) >= 7 }, sorted.filter { !books && ($0.tracks ?? 0) < 7 })
    }
}

/// A part of a listening library, as the website's tabs name them.
public enum MusicTab: String, CaseIterable {
    case home, albums, artists, songs, videos, playlists

    /// `musicVideos`: this person can see a music videos library (`MusicVideos.available`), which gives a music
    /// library its Music videos, between Songs and Playlists.
    public static func tabs(libraryType: String, musicVideos: Bool = false) -> [(MusicTab, String)] {
        switch libraryType {
        case "podcasts": return [(.home, "Home"), (.albums, "Podcasts")]
        case "audiobooks": return [(.home, "Home"), (.albums, "Books"), (.artists, "Authors")]
        default:
            let videos: [(MusicTab, String)] = musicVideos && libraryType == "music" ? [(.videos, "Music videos")] : []
            return [(.home, "Home"), (.albums, "Albums"), (.artists, "Artists"), (.songs, "Songs")] + videos + [(.playlists, "Playlists")]
        }
    }
}

public struct MusicSort: Equatable {
    public let key: String
    public let label: String
    /// Whether choosing it starts from the other end: newest, most.
    public let desc: Bool

    /// The sorts the header offers on a tab, or none.
    public static func options(tab: MusicTab, libraryType: String, songView: String) -> [MusicSort] {
        let books = libraryType == "audiobooks", pods = libraryType == "podcasts"
        switch tab {
        case .albums where !pods:
            return [MusicSort(key: "title", label: "Title", desc: false), MusicSort(key: "artist", label: books ? "Author" : "Artist", desc: false),
                    MusicSort(key: "year", label: "Year", desc: true), MusicSort(key: "added", label: "Recently added", desc: true),
                    MusicSort(key: "played", label: "Most played", desc: true)]
        case .artists:
            return [MusicSort(key: "name", label: "Name", desc: false), MusicSort(key: "albums", label: books ? "Most books" : "Most albums", desc: true)]
        case .songs where songView.isEmpty || songView == "liked":
            return [MusicSort(key: "title", label: "Title", desc: false), MusicSort(key: "artist", label: "Artist", desc: false),
                    MusicSort(key: "album", label: "Album", desc: false), MusicSort(key: "year", label: "Year", desc: true),
                    MusicSort(key: "added", label: "Date added", desc: true), MusicSort(key: "runtime", label: "Length", desc: true)]
        default:
            return []
        }
    }

    /// What a tab starts sorted by.
    public static func start(tab: MusicTab, libraryType: String) -> String {
        tab == .artists ? "name" : libraryType == "audiobooks" ? "artist" : "title"
    }

    /// The server answers year, added and played newest first, so a list is turned round when that isn't asked for.
    public static func reversed(sort: String, desc: Bool) -> Bool {
        let newestFirst = ["year", "added", "played"].contains(sort)
        return desc != newestFirst
    }
}

/// Which songs the Songs tab shows.
public enum SongViews {
    public static let all: [(String, String)] = [("", "All songs"), ("liked", "Liked"), ("played", "Most played"), ("recent", "Played lately"), ("added", "Newest")]

    /// The Playlists tab's own lists, made from these.
    public static let built: [(view: String, name: String, about: String)] = [
        ("liked", "Liked songs", "Everything you've pressed the heart on"),
        ("played", "Most played", "Your favourites, by how often you play them"),
        ("recent", "Played lately", "What you've been listening to"),
        ("added", "Newest", "What came to this library most recently"),
    ]

    /// What an empty list says.
    public static func empty(view: String, filtered: Bool) -> (title: String, text: String) {
        if filtered { return ("Nothing matches that", "") }
        switch view {
        case "liked": return ("No liked songs yet", "Press the heart on a song to keep it here.")
        case "played", "recent": return ("Nothing played yet", "")
        default: return ("No songs here", "")
        }
    }
}

public enum MusicWords {
    /// "1 album", "12 books", "3 shows".
    public static func count(_ n: Int, _ noun: (String, String)) -> String { "\(n) \(n == 1 ? noun.0 : noun.1)" }

    public static func nouns(libraryType: String) -> (String, String) {
        libraryType == "audiobooks" ? ("book", "books") : libraryType == "podcasts" ? ("show", "shows") : ("album", "albums")
    }

    /// "1 h 4 min", "45 min": a whole list's length.
    public static func runtime(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        guard minutes >= 60 else { return "\(max(minutes, 0)) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }

    /// The facts under an album's name.
    public static func albumFacts(tracks: [Item], kind: String) -> String {
        let total = tracks.reduce(0) { $0 + ($1.runtimeSec ?? 0) }
        let pods = kind == "podcasts", books = kind == "audiobooks"
        let noun = pods ? "episodes" : books ? "chapters" : tracks.count == 1 ? "track" : "tracks"
        let parts: [String] = ["\(tracks.count) \(noun)", pods ? "" : runtime(total), pods ? "" : tracks.first?.year.map(String.init) ?? "",
                               pods ? "" : tracks.first?.genres?.first ?? ""]
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The same album in other versions ("Deluxe", "Remastered"): its name without those words.
    public static func baseTitle(_ title: String) -> String {
        var s = title.lowercased()
        s = s.replacingOccurrences(of: "[\\(\\[\\{].*?[\\)\\]\\}]", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\b(deluxe|remaster(ed)?|expanded|special|anniversary|edition|version)\\b", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Where a book starts: the first chapter not finished.
    public static func resumeIndex(_ tracks: [Item]) -> Int { max(0, tracks.firstIndex { $0.progress?.watched != true } ?? 0) }
}
