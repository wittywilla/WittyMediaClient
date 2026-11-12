// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

// WittyTV problems (the canvas's `tvfail`, `tvenc`, `tvback` gap pages): every failure says what happened in the server's own
// words and always offers a way forward. Built as `DesignPageSpec` data from what the channel really is, so the words and
// the buttons are tested without a screen.

public enum TvProblem {
    public enum Kind: Equatable, Sendable {
        /// The channel won't open or stopped.
        case wontPlay
        /// The channel is encrypted: a card or a service this server can't use.
        case encrypted
        /// No tuner is free: another recording or viewer uses it.
        case noTuner
    }

    /// Reads which problem the server's words and the channel's security describe.
    public static func kind(why: String, security: String?) -> Kind {
        if security == "encrypted" { return .encrypted }
        let w = why.lowercased()
        if w.contains("encrypt") || w.contains("scrambled") { return .encrypted }
        if w.contains("no tuner") || w.contains("tuner is in use") || w.contains("tuners are busy") || w.contains("all tuners") { return .noTuner }
        return .wontPlay
    }

    public struct Alternative: Equatable, Sendable {
        public var number: String
        public var name: String
        public init(number: String, name: String) {
            self.number = number
            self.name = name
        }
    }

    /// The page: the channel is the eyebrow, what happened the title's lead, then the ways forward as actions.
    public static func spec(why: String, kind: Kind, number: String, name: String, alternative: Alternative?,
                            fromStart: String?, security: (label: String, detail: String)? = nil) -> DesignPageSpec {
        let title: String
        switch kind {
        case .wontPlay: title = "This channel won’t play"
        case .encrypted: title = "This channel is encrypted"
        case .noTuner: title = "No tuner is free"
        }
        var sections: [DesignPageSpec.Section] = []
        if kind == .encrypted {
            let detail = security.map { $0.detail } ?? ""
            sections.append(.secN("What can I do?", detail.isEmpty ? "Encrypted channels need a card or a service this server can’t use. Hide them under Which channels, or use a set." : detail))
        }
        var actions: [DesignPageSpec.Action] = []
        if let alternative {
            actions.append(DesignPageSpec.Action(id: "alternative", title: "Watch \(alternative.number) \(alternative.name) instead", primary: true))
        }
        if kind != .encrypted { actions.append(DesignPageSpec.Action(id: "try-again", title: "Try again", primary: alternative == nil)) }
        if fromStart != nil { actions.append(.A2("Back to live")) }
        actions.append(.A2("Next channel"))
        actions.append(DesignPageSpec.Action(id: "back-to-the-guide", title: "Back to the guide", primary: kind == .encrypted && alternative == nil))
        var page = DesignPageSpec(eyebrow: "WittyTV · " + [number.isEmpty ? "" : "Ch \(number)", name].filter { !$0.isEmpty }.joined(separator: " "),
                                  title: title, lead: why, sections: sections, actions: actions, layer: true)
        page.start = actions.first(where: \.primary)?.id ?? actions.first?.id ?? ""
        return page
    }
}
