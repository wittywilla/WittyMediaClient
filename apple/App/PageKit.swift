import SwiftUI
import WittyKit
#if canImport(UIKit)
import UIKit
#endif

// The pieces the phone and tablet pages are made of, measured from the server's own website at phone size:
// docs/APP-DESIGN.md, One mobile design with the website, Components. Everything is drawn in the theme's roles,
// so every theme, uploaded or made with the theme maker, looks right. Apple TV keeps its own parts.

// MARK: - Type

/// The website's sizes, as fonts that still follow the person's text size.
enum PageType {
    /// The hero's title and an item's: 30 semibold.
    case display
    /// A page's heading: 24 semibold.
    case title
    /// Above a row or a group: 20 semibold.
    case section
    /// Sentences: 15.
    case body
    /// Rows and tiles: 15 medium.
    case label
    /// A library tile's name, a placeholder poster's title: 15 semibold.
    case strong
    /// Buttons and a poster's title: 14 semibold.
    case button
    /// Facts and explanations: 13.
    case secondary
    /// "See all", a chip: 13 medium.
    case action
    /// Badges, a group's name: 12 medium.
    case caption
    /// What's under a poster's title, a library's count: 12.
    case small

    var size: CGFloat {
        switch self {
        case .display: return 30
        case .title: return 24
        case .section: return 20
        case .body, .label, .strong: return 15
        case .button: return 14
        case .secondary, .action: return 13
        case .caption, .small: return 12
        }
    }

    var weight: Font.Weight {
        switch self {
        case .display, .title, .section, .strong, .button: return .semibold
        case .label, .action, .caption: return .medium
        case .body, .secondary, .small: return .regular
        }
    }

    /// Letters a little closer in the big headings, as on the website.
    var tracking: CGFloat {
        switch self {
        case .display: return -0.66
        case .title: return -0.5
        case .section: return -0.24
        default: return 0
        }
    }

    /// The system style each grows with.
    var style: Font.TextStyle {
        switch self {
        case .display: return .largeTitle
        case .title: return .title2
        case .section: return .title3
        case .body, .label, .strong: return .subheadline
        case .button: return .subheadline
        case .secondary, .action: return .footnote
        case .caption, .small: return .caption
        }
    }
}

private struct PageFontModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize
    let type: PageType
    var italic = false

    func body(content: Content) -> some View {
        let font = Font.system(size: Self.scaled(type.size, type.style, typeSize), weight: type.weight)
        content.font(italic ? font.italic() : font).tracking(type.tracking)
    }

    static func scaled(_ size: CGFloat, _ style: Font.TextStyle, _ typeSize: DynamicTypeSize) -> CGFloat {
        #if canImport(UIKit)
        let traits = UITraitCollection(preferredContentSizeCategory: typeSize.category)
        return UIFontMetrics(forTextStyle: style.uiStyle).scaledValue(for: size, compatibleWith: traits)
        #else
        return size
        #endif
    }
}

