// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

/// The order of the subtitle and sound track menus, as the web app and the Android app have them
/// (web/src/player/trackOrder.ts, android net/TrackOrder.kt): this device's languages first, then the ones
/// picked lately, then the rest by name. Off stays where the menu puts it, first.
public enum TrackOrder {
    static let recentMax = 5

    /// "eng", "ger", "en-GB" and "EN" are all "en". Empty for "und" and nothing.
    public static func base(_ code: String?) -> String {
        let c = (code ?? "").trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "_", with: "-").lowercased()
        let first = String(c.split(separator: "-").first ?? "")
        if first.isEmpty || ["und", "unknown", "zxx", "mul"].contains(first) { return "" }
        if first.count == 3, let two = threeLetter[first] { return two }
        return first
    }

    /// The three-letter codes files carry (both the terminology and the old bibliographic ones), for the languages
    /// films and shows come with most.
    static let threeLetter: [String: String] = [
        "eng": "en", "spa": "es", "fra": "fr", "fre": "fr", "deu": "de", "ger": "de", "ita": "it", "por": "pt", "nld": "nl",
        "dut": "nl", "swe": "sv", "dan": "da", "nor": "no", "nob": "nb", "nno": "nn", "fin": "fi", "pol": "pl", "ces": "cs",
        "cze": "cs", "hun": "hu", "ell": "el", "gre": "el", "tur": "tr", "rus": "ru", "ukr": "uk", "jpn": "ja", "kor": "ko",
        "zho": "zh", "chi": "zh", "hin": "hi", "ara": "ar", "heb": "he", "tha": "th", "vie": "vi", "ind": "id", "msa": "ms",
        "may": "ms", "ron": "ro", "rum": "ro", "bul": "bg", "hrv": "hr", "srp": "sr", "slk": "sk", "slo": "sk", "slv": "sl",
        "est": "et", "lav": "lv", "lit": "lt", "isl": "is", "ice": "is", "fas": "fa", "per": "fa", "cat": "ca", "eus": "eu",
        "baq": "eu", "glg": "gl", "tam": "ta", "tel": "te", "ben": "bn", "urd": "ur", "fil": "fil", "tgl": "tl", "cym": "cy",
        "wel": "cy", "gle": "ga", "mkd": "mk", "mac": "mk", "sqi": "sq", "alb": "sq", "kat": "ka", "geo": "ka", "hye": "hy",
        "arm": "hy", "mal": "ml", "kan": "kn", "mar": "mr", "afr": "af", "swa": "sw", "zul": "zu",
    ]

    /// Sorts tracks: device languages first (most wanted first), then recent ones, then the rest by name.
    public static func order<T>(_ items: [T], language: (T) -> String?, title: (T) -> String, device: [String], recent: [String]) -> [T] {
        var dev: [String] = []
        for d in device.map(base) where !d.isEmpty && !dev.contains(d) { dev.append(d) }
        var rec: [String] = []
        for r in recent.map(base) where !r.isEmpty && !dev.contains(r) && !rec.contains(r) { rec.append(r) }
        let ranked = items.enumerated().map { (i, t) -> (T, Int, Int, Int) in
            let b = base(language(t))
            if !b.isEmpty, let d = dev.firstIndex(of: b) { return (t, 0, d, i) }
            if !b.isEmpty, let r = rec.firstIndex(of: b) { return (t, 1, r, i) }
            return (t, 2, 0, i)
        }
        return ranked.sorted { a, b in
            if a.1 != b.1 { return a.1 < b.1 }
            if a.2 != b.2 { return a.2 < b.2 }
            if a.1 == 2 {
                let c = title(a.0).localizedStandardCompare(title(b.0))
                if c != .orderedSame { return c == .orderedAscending }
            }
            return a.3 < b.3
        }.map { $0.0 }
    }

    /// The languages picked lately, newest first, after picking one.
    public static func remember(_ saved: [String], _ code: String?) -> [String] {
        let b = base(code)
        if b.isEmpty { return saved }
        return Array(([b] + saved.filter { $0 != b }).prefix(recentMax))
    }
}
