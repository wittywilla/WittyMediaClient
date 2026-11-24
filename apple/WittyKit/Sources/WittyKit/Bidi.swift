// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

/// Text that isn't the app's own (a title, an artist, a file name, "2 hr 10 min") joined into one line with others.
///
/// A Hebrew or Arabic title among Latin ones, or Latin ones on a device set to a right-to-left language, would have
/// its digits and dashes moved by the bidi rules ("00-aurora-…-2019" as "…-2019-00", "2018 · 2 hr 10 min" as
/// "hr 10 min 2 · 2018"). Each part is isolated (U+2068 … U+2069, the plain-text `<bdi>`), so it keeps its own order
/// and the line keeps its parts in place. The server's web app and the Android app do the same.
public enum Bidi {
    static let fsi = "\u{2068}"
    static let pdi = "\u{2069}"

    /// Whether the device's first language is written right to left.
    static let rightToLeftDevice: Bool = Locale.characterDirection(forLanguage: Locale.preferredLanguages.first ?? "en") == .rightToLeft

    /// `text` isolated from what's around it, keeping its own direction. Left as it is where nothing could move it:
    /// left-to-right text on a left-to-right device.
    public static func isolate(_ text: String) -> String {
        guard !text.isEmpty, !text.hasPrefix(fsi) else { return text }
        guard rightToLeftDevice || text.unicodeScalars.contains(where: isRightToLeft) else { return text }
        return fsi + text + pdi
    }

    static func isRightToLeft(_ u: Unicode.Scalar) -> Bool {
        (0x0590...0x08FF).contains(u.value) || (0xFB1D...0xFDFF).contains(u.value) || (0xFE70...0xFEFF).contains(u.value)
    }
}

public extension Sequence where Element: StringProtocol {
    /// The parts joined into one line (" · " between them), each isolated: see `Bidi.isolate`.
    func factsLine(_ separator: String = " · ") -> String {
        map { Bidi.isolate(String($0)) }.joined(separator: separator)
    }
}
