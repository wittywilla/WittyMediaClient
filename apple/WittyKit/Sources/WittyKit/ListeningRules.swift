import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// The listening player's decisions, apart from its sound and its screens, so they can be tested
// without either. The same rules as Android's player/ListeningRules.kt: docs/CLIENT-API.md leaves
// these to the client.

/// Which track Play means, and where in it.
public struct ListeningStart: Equatable {
    public let index: Int
    public let atSec: Double

    public init(_ index: Int, atSec: Double = 0) {
        self.index = index
        self.atSec = atSec
    }
}

/// What to tell the server when a track stops playing: where it got to for what keeps its place,
/// and how long it was heard for songs.
public enum ListeningReport: Equatable {
    case place(positionSec: Double, durationSec: Double)
    case listened(seconds: Double)
}

/// What to do when a track fails, as for a film: docs/CLIENT-API.md, "What a TV app must build itself".
public enum ListeningRecovery: Equatable {
    /// The token ran out or the stream went away: ask again.
    case newStream
    /// A busy server or a dropped connection: wait a moment, then ask again.
    case waitThenNewStream
    /// This device couldn't decode what it was sent: ask for a conversion.
    case convert
    case giveUp
}

public enum ListeningRules {
    /// Books and podcasts carry on from where they stopped. Songs start over, as the server decides for /playback.
    public static func keepsPlace(libraryType: String) -> Bool {
        libraryType == "audiobooks" || libraryType == "podcasts"
    }

    /// A saved place on a track, or 0. Songs always start over.
    public static func placeOn(_ track: Item, keepsPlace: Bool) -> Double {
        guard keepsPlace, let progress = track.progress, progress.watched != true else { return 0 }
        return max(progress.positionSec ?? 0, 0)
    }

    /// The one last left in the middle, else the first not finished, else the first again.
    public static func whereToStart(_ tracks: [Item], keepsPlace: Bool) -> ListeningStart {
        guard keepsPlace else { return ListeningStart(0) }
        let middle = tracks.indices
            .filter { placeOn(tracks[$0], keepsPlace: true) > 0 }
            .max { (tracks[$0].progress?.updatedAt ?? 0) < (tracks[$1].progress?.updatedAt ?? 0) }
        if let middle { return ListeningStart(middle, atSec: placeOn(tracks[middle], keepsPlace: true)) }
        return ListeningStart(tracks.firstIndex { $0.progress?.watched != true } ?? 0)
    }

    /// Has this been started, so that the button should say Resume and offer Start over?
    public static func hasPlaceToResume(_ tracks: [Item], keepsPlace: Bool) -> Bool {
        keepsPlace
            && tracks.contains { placeOn($0, keepsPlace: true) > 0 || $0.progress?.watched == true }
            && tracks.contains { $0.progress?.watched != true }
    }

    public static let speeds: [Float] = [0.75, 1, 1.25, 1.5, 1.75, 2]

    public static func nextSpeed(after now: Float) -> Float {
        speeds.first { $0 > now + 0.01 } ?? speeds[0]
    }

