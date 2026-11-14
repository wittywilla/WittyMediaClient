// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// Which title (DVD) or playlist (Blu-ray) of a disc is the film, and why: the server's
// GET /modules/wittydvd|wittybluray/discs/{id}/analysis (feature `disc-ranking`), as the website's DiscWhy.tsx shows it.
// Anyone who may see the disc reads it; an administrator can choose another title for everyone
// (PUT/DELETE .../discs/{id}/choice) and ask for the ranking again (POST .../analysis).
// The shapes are the server's discAnalysisView and library.DiscRank; every field may be missing,
// and a list keeps the entries it can read.

private extension KeyedDecodingContainer {
    /// A field's value, or `otherwise` when it's missing or can't be read.
    func loose<T: Decodable>(_ key: Key, _ otherwise: T) -> T { ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? otherwise }
    func maybe<T: Decodable>(_ key: Key) -> T? { (try? decodeIfPresent(T.self, forKey: key)) ?? nil }
    func list<T: Decodable>(_ key: Key) -> [T] { ((try? decodeIfPresent([Loose<T>].self, forKey: key)) ?? []).compactMap(\.value) }
}

/// GET .../discs/{id}/analysis, and what choosing, clearing and ranking again answer.
public struct DiscAnalysis: Decodable, Equatable, Sendable {
    /// "dvd" or "bluray".
    public var kind: String
    /// The engine in use gave a ranking. False with a module from before rankings.
    public var ranked: Bool
    /// Being worked out in the background on a server that goes easy on its machine: ask again.
    public var pending: Bool
    /// What Play plays: the chosen title, or else the engine's. -1 when there is none.
    public var main: Int
    /// The engine's own pick, -1 when there is none.
    public var engineMain: Int
    public var chosen: DiscChoice?
    /// Who chose, for an administrator.
    public var chosenBy: String?
    public var rank: DiscRank?
    public var canChoose: Bool
    /// The disc is encrypted.
    public var protected: Bool
    /// Whether a libbluray can be asked: Blu-rays, and administrators, only.
    public var secondOpinion: DiscSecondOpinionState?

    private enum CodingKeys: String, CodingKey {
        case kind, ranked, pending, main, engineMain, chosen, chosenBy, rank, canChoose, protected, secondOpinion
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        kind = box.loose(.kind, "dvd")
        ranked = box.loose(.ranked, false)
        pending = box.loose(.pending, false)
        main = box.loose(.main, -1)
        engineMain = box.loose(.engineMain, -1)
        chosen = box.maybe(.chosen)
        chosenBy = box.maybe(.chosenBy)
        rank = box.maybe(.rank)
        canChoose = box.loose(.canChoose, false)
        protected = box.loose(.protected, false)
        secondOpinion = box.maybe(.secondOpinion)
    }

    public var isBluray: Bool { kind == "bluray" }
}

/// The title an administrator chose as the disc's film.
public struct DiscChoice: Decodable, Equatable, Sendable {
    public var ttn: Int
    public var by: Int64
    public var at: Int64
    /// The main title before the choice.
    public var was: Int

    private enum CodingKeys: String, CodingKey { case ttn, by, at, was }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        ttn = try box.decode(Int.self, forKey: .ttn)
        by = box.loose(.by, 0)
        at = box.loose(.at, 0)
        was = box.loose(.was, -1)
    }
}

/// Whether this server can ask a libbluray for a second opinion.
public struct DiscSecondOpinionState: Decodable, Equatable, Sendable {
    public var enabled: Bool
    public var available: Bool
    public var version: String?
    public var reason: String?

    private enum CodingKeys: String, CodingKey { case enabled, available, version, reason }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        enabled = box.loose(.enabled, false)
        available = box.loose(.available, false)
        version = box.maybe(.version)
        reason = box.maybe(.reason)
    }
}

/// The engine's ranking of a disc, as the server keeps and shows it.
public struct DiscRank: Decodable, Equatable, Sendable {
    /// The module and version that gave it, such as "wittydvd 0.4.0".
    public var engine: String
    /// The engine's pick, or -1.
    public var main: Int
    /// 0 to 1.
    public var confidence: Double
    /// high, medium or low.
    public var level: String
    /// One sentence.
    public var why: String
    public var reasons: [String]
    public var against: [String]
    public var runnerUp: Int
    public var feature: DiscFeature?
    public var versions: [DiscVersion]
    public var episodes: [DiscEpisode]
    public var playAll: Int
    public var candidates: [DiscCandidate]
    public var decoys: Int
    public var hidden: Int
    public var warnings: [String]
    public var repairs: [String]
    public var repairCount: Int
    public var issues: [DiscIssue]
    public var issueCount: Int
    public var paddedSectors: Int64
    public var readRetries: Int64
    public var protected: Bool
    public var secondOpinion: DiscSecondOpinion?
    public var at: Int64

