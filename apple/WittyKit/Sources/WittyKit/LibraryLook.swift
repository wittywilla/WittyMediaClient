import Foundation

// How a film or TV library's page draws its cards, worked out as the website does
// (web/src/pages/library/library.css and web/src/components/BrandLogo.tsx), so every app gets the same
// colours and the same logo on the same theme.

/// A category or collection card with no picture: a gradient in a colour of its own, from its name, so it never
/// changes (`.lib-cat`: `linear-gradient(155deg, hsl(h 32% 30%), hsl(h+40 38% 14%))`).
public enum CategoryLook {
    /// The website's `artHue`: each character of the name, as JavaScript reads it, into a hue.
    public static func hue(_ name: String) -> Int {
        var hue = 0
        for scalar in name.unicodeScalars {
            // `for…of` gives whole characters, and `charCodeAt(0)` the first half of one outside the first plane.
            let code = scalar.value > 0xFFFF ? 0xD800 + ((Int(scalar.value) - 0x10000) >> 10) : Int(scalar.value)
            hue = (hue * 31 + code) % 360
        }
        return hue
    }

    /// The gradient's two colours, as `#rrggbb`.
    public static func colours(_ name: String) -> (from: String, to: String) {
        let h = Double(hue(name))
        return (hsl(h, 0.32, 0.30), hsl(h + 40, 0.38, 0.14))
    }

    /// CSS's `hsl()`, to `#rrggbb`.
    public static func hsl(_ hue: Double, _ saturation: Double, _ lightness: Double) -> String {
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let a = saturation * min(lightness, 1 - lightness)
        func channel(_ n: Double) -> Int {
            let k = (n + h / 30).truncatingRemainder(dividingBy: 12)
            let value = lightness - a * max(-1, min(k - 3, 9 - k, 1))
            return Int((value * 255).rounded())
        }
        return String(format: "#%02x%02x%02x", channel(0), channel(8), channel(4))
    }

    /// Where a CSS gradient at this angle starts and ends on a box of this shape (width over height), as
    /// fractions of the box: the line runs through the middle, long enough to reach the far corners.
    public static func ends(degrees: Double, aspect: Double) -> (start: (x: Double, y: Double), end: (x: Double, y: Double)) {
        let angle = degrees * .pi / 180
        let (sine, cosine) = (sin(angle), cos(angle))
        // Half the line, in widths across and in heights down.
        let across = sine * (abs(sine) + abs(cosine) / aspect) / 2
        let down = -cosine * (aspect * abs(sine) + abs(cosine)) / 2
        return ((0.5 - across, 0.5 - down), (0.5 + across, 0.5 + down))
    }
}

/// One name to look up in the logo service: a studio, network or streaming service.
public struct LogoRef: Encodable, Equatable, Hashable {
    public let kind: String
    public let name: String

    public init(kind: String, name: String) {
        self.kind = kind
        self.name = name
    }

    /// How the website matches an answer to what it asked: the kind, and the name trimmed and in small letters.
    public var key: String { LogoLook.key(kind: kind, name: name) }
}

/// What the logo service knows about a name: `POST /logos/lookup`. Without a picture, the name is shown.
public struct LogoInfo: Decodable, Equatable {
    public let id: Int64?
    public let kind: String
    public let name: String
    public let status: String?
    public let has: Bool?
    public let version: Int?
    /// The picture has a background of its own, so it goes on a white plate as it is.
    public let opaque: Bool?

    public var key: String { LogoLook.key(kind: kind, name: name) }
    public var hasPicture: Bool { has == true && id != nil }
}

public enum LogoLook {
    public static func key(kind: String, name: String) -> String {
        kind + "|" + name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Which picture reads on this page: the original for one with its own background, otherwise the dark logo on
    /// a light page and the white one on a dark page, decided by the page's colour as the website does
    /// (`logoVariant`: luminance over 140 of 255 is light). Channels are 0 to 1.
    public static func variant(opaque: Bool, background red: Double, _ green: Double, _ blue: Double) -> String {
        if opaque { return "original" }
        return 0.2126 * red * 255 + 0.7152 * green * 255 + 0.0722 * blue * 255 > 140 ? "dark" : "white"
    }
}
