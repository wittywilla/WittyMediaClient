// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// Where a video's skippable parts are, and what the player does about them: the website's markers.ts, plus what the
// apps add (skipping by itself, and a way back). The server works the parts out from what an administrator set, a
// `.skip.json` or `.edl` beside the file, chapter names, what comparing a season's episodes found, and the show's own
// intro: docs/PLAYING.md, "Skip intro", and docs/CLIENT-API.md, "Media extras".

/// One stretch of a video, in the film's own time.
public struct SkipRange: Decodable, Equatable {
    public let startSec: Double
    public let endSec: Double

    public init(startSec: Double, endSec: Double) {
        self.startSec = startSec
        self.endSec = endSec
    }

    /// A range that ends before it starts is nothing to skip.
    var sound: Bool { startSec.isFinite && endSec.isFinite && endSec > startSec && startSec >= 0 }
}

/// What `GET /media/{id}/markers` answers. Everything is optional: a part the video hasn't got is null.
public struct SkipMarkers: Decodable, Equatable {
    public let intro: SkipRange?
    public let recap: SkipRange?
    public let credits: SkipRange?
    public let commercials: [SkipRange]?
    /// Where the most trusted part came from: manual, skip.json, edl, chapters, detected, show or none.
    public let source: String?
    /// The same for each part: "intro": "detected".
    public let sources: [String: String]?

    public init(intro: SkipRange? = nil, recap: SkipRange? = nil, credits: SkipRange? = nil, commercials: [SkipRange]? = nil,
                source: String? = nil, sources: [String: String]? = nil) {
        self.intro = intro
        self.recap = recap
        self.credits = credits
        self.commercials = commercials
        self.source = source
        self.sources = sources
    }

    /// An older server, or one that hasn't answered yet: the intro the playback answer carries, alone.
    public init(intro: Intro?) {
        self.init(intro: intro.map { SkipRange(startSec: $0.startSec, endSec: $0.endSec) })
    }

    public var isEmpty: Bool { intro == nil && recap == nil && credits == nil && (commercials ?? []).isEmpty }
}

public enum SkipKind: String, CaseIterable, Codable {
    case recap, intro, commercial, credits

    /// The button's words, as the website's.
    public var button: String {
        switch self {
        case .recap: return "Skip recap"
        case .intro: return "Skip intro"
        case .commercial: return "Skip adverts"
        case .credits: return "Skip credits"
        }
    }

    /// What was skipped, for the notice with Undo.
    public var skipped: String {
        switch self {
        case .recap: return "Skipped the recap"
        case .intro: return "Skipped the intro"
        case .commercial: return "Skipped the adverts"
        case .credits: return "Skipped the credits"
        }
    }

    /// The setting's name.
    public var settingName: String {
        switch self {
        case .recap: return "Recaps"
        case .intro: return "Intros"
        case .commercial: return "Adverts"
        case .credits: return "Credits"
        }
    }

    /// Where the part came from, for an administrator: "found by comparing episodes".
    public static func sourceWords(_ source: String?) -> String {
        switch source {
        case "manual": return "set by hand"
        case "skip.json": return "from a .skip.json beside the file"
        case "edl": return "from an .edl beside the file"
        case "chapters": return "from the file's chapters"
        case "detected": return "found by comparing episodes"
        case "show": return "the show's own intro"
        default: return ""
        }
    }
}

/// What the player offers right now: a part to jump past, or the next episode while the last credits roll.
public struct SkipOffer: Equatable {
    public let kind: SkipKind
    /// The film's time to jump to. Not used when `next` is true.
    public let to: Double
    /// The credits run to the very end and something follows: the button goes to the next episode instead.
    public let next: Bool
    /// The same for the same part of the same video, however often it's offered.
    public let id: String

    public var label: String { next ? "Next episode" : kind.button }

    public init(kind: SkipKind, from: Double, to: Double, next: Bool = false) {
        self.kind = kind
        self.to = to
        self.next = next
        self.id = "\(kind.rawValue)@\(Int((from * 10).rounded()))"
    }
}