    /// "1.5×", and no longer than it needs to be.
    public static func speedWords(_ speed: Float) -> String {
        var text = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), Double(speed))
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text + "×"
    }

    /// A song counts as played once it's been heard for this long: the same as the web player.
    public static let countsAsListenedSeconds = 5.0

    /// Moving on by itself means the end was reached, which marks it as finished.
    public static func report(keepsPlace: Bool, positionSec: Double, durationSec: Double, listenedSec: Double, reachedEnd: Bool) -> ListeningReport? {
        guard keepsPlace else { return listenedSec >= countsAsListenedSeconds ? .listened(seconds: listenedSec) : nil }
        guard durationSec > 0 else { return nil }
        if reachedEnd { return .place(positionSec: durationSec, durationSec: durationSec) }
        // A place in the first few seconds isn't worth saving: the rule every client shares.
        return positionSec >= PlaybackClock.notBeforeSeconds ? .place(positionSec: positionSec, durationSec: durationSec) : nil
    }

    /// Previous goes to the start of this one first, as players do, unless it has only just begun.
    public static let previousRestartsAfterSeconds = 3.0

    /// What a failure means, from the error the player or the server gave. The player's own errors
    /// hide what went wrong underneath, so every layer of it is looked at.
    public static func recovery(for error: Error?) -> ListeningRecovery {
        if let error = error as? APIError { return recovery(status: error.status) }
        if error is URLError { return .waitThenNewStream }
        var layer = error.flatMap(nsError)
        while let found = layer {
            if found.domain == NSURLErrorDomain { return .waitThenNewStream }
            if found.domain == "AVFoundationErrorDomain", undecodable.contains(found.code) { return .convert }
            layer = found.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        // Anything else is most often a token that ran out or a stream that went away.
        return .newStream
    }

    private static func nsError(_ error: Error) -> NSError? {
        #if canImport(Darwin)
        return error as NSError
        #else
        return error as Any as? NSError
        #endif
    }

    /// The server's answer to asking for a stream.
    public static func recovery(status: Int) -> ListeningRecovery {
        switch status {
        case 401, 404: return .newStream
        case 429, 503: return .waitThenNewStream
        case 0: return .waitThenNewStream
        default: return .giveUp
        }
    }

    /// AVFoundation's codes for a file it can't read or decode.
    private static let undecodable: Set<Int> = [-11821, -11822, -11828, -11829, -11833, -11853, -11855]

    /// In plain words. The details go in the log, not on the screen.
    public static func failureWords(_ recovery: ListeningRecovery, status: Int?) -> String {
        if let status, status != 0 {
            if status == 403 { return "This profile isn't allowed to play this." }
            if status == 503 { return "The server is busy. Try again in a moment." }
            if status >= 500 { return "The server had a problem playing this." }
            return "The server wouldn't play this."
        }
        switch recovery {
        case .waitThenNewStream: return "Lost contact with your server. Check that it is running, then try again."
        case .convert: return "This device can't play this, even after the server converted it."
        case .newStream, .giveUp: return "This can't be played."
        }
    }

    // MARK: Words

    /// The words for a library's own parts.
    public static func albumsWord(libraryType: String) -> String {
        switch libraryType {
        case "audiobooks": return "Books"
        case "podcasts": return "Podcasts"
        default: return "Albums"
        }
    }

    public static func artistsWord(libraryType: String) -> String {
        libraryType == "audiobooks" ? "Authors" : "Artists"
    }

    /// "1 song", "12 parts", "3 episodes".
    public static func tracksWords(libraryType: String, count: Int) -> String {
        let word: String
        switch libraryType {
        case "audiobooks": word = "part"
        case "podcasts": word = "episode"
        default: word = "song"
        }
        return count == 1 ? "1 \(word)" : "\(count) \(word)s"
    }

    /// "48 min", "3 h 5 min".
    public static func lengthWords(_ seconds: Double) -> String {
        let minutes = Int((seconds + 30) / 60)
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }

    /// "3:07", "1:02:03".
    public static func clock(_ seconds: Double) -> String {
        let total = seconds.isFinite ? max(Int(seconds), 0) : 0
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// The same clock for a screen reader: "1 hour 2 minutes 3 seconds".
    public static func spokenClock(_ seconds: Double) -> String {
        let total = seconds.isFinite ? max(Int(seconds), 0) : 0
        var parts: [String] = []
        func add(_ n: Int, _ word: String) { if n > 0 { parts.append("\(n) \(word)\(n == 1 ? "" : "s")") } }
        add(total / 3600, "hour")
        add((total % 3600) / 60, "minute")
        add(total % 60, "second")
        return parts.isEmpty ? "0 seconds" : parts.joined(separator: " ")
    }
}

/// Off, the whole queue again, or this one again.
public enum RepeatMode: Equatable {
    case off, all, one

    /// What the button goes to next.
    public var next: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }
}

/// The queue: what's in it in the order it was added, which one is playing, and the order it plays
/// in, which shuffling changes. Positions here are always places in `entries`.
public struct ListeningQueue<Entry> {
    public private(set) var entries: [Entry] = []
    /// The one playing.
    public private(set) var current = 0
    public private(set) var shuffled = false
    public var repeatMode: RepeatMode = .off
    private var shuffleOrder: [Int] = []

    public init() {}