#if canImport(UIKit)
private extension DynamicTypeSize {
    var category: UIContentSizeCategory {
        switch self {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}

private extension Font.TextStyle {
    var uiStyle: UIFont.TextStyle {
        switch self {
        #if os(tvOS)
        case .largeTitle: return .title1
        #else
        case .largeTitle: return .largeTitle
        #endif
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        default: return .body
        }
    }
}
#endif

extension View {
    func pageFont(_ type: PageType, italic: Bool = false) -> some View {
        modifier(PageFontModifier(type: type, italic: italic))
    }
}

// MARK: - Buttons

/// The website's buttons on a page: Primary in the accent, Ghost outlined, Secondary in `card`.
enum PageButtonKind {
    case primary, ghost, secondary
}

/// 44 high, 16 inside, the theme's medium radius, words in 14 semibold with an 18 icon 8 before them.
struct PageButtonStyle: ButtonStyle {
    var kind: PageButtonKind = .secondary
    var wide = false
    /// Only an icon, such as "⋯": a 44 square.
    var square = false

    func makeBody(configuration: Configuration) -> some View {
        PageButtonBody(label: configuration.label, pressed: configuration.isPressed, kind: kind, wide: wide, square: square)
    }
}

private struct PageButtonBody<Label: View>: View {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let label: Label
    let pressed: Bool
    let kind: PageButtonKind
    let wide: Bool
    let square: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
        let fill: Color = switch kind {
        case .primary: palette.accent
        case .secondary: palette.card
        case .ghost: .clear
        }
        label
            .pageFont(.button)
            .labelStyle(PageLabelStyle())
            .foregroundStyle(kind == .primary ? palette.onAccent : palette.text)
            .tint(kind == .primary ? palette.onAccent : palette.text)
            .lineLimit(1)
            .padding(.horizontal, square ? 0 : Tokens.Space.s4)
            .frame(minWidth: 44, maxWidth: wide ? .infinity : nil, minHeight: 44)
            .background(shape.fill(fill))
            .overlay { if kind == .ghost { shape.strokeBorder(palette.text.opacity(0.2), lineWidth: 1) } }
            .contentShape(shape)
            .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
            .opacity(enabled ? (pressed ? 0.85 : 1) : 0.55)
            .animation(.easeOut(duration: Tokens.Motion.press), value: pressed)
    }
}

/// An 18 icon 8 before the words.
private struct PageLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Tokens.Space.s2) {
            configuration.icon.font(.system(size: 15, weight: .semibold)).frame(width: 18, height: 18)
            configuration.title
        }
    }
}

extension View {
    func pageButton(_ kind: PageButtonKind, wide: Bool = false) -> some View {
        buttonStyle(PageButtonStyle(kind: kind, wide: wide))
    }

    /// A Ghost button with only an icon: "⋯".
    func squareButton(_ kind: PageButtonKind = .ghost) -> some View {
        buttonStyle(PageButtonStyle(kind: kind, square: true))
    }
}

// MARK: - Section title

/// 20 semibold, and on the right its action in 13 medium `textSecondary` with a chevron.
struct SectionHead: View {
    @Environment(\.palette) private var palette
    let title: String
    var action = "See all"
    var route: Route?
    /// Or, instead of a route, what pressing it does here.
    var tap: (() -> Void)?

    private var link: some View {
        HStack(spacing: 2) {
            Text(action)
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
        }
        .pageFont(.action)
        .foregroundStyle(palette.textSecondary)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    var body: some View {
        HStack(alignment: .center, spacing: Tokens.Space.s4) {
            Text(title)
                .pageFont(.section)
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if let route {
                NavigationLink(value: route) { link }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(action), \(title)")
            } else if let tap {
                Button(action: tap) { link }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(action), \(title)")
            }
        }
    }
}

/// A group's name over its things: `SORT`, `LIBRARIES`. Caption, upper case, `textHint`.
struct CaptionLabel: View {
    @Environment(\.palette) private var palette
    let words: String
    init(_ words: String) { self.words = words }

