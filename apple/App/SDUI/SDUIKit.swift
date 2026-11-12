// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// What every server-driven component draws with: the page's device profile, the theme with the page's and
// the node's own tokens on top, text sized by role, and pictures asked for exactly as the page names them.

private struct SDUILayoutKey: EnvironmentKey {
    static let defaultValue = SDUILayout.fallback
}

private struct SDUIThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme? = nil
}

private struct SDUIOnImageKey: EnvironmentKey {
    static let defaultValue = Color.white
}

private struct SDUIWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private struct SDUIFocusKey: EnvironmentKey {
    static let defaultValue: FocusState<String?>.Binding? = nil
}

extension EnvironmentValues {
    /// The device profile the page was fitted to: every size a component uses comes from here.
    var sduiLayout: SDUILayout {
        get { self[SDUILayoutKey.self] }
        set { self[SDUILayoutKey.self] = newValue }
    }

    /// The theme with the tokens of the scopes above this view applied, for the next scope to build on.
    var sduiTheme: AppTheme? {
        get { self[SDUIThemeKey.self] }
        set { self[SDUIThemeKey.self] = newValue }
    }

    /// The colour of text over a picture: token `onImage`.
    var sduiOnImage: Color {
        get { self[SDUIOnImageKey.self] }
        set { self[SDUIOnImageKey.self] = newValue }
    }

    /// The width the page has, in points.
    var sduiWidth: CGFloat {
        get { self[SDUIWidthKey.self] }
        set { self[SDUIWidthKey.self] = newValue }
    }

    /// The page's focus: which node has it, by ID.
    var sduiFocus: FocusState<String?>.Binding? {
        get { self[SDUIFocusKey.self] }
        set { self[SDUIFocusKey.self] = newValue }
    }
}

extension SDUILayout {
    func sp(_ step: String) -> CGFloat { CGFloat(space(step)) }
    var gap: CGFloat { CGFloat(cardGap) }
    var margin: CGFloat { CGFloat(sideMargin) }
    var compact: Bool { breakpoint == "compact" }
    var phone: Bool { formFactor == "phone" }
}

/// A scope's colour tokens on top of the theme, for a node and everything in it.
private struct SDUIScope: ViewModifier {
    @Environment(\.sduiTheme) private var theme
    @EnvironmentObject private var model: AppModel
    let tokens: [String: String]

    func body(content: Content) -> some View {
        if tokens.isEmpty {
            content
        } else {
            let scoped = SDUITheme.apply(tokens, to: theme ?? model.appTheme)
            let palette = Palette(scoped)
            let over = SDUITheme.onImage(tokens)
            content
                .environment(\.sduiTheme, scoped)
                .environment(\.palette, palette)
                .environment(\.sduiOnImage, tokens["onImage"] == nil ? Color.white : Color(.sRGB, red: over.red, green: over.green, blue: over.blue, opacity: over.alpha))
                .tint(palette.accentText)
        }
    }
}

/// Text at a role's size from the page's device profile, following the person's own text size where the
/// system has one: the profile's numbers are the sizes at the default setting.
private struct SDUIRoleFont: ViewModifier {
    @Environment(\.sduiLayout) private var layout
    @Environment(\.sduiDraw) private var draw
    @Environment(\.dynamicTypeSize) private var typeSize
    let role: String
    let weight: Font.Weight?

    static func style(_ role: String) -> UIFont.TextStyle {
        switch role {
        case "display", "pageTitle": return .title1
        case "heading": return .title2
        case "title": return .headline
        case "caption", "badge": return .caption1
        default: return .body
        }
    }

    func body(content: Content) -> some View {
        // Read so that this is worked out again when the person changes their text size.
        _ = typeSize
        let size = UIFontMetrics(forTextStyle: SDUIRoleFont.style(role)).scaledValue(for: CGFloat(layout.textSize(role)))
        // The size is the device's (layout.text); the typeface and weight the theme's (docs/THEMES.md, Shape and type).
        return content.font(draw.font(role, size: size, weight: weight))
    }
}

