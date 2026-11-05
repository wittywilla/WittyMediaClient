import Foundation

/// A profile's tile: its initial on a colour picked from its name, so each person keeps the same
/// colour on every device and in the browser. The same rule as the server's web pages
/// (`web/src/pages/AuthPage.tsx`, `Avatar`), and as `docs/APP-DESIGN.md` describes.
public enum AvatarLook {
    /// All dark enough for a white initial (4.5:1).
    public static let colours = ["#c9302f", "#b8500d", "#99690a", "#2e7d3c", "#0e7c6f",
                                 "#0a6fb8", "#3e5bd0", "#7f46b8", "#bd2f85", "#8d6444"]

    /// The web walks the name by code point and adds each one's first UTF-16 unit, in 32 bits.
    public static func colourIndex(for name: String) -> Int {
        var hash: UInt32 = 0
        for scalar in name.unicodeScalars {
            let unit = UInt32(String(scalar).utf16.first ?? 0)
            hash = hash &* 31 &+ unit
        }
        return Int(hash % UInt32(colours.count))
    }

    public static func colour(for name: String) -> String { colours[colourIndex(for: name)] }

    /// The first letter, in capitals. A name with nothing in it gets a question mark, as on the web.
    public static func initial(of name: String) -> String {
        guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first else { return "?" }
        return String(first).uppercased()
    }
}