    var body: some View {
        Text(words.uppercased())
            .pageFont(.caption)
            .tracking(0.8)
            .foregroundStyle(palette.textHint)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Posters

/// No artwork: a gradient from the title's own colour (the avatar rule) to `card`, with the title in 15 semibold
/// white over its lower third, on the colour, so it reads in every theme.
struct PlaceholderArt: View {
    @Environment(\.palette) private var palette
    let title: String
    /// Small cards have room for fewer lines; none leaves the title off, for a card that names itself.
    var lines = 3

    var body: some View {
        // The website's phone placeholder: the title's colour rising from the card's, solid by 64%, with the title
        // in white over the lower third. Too small to read (72 or less), the colour alone.
        let colour = Color(hex: AvatarLook.colour(for: title))
        GeometryReader { geo in
            LinearGradient(stops: [.init(color: palette.card, location: 0), .init(color: colour, location: 0.64)], startPoint: .top, endPoint: .bottom)
                .overlay(alignment: .bottomLeading) {
                    if lines > 0, geo.size.width > 72 {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(min(lines, 3))
                            .multilineTextAlignment(.leading)
                            .padding(Tokens.Space.s3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
        }
        .accessibilityHidden(true)
    }
}

/// The website's poster card: the poster 2:3 (square for music) with the theme's medium radius and how far
/// through it is; 8 under it the title in 14 semibold, two lines, and the facts in 12 `textHint`.
struct PosterCard: View {
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    let subtitle: String
    let url: URL?
    var progress: Double?
    var aspect: CGFloat = 2.0 / 3.0
    /// The row's card width, or nil to fill a grid's column.
    var width: CGFloat?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(aspect, contentMode: .fit)
                .overlay { PosterArt(url: url, title: title, width: width ?? 160) }
                .overlay(alignment: .bottom) {
                    if let progress {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.white.opacity(0.28))
                                Rectangle().fill(palette.accent).frame(width: geo.size.width * min(max(progress, 0), 1))
                            }
                        }
                        .frame(height: 3)
                        .accessibilityHidden(true)
                    }
                }
                // A hairline inside the edge, so dark artwork keeps its shape on a dark page.
                .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                .clipShape(shape)
            Text(title)
                .pageFont(.button)
                .foregroundStyle(palette.text)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Tokens.Space.s2)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .pageFont(.small)
                    .foregroundStyle(palette.textHint)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
        }
        .frame(width: width, alignment: .leading)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// A poster, or the placeholder when there's none. The server answers 404 for a missing picture.
struct PosterArt: View {
    @Environment(\.client) private var client
    @Environment(\.displayScale) private var displayScale
    let url: URL?
    let title: String
    var width: CGFloat
    @State private var image: CGImage?
    @State private var missing = false

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else if missing || url == nil {
                PlaceholderArt(title: title, lines: width < 90 ? 2 : 3)
            } else {
                PlaceholderArt(title: title).opacity(0)
                    .background(SkeletonShape())
            }
        }
        .clipped()
        .accessibilityHidden(true)
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { return }
        let pixels = Int(width * displayScale)
        let key = "\(url.absoluteString)#\(pixels)" as NSString
        if let cached = ArtCache.shared.object(forKey: key) {
            image = cached
            return
        }
        guard let data = try? await client.imageData(url) else {
            if !Task.isCancelled { missing = true }
            return
        }
        let decoded = await Task.detached(priority: .utility) { decodeArt(data, maxPixels: pixels) }.value
        guard !Task.isCancelled else { return }
        guard let decoded else {
            missing = true
            return
        }
        ArtCache.shared.setObject(decoded, forKey: key, cost: decoded.bytesPerRow * decoded.height)
        image = decoded
    }
}

// MARK: - Libraries and categories

extension Library {
    /// The website's icon for each kind of library (web/src/icons.tsx, `libIcon`), as a symbol.
    var symbol: String {
        // Filled, as the website's are.
        switch type {
        case "games": return "gamecontroller.fill"
        case "photos": return "photo.fill"
        case "shorts": return "rectangle.portrait.on.rectangle.portrait.fill"
        case "channels", "musicvideos": return "play.rectangle.fill"
        case "radio": return "radio.fill"
        case "movies": return "film.fill"
        case "shows": return "tv.fill"
        case "anime": return "star.fill"
        case "music": return "music.note"
        case "podcasts": return "mic.fill"
        case "audiobooks": return "headphones"
        case "books": return "book.closed.fill"
        case "videos": return "video.fill"
        default: return "opticaldisc.fill"
        }
    }

    /// "35 titles", "6 episodes", as the website counts.
    var countWords: String { LibraryWords.count(itemCount ?? 0, type: type) }
}

/// 64 high, 10 inside, `panel` with a hairline, the large radius: a 38 icon square in `accent` at 14% with the
/// icon in `accentText`, then 10 after it the name in 15 semibold over the count in 12 `textHint`.
struct LibraryTile: View {
    @Environment(\.palette) private var palette
    let library: Library

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous)
        HStack(spacing: 10) {
            Image(systemName: library.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.accentText)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(palette.accent.opacity(0.14)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(library.name).pageFont(.strong).foregroundStyle(palette.text).lineLimit(1)
                Text(library.countWords).pageFont(.small).foregroundStyle(palette.textHint).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(minHeight: 64)
        .background(shape.fill(palette.panel))
        .overlay(shape.strokeBorder(palette.border, lineWidth: 1))
        .contentShape(shape)
        .accessibilityElement(children: .combine)
    }
}

