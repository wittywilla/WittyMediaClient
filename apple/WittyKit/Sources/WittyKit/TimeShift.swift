// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// Time-shift for everyone (server #648), as web/src/pages/tv/timeshift.ts and the Android app have it: a library
// channel's programme started over for this viewer only, its breaks skipped, and rewinding further back than the
// stream keeps. Times are the schedule's, in Unix seconds; the stream's program date-times say where the picture is.

public struct Span: Decodable, Equatable {
    public let start: Int64
    public let end: Int64
    public init(start: Int64, end: Int64) { self.start = start; self.end = end }
}

/// What GET /tv/{key}/startover and /timeline say about the programme a start-over stream is in.
public struct Timeline: Decodable, Equatable {
    public let programme: GuideProgramme
    public let breaks: [Span]?
    public let from: Int64?
    public let live: Int64
    public let earliest: Int64
}

public enum TimeShiftRules {
    /// A start over closer to live than this is live: the player goes back to the shared stream.
    public static let liveEdge: Double = 20

    public enum Seek: Equatable {
        case live
        case within(Double)
        case restart(Int64)
    }

    public static func isLibrary(_ key: String) -> Bool { key.hasPrefix("lib-") }

    /// The break the picture is in at moment t, if any.
    public static func breakAt(_ breaks: [Span]?, _ t: Double?) -> Span? {
        guard let t, let breaks else { return nil }
        return breaks.first { Double($0.start) <= t && t < Double($0.end) }
    }

    /// A seek to schedule moment target, with the picture at media time cur (schedule moment sched) and media times
    /// low...high loaded: within them it's a seek; further back, the viewer's stream starts again from there; at live,
    /// back to the channel everyone shares.
    public static func plan(_ target: Double, sched: Double, cur: Double, low: Double, high: Double, live: Double, earliest: Double = -.infinity) -> Seek {
        if target >= live - liveEdge { return .live }
        let at = max(earliest, target)
        let to = cur + (at - sched)
        if to >= low - 0.5, to <= high { return .within(max(low, to)) }
        return .restart(Int64(at.rounded(.down)))
    }

    /// After a pause longer than the stream keeps (less a margin), start again from where it paused.
    public static func restartAfterPause(pausedAt: Date, now: Date, bufferSec: Double) -> Bool {
        now.timeIntervalSince(pausedAt) > max(30, bufferSec - 30)
    }

    /// Whether Start over is worth offering: a programme that began more than a moment ago.
    public static func canStartOver(_ tuned: Tuned?, now: Double) -> Bool {
        guard let tuned, tuned.startOver == true, let p = tuned.now, p.kind != "slate", p.end > p.start else { return false }
        return now - Double(p.start) > liveEdge
    }

    /// GET /tv/{key}/startover, with a pass in the stream's address as tune has it.
    public static func query(key: String, from: Int64?, viewer: String) -> String {
        "/tv/\(WittyClient.pathPart(key))/startover?viewer=\(WittyClient.pathPart(viewer))&streamToken=1" + (from.map { "&from=\($0)" } ?? "")
    }

    public static func leaveQuery(key: String, viewer: String, shift: Bool) -> String {
        "/tv/\(WittyClient.pathPart(key))/leave?viewer=\(WittyClient.pathPart(viewer))" + (shift ? "&shift=1" : "")
    }
}