    private enum CodingKeys: String, CodingKey {
        case engine, main, confidence, level, why, reasons, against, runnerUp, feature, versions, episodes, playAll, candidates
        case decoys, hidden, warnings, repairs, repairCount, issues, issueCount, paddedSectors, readRetries, protected, secondOpinion, at
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        engine = box.loose(.engine, "")
        main = box.loose(.main, -1)
        confidence = min(max(box.loose(.confidence, 0.0), 0), 1)
        level = box.loose(.level, "")
        why = box.loose(.why, "")
        reasons = box.list(.reasons)
        against = box.list(.against)
        runnerUp = box.loose(.runnerUp, -1)
        feature = box.maybe(.feature)
        versions = box.list(.versions)
        episodes = box.list(.episodes)
        playAll = box.loose(.playAll, -1)
        candidates = box.list(.candidates)
        decoys = box.loose(.decoys, 0)
        hidden = box.loose(.hidden, 0)
        warnings = box.list(.warnings)
        repairs = box.list(.repairs)
        repairCount = box.loose(.repairCount, 0)
        issues = box.list(.issues)
        issueCount = box.loose(.issueCount, 0)
        paddedSectors = box.loose(.paddedSectors, 0)
        readRetries = box.loose(.readRetries, 0)
        protected = box.loose(.protected, false)
        secondOpinion = box.maybe(.secondOpinion)
        at = box.loose(.at, 0)
    }
}

/// What plays for the film on a DVD, when that is more than one title's chapter table.
public struct DiscFeature: Decodable, Equatable, Sendable {
    public var titles: [Int]
    public var durationSec: Double
    /// chapters, commands or chain.
    public var source: String
    public var assembled: Bool

    private enum CodingKeys: String, CodingKey { case titles, durationSec, source, assembled }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        titles = box.list(.titles)
        durationSec = box.loose(.durationSec, 0)
        source = box.loose(.source, "")
        assembled = box.loose(.assembled, false)
    }
}

/// Another way to see the film: an angle, a parental version, a cut or an edition.
public struct DiscVersion: Decodable, Equatable, Sendable {
    public var kind: String
    public var ttn: Int
    public var angle: Int
    public var parentalLevels: [Int]
    public var durationSec: Double
    public var label: String
    public var main: Bool

    private enum CodingKeys: String, CodingKey { case kind, ttn, angle, parentalLevels, durationSec, label, main }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        kind = box.loose(.kind, "")
        ttn = try box.decode(Int.self, forKey: .ttn)
        angle = box.loose(.angle, 0)
        parentalLevels = box.list(.parentalLevels)
        durationSec = box.loose(.durationSec, 0)
        label = box.loose(.label, "")
        main = box.loose(.main, false)
    }
}

/// One episode of a TV disc, in viewing order. One with no title of its own is a stretch of the play-all title.
public struct DiscEpisode: Decodable, Equatable, Sendable {
    public var index: Int
    public var ttn: Int
    public var durationSec: Double
    public var startSec: Double
    public var chapter: Int
    public var item: Int
    public var part: Bool

    private enum CodingKeys: String, CodingKey { case index, ttn, durationSec, startSec, chapter, item, part }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        index = try box.decode(Int.self, forKey: .index)
        ttn = box.loose(.ttn, -1)
        durationSec = box.loose(.durationSec, 0)
        startSec = box.loose(.startSec, 0)
        chapter = box.loose(.chapter, 0)
        item = box.loose(.item, 0)
        part = box.loose(.part, false)
    }
}

/// One title as the engine scored it.
public struct DiscCandidate: Decodable, Equatable, Sendable {
    public var ttn: Int
    public var durationSec: Double
    public var chapters: Int
    public var `class`: String
    public var score: Double
    public var decoy: Bool
    public var reasons: [String]

