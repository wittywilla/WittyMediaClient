// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

/// A person card's presence dot (catalogue revision 8; the server's docs/SDUI.md, Shelf: "A person card draws a
/// presence dot on its avatar from its badge text, by the card style's `badgeTones`"). The same on every app.
public enum SDUIPresence {
    public enum Tone: String, Equatable, Sendable { case ok, warn, muted }

    /// The catalogue's own words when it doesn't send `badgeTones`: Playing and Online ok, Away warn, Offline muted.
    public static let defaultTones: [String: Tone] = ["playing": .ok, "online": .ok, "away": .warn, "offline": .muted]

    /// The dot for a card's first badge, by the style's `badgeTones` (badge text to `ok`, `warn` or `muted`; case is
    /// ignored), else the defaults. Nil: no dot, as for a badge that isn't a presence at all.
    public static func tone(badges: [String], tones: [String: String]? = nil) -> Tone? {
        guard let badge = badges.first?.trimmingCharacters(in: .whitespaces).lowercased(), !badge.isEmpty else { return nil }
        if let tones {
            let sent = Dictionary(tones.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
            if let word = sent[badge] { return Tone(rawValue: word) }
        }
        return defaultTones[badge]
    }
}