/// The website's category card (`.lib-cat`): 16:9 with the theme's radius, a picture of something in it over a
/// gradient in the name's own colour, the scrim over its lower 60%, and in white 16 in from the left and 12 up
/// the name in 20 semibold over the count in 13 at 90%. A small shadow under it.
struct CategoryCard: View {
    @Environment(\.palette) private var palette
    @Environment(\.client) private var client
    let name: String
    let count: Int?
    let art: CategoryArt?
    /// 220 on a phone: the website's `clamp(220px, 26vw, 340px)`.
    var width: CGFloat = 220

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
        let height = width * 9 / 16
        let colours = CategoryLook.colours(name)
        let ends = CategoryLook.ends(degrees: 155, aspect: 16.0 / 9.0)
        Color.clear
            .frame(width: width, height: height)
            .background(LinearGradient(colors: [Color(hex: colours.from), Color(hex: colours.to)],
                                       startPoint: UnitPoint(x: ends.start.x, y: ends.start.y), endPoint: UnitPoint(x: ends.end.x, y: ends.end.y)))
            .overlay {
                // A picture that won't load leaves the gradient, as the website hides a broken one.
                if let art { ArtImage(url: client.backdropURL(art), width: width, blank: true) }
            }
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [palette.scrim, palette.scrim.opacity(0)], startPoint: .bottom, endPoint: .top)
                    .frame(height: height * 0.6)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    // Over a picture, so white in every theme, as the website's `--on-image`.
                    Text(name).pageFont(.section).multilineTextAlignment(.leading)
                    if let count {
                        Text("\(count) \(count == 1 ? "title" : "titles")").pageFont(.secondary).opacity(0.9)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Tokens.Space.s4)
                .padding(.bottom, Tokens.Space.s3)
            }
            .clipShape(shape)
            // The website's `--e-1`: resting artwork.
            .shadow(color: .black.opacity(0.16), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
            .contentShape(shape)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(count.map { "\(name), \($0) \($0 == 1 ? "title" : "titles")" } ?? name)
    }
}

/// The hero's darkening from the bottom: `background` at 100%, 94% at 34%, 72% at 56% and none at 82%.
struct HeroShade: View {
    @Environment(\.palette) private var palette

    var body: some View {
        LinearGradient(stops: [
            .init(color: palette.background, location: 0),
            .init(color: palette.background.opacity(0.94), location: 0.34),
            .init(color: palette.background.opacity(0.72), location: 0.56),
            .init(color: palette.background.opacity(0), location: 0.82),
        ], startPoint: .bottom, endPoint: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Chips

/// 32 high, 12 inside, fully round, 13 medium. The chosen one is filled with `raised` in `text`; the others are
/// `textSecondary`. The button around it is 44 high, so it's easy to hit.
struct ChipStyle: ButtonStyle {
    var chosen = false

    func makeBody(configuration: Configuration) -> some View {
        ChipBody(label: configuration.label, pressed: configuration.isPressed, chosen: chosen)
    }
}

private struct ChipBody<Label: View>: View {
    @Environment(\.palette) private var palette
    let label: Label
    let pressed: Bool
    let chosen: Bool

    var body: some View {
        // The website's `.chip`: 44 high on a touch screen, outlined in the text colour at 20%, and the chosen one
        // inverted, in every theme.
        label
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(chosen ? palette.background : pressed ? palette.text : palette.textSecondary)
            .padding(.horizontal, Tokens.Space.s3)
            .frame(minHeight: 44)
            .background(Capsule().fill(chosen ? palette.text : (pressed ? palette.text.opacity(0.07) : Color.clear)))
            .overlay(Capsule().strokeBorder(chosen ? palette.text : palette.text.opacity(0.2), lineWidth: 1))
            .contentShape(Capsule())
            .accessibilityAddTraits(chosen ? [.isSelected] : [])
    }
}

extension View {
    func chip(chosen: Bool = false) -> some View { buttonStyle(ChipStyle(chosen: chosen)) }
}

// MARK: - Loading

/// Grey shapes where a page's content is coming: `card` at 60%, with a slow 1.2 s shimmer that stands still
/// with Reduce Motion. Never an empty page.
struct SkeletonShape: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var radius: CGFloat = Tokens.Radius.md
    @State private var phase: CGFloat = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(palette.card.opacity(0.6))
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        let band = max(geo.size.width * 0.6, 60)
                        LinearGradient(colors: [.clear, palette.text.opacity(0.06), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: band)
                            .offset(x: -band + phase * (geo.size.width + band))
                    }
                    .clipShape(shape)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1 }
            }
            .accessibilityHidden(true)
    }
}