public enum SkipRules {
    /// A part isn't worth a button in its last second.
    static let tail = 1.0
    /// Credits ending this close to the end are "to the end": nothing follows them worth jumping to.
    static let endSlack = 5.0
    /// In the last half minute the player's own "next episode" takes over.
    static let nextTakesOver = 30.0

    /// The part playing at `now`, if skipping it is worth a button (the website's skipAt): more than a second of it
    /// is left, and for credits there is something after them. Credits that run to the end are what "next episode" is
    /// for, so that's what they offer when there is one, until the player's own countdown takes over.
    public static func offer(_ markers: SkipMarkers?, at now: Double, duration: Double, hasNext: Bool) -> SkipOffer? {
        guard let markers, now.isFinite else { return nil }
        func inside(_ range: SkipRange?) -> Bool {
            guard let range, range.sound else { return false }
            return now >= range.startSec && now < range.endSec - tail
        }
        if let recap = markers.recap, inside(recap) { return SkipOffer(kind: .recap, from: recap.startSec, to: recap.endSec) }
        if let intro = markers.intro, inside(intro) { return SkipOffer(kind: .intro, from: intro.startSec, to: intro.endSec) }
        for advert in markers.commercials ?? [] where inside(advert) {
            return SkipOffer(kind: .commercial, from: advert.startSec, to: advert.endSec)
        }
        if let credits = markers.credits, inside(credits), duration > 0 {
            if credits.endSec < duration - endSlack { return SkipOffer(kind: .credits, from: credits.startSec, to: credits.endSec) }
            if hasNext, now < duration - nextTakesOver {
                return SkipOffer(kind: .credits, from: credits.startSec, to: credits.endSec, next: true)
            }
        }
        return nil
    }

    /// The parts as an administrator reads them: "Intro 0:05 to 0:20, found by comparing episodes".
    public static func summary(_ markers: SkipMarkers?) -> [String] {
        guard let markers else { return [] }
        var lines: [String] = []
        func add(_ name: String, _ key: String, _ range: SkipRange?) {
            guard let range, range.sound else { return }
            let from = SkipKind.sourceWords(markers.sources?[key])
            lines.append("\(name) \(PlayerTime.format(range.startSec)) to \(PlayerTime.format(range.endSec))" + (from.isEmpty ? "" : ", \(from)"))
        }
        add("Recap", "recap", markers.recap)
        add("Intro", "intro", markers.intro)
        for advert in markers.commercials ?? [] { add("Adverts", "commercials", advert) }
        add("Credits", "credits", markers.credits)
        return lines
    }
}

/// Which parts this device skips by itself. Kept on the device, like the player's other choices; off until chosen.
public struct SkipPrefs: Codable, Equatable {
    public var intro = false
    public var recap = false
    public var credits = false
    public var adverts = false

    public init(intro: Bool = false, recap: Bool = false, credits: Bool = false, adverts: Bool = false) {
        self.intro = intro
        self.recap = recap
        self.credits = credits
        self.adverts = adverts
    }

    private enum CodingKeys: String, CodingKey { case intro, recap, credits, adverts }

    // A saved set from another version keeps what it can.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        intro = (try? c.decodeIfPresent(Bool.self, forKey: .intro)) ?? false
        recap = (try? c.decodeIfPresent(Bool.self, forKey: .recap)) ?? false
        credits = (try? c.decodeIfPresent(Bool.self, forKey: .credits)) ?? false
        adverts = (try? c.decodeIfPresent(Bool.self, forKey: .adverts)) ?? false
    }

    public func skips(_ kind: SkipKind) -> Bool {
        switch kind {
        case .intro: return intro
        case .recap: return recap
        case .credits: return credits
        case .commercial: return adverts
        }
    }

    public mutating func set(_ kind: SkipKind, _ on: Bool) {
        switch kind {
        case .intro: intro = on
        case .recap: recap = on
        case .credits: credits = on
        case .commercial: adverts = on
        }
    }

    public var any: Bool { intro || recap || credits || adverts }

    static let key = "wms.skip.auto"

    public static func load(_ defaults: UserDefaults = .standard) -> SkipPrefs {
        guard let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(SkipPrefs.self, from: data) else { return SkipPrefs() }
        return saved
    }

    public static func save(_ prefs: SkipPrefs, _ defaults: UserDefaults = .standard) {
        if prefs == SkipPrefs() {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(prefs) {
            defaults.set(data, forKey: key)
        }
    }
}