extension View {
    func sduiScope(_ tokens: [String: String]) -> some View { modifier(SDUIScope(tokens: tokens)) }

    /// A module's own screen, drawn by this app, in the module's colours from the theme (`/theme` modules).
    func moduleScope(_ module: String) -> some View { modifier(ModuleScope(module: module)) }

    /// One of the five text roles: `pageTitle`, `heading`, `title`, `body`, `caption`.
    func sduiFont(_ role: String, weight: Font.Weight? = nil) -> some View { modifier(SDUIRoleFont(role: role, weight: weight)) }

    /// A node's place in the page's focus, where a remote or a keyboard moves it.
    @ViewBuilder func sduiFocusable(_ focus: FocusState<String?>.Binding?, _ id: String) -> some View {
        if let focus {
            self.focused(focus, equals: id)
        } else {
            self
        }
    }

    /// A line limit that is nothing when the part isn't limited.
    func sduiLines(_ limit: Int?) -> some View { lineLimit(limit.flatMap { $0 > 0 ? $0 : nil }) }
}

/// A picture as a page names it. The address already carries the width to ask for, so it's asked for as it is
/// and decoded no bigger than it was sent: an Apple TV HD has 2 GB for everything. While it loads, and if it
/// fails, its place is token `bg3` with the kind's icon in `fg2`. Leaving the screen cancels it.
struct SDUIPicture: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.displayScale) private var displayScale
    let picture: SDUIImageRef?
    /// The system symbol drawn when there's no picture, on purpose or because it failed.
    var symbol = "photo"
    /// Fitted inside on a plain tile (a channel's logo, a title's logo) rather than cropped to fill.
    var contain = false
    /// Nothing at all while there's no picture: a backdrop behind a page.
    var blank = false
    /// The width it's drawn at in points, where that's less than it was asked for at.
    var shownWidth: CGFloat?
    @State private var image: CGImage?

    var body: some View {
        Rectangle()
            .fill(blank ? Color.clear : palette.card)
            .overlay {
                if let image {
                    if contain {
                        Image(decorative: image, scale: 1).resizable().scaledToFit().padding(8)
                    } else {
                        Image(decorative: image, scale: 1).resizable().scaledToFill()
                    }
                } else if !blank {
                    Image(systemName: symbol)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .clipped()
            .accessibilityHidden(true)
            .task(id: picture?.url) { await load() }
    }

    private func load() async {
        guard let picture, let url = client.mediaURL(picture.url) else {
            image = nil
            return
        }
        // No bigger than it was asked for, and no bigger than it's drawn.
        var pixels = max(picture.width, picture.height, 64)
        if let shownWidth, shownWidth > 0 {
            let drawn = Int(shownWidth * displayScale / CGFloat(min(picture.ratio, 1)))
            pixels = min(pixels, max(drawn, 64))
        }
        let key = "\(url.absoluteString)#\(pixels)" as NSString
        if let cached = ArtCache.shared.object(forKey: key) {
            image = cached
            return
        }
        image = nil
        guard let data = try? await client.imageData(url), !Task.isCancelled else { return }
        let decoded = await Task.detached(priority: .utility) { decodeArt(data, maxPixels: pixels) }.value
        guard let decoded, !Task.isCancelled else { return }
        ArtCache.shared.setObject(decoded, forKey: key, cost: decoded.bytesPerRow * decoded.height)
        image = decoded
    }
}

/// Grey rounded rectangles of a card's size, as many as are at least partly on screen: a row whose items
/// are on their way. They pulse unless motion is reduced (SkeletonShape follows the system's setting).
struct SDUIPlaceholderRow: View {
    @Environment(\.sduiDraw) private var draw
    @Environment(\.sduiLayout) private var layout
    let count: Int
    let width: CGFloat
    let height: CGFloat
    var circle = false

    var body: some View {
        HStack(alignment: .top, spacing: layout.gap) {
            ForEach(0..<max(count, 1), id: \.self) { _ in
                SkeletonShape(radius: circle ? width / 2 : draw.radius("Card")).frame(width: width, height: height)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, layout.margin)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

/// "Couldn't load this", with Retry: a section whose request failed.
struct SDUISectionError: View {
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    @Environment(\.sduiFocus) private var focus
    let id: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: layout.sp("m")) {
            Text("Couldn't load this").sduiFont("body").foregroundStyle(palette.textSecondary)
            Button("Retry", action: retry)
                .action()
                .sduiFocusable(focus, id)
        }
        .padding(.horizontal, layout.margin)
        .accessibilityElement(children: .contain)
    }
}

/// A section's heading, at the title size, with its subtitle and, on a touch screen, "See all" at its end.
struct SDUISectionHeading: View {
    @Environment(\.palette) private var palette
    @Environment(\.sduiLayout) private var layout
    let element: SDUIElement
    var seeAll: (() -> Void)?

    var body: some View {
        if !element.shown("title").isEmpty || !element.shown("subtitle").isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: layout.sp("s")) {
                VStack(alignment: .leading, spacing: 2) {
                    if !element.shown("title").isEmpty {
                        Text(element.shown("title"))
                            .sduiFont("title")
                            .foregroundStyle(palette.text)
                            .sduiLines(element.lineLimit("title"))
                            .accessibilityAddTraits(.isHeader)
                    }
                    if !element.shown("subtitle").isEmpty {
                        Text(element.shown("subtitle")).sduiFont("caption").foregroundStyle(palette.textSecondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if let seeAll, !layout.isTV {
                    Button(action: seeAll) {
                        HStack(spacing: 2) {
                            Text("See all")
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                        }
                        .sduiFont("caption", weight: .medium)
                        .foregroundStyle(palette.textSecondary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("See all, \(element.shown("title"))")
                }
            }
            .padding(.horizontal, layout.margin)
        }
    }
}

extension View {
    /// `onChange` in the form each system wants: Apple TV's oldest system here already has the newer one.
    @ViewBuilder func sduiOnChange<Value: Equatable>(of value: Value, _ action: @escaping (Value) -> Void) -> some View {
        #if os(tvOS)
        self.onChange(of: value) { _, now in action(now) }
        #else
        if #available(iOS 17, visionOS 1, *) {
            self.onChange(of: value) { _, now in action(now) }
        } else {
            self.onChange(of: value, perform: action)
        }
        #endif
    }
}

private struct ModuleScope: ViewModifier {
    @EnvironmentObject private var model: AppModel
    let module: String

    func body(content: Content) -> some View {
        content.sduiScope(model.modulePalettes[module] ?? [:])
    }
}

// MARK: - The theme's corners and type

/// The resolved theme's corners, typefaces and the server's name (`GET /theme`), on a server that has them.
struct ThemeStyle: Equatable {
    var shape: [String: Double]
    var type: ResolvedTheme.ThemeType?
    var brand: ResolvedTheme.Brand?
}

/// How a server-driven node is drawn from the theme (the server's docs/THEMES.md, SDUI tokens): a component's rounded
/// part → its shape token in the catalogue → that token's corner in the resolved theme; a text role → its typeface and
/// weight. Against a server without them, the same corners and weights the app always drew.
struct SDUIDraw {
    var catalog: SDUICatalog = .builtIn
    var style: ThemeStyle?

    /// The corners this app drew before themes said: the default theme's own (radius 10).
    static let fallback: [String: Double] = [
        "radius": 10, "card": Double(Tokens.Radius.md), "button": Double(Tokens.Radius.md), "field": Double(Tokens.Radius.md),
        "row": Double(Tokens.Radius.md), "thumb": Double(Tokens.Radius.sm), "badge": Double(Tokens.Radius.xs),
        "image": Double(Tokens.Radius.lg), "sheet": Double(Tokens.Radius.lg), "dialog": 20, "chip": 999, "pill": 999,
    ]

    /// A rounded part's corner in points: `part` of `component` (or of the card style, which comes first).
    func radius(_ component: String, _ part: String = "corner", style cardStyle: String? = nil) -> CGFloat {
        let name = cardStyle.flatMap { catalog.cardStyle($0)?.tokens?.shape?[part] }
            ?? catalog.componentTokens[component]?.shape?[part]
            ?? SDUIDraw.defaultShape(component, part)
        let value = style?.shape[name] ?? SDUIDraw.fallback[name] ?? Double(Tokens.Radius.md)
        return CGFloat(max(0, min(value, 999)))
    }

    /// The part's shape token where the catalogue doesn't say (an older server).
    private static func defaultShape(_ component: String, _ part: String) -> String {
        switch part {
        case "badge", "code": return "badge"
        case "art", "thumb": return component == "Banner" ? "card" : "thumb"
        case "button": return "button"
        case "season", "chip", "segment": return "chip"
        case "row": return "row"
        case "still", "poster": return "card"
        default:
            switch component {
            case "Hero", "Banner", "Image", "NativeView": return "image"
            case "Button": return "button"
            case "SearchBox": return "field"
            case "ListItem": return "row"
            default: return "card"
            }
        }
    }

    /// A text role's typeface: the first of the theme's families this device has, else the system's.
    func font(_ role: String, size: CGFloat, weight explicit: Font.Weight?) -> Font {
        let typeRole = catalog.typeRoles[role] ?? SDUIDraw.defaultRoles[role] ?? SDUITypeRole(family: "body", weight: "body")
        let weight = explicit ?? SDUIDraw.weight(style?.type?.weights[typeRole.weight] ?? SDUIDraw.defaultWeights[typeRole.weight] ?? 400)
        let monospaced = typeRole.family == "mono"
        for family in style?.type?.families(typeRole.family) ?? [] {
            let name = family.trimmingCharacters(in: .whitespaces)
            if ["system-ui", "-apple-system", "sans-serif", "ui-sans-serif", "BlinkMacSystemFont"].contains(name) { break }
            if ["ui-monospace", "monospace", "SFMono-Regular"].contains(name) { return .system(size: size, weight: weight, design: .monospaced) }
            if UIFont(name: name, size: size) != nil { return .custom(name, fixedSize: size).weight(weight) }
        }
        return .system(size: size, weight: weight, design: monospaced ? .monospaced : .default)
    }

    static let defaultRoles: [String: SDUITypeRole] = [
        "display": SDUITypeRole(family: "display", weight: "heading"),
        "pageTitle": SDUITypeRole(family: "display", weight: "heading"), "heading": SDUITypeRole(family: "display", weight: "heading"),
        "title": SDUITypeRole(family: "body", weight: "strong"), "body": SDUITypeRole(family: "body", weight: "body"),
        "caption": SDUITypeRole(family: "body", weight: "body"), "badge": SDUITypeRole(family: "body", weight: "strong"),
    ]
    static let defaultWeights: [String: Int] = ["body": 400, "medium": 500, "strong": 600, "heading": 700]

    /// A CSS weight as the system's nearest.
    static func weight(_ css: Int) -> Font.Weight {
        switch css {
        case ..<250: return .thin
        case ..<350: return .light
        case ..<450: return .regular
        case ..<550: return .medium
        case ..<640: return .semibold
        case ..<750: return .bold
        case ..<850: return .heavy
        default: return .black
        }
    }
}

private struct SDUIDrawKey: EnvironmentKey { static let defaultValue = SDUIDraw() }

extension EnvironmentValues {
    var sduiDraw: SDUIDraw {
        get { self[SDUIDrawKey.self] }
        set { self[SDUIDrawKey.self] = newValue }
    }
}