/// A row of grey posters with a grey section title over it.
struct SkeletonRow: View {
    @Environment(\.metrics) private var metrics
    var count = 4

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s6) {
            SkeletonShape(radius: Tokens.Radius.sm).frame(width: 160, height: 22).padding(.vertical, 11)
            HStack(alignment: .top, spacing: Tokens.Space.s4) {
                ForEach(0..<count, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                        SkeletonShape().aspectRatio(2.0 / 3.0, contentMode: .fit)
                        SkeletonShape(radius: Tokens.Radius.xs).frame(height: 12)
                        SkeletonShape(radius: Tokens.Radius.xs).frame(width: metrics.cardWidth * 0.5, height: 10)
                    }
                    .frame(width: metrics.cardWidth)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        .padding(.leading, metrics.gutter)
        .accessibilityHidden(true)
    }
}

/// Grey posters filling a grid, three across a phone.
struct SkeletonGrid: View {
    @Environment(\.metrics) private var metrics
    var count = 9

    var body: some View {
        LazyVGrid(columns: posterColumns(metrics), alignment: .leading, spacing: Tokens.Space.s6) {
            ForEach(0..<count, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                    SkeletonShape().aspectRatio(2.0 / 3.0, contentMode: .fit)
                    SkeletonShape(radius: Tokens.Radius.xs).frame(height: 12)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

/// The website's `.grid`: as many columns of at least the card's width as fit, 16 apart. On a phone, 104 wide in
/// a page with 16 at each side: floor((width − 16) / 120) of them, three on most phones and two on the smallest.
func posterColumns(_ metrics: Metrics) -> [GridItem] {
    if metrics.cardWidth <= 104 {
        let width = screenSize.width
        let count = max(2, Int((width - 16) / 120))
        return Array(repeating: GridItem(.flexible(), spacing: Tokens.Space.s4, alignment: .top), count: count)
    }
    return [GridItem(.adaptive(minimum: metrics.cardWidth, maximum: metrics.cardWidth * 1.3), spacing: Tokens.Space.s4, alignment: .top)]
}

/// The screen's size, for the website's sizes in vw and vh. Vision Pro has no screen: a window's usual size.
var screenSize: CGSize {
    #if os(visionOS)
    return CGSize(width: 1280, height: 720)
    #else
    return UIScreen.main.bounds.size
    #endif
}

// MARK: - Empty

/// When there's honestly nothing: a round icon, what that means, and what to do.
struct EmptyState: View {
    @Environment(\.palette) private var palette
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: Tokens.Space.s2) {
            // The website's `.empty`: a 26 icon in `textHint` on a 56 circle of `card`, the title 17, the words 14.
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textHint)
                .frame(width: 56, height: 56)
                .background(Circle().fill(palette.card))
                .padding(.bottom, Tokens.Space.s4 - Tokens.Space.s1)
                .accessibilityHidden(true)
            Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(palette.text).multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
            if !detail.isEmpty {
                Text(detail).font(.system(size: 14)).foregroundStyle(palette.textSecondary).multilineTextAlignment(.center)
                    .frame(maxWidth: 46 * 7.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 64)
        .frame(maxWidth: .infinity)
    }
}
