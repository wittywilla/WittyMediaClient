// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

/// What this app says about itself with every server-driven request: the server's docs/SDUI.md, "What a client sends".
public struct SDUIDevice: Equatable, Hashable, Sendable {
    /// `tvos` or `ios`.
    public var platform: String
    /// `tv`, `phone` or `tablet`.
    public var formFactor: String
    /// `hd` or `4k`, for an Apple TV.
    public var deviceClass: String?
    /// The window in points. Not sent by a television, whose canvas is fixed.
    public var viewport: SDUILayout.Size?
    public var locale: String?
    /// `reducedMotion`, `touch`, `pointer`, `keyboard`, `hdr`.
    public var capabilities: [String]
    /// The optional components this app draws. Nil sends nothing: every optional component of its revision.
    public var components: [String]?
    /// The app's own views a `NativeView` can name.
    public var views: [String]
    /// This installation's own name for itself (`device=`), so a profile's layout choice is kept for this device:
    /// letters, digits, `-` and `_`, made up once, never anything that identifies the hardware.
    public var appId: String?

    public init(platform: String, formFactor: String, deviceClass: String? = nil, viewport: SDUILayout.Size? = nil,
                locale: String? = nil, capabilities: [String] = [], components: [String]? = nil, views: [String] = []) {
        self.platform = platform
        self.formFactor = formFactor
        self.deviceClass = deviceClass
        self.viewport = viewport
        self.locale = locale
        self.capabilities = capabilities
        self.components = components
        self.views = views
    }

    /// An Apple TV. `pixelsWide` is the screen's own width in pixels: 3840 on a 4K one showing 4K, 1920 on an
    /// Apple TV HD or a 4K one set to 1080p, which gets the HD budgets and pictures.
    public static func appleTV(pixelsWide: Int, reducedMotion: Bool, hdr: Bool = false, locale: String? = nil, views: [String]) -> SDUIDevice {
        var has: [String] = []
        if reducedMotion { has.append("reducedMotion") }
        if hdr { has.append("hdr") }
        return SDUIDevice(platform: "tvos", formFactor: "tv", deviceClass: pixelsWide >= 3840 ? "4k" : "hd", locale: locale,
                          capabilities: has, views: views)
    }

    /// An iPhone or an iPad, with its window as it is now: an iPad sharing its screen sends the part it has.
    public static func touch(pad: Bool, width: Double, height: Double, reducedMotion: Bool, pointer: Bool = false,
                             keyboard: Bool = false, locale: String? = nil, views: [String]) -> SDUIDevice {
        var has = ["touch"]
        if reducedMotion { has.append("reducedMotion") }
        if pointer { has.append("pointer") }
        if keyboard { has.append("keyboard") }
        let size = width >= 1 && height >= 1 ? SDUILayout.Size(width: Int(width.rounded()), height: Int(height.rounded())) : nil
        return SDUIDevice(platform: "ios", formFactor: pad ? "tablet" : "phone", viewport: size, locale: locale, capabilities: has, views: views)
    }

    /// A name the server takes for `device=`: 1 to 64 letters, digits, `-` and `_`.
    public static func isAppId(_ name: String) -> Bool {
        (1...64).contains(name.count) && name.allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "-" || $0 == "_" }
    }

    /// A new name for this installation: the platform and twelve random letters and digits.
    public static func newAppId(platform: String) -> String {
        let letters = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return "apple-\(platform)-" + String((0..<12).map { _ in letters.randomElement() ?? "x" })
    }

    /// The breakpoint of the window, when it's known.
    public var breakpoint: String? { viewport.map { SDUILayout.breakpoint(width: Double($0.width)) } }

    /// The query every server-driven request carries, in a fixed order so the same device asks the same thing.
    public var query: [(String, String)] {
        var out: [(String, String)] = [("catalog", String(SDUI.catalog)), ("platform", platform), ("formFactor", formFactor)]
        if let deviceClass { out.append(("deviceClass", deviceClass)) }
        if let viewport, formFactor != "tv" { out.append(("viewport", "\(viewport.width)x\(viewport.height)")) }
        if let components { out.append(("components", components.isEmpty ? "none" : components.joined(separator: ","))) }
        if !views.isEmpty { out.append(("views", views.joined(separator: ","))) }
        if !capabilities.isEmpty { out.append(("capabilities", capabilities.joined(separator: ","))) }
        if let locale, !locale.isEmpty { out.append(("locale", locale)) }
        if let appId, SDUIDevice.isAppId(appId) { out.append(("device", appId)) }
        return out
    }

    /// Whether going from another window to this one needs the page asked for again: only when a breakpoint was
    /// crossed, or anything else about the device changed. Within a breakpoint the app recomputes columns itself.
    public func needsNewPage(after other: SDUIDevice) -> Bool {
        var a = self, b = other
        a.viewport = nil
        b.viewport = nil
        return a != b || breakpoint != other.breakpoint
    }

    /// A name for what was asked, for the cache: the same for every window within a breakpoint.
    public var cacheName: String {
        "\(platform)-\(formFactor)-\(deviceClass ?? "")-\(breakpoint ?? "")-\(capabilities.contains("reducedMotion") ? "rm" : "")-\(views.joined(separator: "+"))-\(locale ?? "")"
    }
}

public enum SDUIQuery {
    /// `name=value&…` with everything that isn't plainly safe percent-encoded.
    public static func encode(_ pairs: [(String, String)]) -> String {
        var safe = CharacterSet.alphanumerics
        safe.insert(charactersIn: "-._~")
        func enc(_ text: String) -> String { text.addingPercentEncoding(withAllowedCharacters: safe) ?? "" }
        return pairs.map { enc($0.0) + "=" + enc($0.1) }.joined(separator: "&")
    }

    /// A page's own parameters in a fixed order, then the device's.
    public static func page(_ params: [String: String], _ device: SDUIDevice) -> String {
        encode(params.filter { !$0.value.isEmpty }.sorted { $0.key < $1.key }.map { ($0.key, $0.value) } + device.query)
    }

    /// An address the server put in a page (`props.more.url`, a season's, `personal.url`) as a path under this
    /// app's API with the device's parameters added. Nil for anything that isn't the server-driven API's own.
    public static func path(fromServer url: String, device: SDUIDevice?) -> String? {
        var rest: Substring
        if url.hasPrefix("/api/v1/sdui/") {
            rest = url.dropFirst("/api/v1".count)
        } else if url.hasPrefix("/api/sdui/") {
            rest = url.dropFirst("/api".count)
        } else {
            return nil
        }
        guard rest.utf8.count <= 4096, !rest.contains("#"), !rest.contains(".."), !rest.contains("\\"),
              rest.unicodeScalars.allSatisfy({ $0.value > 0x20 && $0.value < 0x7f }) else { return nil }
        guard let device else { return String(rest) }
        // What the address already says wins: it is the server's own.
        let (_, said) = SDUIRouter.split(String(rest))
        let extra = device.query.filter { said[$0.0] == nil }
        if extra.isEmpty { return String(rest) }
        rest += (rest.contains("?") ? "&" : "?") + encode(extra)
        return String(rest)
    }
}