    private enum CodingKeys: String, CodingKey { case ttn, durationSec, chapters, `class`, score, decoy, reasons }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        ttn = try box.decode(Int.self, forKey: .ttn)
        durationSec = box.loose(.durationSec, 0)
        chapters = box.loose(.chapters, 0)
        `class` = box.loose(.class, "")
        score = box.loose(.score, 0)
        decoy = box.loose(.decoy, false)
        reasons = box.list(.reasons)
    }
}

/// One place where a copy's structures disagree.
public struct DiscIssue: Decodable, Equatable, Sendable {
    /// error, warn or info.
    public var severity: String
    public var kind: String
    /// -1 when it is about no one title.
    public var ttn: Int
    public var what: String

    private enum CodingKeys: String, CodingKey { case severity, kind, ttn, what }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        severity = box.loose(.severity, "")
        kind = box.loose(.kind, "")
        ttn = box.loose(.ttn, -1)
        what = box.loose(.what, "")
    }
}

/// How a libbluray on the server's machine read the same disc.
public struct DiscSecondOpinion: Decodable, Equatable, Sendable {
    public var source: String
    public var agrees: Bool
    public var main: Int
    public var differences: [String]
    public var more: Int
    /// Why none was taken, when one was asked for.
    public var note: String

    private enum CodingKeys: String, CodingKey { case source, agrees, main, differences, more, note }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        source = box.loose(.source, "")
        agrees = box.loose(.agrees, false)
        main = box.loose(.main, -1)
        differences = box.list(.differences)
        more = box.loose(.more, 0)
        note = box.loose(.note, "")
    }
}

// MARK: - The words

/// The words and addresses of a disc's "Why this title" section, as the website's DiscWhy.tsx says them.
public enum DiscRanking {
    /// The server's feature name in /capabilities.
    public static let feature = "disc-ranking"

    /// A pending ranking is asked for again this many seconds later, at most `pendingTries` times.
    public static let pendingWait: Double = 4
    public static let pendingTries = 15

    /// "Playlist" on a Blu-ray, "Title" on a DVD.
    public static func unit(_ a: DiscAnalysis) -> String { a.isBluray ? "Playlist" : "Title" }

    /// "Title 3", or "Playlist 00800" as a Blu-ray names its playlist files.
    public static func name(_ ttn: Int, _ a: DiscAnalysis) -> String {
        "\(unit(a)) " + (a.isBluray ? String(format: "%05d", ttn) : String(ttn))
    }

    /// The section's heading: "Why this title" or "Why this playlist".
    public static func heading(_ a: DiscAnalysis) -> String { "Why this \(unit(a).lowercased())" }

    /// "92% sure".
    public static func sure(_ confidence: Double) -> String { "\(Int((min(max(confidence, 0), 1) * 100).rounded()))% sure" }

    /// "High confidence", "Medium confidence" or "Low confidence"; empty for a level the app doesn't know.
    public static func levelWords(_ level: String) -> String {
        switch level {
        case "high": return "High confidence"
        case "medium": return "Medium confidence"
        case "low": return "Low confidence"
        default: return ""
        }
    }

    /// How sure the engine is, in words: the level, or the percentage when there's no level.
    public static func confidence(_ rank: DiscRank) -> String {
        let words = levelWords(rank.level)
        return words.isEmpty ? sure(rank.confidence) : words
    }

    /// The engine's sentence, or what it picked when it gave none.
    public static func why(_ a: DiscAnalysis) -> String {
        guard let rank = a.rank else { return "" }
        let said = rank.why.trimmingCharacters(in: .whitespacesAndNewlines)
        return said.isEmpty ? "The engine picked \(name(rank.main, a))." : said
    }

    /// With a choice: "Title 2 was chosen as this disc's film by Willa; the engine picks Title 1."
    public static func chosenLine(_ a: DiscAnalysis) -> String? {
        guard a.chosen != nil else { return nil }
        var line = "\(name(a.main, a)) was chosen as this disc\u{2019}s film"
        if let by = a.chosenBy, !by.isEmpty { line += " by \(by)" }
        if a.engineMain >= 0, a.engineMain != a.main { line += "; the engine picks \(name(a.engineMain, a))" }
        return line + "."
    }

    /// What a module from before rankings says instead.
    public static func unrankedLine(_ a: DiscAnalysis) -> String {
        "The disc module in use is from before ranking, so the film is the longest sensible \(unit(a).lowercased()). Updating the module explains its pick."
    }