/// A part was skipped without anyone asking: said for a few seconds, with a way back.
public struct SkipNotice: Equatable {
    public let kind: SkipKind
    /// Where the film was when it jumped: Undo goes back there.
    public let from: Double
    public var words: String { kind.skipped }
}

/// Skipping by itself, for one video from when it opens until it's left. The rules:
///
/// - A part is skipped only when the film plays into it (or opens in it), never when someone seeks into it: a
///   person who went back to the intro wants to see it.
/// - Each part is skipped once. After Undo, or after any seek into it, it's left alone for good.
/// - Nothing is skipped while paused, and "next episode" is never pressed for anyone.
///
/// The player tells it the film's time about once a second, and whenever it seeks. A jump in time it wasn't told
/// about (another app's remote, a watch party) counts as a seek too.
public struct SkipTracker {
    /// How far the film may move between two looks and still count as playing on: generous at 1×, wider when fast.
    static func stride(rate: Double) -> Double { max(2.5, 2.5 * rate) }
    /// How long the notice stays.
    public static let noticeSeconds = 6.0

    private var last: Double?
    private var settled: Set<String> = []
    private var jumped = false
    /// Where this tracker's own jump is going, and how many more looks it may take to get there: the player
    /// reports the old place for a moment after a seek, which mustn't be read as someone seeking back.
    private var landing: (at: Double, patience: Int)?
    public private(set) var notice: SkipNotice?

    public init() {}

    /// A seek is on its way: whatever the next time is, the film didn't play its way there.
    public mutating func seeked() {
        jumped = true
        landing = nil
    }

    /// A part was skipped with its button: it isn't skipped again by itself, and there's nothing to undo.
    public mutating func pressed(_ offer: SkipOffer) {
        settled.insert(offer.id)
        notice = nil
    }

    /// The notice has been shown for long enough, or was closed.
    public mutating func clearNotice() { notice = nil }

    /// Back to where the film was. The part is already settled, so it plays this time.
    public mutating func undo() -> Double? {
        guard let from = notice?.from else { return nil }
        notice = nil
        jumped = true
        landing = nil
        return from
    }

    /// The film's time now, and what's on offer there. Answers where to jump to, when this part is to be skipped.
    public mutating func tick(now: Double, rate: Double, playing: Bool, offer: SkipOffer?, prefs: SkipPrefs) -> Double? {
        guard now.isFinite else { return nil }
        let playedHere: Bool
        if jumped {
            playedHere = false
        } else if let coming = landing {
            if abs(now - coming.at) <= Self.stride(rate: rate) {
                // Arrived where the skip went: a part that starts right there was played into.
                landing = nil
                playedHere = true
            } else if coming.patience > 0 {
                landing = (coming.at, coming.patience - 1)
                return nil
            } else {
                landing = nil
                playedHere = false
            }
        } else if let last {
            let moved = now - last
            playedHere = moved >= -0.5 && moved <= Self.stride(rate: rate)
        } else {
            playedHere = true
        }
        jumped = false
        last = now
        guard let offer, !offer.next else { return nil }
        if !playedHere {
            settled.insert(offer.id)
            return nil
        }
        guard playing, prefs.skips(offer.kind), !settled.contains(offer.id) else { return nil }
        settled.insert(offer.id)
        notice = SkipNotice(kind: offer.kind, from: now)
        // The jump is this tracker's own: arriving there isn't a person's seek into something else.
        landing = (offer.to, 5)
        return offer.to
    }
}
