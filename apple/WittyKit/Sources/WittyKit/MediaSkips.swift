// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// Where a video's skippable parts are, and what the player does about them: the website's markers.ts, plus what the
// apps add (skipping by itself, and a way back). The server works the parts out from what an administrator set, a
// `.skip.json` or `.edl` beside the file, chapter names, what comparing a season's episodes found, and the show's own
// intro: docs/PLAYING.md, "Skip intro", and docs/CLIENT-API.md, "Media extras". From WittyMediaServer 0.8.1 a
// `.wittyinfo` beside the video adds previews, a scene after the credits and parts someone named, each with an action
// (a button, skipped by itself, or only marked), and every part comes in one list, `segments`.

/// One stretch of a video, in the film's own time. `label` names a part someone named; `action` is "button", "auto"
/// (skipped by itself where the profile follows the file) or "mark" (only marked: never a button).
public struct SkipRange: Decodable, Equatable {
    public let startSec: Double
    public let endSec: Double
    public let label: String?
    public let action: String?

    public init(startSec: Double, endSec: Double, label: String? = nil, action: String? = nil) {
        self.startSec = startSec
        self.endSec = endSec
        self.label = label
        self.action = action
    }

    /// A range that ends before it starts is nothing to skip.
    var sound: Bool { startSec.isFinite && endSec.isFinite && endSec > startSec && startSec >= 0 }
}

/// One part in the server's list of every part, in time order. `kind` is intro, recap, credits, commercial, preview,
/// postcredits (a scene after the credits) or custom (a part someone named, in `label`).
public struct SkipSegment: Decodable, Equatable {
    public let kind: String
    public let startSec: Double
    public let endSec: Double
    public let label: String?
    public let action: String?
    public let source: String?

    public init(kind: String, startSec: Double, endSec: Double, label: String? = nil, action: String? = nil, source: String? = nil) {
        self.kind = kind
        self.startSec = startSec
        self.endSec = endSec
        self.label = label
        self.action = action
        self.source = source
    }
}

/// What `GET /media/{id}/markers` answers. Everything is optional: a part the video hasn't got is null.
public struct SkipMarkers: Decodable, Equatable {
    public let intro: SkipRange?
    public let recap: SkipRange?
    public let credits: SkipRange?
    public let commercials: [SkipRange]?
    /// From a `.wittyinfo`: a preview of the next episode, a scene after the credits, and parts someone named.
    public let preview: SkipRange?
    public let postCredits: SkipRange?
    public let custom: [SkipRange]?
    /// Every part, in time order (0.8.1 and later). When it's there, it's what the player goes by.
    public let segments: [SkipSegment]?
    /// Where the most trusted part came from: wittyinfo, manual, skip.json, edl, chapters, detected, show or none.
    public let source: String?
    /// The same for each part: "intro": "detected".
    public let sources: [String: String]?

    public init(intro: SkipRange? = nil, recap: SkipRange? = nil, credits: SkipRange? = nil, commercials: [SkipRange]? = nil,
                preview: SkipRange? = nil, postCredits: SkipRange? = nil, custom: [SkipRange]? = nil, segments: [SkipSegment]? = nil,
                source: String? = nil, sources: [String: String]? = nil) {
        self.intro = intro
        self.recap = recap
        self.credits = credits
        self.commercials = commercials
        self.preview = preview
        self.postCredits = postCredits
        self.custom = custom
        self.segments = segments
        self.source = source
        self.sources = sources
    }

    /// An older server, or one that hasn't answered yet: the intro the playback answer carries, alone.
    public init(intro: Intro?) {
        self.init(intro: intro.map { SkipRange(startSec: $0.startSec, endSec: $0.endSec) })
    }

    public var isEmpty: Bool {
        intro == nil && recap == nil && credits == nil && (commercials ?? []).isEmpty && preview == nil && (custom ?? []).isEmpty
            && (segments ?? []).isEmpty
    }
}

/// The parts that can have a button, in the order they win when two overlap (the website's markers.ts).
public enum SkipKind: String, CaseIterable, Codable {
    case recap, intro, commercial, custom, preview, credits

    /// The server's word for a kind in `segments`. A scene after the credits, and anything unknown, has no button.
    public init?(segment kind: String) {
        switch kind {
        case "commercial", "commercials": self = .commercial
        default: self.init(rawValue: kind)
        }
    }

    /// The button's words, as the website's.
    public var button: String {
        switch self {
        case .recap: return "Skip recap"
        case .intro: return "Skip intro"
        case .commercial: return "Skip adverts"
        case .custom: return "Skip this part"
        case .preview: return "Skip preview"
        case .credits: return "Skip credits"
        }
    }