    public init(_ entries: [Entry], start: Int) {
        self.entries = entries
        current = entries.isEmpty ? 0 : min(max(start, 0), entries.count - 1)
    }

    public var isEmpty: Bool { entries.isEmpty }
    public var now: Entry? { entries.indices.contains(current) ? entries[current] : nil }

    /// Positions in `entries`, in the order they'll play.
    public var order: [Int] { shuffled ? shuffleOrder : Array(entries.indices) }

    private var place: Int { order.firstIndex(of: current) ?? 0 }

    /// What Next goes to, or nil at the end. Repeating one doesn't stop a person moving on.
    public var next: Int? {
        let order = order
        let at = place
        if at + 1 < order.count { return order[at + 1] }
        return repeatMode == .all && !order.isEmpty ? order[0] : nil
    }

    public var previous: Int? {
        let order = order
        let at = place
        if at > 0 { return order[at - 1] }
        return repeatMode == .all && !order.isEmpty ? order[order.count - 1] : nil
    }

    /// What plays by itself once this one ends.
    public var afterEnd: Int? { repeatMode == .one && !entries.isEmpty ? current : next }

    /// The first in the order: where a finished queue starts again.
    public var first: Int? { order.first }

    public mutating func jump(to index: Int) {
        if entries.indices.contains(index) { current = index }
    }

    /// The one playing stays where it is and comes first; everything else is in a new order.
    public mutating func setShuffled<G: RandomNumberGenerator>(_ on: Bool, using generator: inout G) {
        shuffled = on
        guard on else { shuffleOrder = []; return }
        var rest = entries.indices.filter { $0 != current }
        rest.shuffle(using: &generator)
        shuffleOrder = entries.isEmpty ? [] : [current] + rest
    }

    public mutating func setShuffled(_ on: Bool) {
        var generator = SystemRandomNumberGenerator()
        setShuffled(on, using: &generator)
    }

    /// At the end, of the shuffled order too.
    public mutating func append(_ more: [Entry]) {
        let from = entries.count
        entries += more
        if shuffled { shuffleOrder += Array(from..<entries.count) }
    }

    /// Straight after the one playing, in whichever order is in use.
    public mutating func insertNext(_ more: [Entry]) {
        guard !entries.isEmpty else { append(more); return }
        let at = current + 1
        entries.insert(contentsOf: more, at: at)
        guard shuffled else { return }
        let added = Array(at..<(at + more.count))
        shuffleOrder = shuffleOrder.map { $0 >= at ? $0 + more.count : $0 }
        shuffleOrder.insert(contentsOf: added, at: (shuffleOrder.firstIndex(of: current) ?? -1) + 1)
    }

    /// Takes one out. True when it was the one playing, which the next in the order then replaces,
    /// or the one before it at the end.
    @discardableResult
    public mutating func remove(at index: Int) -> Bool {
        guard entries.indices.contains(index) else { return false }
        let wasCurrent = index == current
        if wasCurrent {
            let order = order
            let at = place
            let replacement = at + 1 < order.count ? order[at + 1] : (at > 0 ? order[at - 1] : nil)
            current = replacement ?? 0
        }
        entries.remove(at: index)
        shuffleOrder = shuffleOrder.filter { $0 != index }.map { $0 > index ? $0 - 1 : $0 }
        if current > index { current -= 1 }
        if entries.isEmpty { current = 0 }
        return wasCurrent
    }

    /// Moves one to another place in the list. The one playing carries on.
    public mutating func move(from: Int, to: Int) {
        guard entries.indices.contains(from), entries.indices.contains(to), from != to else { return }
        var positions = Array(entries.indices)
        positions.insert(positions.remove(at: from), at: to)
        let newPlace = Dictionary(uniqueKeysWithValues: positions.enumerated().map { ($0.element, $0.offset) })
        entries = positions.map { entries[$0] }
        current = newPlace[current] ?? current
        shuffleOrder = shuffleOrder.map { newPlace[$0] ?? $0 }
    }

    /// Changes the entries without moving anything: a track's details filled in later.
    public mutating func update(at index: Int, _ change: (inout Entry) -> Void) {
        if entries.indices.contains(index) { change(&entries[index]) }
    }
}