    public static let pendingTitle = "Working out which title is the film"
    public static let pendingLine = "This disc is being looked at in the background. This page updates by itself."
    /// After the last try.
    public static let pendingGaveUp = "This disc is still being looked at in the background. Open this page again in a while to see why."

    /// What is said for the whole section to VoiceOver: what plays, why and how sure.
    public static func summaryLabel(_ a: DiscAnalysis) -> String {
        if let chosen = chosenLine(a) { return chosen }
        guard let rank = a.rank else { return "" }
        return "\(confidence(rank)), \(sure(rank.confidence)). \(why(a))"
    }

    // MARK: How the engine decided

    /// One part of "How the engine decided": a heading (or none) and its lines.
    public struct Part: Equatable, Sendable {
        public var heading: String
        public var lines: [String]
        public init(_ heading: String, _ lines: [String]) {
            self.heading = heading
            self.lines = lines
        }
    }

    /// Everything under "How the engine decided", in the website's order.
    public static func details(_ a: DiscAnalysis) -> [Part] {
        guard let rk = a.rank else { return [] }
        var parts: [Part] = []
        let unitWord = unit(a).lowercased()
        if !rk.reasons.isEmpty { parts.append(Part("For \(name(rk.main, a))", rk.reasons)) }
        if !rk.against.isEmpty { parts.append(Part("Against it", rk.against)) }
        if let f = rk.feature, f.assembled, !f.titles.isEmpty {
            let titles = f.titles.count > 1 ? "titles \(f.titles.map(String.init).joined(separator: ", "))" : "title \(f.titles[0])"
            parts.append(Part("", ["The film runs through \(titles) (\(TitleLook.clock(f.durationSec))), which play here as one."]))
        }
        if rk.decoys > 0 || rk.hidden > 0 {
            var line = rk.decoys > 0 ? "\(rk.decoys) \(unitWord)s look like decoys and aren\u{2019}t listed." : ""
            if rk.hidden > 0 { line += (line.isEmpty ? "" : " ") + "\(rk.hidden) more aren\u{2019}t shown." }
            parts.append(Part("", [line]))
        }
        if !rk.warnings.isEmpty { parts.append(Part("Worth knowing", rk.warnings)) }
        if rk.repairCount > 0 || rk.issueCount > 0 || rk.paddedSectors > 0 {
            var lines = rk.repairs
            if rk.repairCount > rk.repairs.count { lines.append("and \(rk.repairCount - rk.repairs.count) more mended") }
            for x in rk.issues {
                lines.append((x.severity == "error" ? "Won\u{2019}t play: " : "") + x.what + (x.ttn >= 0 ? " (\(name(x.ttn, a)))" : ""))
            }
            if rk.paddedSectors > 0 {
                lines.append("\(rk.paddedSectors) unreadable sectors were passed over as blank while reading the disc\u{2019}s index.")
            }
            parts.append(Part("The copy", lines))
        }
        if let so = rk.secondOpinion {
            let source = so.source.isEmpty ? "libbluray" : so.source
            let line: String
            if !so.note.isEmpty {
                line = "No second opinion: \(so.note)"
            } else if so.agrees {
                line = "\(source) agrees."
            } else {
                line = "\(source) reads it differently" + (so.main >= 0 ? " and picks \(name(so.main, a))" : "") + "."
            }
            parts.append(Part("Second opinion", [line] + so.differences))
        }
        if !rk.engine.isEmpty { parts.append(Part("", [rk.engine])) }
        return parts
    }

    // MARK: Choosing

    /// The candidates an administrator can make the film: every listed one but what plays now.
    public static func others(_ a: DiscAnalysis) -> [DiscCandidate] {
        (a.rank?.candidates ?? []).filter { $0.ttn != a.main }
    }