    /// What was skipped, for the notice with Undo.
    public var skipped: String {
        switch self {
        case .recap: return "Skipped the recap"
        case .intro: return "Skipped the intro"
        case .commercial: return "Skipped the adverts"
        case .custom: return "Skipped a part"
        case .preview: return "Skipped the preview"
        case .credits: return "Skipped the credits"
        }
    }

    /// The setting's name.
    public var settingName: String {
        switch self {
        case .recap: return "Recaps"
        case .intro: return "Intros"
        case .commercial: return "Adverts"
        case .custom: return "Other parts someone named"
        case .preview: return "Previews"
        case .credits: return "Credits"
        }
    }

    /// Where the part came from, for an administrator: "found by comparing episodes".
    public static func sourceWords(_ source: String?) -> String {
        switch source {
        case "wittyinfo": return "from the title's .wittyinfo"
        case "wittyinfo-season": return "from the season's .wittyinfo"
        case "wittyinfo-show": return "from the show's .wittyinfo"
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
    /// What someone called a custom part ("Dream sequence"), or "".
    public let name: String
    /// The video's `.wittyinfo` says to skip this part by itself.
    public let fileAuto: Bool

    public var label: String {
        if next { return "Next episode" }
        return kind == .custom && !name.isEmpty ? "Skip " + SkipRules.lowerFirst(SkipRules.short(name)) : kind.button
    }

    /// What's said once it skipped by itself.
    public var skipped: String { kind == .custom && !name.isEmpty ? "Skipped " + SkipRules.lowerFirst(name) : kind.skipped }

    public init(kind: SkipKind, from: Double, to: Double, next: Bool = false, name: String = "", fileAuto: Bool = false) {
        self.kind = kind
        self.to = to
        self.next = next
        self.name = name
        self.fileAuto = fileAuto
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

    /// A named part's name is cut here on its button, as the website does.
    static let nameMax = 40

    static func short(_ name: String) -> String { name.count > nameMax ? String(name.prefix(nameMax - 1)) + "…" : name }
    static func lowerFirst(_ text: String) -> String { text.prefix(1).lowercased() + text.dropFirst() }

    /// One part that can have a button: its kind, where it is, and what the file says about it.
    public struct Part: Equatable {
        public let kind: SkipKind
        public let startSec: Double
        public let endSec: Double
        public let name: String
        public let fileAuto: Bool
        /// These credits stop where a scene after them starts: skipping them never skips it, and they never count as
        /// running to the end.
        public let toScene: Bool
    }

    /// Where a scene after the credits starts, when one starts inside these credits or just after them.
    static func sceneAfter(_ markers: SkipMarkers, _ start: Double, _ end: Double) -> Double? {
        let fromField = markers.postCredits.flatMap { $0.sound ? $0.startSec : nil }
        let fromList = markers.segments?.first { $0.kind == "postcredits" && SkipRange(startSec: $0.startSec, endSec: $0.endSec).sound }?.startSec
        guard let scene = fromField ?? fromList, scene > start, scene <= end + endSlack else { return nil }
        return scene
    }

    /// Every part with a button, in the order they win (recap, intro, adverts, named parts, preview, credits) and then
    /// by time. From `segments` when the server sends it; else from the separate fields. A part only marked, and a
    /// scene after the credits, have none.
    public static func parts(_ markers: SkipMarkers) -> [Part] {
        func part(_ kind: SkipKind, _ start: Double, _ end: Double, _ label: String?, _ action: String?) -> Part? {
            guard action != "mark", SkipRange(startSec: start, endSec: end).sound else { return nil }
            let scene = kind == .credits ? sceneAfter(markers, start, end) : nil
            let name = kind == .custom ? (label ?? "").trimmingCharacters(in: .whitespaces) : ""
            return Part(kind: kind, startSec: start, endSec: scene.map { min($0, end) } ?? end, name: name, fileAuto: action == "auto", toScene: scene != nil)
        }
        let order = SkipKind.allCases
        func sorted(_ list: [Part]) -> [Part] {
            list.sorted { a, b in
                let ia = order.firstIndex(of: a.kind) ?? 0, ib = order.firstIndex(of: b.kind) ?? 0
                return ia != ib ? ia < ib : a.startSec < b.startSec
            }
        }
        if let segments = markers.segments, !segments.isEmpty {
            return sorted(segments.compactMap { seg in SkipKind(segment: seg.kind).flatMap { part($0, seg.startSec, seg.endSec, seg.label, seg.action) } })
        }
        var out: [Part] = []
        func add(_ kind: SkipKind, _ range: SkipRange?) {
            if let range, let p = part(kind, range.startSec, range.endSec, range.label, range.action) { out.append(p) }
        }
        add(.recap, markers.recap)
        add(.intro, markers.intro)
        for advert in markers.commercials ?? [] { add(.commercial, advert) }
        for named in markers.custom ?? [] { add(.custom, named) }
        add(.preview, markers.preview)
        add(.credits, markers.credits)
        return sorted(out)
    }

    /// The part playing at `now`, if skipping it is worth a button (the website's skipAt): more than a second of it
    /// is left, and for credits there is something after them. Credits that run to the end are what "next episode" is
    /// for, so that's what they offer when there is one, until the player's own countdown takes over. Credits with a
    /// scene after them go to the scene.
    public static func offer(_ markers: SkipMarkers?, at now: Double, duration: Double, hasNext: Bool) -> SkipOffer? {
        guard let markers, now.isFinite else { return nil }
        for p in parts(markers) where now >= p.startSec && now < p.endSec - tail {
            let offer = SkipOffer(kind: p.kind, from: p.startSec, to: p.endSec, name: p.name, fileAuto: p.fileAuto)
            guard p.kind == .credits, !p.toScene else { return offer }
            guard duration > 0 else { continue }
            if p.endSec < duration - endSlack { return offer }
            if hasNext, now < duration - nextTakesOver {
                return SkipOffer(kind: .credits, from: p.startSec, to: p.endSec, next: true, fileAuto: p.fileAuto)
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
        for named in markers.custom ?? [] { add(named.label.map { "“\($0)”" } ?? "A part someone named", "custom", named) }
        add("Preview", "preview", markers.preview)
        add("Credits", "credits", markers.credits)
        add("A scene after the credits", "postCredits", markers.postCredits)
        return lines
    }
}

/// Which parts this device skips by itself. Kept on the device, like the player's other choices; off until chosen,
/// except following the file: what a video's `.wittyinfo` says to skip by itself is skipped unless turned off, as the
/// website's `autoSkip.fileAuto`.
public struct SkipPrefs: Codable, Equatable {
    public var intro = false
    public var recap = false
    public var credits = false
    public var adverts = false
    public var preview = false
    public var custom = false
    public var fileAuto = true

    public init(intro: Bool = false, recap: Bool = false, credits: Bool = false, adverts: Bool = false,
                preview: Bool = false, custom: Bool = false, fileAuto: Bool = true) {
        self.intro = intro
        self.recap = recap
        self.credits = credits
        self.adverts = adverts
        self.preview = preview
        self.custom = custom
        self.fileAuto = fileAuto
    }

    /// Nothing skips by itself, not even what a file asks: while something else decides where the film is.
    public static let none = SkipPrefs(fileAuto: false)

    private enum CodingKeys: String, CodingKey { case intro, recap, credits, adverts, preview, custom, fileAuto }

    // A saved set from another version keeps what it can.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        intro = (try? c.decodeIfPresent(Bool.self, forKey: .intro)) ?? false
        recap = (try? c.decodeIfPresent(Bool.self, forKey: .recap)) ?? false
        credits = (try? c.decodeIfPresent(Bool.self, forKey: .credits)) ?? false
        adverts = (try? c.decodeIfPresent(Bool.self, forKey: .adverts)) ?? false
        preview = (try? c.decodeIfPresent(Bool.self, forKey: .preview)) ?? false
        custom = (try? c.decodeIfPresent(Bool.self, forKey: .custom)) ?? false
        fileAuto = (try? c.decodeIfPresent(Bool.self, forKey: .fileAuto)) ?? true
    }

    public func skips(_ kind: SkipKind) -> Bool {
        switch kind {
        case .intro: return intro
        case .recap: return recap
        case .credits: return credits
        case .commercial: return adverts
        case .preview: return preview
        case .custom: return custom
        }
    }

    /// This part: its kind was chosen, or its file says to skip it and this device follows the file.
    public func skips(_ offer: SkipOffer) -> Bool { skips(offer.kind) || (offer.fileAuto && fileAuto) }

    public mutating func set(_ kind: SkipKind, _ on: Bool) {
        switch kind {
        case .intro: intro = on
        case .recap: recap = on
        case .credits: credits = on
        case .commercial: adverts = on
        case .preview: preview = on
        case .custom: custom = on
        }
    }

    public var any: Bool { intro || recap || credits || adverts || preview || custom || fileAuto }

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
    /// What someone called a custom part, or "".
    public var name: String = ""
    public var words: String { kind == .custom && !name.isEmpty ? "Skipped " + SkipRules.lowerFirst(name) : kind.skipped }
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
        guard playing, prefs.skips(offer), !settled.contains(offer.id) else { return nil }
        settled.insert(offer.id)
        notice = SkipNotice(kind: offer.kind, from: now, name: offer.name)
        // The jump is this tracker's own: arriving there isn't a person's seek into something else.
        landing = (offer.to, 5)
        return offer.to
    }
}