    /// "Title 2 · 1:42:05 · feature".
    public static func candidateLabel(_ c: DiscCandidate, _ a: DiscAnalysis) -> String {
        [name(c.ttn, a), TitleLook.clock(c.durationSec), c.class].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// What VoiceOver says for a candidate's button.
    public static func chooseLabel(_ c: DiscCandidate, _ a: DiscAnalysis) -> String {
        "Make \(name(c.ttn, a)) the film, \(TitleLook.runtime(c.durationSec))" + (c.class.isEmpty ? "" : ", \(c.class)")
    }

    public static func chosenToast(_ ttn: Int, _ a: DiscAnalysis) -> String { "\(name(ttn, a)) is now this disc\u{2019}s film" }

    public static let clearTitle = "Use the engine\u{2019}s pick again?"
    public static let clearButton = "Use the engine\u{2019}s pick"
    public static let clearedToast = "The engine\u{2019}s pick is the film again"

    /// "Play will play Title 1 again, for everyone."
    public static func clearMessage(_ a: DiscAnalysis) -> String {
        "Play will play \(a.engineMain >= 0 ? name(a.engineMain, a) : "what the engine picks") again, for everyone."
    }

    public static let againButton = "Rank again"
    public static let againToast = "The disc was ranked again"
    public static let secondOpinionButton = "Compare with libbluray"
    public static let secondOpinionToast = "libbluray\u{2019}s reading was compared"

    /// An administrator may ask a libbluray: a Blu-ray that isn't encrypted, with the setting on and one found.
    public static func offersSecondOpinion(_ a: DiscAnalysis) -> Bool {
        a.isBluray && !a.protected && a.secondOpinion?.enabled == true && a.secondOpinion?.available == true
    }

    // MARK: Episodes and versions

    /// The film's other versions: every one but the one Play plays.
    public static func otherVersions(_ rank: DiscRank) -> [DiscVersion] { rank.versions.filter { !$0.main } }

    /// A version's own label, or "Title 4".
    public static func versionLabel(_ v: DiscVersion, _ a: DiscAnalysis) -> String {
        let label = v.label.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? "\(unit(a)) \(v.ttn)" : label
    }

    /// "Episode 3".
    public static func episodeLabel(_ e: DiscEpisode) -> String { "Episode \(e.index)" }

    /// "22:04 · title 3", or "22:04 · from 44:10 of playlist 800" for a stretch of the play-all title.
    public static func episodeDetail(_ e: DiscEpisode, _ a: DiscAnalysis) -> String {
        let unitWord = unit(a).lowercased()
        return TitleLook.clock(e.durationSec) + (e.part ? " · from \(TitleLook.clock(e.startSec)) of \(unitWord) \(e.ttn)" : " · \(unitWord) \(e.ttn)")
    }

    /// The server's disc player at one episode (`?mode=title&episode=…`).
    public static func episodePath(_ item: Int64, _ e: DiscEpisode) -> String { "/play/\(item)?mode=title&episode=\(e.index)" }

    /// The server's disc player at a version: its title, and its angle for an angle.
    public static func versionPath(_ item: Int64, _ v: DiscVersion) -> String {
        "/play/\(item)?mode=title&ttn=\(v.ttn)" + (v.kind == "angle" && v.angle > 0 ? "&angle=\(v.angle)" : "")
    }
}

// MARK: - The routes

public extension WittyClient {
    /// Which title is the film and why. `pending` says to ask again in a few seconds.
    func discAnalysis(_ item: Int64, kind: String) async throws -> DiscAnalysis { try await get(Self.discPath(item, kind: kind) + "/analysis") }

    /// An administrator's: this title or playlist is the disc's film, for everyone.
    func chooseDiscTitle(_ item: Int64, kind: String, ttn: Int) async throws -> DiscAnalysis {
        let data = try await call("PUT", Self.discPath(item, kind: kind) + "/choice", body: try JSONEncoder().encode(["ttn": ttn]))
        return try JSONDecoder().decode(DiscAnalysis.self, from: data)
    }

    /// An administrator's: forget the choice, so the engine's pick is the film again.
    func clearDiscChoice(_ item: Int64, kind: String) async throws -> DiscAnalysis {
        try JSONDecoder().decode(DiscAnalysis.self, from: try await call("DELETE", Self.discPath(item, kind: kind) + "/choice"))
    }

    /// An administrator's: work the ranking out again; `secondOpinion` also asks a libbluray (Blu-ray only).
    func rankDiscAgain(_ item: Int64, kind: String, secondOpinion: Bool = false) async throws -> DiscAnalysis {
        let data = try await call("POST", Self.discPath(item, kind: kind) + "/analysis", body: try JSONEncoder().encode(["secondOpinion": secondOpinion]))
        return try JSONDecoder().decode(DiscAnalysis.self, from: data)
    }
}
