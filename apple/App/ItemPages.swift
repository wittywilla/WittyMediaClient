import SwiftUI
import WittyKit

// An item (a film, an episode, a video, a disc) and a show on a phone and a tablet, as the server's website draws
// them at phone size (web/src/pages/ItemPage.tsx, ShowPage.tsx, components/edit/TitleExtras.tsx, and the detail
// rules in styles.css and player.css). The words and which rows go where are WittyKit's TitlePage.swift. Apple TV
// has its own pages: ItemView and ShowView in BrowseViews.swift choose.

// MARK: - Shared by both pages

/// The season the show's page should open at, as the website's `?season=`: the routes to a show carry only its id.
@MainActor
private enum ShowSeasonAsked {
    private static var asked: [Int64: Int] = [:]

    static func ask(_ season: Int?, of show: Int64) { asked[show] = season }
    static func take(_ show: Int64) -> Int? { asked.removeValue(forKey: show) }
}

/// Links inside a line of text that go to one of the server's pages, as the website's do.
private enum TitlePageLink {
    static let scheme = "wittypage:"

    static func url(_ path: String) -> URL? { URL(string: scheme + path) }

    static func path(_ url: URL) -> String? {
        let text = url.absoluteString
        guard text.hasPrefix(scheme) else { return nil }
        return String(text.dropFirst(scheme.count))
    }
}

/// The legal notices are the same on every page of a server, so they're asked for once.
@MainActor
private enum TitleLegalWords {
    private static var known: [String: LegalNotices] = [:]

    static func load(_ client: WittyClient) async -> LegalNotices? {
        if let notices = known[client.base] { return notices }
        guard let notices = try? await client.legalNotices() else { return nil }
        known[client.base] = notices
        return notices
    }
}

/// A picture from the server, decoded at the size it's shown and kept with the others.
private func titlePicture(_ client: WittyClient, _ url: URL?, pixels: Int) async -> CGImage? {
    guard let url else { return nil }
    let key = "\(url.absoluteString)#\(pixels)" as NSString
    if let cached = ArtCache.shared.object(forKey: key) { return cached }
    guard let data = try? await client.imageData(url) else { return nil }
    let decoded = await Task.detached(priority: .utility) { decodeArt(data, maxPixels: pixels) }.value
    if let decoded { ArtCache.shared.setObject(decoded, forKey: key, cost: decoded.bytesPerRow * decoded.height) }
    return decoded
}

/// Pressed, it dims a little and shrinks a touch, as the website's buttons do.
private struct TitlePress: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: Tokens.Motion.press), value: configuration.isPressed)
    }
}

/// The backdrop across the top, 38% of the window high (240 to 560). The picture itself fades out from 40% of the
/// way down, so there's no line where it ends, and a shade of the page's colour rises over it from the bottom.
private struct TitleBackdrop: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.displayScale) private var displayScale
    let url: URL?
    let height: CGFloat
    @State private var image: CGImage?

    var body: some View {
        GeometryReader { geo in
            if let image {
                // Covering the box, a quarter of the way down the picture, as `background-position: center 25%`.
                let width = CGFloat(image.width), tall = CGFloat(image.height)
                let scale = max(geo.size.width / max(width, 1), geo.size.height / max(tall, 1))
                Image(decorative: image, scale: 1)
                    .resizable()
                    .frame(width: width * scale, height: tall * scale)
                    .offset(x: (geo.size.width - width * scale) / 2, y: (geo.size.height - tall * scale) * 0.25)
            }
        }
        .frame(height: height)
        .clipped()
        .mask(LinearGradient(stops: [.init(color: .black, location: 0.4), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
        .overlay(
            LinearGradient(stops: [
                .init(color: palette.background, location: 0),
                .init(color: palette.background.opacity(0.7), location: 0.3),
                .init(color: palette.background.opacity(0.35), location: 0.65),
                .init(color: palette.background.opacity(0.15), location: 1),
            ], startPoint: .bottom, endPoint: .top)
        )
        .accessibilityHidden(true)
        .task(id: url) { image = await titlePicture(client, url, pixels: Int(screenSize.width * displayScale)) }
    }
}

/// The poster: 132 wide, the large radius, with the large shadow. Blank in `card` where there's none, and a frame of
/// the video is shown whole on a colour of its own, worked out from the title.
private struct TitlePoster: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.displayScale) private var displayScale
    let url: URL?
    /// The frame's colour, for a poster that is a frame of the video.
    var frameHue: Int?
    @State private var image: CGImage?

    static let width: CGFloat = 132

    private func colour(_ hue: Int, _ saturation: Double, _ lightness: Double) -> Color {
        let (r, g, b) = TitleLook.rgb(hue: Double(hue), saturation: saturation, lightness: lightness)
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous)
        let width = Self.width
        ZStack {
            if let hue = frameHue {
                // linear-gradient(170deg, hsl(h 26% 26%), hsl(h+40 34% 11%))
                LinearGradient(colors: [colour(hue, 0.26, 0.26), colour(hue + 40, 0.34, 0.11)],
                               startPoint: UnitPoint(x: 0.41, y: 0), endPoint: UnitPoint(x: 0.59, y: 1))
            } else {
                palette.card
            }
            if let image {
                if frameHue != nil {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                        .frame(width: width, height: width * 9 / 16)
                        .clipped()
                        .shadow(color: .black.opacity(0.4), radius: 9, y: 6)
                } else {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                        .frame(width: width, height: width * 1.5)
                        .clipped()
                }
            }
        }
        .frame(width: width, height: width * 1.5)
        .clipShape(shape)
        .background(shape.fill(palette.card).shadow(color: .black.opacity(0.45), radius: 15, y: 10))
        .accessibilityHidden(true)
        .task(id: url) { image = await titlePicture(client, url, pixels: Int(width * 2 * displayScale)) }
    }
}

/// The title in 28 to 29 on a phone, with its soft shadow; or the title's logo where it has one (no wider than 420
/// or the column, no taller than 160). The words stay until the logo has come, and if it can't come.
private struct TitleHeading: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @ScaledMetric(relativeTo: .largeTitle) private var grow: CGFloat = 100
    let title: String
    let logo: URL?
    let width: CGFloat
    @State private var image: CGImage?

    var body: some View {
        let size = CGFloat(TitleLook.titleSize(width: Double(screenSize.width))) * grow / 100
        Group {
            if let image {
                let aspect = CGFloat(image.width) / max(CGFloat(image.height), 1)
                let shown = min(min(420, width), 160 * aspect, CGFloat(image.width))
                Image(decorative: image, scale: 1)
                    .resizable()
                    .frame(width: shown, height: shown / aspect)
            } else {
                Text(title)
                    .font(.system(size: size, weight: .semibold))
                    .tracking(-0.022 * size)
                    .foregroundStyle(palette.text)
                    .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
        .task(id: logo) {
            image = nil
            guard logo != nil else { return }
            image = await titlePicture(client, logo, pixels: 840)
        }
    }
}

/// The website's `.meta` and `.title-facts`: things in rows that wrap, each in the middle of its row's height.
/// Something wider than the column gets the column's width and wraps inside it.
private struct TitleWrapRow: Layout {
    var spacing: CGFloat = Tokens.Space.s4
    var rowSpacing: CGFloat = 2

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[(Int, CGSize)]] {
        var rows: [[(Int, CGSize)]] = [[]]
        var used: CGFloat = 0
        for (index, view) in subviews.enumerated() {
            let ideal = view.sizeThatFits(.unspecified)
            let size = ideal.width > width ? view.sizeThatFits(ProposedViewSize(width: width, height: nil)) : ideal
            if used > 0, used + spacing + size.width > width {
                rows.append([])
                used = 0
            }
            used += (used > 0 ? spacing : 0) + size.width
            rows[rows.count - 1].append((index, size))
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var height: CGFloat = 0
        var widest: CGFloat = 0
        for (number, row) in rows(subviews, width: width).enumerated() where !row.isEmpty {
            widest = max(widest, row.map(\.1.width).reduce(0, +) + spacing * CGFloat(row.count - 1))
            height += (row.map(\.1.height).max() ?? 0) + (number > 0 ? rowSpacing : 0)
        }
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) where !row.isEmpty {
            let height = row.map(\.1.height).max() ?? 0
            var x = bounds.minX
            for (index, size) in row {
                subviews[index].place(at: CGPoint(x: x, y: y + (height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += height + rowSpacing
        }
    }
}

extension View {
    /// The dot before a fact, 10 to its left in the gap. The row is clipped, so one starting a line has none.
    fileprivate func factDot(_ shown: Bool, _ palette: Palette) -> some View {
        overlay(alignment: .leading) {
            if shown {
                Text("·").font(.system(size: 14)).foregroundStyle(palette.textHint).fixedSize().offset(x: -10).accessibilityHidden(true)
            }
        }
    }
}

/// A rating box: 20 high, outlined in the text colour at 20%, 11 semibold.
private struct TitlePill: View {
    @Environment(\.palette) private var palette
    let words: String

    var body: some View {
        Text(words)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.22)
            .foregroundStyle(palette.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, Tokens.Space.s2)
            .frame(minHeight: 20)
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.xs, style: .continuous).strokeBorder(palette.text.opacity(0.2), lineWidth: 1))
    }
}

/// ★ 7.9, the star in `warn`.
private struct TitleStar: View {
    @Environment(\.palette) private var palette
    let rating: Double

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill").font(.system(size: 12)).foregroundStyle(palette.warn).frame(width: 14, height: 14)
            Text(String(format: "%.1f", rating))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: "Rated %.1f", rating))
    }
}

/// A studio's, a network's or a streaming service's logo from the logo service, or its name. A logo with its own
/// background is on a white plate; any other comes white for a dark theme and dark for a light one.
private struct TitleBrandMark: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.displayScale) private var displayScale
    let name: String
    let logo: LogoAnswer?
    /// The room it has: the logo is as big as fits in it, and never bigger than it was drawn.
    let box: CGSize
    var size: CGFloat = 12
    @State private var image: CGImage?

    private var url: URL? {
        guard let logo, logo.has == true else { return nil }
        return client.logoImageURL(logo, variant: logo.opaque == true ? "original" : palette.isLight ? "dark" : "white")
    }

    var body: some View {
        Group {
            if let image {
                let plate = logo?.opaque == true
                let room = CGSize(width: box.width - (plate ? 8 : 0), height: box.height - (plate ? 8 : 0))
                let width = CGFloat(image.width), height = max(CGFloat(image.height), 1)
                let scale = min(room.width / max(width, 1), room.height / height, 1)
                let picture = Image(decorative: image, scale: 1).resizable().frame(width: width * scale, height: height * scale)
                if plate {
                    picture.padding(Tokens.Space.s1).background(RoundedRectangle(cornerRadius: Tokens.Radius.xs, style: .continuous).fill(Color.white))
                } else {
                    picture
                }
            } else {
                Text(name)
                    .font(.system(size: size, weight: .semibold))
                    .tracking(-0.012 * size)
                    .multilineTextAlignment(.center)
                    .lineLimit(box.height < 30 ? 1 : nil)
                    .frame(maxWidth: box.width)
            }
        }
        .accessibilityLabel(name)
        .task(id: url) { image = await titlePicture(client, url, pixels: Int(240 * displayScale)) }
    }
}

/// A studio or a streaming service as a tile: 120 by 56 in `card`, the theme's radius.
private struct TitleBrandTile: View {
    @Environment(\.palette) private var palette
    let name: String
    let logo: LogoAnswer?

    var body: some View {
        TitleBrandMark(name: name, logo: logo, box: CGSize(width: 120 - Tokens.Space.s3 * 2, height: 56 - Tokens.Space.s2 * 2))
            .foregroundStyle(palette.text)
            .frame(width: 120, height: 56)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(palette.card))
            .contentShape(Rectangle())
    }
}

/// Small print in `textHint` with links in `accentText`, underlined so colour isn't the only sign.
private struct TitleFinePrint: View {
    @Environment(\.palette) private var palette
    let words: AttributedString

    init(markdown: String) {
        var text = (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
        for run in text.runs where run.link != nil { text[run.range].underlineStyle = Text.LineStyle.single }
        words = text
    }

    init(words: String, link: String, path: String) {
        var text = AttributedString(words + " ")
        var go = AttributedString(link)
        go.link = TitlePageLink.url(path)
        go.underlineStyle = Text.LineStyle.single
        text.append(go)
        self.words = text
    }

    var body: some View {
        Text(words)
            .font(.system(size: 12))
            .lineSpacing(4)
            .foregroundStyle(palette.textHint)
            .tint(palette.accentText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One of the server's short legal notices, with its link to the Legal page.
private struct TitleLegalLine: View {
    let notices: LegalNotices?
    let kind: String

    var body: some View {
        if let note = notices?.notice(kind) {
            TitleFinePrint(words: note.words, link: note.link, path: note.path)
        }
    }
}

/// "‹ Back to library", at the end of the page: 44 high and round, `textSecondary` in 14 semibold.
private struct TitleBackLink: View {
    let words: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Tokens.Space.s1) {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold)).frame(width: 18, height: 18)
                Text(words).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            }
            .padding(.leading, Tokens.Space.s1)
            .padding(.trailing, Tokens.Space.s3)
            .frame(minHeight: 44)
        }
        .buttonStyle(TitleBackLinkStyle())
        .padding(.leading, -Tokens.Space.s1)
    }
}

private struct TitleBackLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { TitleBackLinkBody(label: configuration.label, pressed: configuration.isPressed) }
}

private struct TitleBackLinkBody<Label: View>: View {
    @Environment(\.palette) private var palette
    let label: Label
    let pressed: Bool

    var body: some View {
        label
            .foregroundStyle(pressed ? palette.text : palette.textSecondary)
            .background(Capsule().fill(pressed ? palette.text.opacity(0.07) : Color.clear))
            .contentShape(Capsule())
    }
}

/// A heading inside the extras: 17, 8 above what it names.
private struct TitleExtrasHeading: View {
    @Environment(\.palette) private var palette
    let words: String

    var body: some View {
        Text(words)
            .font(.system(size: 17, weight: .semibold))
            .tracking(-0.2)
            .foregroundStyle(palette.text)
            .accessibilityAddTraits(.isHeader)
            .padding(.bottom, Tokens.Space.s2)
    }
}

// MARK: - The sheet behind "⋯"

/// One row of a sheet: an icon, its words, and what choosing it does once the sheet has gone.
private struct TitleSheetRow: Identifiable {
    let id: String
    let icon: String
    let words: String
    var disabled = false
    let run: () -> Void
}

private struct TitleSheetHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The website's sheet of rows from the bottom of a phone (ui/RowSheet.tsx): `panel`, its title in 20 with a Close
/// button, and the rows together on a `card`, each 52 high with a 20 icon in `textSecondary` and its words in 15
/// medium, a hairline between them. It's as tall as what's in it.
private struct TitleRowSheet: View {
    @Environment(\.palette) private var palette
    let title: String
    let rows: [TitleSheetRow]
    /// A row, or nil for Close.
    let choose: (TitleSheetRow?) -> Void
    @State private var height: CGFloat

    init(title: String, rows: [TitleSheetRow], choose: @escaping (TitleSheetRow?) -> Void) {
        self.title = title
        self.rows = rows
        self.choose = choose
        _height = State(initialValue: 20 + 44 + 16 + 52 * CGFloat(rows.count) + 20 + 34)
    }

    var body: some View {
        GeometryReader { outer in
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: Tokens.Space.s3) {
                    Text(title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                    Button { choose(nil) } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)) }
                        .squareButton()
                        .accessibilityLabel("Close")
                }
                .padding(.bottom, Tokens.Space.s4)
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        Button { choose(row) } label: {
                            HStack(spacing: Tokens.Space.s3) {
                                Image(systemName: row.icon).font(.system(size: 17)).foregroundStyle(palette.textSecondary).frame(width: 20, height: 20)
                                Text(row.words).font(.system(size: 15, weight: .medium)).foregroundStyle(palette.text)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(TitleSheetRowStyle(divider: index > 0))
                        .disabled(row.disabled)
                    }
                }
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).fill(palette.card))
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous))
            }
            .padding(.horizontal, Tokens.Space.s4)
            .padding(.vertical, Tokens.Space.s5)
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { geo in Color.clear.preference(key: TitleSheetHeight.self, value: geo.size.height) })
            .frame(maxHeight: .infinity, alignment: .top)
            .onPreferenceChange(TitleSheetHeight.self) { measured in
                let next = measured + outer.safeAreaInsets.bottom
                if measured > 0, abs(next - height) > 0.5 { height = next }
            }
        }
        .background(palette.panel.ignoresSafeArea())
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.hidden)
        .modifier(TitleSheetLook(fill: palette.panel))
    }
}

private struct TitleSheetLook: ViewModifier {
    let fill: Color

    func body(content: Content) -> some View {
        if #available(iOS 16.4, tvOS 16.4, visionOS 1.0, *) {
            content.presentationBackground(fill).presentationCornerRadius(Tokens.Radius.xl)
        } else {
            content
        }
    }
}

private struct TitleSheetRowStyle: ButtonStyle {
    let divider: Bool

    func makeBody(configuration: Configuration) -> some View {
        TitleSheetRowBody(label: configuration.label, pressed: configuration.isPressed, divider: divider)
    }
}

private struct TitleSheetRowBody<Label: View>: View {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var enabled
    let label: Label
    let pressed: Bool
    let divider: Bool

    var body: some View {
        label
            .padding(.horizontal, Tokens.Space.s4)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(pressed ? palette.text.opacity(0.12) : Color.clear)
            .overlay(alignment: .top) {
                if divider { Rectangle().fill(palette.border).frame(height: 1).padding(.leading, Tokens.Space.s4 + 20 + Tokens.Space.s3) }
            }
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

/// What a page has open over it: the rows behind "⋯", or Save.
private enum TitleSheet: String, Identifiable {
    case more, save
    var id: String { rawValue }
}

// MARK: - What both pages show under the synopsis

/// The website's TitleExtras: who made it, its editions and tags, its studios, other versions, bonus features, and
/// where it's listed if the owner turned that on.
private struct TitleExtrasView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let target: TitleTarget
    let attached: TitleAttached
    let listings: TitleListings?
    let libraryId: Int64?
    let logos: [String: LogoAnswer]
    let legal: LegalNotices?

    private func go(_ route: Route) { model.path.append(route) }

    private func goToPage(_ path: String) { go(.page(path)) }

    @ViewBuilder private var facts: some View {
        let director = attached.director ?? ""
        let editions = attached.edition ?? []
        let tags = attached.tags ?? []
        if !director.isEmpty || !editions.isEmpty || !tags.isEmpty {
            TitleWrapRow(spacing: Tokens.Space.s3, rowSpacing: Tokens.Space.s2) {
                if !director.isEmpty {
                    (Text(target == .show ? "Created by" : "Directed by").foregroundColor(palette.textHint) + Text(" " + director).foregroundColor(palette.text))
                        .font(.system(size: 14))
                }
                ForEach(editions, id: \.self) { TitlePill(words: $0) }
                ForEach(tags, id: \.self) { tag in
                    Button(tag) { if let libraryId { goToPage(TitleLook.tagPath(library: libraryId, tag)) } }.chip()
                }
            }
        }
    }

    private struct BrandLink: Identifiable {
        let name: String
        let path: String
        var id: String { name }
    }

    private func brands(_ kind: String, _ names: [BrandLink]) -> some View {
        TitleWrapRow(spacing: Tokens.Space.s2, rowSpacing: Tokens.Space.s2) {
            ForEach(names) { brand in
                Button { goToPage(brand.path) } label: { TitleBrandTile(name: brand.name, logo: logos[LogoAnswer.key(kind, brand.name)]) }
                    .buttonStyle(TitlePress())
            }
        }
    }

    private var cardWidth: CGFloat { metrics.cardWidth <= 104 ? 232 : 260 }

    private func bonusCard(_ extra: TitleAttached.Extra) -> some View {
        let item = extra.item
        let wideTitle = item.showTitle?.isEmpty == false ? item.showTitle! : item.title
        let sub = item.showId != nil
            ? [item.episodeLabel, item.title].filter { !$0.isEmpty }.joined(separator: " · ")
            : [item.year.map(String.init) ?? "", TitleLook.runtime(item.runtimeSec)].filter { !$0.isEmpty }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: Tokens.Space.s1) {
            Button { go(.item(item.id)) } label: {
                PosterCard(title: wideTitle, subtitle: sub, url: client.posterURL(item), progress: item.progressFraction, aspect: 16.0 / 9.0, width: cardWidth)
            }
            .buttonStyle(TitlePress())
            Text(TitleLook.extraName(extra.link?.extraType)).font(.system(size: 15)).foregroundStyle(palette.textHint)
        }
        .frame(width: cardWidth, alignment: .leading)
    }

    var body: some View {
        let studios = attached.studios ?? []
        let versions = attached.versions ?? []
        let extras = attached.extras ?? []
        let platforms = listings?.platforms ?? []
        let logoShown = studios.contains { logos[LogoAnswer.key("studio", $0)]?.has == true }
            || platforms.contains { logos[LogoAnswer.key("platform", $0.name)]?.has == true }
        VStack(alignment: .leading, spacing: Tokens.Space.s4) {
            facts
            if !studios.isEmpty, let libraryId {
                brands("studio", studios.map { BrandLink(name: $0, path: TitleLook.brandPath("studio", $0, library: libraryId)) })
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Studios")
            }
            if !versions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    TitleExtrasHeading(words: "Other versions")
                    TitleWrapRow(spacing: Tokens.Space.s2, rowSpacing: Tokens.Space.s2) {
                        ForEach(versions, id: \.item.id) { version in
                            Button(TitleLook.versionLabel(version)) { go(.item(version.item.id)) }.pageButton(.secondary)
                        }
                    }
                }
            }
            if !extras.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    TitleExtrasHeading(words: "Bonus features")
                    // The website's row: out to the screen's edges, 12 above the cards and 16 below.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: Tokens.Space.s4) {
                            ForEach(extras, id: \.item.id) { bonusCard($0) }
                        }
                        .padding(.horizontal, metrics.gutter)
                        .padding(.top, Tokens.Space.s3)
                        .padding(.bottom, Tokens.Space.s4)
                    }
                    .padding(.horizontal, -metrics.gutter)
                }
            }
            if !platforms.isEmpty, let listings, let libraryId {
                VStack(alignment: .leading, spacing: 0) {
                    TitleExtrasHeading(words: "Also listed on")
                    brands("platform", platforms.map { BrandLink(name: $0.name, path: TitleLook.platformPath(library: libraryId, $0.key)) })
                    (Text("Nothing plays from these services. ").fontWeight(.semibold)
                        + Text(TitleLook.listedNote(listings) { $0.formatted(date: .numeric, time: .omitted) }))
                        .font(.system(size: 13))
                        .foregroundStyle(palette.textHint)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Tokens.Space.s2)
                    TitleLegalLine(notices: legal, kind: "listings").padding(.top, Tokens.Space.s4)
                }
            }
            if logoShown { TitleLegalLine(notices: legal, kind: "logos") }
        }
    }
}

/// Grey shapes where an item or a show is coming, as the website's: the backdrop, the poster, and lines for the
/// caption, the title, the facts, the buttons and the synopsis.
private struct TitleSkeleton: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let hero: CGFloat

    private func line(_ width: CGFloat?, _ height: CGFloat = 15, radius: CGFloat = Tokens.Radius.xs) -> some View {
        SkeletonShape(radius: radius).frame(width: width, height: height).frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    var body: some View {
        GeometryReader { geo in
            let column = geo.size.width - metrics.gutter * 2
            VStack(alignment: .leading, spacing: 0) {
                LinearGradient(colors: [palette.card.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom).frame(height: hero)
                VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                    SkeletonShape(radius: Tokens.Radius.lg).frame(width: TitlePoster.width, height: TitlePoster.width * 1.5).padding(.bottom, Tokens.Space.s5 - Tokens.Space.s3)
                    line(80, 12)
                    line(column * 0.6, 32)
                    line(column * 0.4)
                    HStack(spacing: Tokens.Space.s2) {
                        SkeletonShape().frame(width: 144, height: 44)
                        SkeletonShape().frame(width: 96, height: 44)
                        SkeletonShape().frame(width: 44, height: 44)
                    }
                    line(nil)
                    line(nil)
                    line(column * 0.7)
                }
                .padding(.top, -96)
                .padding(.horizontal, metrics.gutter)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

// MARK: - An item

struct ItemPage: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let id: Int64
    @State private var item: Item?
    @State private var facts = ItemFacts()
    @State private var attached: TitleAttached?
    @State private var listings: TitleListings?
    @State private var logos: [String: LogoAnswer] = [:]
    @State private var legal: LegalNotices?
    @State private var error = ""
    @State private var sheet: TitleSheet?
    /// What a row of "⋯" does, once its sheet has gone.
    @State private var chosen: (() -> Void)?

    private func load() async {
        do {
            let (fresh, more) = try await client.itemPage(id)
            error = ""
            if fresh != item { item = fresh }
            if more != facts { facts = more }
        } catch {
            let words = model.handle(error)
            if item == nil, !words.isEmpty { self.error = words }
        }
    }

    private func loadExtras() async {
        async let found = try? client.attached(.item, id)
        async let listed = try? client.listings(.item, id)
        async let notices = TitleLegalWords.load(client)
        let (fresh, places, words) = await (found, listed, notices)
        attached = fresh
        listings = places
        legal = words
        let names = (fresh?.studios ?? []).map { (kind: "studio", name: $0) } + (places?.platforms ?? []).map { (kind: "platform", name: $0.name) }
        if !names.isEmpty, let answers = try? await client.lookUpLogos(names) {
            logos = Dictionary(answers.map { (LogoAnswer.key($0.kind, $0.name), $0) }, uniquingKeysWith: { first, _ in first })
        }
    }

    private var isAdmin: Bool { model.user?.isAdmin == true }
    private var canSave: Bool { model.user.map { TitleLook.canSave(isAdmin: $0.isAdmin == true, kind: $0.kind) } ?? false }

    private func go(_ route: Route) { model.path.append(route) }

    private func library(_ id: Int64?) -> Library? { id.flatMap { id in model.libraries.first { $0.id == id } } }

    private func openLibrary(_ id: Int64?) {
        if let library = library(id) { model.openLibrary(library) } else if let id { go(.page("/library/\(id)")) }
    }

    private func openShow(_ show: Int64, season: Int?) {
        ShowSeasonAsked.ask(season, of: show)
        go(.show(show))
    }

    // MARK: Parts

    private func crumbs(_ item: Item) -> some View {
        let crumbs = TitleLook.crumbs(item, libraryName: library(item.libraryId)?.name)
        return TitleWrapRow(spacing: 6, rowSpacing: 2) {
            ForEach(Array(crumbs.enumerated()), id: \.offset) { index, crumb in
                if index > 0 {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textHint)
                        .frame(width: 14, height: 14).accessibilityHidden(true)
                }
                switch crumb.goes {
                case .library(let library):
                    Button(crumb.words) { openLibrary(library) }.buttonStyle(.plain)
                case .show(let show, let season):
                    Button(crumb.words) { openShow(show, season: season) }.buttonStyle(.plain)
                case .nowhere:
                    Text(crumb.words)
                }
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(palette.textSecondary)
    }

    private func genreLinks(_ item: Item) -> Text {
        let (shown, more) = TitleLook.genres(item.genres)
        var line = AttributedString()
        for (index, genre) in shown.enumerated() {
            if index > 0 { line.append(AttributedString(", ")) }
            var link = AttributedString(genre)
            if let library = item.libraryId { link.link = TitlePageLink.url(TitleLook.genrePath(library: library, genre)) }
            line.append(link)
        }
        if more { line.append(AttributedString("…")) }
        return Text(line)
    }

    /// The facts under the title: when it aired or its year, its length, its rating box, ★ and four genres.
    private func meta(_ item: Item) -> some View {
        let first = (item.aired?.isEmpty == false ? item.aired : nil) ?? item.year.map(String.init)
        let runtime = TitleLook.runtime(item.runtimeSec)
        let rated = item.contentRating?.isEmpty == false ? item.contentRating : nil
        let genres = !(item.genres ?? []).isEmpty
        let stars = facts.rating.flatMap { $0 > 0 ? $0 : nil }
        // Every fact has its dot but the rating box and the one after it.
        return TitleWrapRow(spacing: Tokens.Space.s4, rowSpacing: 2) {
            if let first { Text(first).factDot(true, palette) }
            if !runtime.isEmpty { Text(runtime).factDot(true, palette) }
            if let rated { TitlePill(words: rated) }
            if let stars { TitleStar(rating: stars).factDot(rated == nil, palette) }
            if genres { genreLinks(item).factDot(!(rated != nil && stars == nil), palette) }
        }
        .font(.system(size: 14))
        .foregroundStyle(palette.textSecondary)
        .tint(palette.textSecondary)
        .clipped()
    }

    private func moreButton() -> some View {
        Button { sheet = .more } label: { Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold)) }
            .squareButton()
            .accessibilityLabel("More")
    }

    @ViewBuilder private func actions(_ item: Item) -> some View {
        let rows = moreRows(item)
        if TitleLook.isDisc(item) {
            // A disc: Insert, and "⋯"; no Save on a phone. What Insert does is said under them.
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                HStack(spacing: Tokens.Space.s2) {
                    NavigationLink(value: Route.page(TitleLook.insertPath(item, facts))) {
                        Label("Insert \(TitleLook.discName(item))", systemImage: "opticaldisc")
                    }
                    .pageButton(.primary, wide: true)
                    .disabled(!TitleLook.playable(item, facts))
                    if !rows.isEmpty { moreButton() }
                }
                Text(TitleLook.discHint(item, facts, admin: isAdmin))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textHint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            HStack(spacing: Tokens.Space.s2) {
                if item.isPlayable {
                    // The server decides where Resume goes; nothing to resume means start at the beginning.
                    NavigationLink(value: Route.player(item.id, startOver: item.resumeSeconds == nil)) {
                        Label(item.resumeSeconds == nil ? "Play" : "Resume", systemImage: "play.fill")
                    }
                    .pageButton(.primary, wide: true)
                    .accessibilityLabel(item.resumeSeconds == nil ? "Play" : "Resume from \(TitleLook.clock(item.progress?.positionSec))")
                } else if !item.isRigGame {
                    // What this app doesn't play itself opens where the server plays it.
                    NavigationLink(value: Route.page(ServerPages.path(item))) {
                        Label("Open", systemImage: "arrow.up.forward.square")
                    }
                    .pageButton(.primary, wide: true)
                }
                if canSave {
                    Button { sheet = .save } label: { Label("Save", systemImage: "plus") }.pageButton(.secondary)
                }
                if !rows.isEmpty { moreButton() }
                if !item.isPlayable, item.isRigGame { Spacer(minLength: 0) }
            }
        }
    }

    /// "⋯": what the row has no room for, each going where the website's does. The server's own page has an
    /// administrator's tools: its edit window at Artwork or Match, and Refresh and Disc settings in its "⋯".
    private func moreRows(_ item: Item) -> [TitleSheetRow] {
        TitleLook.moreRows(item, facts, admin: isAdmin).map { row in
            let playable = TitleLook.playable(item, facts)
            switch row {
            case .resumeDisc(let words, let path), .discFromStart(let words, let path):
                return TitleSheetRow(id: "play", icon: "play.fill", words: words, disabled: !playable) { go(.page(path)) }
            case .mainMenu(let path):
                return TitleSheetRow(id: "menu", icon: "line.3.horizontal", words: row.words, disabled: !playable) { go(.page(path)) }
            case .discSettings:
                return TitleSheetRow(id: "disc", icon: "gearshape", words: row.words) { go(.page(TitleLook.editPath(.item, item.id))) }
            case .playFromStart:
                return TitleSheetRow(id: "start", icon: "play.fill", words: row.words) { go(.player(item.id, startOver: true)) }
            case .nextEpisode(let next):
                return TitleSheetRow(id: "next", icon: "forward.end.fill", words: row.words) { go(.item(next)) }
            case .artwork:
                return TitleSheetRow(id: "art", icon: "photo", words: row.words) { go(.page(TitleLook.editPath(.item, item.id, section: "artwork"))) }
            case .edit:
                return TitleSheetRow(id: "edit", icon: "pencil", words: row.words) { go(.page(TitleLook.editPath(.item, item.id, section: "match"))) }
            case .refresh:
                return TitleSheetRow(id: "refresh", icon: "arrow.clockwise", words: row.words) { go(.page(TitleLook.editPath(.item, item.id))) }
            }
        }
    }

    private func factsTable(_ item: Item, width: CGFloat) -> some View {
        let all = TitleLook.facts(item, facts, admin: isAdmin)
        let columns = Array(repeating: GridItem(.flexible(), spacing: Tokens.Space.s6, alignment: .topLeading),
                            count: TitleLook.factColumns(width: Double(width)))
        return VStack(alignment: .leading, spacing: Tokens.Space.s4) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: Tokens.Space.s4) {
                ForEach(all.filter { !$0.wide }, id: \.key) { fact in factCell(fact) }
            }
            ForEach(all.filter(\.wide), id: \.key) { fact in factCell(fact) }
        }
        .padding(.top, Tokens.Space.s5)
        .overlay(alignment: .top) { Rectangle().fill(palette.border).frame(height: 1) }
    }

    private func factCell(_ fact: TitleLook.Fact) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(fact.key.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.77)
                .foregroundStyle(palette.textHint)
            Text(fact.value)
                .font(fact.wide ? .system(size: 12, design: .monospaced) : .system(size: 14, weight: .medium))
                .foregroundStyle(fact.wide ? palette.textSecondary : palette.text)
                .lineSpacing(fact.wide ? 3 : 0)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: The page

    @ViewBuilder private func page(_ item: Item, hero: CGFloat, column: CGFloat) -> some View {
        let overview = item.overview ?? ""
        let credit = TitleLook.credit(provider: facts.provider, id: facts.providerId)
        let scrambled = TitleLook.isDisc(item) && facts.disc?.scrambled == true
        let posterURL = (facts.poster ?? "").isEmpty ? nil : client.posterURL(item)
        let backdrop = (facts.poster ?? "").isEmpty && (facts.backdrop ?? "").isEmpty ? nil : client.backdropURL(item)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TitleBackdrop(url: backdrop, height: hero)
                VStack(alignment: .leading, spacing: 0) {
                    TitlePoster(url: posterURL, frameHue: TitleLook.isFrame(poster: facts.poster) ? TitleLook.artHue(item.title) : nil)
                    VStack(alignment: .leading, spacing: 0) {
                        if !TitleLook.crumbs(item, libraryName: library(item.libraryId)?.name).isEmpty {
                            crumbs(item).padding(.bottom, Tokens.Space.s2)
                        }
                        TitleHeading(title: item.title, logo: attached?.hasLogo == true ? client.titleLogoURL(.item, item.id, version: item.updatedAt) : nil, width: column)
                            .padding(.bottom, Tokens.Space.s2)
                        if let tagline = item.tagline, !tagline.isEmpty, !item.isRigGame {
                            Text(tagline)
                                .font(.system(size: 17).italic())
                                .foregroundStyle(palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.bottom, Tokens.Space.s2)
                        }
                        meta(item).padding(.bottom, Tokens.Space.s5)
                        if !error.isEmpty { ProblemLine(error).padding(.bottom, Tokens.Space.s3) }
                        if item.isRigGame { RigPlayPanel(item: item).padding(.bottom, Tokens.Space.s5) }
                        actions(item)
                        if !overview.isEmpty {
                            Text(overview)
                                .font(.system(size: 15))
                                .lineSpacing(6)
                                .foregroundStyle(palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, Tokens.Space.s6)
                        }
                        if let credit {
                            TitleFinePrint(markdown: credit).padding(.top, overview.isEmpty ? Tokens.Space.s6 : Tokens.Space.s5)
                        }
                        if scrambled {
                            Text("This disc is encrypted, so it can't be played: encrypted media isn't supported, and nothing here bypasses copy protection.")
                                .font(.system(size: 14))
                                .lineSpacing(3)
                                .foregroundStyle(palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 10)
                                .padding(.horizontal, Tokens.Space.s3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(palette.danger.opacity(0.11)))
                                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).strokeBorder(palette.danger.opacity(0.5), lineWidth: 1))
                                .padding(.top, credit != nil ? 0 : overview.isEmpty ? Tokens.Space.s6 : Tokens.Space.s5)
                        }
                        factsTable(item, width: column).padding(.top, Tokens.Space.s6)
                        if let attached {
                            TitleExtrasView(target: .item, attached: attached, listings: listings, libraryId: item.libraryId, logos: logos, legal: legal)
                                .padding(.top, Tokens.Space.s4)
                        }
                        Group {
                            if let show = item.showId {
                                TitleBackLink(words: "Back to \(item.showTitle ?? "")") { openShow(show, season: item.season ?? -1) }
                            } else {
                                TitleBackLink(words: "Back to library") { openLibrary(item.libraryId) }
                            }
                        }
                        .padding(.top, Tokens.Space.s8)
                        TitleLegalLine(notices: legal, kind: "metadata").padding(.top, Tokens.Space.s4)
                    }
                    .padding(.top, Tokens.Space.s5)
                }
                .frame(maxWidth: column, alignment: .leading)
                .padding(.top, -96)
                .padding(.horizontal, metrics.gutter)
                #if os(iOS) || os(visionOS)
                // The page has its own notice, so the foot is the version alone, as the website hides its general one.
                PageFoot(notice: "")
                #endif
            }
            .padding(.bottom, Tokens.Space.s6)
        }
        .refreshable { await load() }
    }

    var body: some View {
        GeometryReader { outer in
            let top = outer.safeAreaInsets.top
            let hero = CGFloat(TitleLook.heroHeight(window: Double(outer.size.height + top + outer.safeAreaInsets.bottom)))
            let column = min(outer.size.width - metrics.gutter * 2, 720)
            ZStack(alignment: .top) {
                if let item {
                    page(item, hero: hero, column: column)
                } else if !error.isEmpty {
                    ProblemView(words: error, retry: { error = ""; Task { await load() } }).padding(.top, top + 48)
                } else {
                    TitleSkeleton(hero: hero)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .pageBackground(palette)
        .environment(\.openURL, OpenURLAction { url in
            guard let path = TitlePageLink.path(url) else { return .systemAction }
            go(.page(path))
            return .handled
        })
        .task(id: id) { await load() }
        .task(id: id) { await loadExtras() }
        .sheet(item: $sheet, onDismiss: {
            chosen?()
            chosen = nil
        }) { which in
            if let item {
                switch which {
                case .save:
                    SaveSheet(title: displayTitle(item), item: item.id, show: nil)
                        .environment(\.palette, palette)
                case .more:
                    TitleRowSheet(title: item.title, rows: moreRows(item)) { row in
                        chosen = row?.run
                        sheet = nil
                    }
                    .environment(\.palette, palette)
                }
            }
        }
    }
}

// MARK: - Saving

/// Watch later and the person's own collections, each with a check when this is in it. Choosing one puts it in
/// or takes it out at once. A film or an episode, or a whole show.
struct SaveSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let title: String
    let item: Int64?
    let show: Int64?
    @State private var lists: [TitleCollection]?
    @State private var holding: Set<Int64> = []
    @State private var busy: Int64?
    @State private var error = ""

    private func load() async {
        do {
            let me = model.user?.id
            async let all = client.collections()
            let inThem: [Int64]
            if let show { inThem = try await client.collectionsHolding(show: show) } else { inThem = try await client.collectionsHolding(item: item ?? 0) }
            let found = try await all
            lists = found.filter { $0.takesTitles && $0.ownerId == me }
            holding = Set(inThem)
        } catch {
            let words = model.handle(error)
            if !words.isEmpty { self.error = words }
            if lists == nil { lists = [] }
        }
    }

    private func toggle(_ list: TitleCollection?) async {
        busy = list?.id ?? -1
        defer { busy = nil }
        do {
            if let list {
                let isIn = holding.contains(list.id)
                if let show { try await client.setInCollection(list.id, show: show, !isIn) } else { try await client.setInCollection(list.id, item: item ?? 0, !isIn) }
                if isIn { holding.remove(list.id) } else { holding.insert(list.id) }
                announce(isIn ? "Taken out of \(list.name)" : "Saved to \(list.name)")
            } else {
                let made: Int64
                if let show { made = try await client.saveForLater(show: show) } else { made = try await client.saveForLater(item: item ?? 0) }
                holding.insert(made)
                announce("Saved to Watch later")
                await load()
            }
            error = ""
        } catch {
            let words = model.handle(error)
            if !words.isEmpty { self.error = words }
        }
    }

    private func row(_ name: String, icon: String, tint: String, on: Bool, list: TitleCollection?) -> some View {
        Button {
            Task { await toggle(list) }
        } label: {
            HStack(spacing: 0) {
                RowLabel(icon: icon, tint: tint, title: name, value: list?.count.map { "\($0)" } ?? "", chevron: false)
                Group {
                    if busy == (list?.id ?? -1) {
                        ProgressView()
                    } else {
                        Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(palette.accentText).opacity(on ? 1 : 0)
                    }
                }
                .frame(width: 24)
                .padding(.trailing, Tokens.Space.s4)
            }
        }
        .rowStyle()
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                    Text(title).pageFont(.secondary).foregroundStyle(palette.textSecondary)
                    if !error.isEmpty { ProblemLine(error) }
                    if let lists {
                        let later = lists.first { $0.name.caseInsensitiveCompare("Watch later") == .orderedSame }
                        ListGroup(title: "") {
                            row("Watch later", icon: "clock", tint: "#0a6fb8", on: later.map { holding.contains($0.id) } ?? false, list: later)
                            ForEach(lists.filter { $0.id != later?.id }) { list in
                                row(list.name, icon: "square.stack", tint: "#0e7c6f", on: holding.contains(list.id), list: list)
                            }
                        }
                        Text("Your collections are on the server's Collections page, where you can make new ones.")
                            .pageFont(.secondary).foregroundStyle(palette.textHint)
                    } else {
                        SkeletonShape(radius: Tokens.Radius.lg).frame(height: 104)
                    }
                }
                .padding(Tokens.Space.s4)
            }
            .pageBackground(palette)
            .navigationTitle("Save")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.tint(palette.accentText) }
            }
        }
        .presentationDetents([.medium, .large])
        .task { await load() }
    }
}

// MARK: - A show

struct ShowPage: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let id: Int64
    @State private var detail: ShowDetail?
    @State private var facts = ShowFacts()
    @State private var attached: TitleAttached?
    @State private var listings: TitleListings?
    @State private var logos: [String: LogoAnswer] = [:]
    @State private var legal: LegalNotices?
    @State private var serverView: String?
    /// The layout chosen here, over the show's own; "" goes back to the server's.
    @State private var chosenView: String?
    @State private var season: Int?
    @State private var error = ""
    @State private var sheet: TitleSheet?
    @State private var chosen: (() -> Void)?

    private func load() async {
        do {
            let (fresh, more) = try await client.showPage(id)
            error = ""
            if fresh != detail { detail = fresh }
            if more != facts { facts = more }
        } catch {
            let words = model.handle(error)
            if detail == nil, !words.isEmpty { self.error = words }
        }
    }

    private func loadExtras() async {
        async let found = try? client.attached(.show, id)
        async let listed = try? client.listings(.show, id)
        async let notices = TitleLegalWords.load(client)
        async let prefs = try? client.prefs()
        let (fresh, places, words, server) = await (found, listed, notices, prefs)
        attached = fresh
        listings = places
        legal = words
        serverView = server?.episodeView
        await lookUpLogos()
    }

    /// The network's logo with the studios' and the services', in one question.
    private func lookUpLogos() async {
        var names = (attached?.studios ?? []).map { (kind: "studio", name: $0) } + (listings?.platforms ?? []).map { (kind: "platform", name: $0.name) }
        if let network = facts.network, !network.isEmpty { names.append((kind: "network", name: network)) }
        guard !names.isEmpty, let answers = try? await client.lookUpLogos(names) else { return }
        logos = Dictionary(answers.map { (LogoAnswer.key($0.kind, $0.name), $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var isAdmin: Bool { model.user?.isAdmin == true }
    private var canSave: Bool { model.user.map { TitleLook.canSave(isAdmin: $0.isAdmin == true, kind: $0.kind) } ?? false }

    private func go(_ route: Route) { model.path.append(route) }

    private func play(_ episode: Item) { go(.player(episode.id, startOver: episode.resumeSeconds == nil)) }

    private func setView(_ view: String) {
        chosenView = view
        // An administrator's choice is the show's, for everyone.
        guard isAdmin else { return }
        Task {
            do { try await client.setShowView(id, view) } catch { self.error = model.handle(error) }
        }
    }

    // MARK: Parts

    private func meta(_ detail: ShowDetail) -> some View {
        let show = detail.show
        let rated = facts.contentRating?.isEmpty == false ? facts.contentRating : nil
        let network = facts.network?.isEmpty == false ? facts.network : nil
        let status = facts.status?.isEmpty == false ? facts.status : nil
        let genres = (facts.genres ?? []).joined(separator: ", ")
        // Every fact has its dot but the rating box and the one after it: the network, the status or the count.
        let afterPill = rated != nil
        return TitleWrapRow(spacing: Tokens.Space.s4, rowSpacing: 2) {
            if let year = show.year { Text(String(year)).factDot(true, palette) }
            if let rated { TitlePill(words: rated) }
            if let network, let library = facts.libraryId {
                Button { go(.page(TitleLook.brandPath("network", network, library: library))) } label: {
                    TitleBrandMark(name: network, logo: logos[LogoAnswer.key("network", network)], box: CGSize(width: 120, height: 22.4), size: 14)
                }
                .buttonStyle(.plain)
                .factDot(!afterPill, palette)
            }
            if let status { Text(status).factDot(!(afterPill && network == nil), palette) }
            Text(TitleLook.seasonsLine(seasons: show.seasonCount ?? detail.seasons?.count ?? 0, episodes: show.episodeCount ?? 0))
                .factDot(!(afterPill && network == nil && status == nil), palette)
            if !genres.isEmpty { Text(genres).factDot(true, palette) }
        }
        .font(.system(size: 14))
        .foregroundStyle(palette.textSecondary)
        .clipped()
    }

    @ViewBuilder private func actions(_ detail: ShowDetail) -> some View {
        let next = detail.episodes?.first { $0.id == detail.nextUpId }
        HStack(spacing: Tokens.Space.s2) {
            if let next {
                let label = TitleLook.playLabel(next)
                Button { play(next) } label: { Label(label.words, systemImage: "play.fill") }
                    .pageButton(.primary, wide: true)
                    .accessibilityLabel(label.spoken ?? label.words)
            }
            if canSave {
                Button { sheet = .save } label: { Label("Save", systemImage: "plus") }.pageButton(.secondary)
            }
            if isAdmin {
                Button { sheet = .more } label: { Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold)) }
                    .squareButton()
                    .accessibilityLabel("More")
            }
            if next == nil { Spacer(minLength: 0) }
        }
    }

    /// An administrator's tools, on the server's own page for the show.
    private var moreRows: [TitleSheetRow] {
        [
            TitleSheetRow(id: "art", icon: "photo", words: "Artwork") { go(.page(TitleLook.editPath(.show, id, section: "artwork"))) },
            TitleSheetRow(id: "edit", icon: "pencil", words: "Edit") { go(.page(TitleLook.editPath(.show, id, section: "match"))) },
            TitleSheetRow(id: "refresh", icon: "arrow.clockwise", words: "Refresh") { go(.page(TitleLook.editPath(.show, id))) },
        ]
    }

    /// A season as its poster, 108 wide, with its name and how many are left; the chosen one ringed in `accent`.
    private func seasonTab(_ title: String, line: String, poster: URL?, chosen: Bool, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
        return Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    palette.card
                    if let poster { ArtImage(url: poster, width: 108, blank: true) }
                }
                .frame(width: 108, height: 162)
                .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                .clipShape(shape)
                .overlay {
                    if chosen {
                        RoundedRectangle(cornerRadius: Tokens.Radius.md + 4, style: .continuous)
                            .strokeBorder(palette.accent, lineWidth: 2)
                            .padding(-4)
                    }
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Tokens.Space.s2)
                if !line.isEmpty { Text(line).font(.system(size: 12)).foregroundStyle(palette.textHint) }
            }
            .frame(width: 108, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(TitlePress())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, line].filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityAddTraits(chosen ? [.isSelected, .isButton] : .isButton)
    }

    private func seasonTabs(_ detail: ShowDetail, selected: Int) -> some View {
        let others = TitleLook.otherVideos(detail)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Tokens.Space.s3) {
                ForEach(uniqued(detail.seasons ?? [])) { s in
                    seasonTab(s.displayTitle, line: TitleLook.seasonLine(s), poster: client.seasonPosterURL(detail.show, season: s.number),
                              chosen: s.number == selected) { season = s.number }
                }
                if !others.isEmpty {
                    seasonTab("Other videos", line: "\(others.count)", poster: nil, chosen: selected == -1) { season = -1 }
                }
            }
            // Room for the ring round the chosen one.
            .padding(.horizontal, Tokens.Space.s1)
            .padding(.top, Tokens.Space.s1)
            .padding(.bottom, Tokens.Space.s3)
        }
    }

    /// Layout: Cards or Playlist, and Use default when this show has its own.
    private func viewSwitch(current: String, own: Bool) -> some View {
        HStack(spacing: Tokens.Space.s3) {
            Text("Layout").font(.system(size: 13)).foregroundStyle(palette.textHint)
            HStack(spacing: 2) {
                segment("Cards", on: current == "cards") { setView("cards") }
                segment("Playlist", on: current == "list") { setView("list") }
            }
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(palette.card))
            if own {
                Button("Use default") { setView("") }
                    .buttonStyle(TitleSmallGhostStyle())
                    .accessibilityHint("Use the layout set in Settings")
            }
            Spacer(minLength: 0)
        }
    }

    private func segment(_ words: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(words)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(on ? palette.background : palette.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, Tokens.Space.s3)
                .frame(minHeight: 44)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.md - 3, style: .continuous).fill(on ? palette.text : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    // MARK: The page

    @ViewBuilder private func page(_ detail: ShowDetail, hero: CGFloat, column: CGFloat) -> some View {
        let show = detail.show
        let selected = season ?? TitleLook.openingSeason(detail, asked: nil)
        let episodes = TitleLook.episodes(detail, season: selected)
        let own = chosenView ?? facts.view ?? ""
        let view = TitleLook.episodeView(chosen: nil, show: own, server: serverView)
        let overview = show.overview ?? ""
        let network = facts.network ?? ""
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TitleBackdrop(url: client.backdropURL(show), height: hero)
                VStack(alignment: .leading, spacing: 0) {
                    TitlePoster(url: client.posterURL(show))
                    VStack(alignment: .leading, spacing: 0) {
                        TitleHeading(title: show.title, logo: attached?.hasLogo == true ? client.titleLogoURL(.show, show.id, version: show.updatedAt) : nil, width: column)
                            .padding(.bottom, Tokens.Space.s2)
                        meta(detail).padding(.bottom, Tokens.Space.s5)
                        if !error.isEmpty { ProblemLine(error).padding(.bottom, Tokens.Space.s3) }
                        actions(detail)
                        if !overview.isEmpty {
                            Text(overview)
                                .font(.system(size: 15))
                                .lineSpacing(6)
                                .foregroundStyle(palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, Tokens.Space.s6)
                        }
                        if let attached {
                            TitleExtrasView(target: .show, attached: attached, listings: listings, libraryId: facts.libraryId, logos: logos, legal: legal)
                                .padding(.top, overview.isEmpty ? Tokens.Space.s6 : Tokens.Space.s5)
                        }
                        seasonTabs(detail, selected: selected).padding(.top, Tokens.Space.s6)
                        viewSwitch(current: view, own: !own.isEmpty).padding(.top, Tokens.Space.s2).padding(.bottom, Tokens.Space.s3)
                        if view == "list" {
                            TitleEpisodeTable(episodes: episodes, open: { go(.item($0.id)) }, play: play)
                        } else {
                            VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                                ForEach(episodes) { episode in
                                    TitleEpisodeRow(episode: episode, open: { go(.item(episode.id)) }, play: { play(episode) })
                                }
                            }
                            .padding(.horizontal, -Tokens.Space.s2)
                        }
                        TitleBackLink(words: "Back to library") {
                            if let library = model.libraries.first(where: { $0.id == facts.libraryId }) {
                                model.openLibrary(library)
                            } else if let library = facts.libraryId {
                                go(.page("/library/\(library)"))
                            }
                        }
                        .padding(.top, Tokens.Space.s8)
                        if let credit = TitleLook.credit(provider: facts.provider, id: facts.providerId, show: true) {
                            TitleFinePrint(markdown: credit).padding(.top, Tokens.Space.s3)
                        }
                        TitleLegalLine(notices: legal, kind: "metadata").padding(.top, Tokens.Space.s4)
                        if !network.isEmpty, logos[LogoAnswer.key("network", network)]?.has == true {
                            TitleLegalLine(notices: legal, kind: "logos").padding(.top, Tokens.Space.s4)
                        }
                    }
                    .padding(.top, Tokens.Space.s5)
                }
                .frame(maxWidth: column, alignment: .leading)
                .padding(.top, -96)
                .padding(.horizontal, metrics.gutter)
                #if os(iOS) || os(visionOS)
                // The page has its own notice, so the foot is the version alone, as the website hides its general one.
                PageFoot(notice: "")
                #endif
            }
            .padding(.bottom, Tokens.Space.s6)
        }
        .refreshable { await load() }
    }

    var body: some View {
        GeometryReader { outer in
            let top = outer.safeAreaInsets.top
            let hero = CGFloat(TitleLook.heroHeight(window: Double(outer.size.height + top + outer.safeAreaInsets.bottom)))
            let column = min(outer.size.width - metrics.gutter * 2, 720)
            ZStack(alignment: .top) {
                if let detail {
                    page(detail, hero: hero, column: column)
                } else if !error.isEmpty {
                    ProblemView(words: error, retry: { error = ""; Task { await load() } }).padding(.top, top + 48)
                } else {
                    TitleSkeleton(hero: hero)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .pageBackground(palette)
        .environment(\.openURL, OpenURLAction { url in
            guard let path = TitlePageLink.path(url) else { return .systemAction }
            go(.page(path))
            return .handled
        })
        .onAppear { if season == nil { season = ShowSeasonAsked.take(id) } }
        .task(id: id) { await load() }
        .task(id: id) { await loadExtras() }
        .onChange(of: facts.network) { _ in Task { await lookUpLogos() } }
        .sheet(item: $sheet, onDismiss: {
            chosen?()
            chosen = nil
        }) { which in
            if let detail {
                switch which {
                case .save:
                    SaveSheet(title: detail.show.title, item: nil, show: detail.show.id)
                        .environment(\.palette, palette)
                case .more:
                    TitleRowSheet(title: detail.show.title, rows: moreRows) { row in
                        chosen = row?.run
                        sheet = nil
                    }
                    .environment(\.palette, palette)
                }
            }
        }
    }
}

/// The website's small Ghost button: 44 high on a touch screen, 12 inside, 13 semibold, outlined at 20%.
private struct TitleSmallGhostStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { TitleSmallGhostBody(label: configuration.label, pressed: configuration.isPressed) }
}

private struct TitleSmallGhostBody<Label: View>: View {
    @Environment(\.palette) private var palette
    let label: Label
    let pressed: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
        label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(palette.text)
            .lineLimit(1)
            .padding(.horizontal, Tokens.Space.s3)
            .frame(minHeight: 44)
            .background(shape.fill(pressed ? palette.text.opacity(0.07) : Color.clear))
            .overlay(shape.strokeBorder(palette.text.opacity(0.2), lineWidth: 1))
            .contentShape(shape)
    }
}

// MARK: - Episodes

/// The website's episode card: the picture 132 wide (the theme's radius) which plays it, with how far through and
/// a mark once watched; beside it the number in 12 `textHint` before the title in 15 semibold, when it aired and how
/// long it is, and two lines of what happens. Anywhere else on the row opens the episode's page.
private struct TitleEpisodeRow: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    let episode: Item
    let open: () -> Void
    let play: () -> Void

    private var thumb: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
        return ZStack {
            palette.card
            ArtImage(url: client.posterURL(episode), width: 132, blank: true)
        }
        .frame(width: 132, height: 132 * 9 / 16)
        .overlay(alignment: .bottom) {
            if let fraction = episode.progressFraction {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.white.opacity(0.28))
                        Rectangle().fill(palette.accent).frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 3)
            }
        }
        .overlay(alignment: .topTrailing) {
            if episode.progress?.watched == true {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(palette.scrim))
                    .padding(Tokens.Space.s2)
            }
        }
        .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(shape)
    }

    var body: some View {
        let line = TitleLook.episodeLine(episode)
        let number = episode.episodeLabel
        HStack(alignment: .top, spacing: Tokens.Space.s3) {
            Button(action: play) { thumb }
                .buttonStyle(TitlePress())
                .accessibilityLabel("Play \(episode.title)")
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if number.isEmpty {
                        Text(episode.title)
                    } else {
                        Text(number).font(.system(size: 12, weight: .semibold)).foregroundColor(palette.textHint)
                            + Text(" ").font(.system(size: 15)).kerning(6)
                            + Text(episode.title)
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(palette.text)
                .fixedSize(horizontal: false, vertical: true)
                if !line.isEmpty {
                    Text(line).font(.system(size: 12)).foregroundStyle(palette.textHint).padding(.top, 2)
                }
                if let overview = episode.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: 13))
                        .lineSpacing(3)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                        .padding(.top, Tokens.Space.s2)
                }
            }
            .padding(.top, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The row's own button, behind, takes a tap here and says all this to a screen reader.
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .padding(Tokens.Space.s2)
        .background {
            Button(action: open) { Color.clear.contentShape(Rectangle()) }
                .buttonStyle(TitleEpisodeRowStyle())
                .accessibilityLabel([number, episode.title, line].filter { !$0.isEmpty }.joined(separator: ", "))
                .accessibilityValue(episode.progress?.watched == true ? "Watched" : episode.progressFraction.map { "\(Int($0 * 100)) percent watched" } ?? "")
                .accessibilityHint(episode.overview ?? "")
        }
    }
}

private struct TitleEpisodeRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { TitleEpisodeRowBody(label: configuration.label, pressed: configuration.isPressed) }
}

private struct TitleEpisodeRowBody<Label: View>: View {
    @Environment(\.palette) private var palette
    let label: Label
    let pressed: Bool

    var body: some View {
        label.background(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).fill(pressed ? palette.text.opacity(0.07) : Color.clear))
    }
}

/// The website's Playlist layout: a table of the season, scrolling sideways on a phone. The picture, the number,
/// the title, when it aired, how long, watched or where it was left, and Play. A row opens the episode.
private struct TitleEpisodeTable: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    let episodes: [Item]
    let open: (Item) -> Void
    let play: (Item) -> Void

    private func head(_ words: String) -> some View {
        Text(words.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.77)
            .foregroundStyle(palette.textHint)
            .padding(.vertical, Tokens.Space.s2)
            .padding(.horizontal, Tokens.Space.s3)
    }

    private func cell<Content: View>(_ episode: Item, leading: CGFloat = Tokens.Space.s3, trailing: CGFloat = Tokens.Space.s3,
                                     @ViewBuilder _ content: () -> Content) -> some View {
        // Every cell as tall as the row's Play, so a tap anywhere on the row opens it.
        content()
            .frame(minHeight: 44)
            .padding(.vertical, 10)
            .padding(.leading, leading)
            .padding(.trailing, trailing)
            .contentShape(Rectangle())
            .onTapGesture { open(episode) }
    }

    private func state(_ episode: Item) -> some View {
        Group {
            if episode.progress?.watched == true {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).accessibilityLabel("Watched")
            } else if let at = episode.progress?.resumeSec, at > 0 {
                Text(TitleLook.clock(episode.progress?.positionSec))
            } else {
                Text("")
            }
        }
        .foregroundStyle(palette.textHint)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    head("")
                    head("#")
                    head("Title")
                    head("Aired")
                    head("Length")
                    head("")
                    head("")
                }
                Rectangle().fill(palette.text.opacity(0.2)).frame(height: 1)
                ForEach(episodes) { episode in
                    GridRow {
                        cell(episode, trailing: 0) {
                            ZStack {
                                palette.card
                                ArtImage(url: client.posterURL(episode), width: 52, blank: true)
                            }
                            .frame(width: 52, height: 52 * 9 / 16)
                            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.xs, style: .continuous))
                        }
                        cell(episode) { Text(TitleLook.playlistNumber(episode)).fontWeight(.semibold).foregroundStyle(palette.textHint) }
                        cell(episode) { Text(episode.title).foregroundStyle(palette.text) }
                        cell(episode) { Text(episode.aired ?? "").foregroundStyle(palette.textHint) }
                        cell(episode) { Text((episode.runtimeSec ?? 0) > 0 ? TitleLook.clock(episode.runtimeSec) : "").foregroundStyle(palette.text) }
                        cell(episode) { state(episode) }
                        cell(episode) {
                            Button { play(episode) } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "play.fill").font(.system(size: 12, weight: .semibold)).frame(width: 16, height: 16)
                                    Text("Play")
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.text)
                                .padding(.horizontal, Tokens.Space.s3)
                                .frame(minHeight: 44)
                                .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(palette.card))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(TitlePress())
                            .accessibilityLabel("Play \(episode.title)")
                        }
                    }
                    Rectangle().fill(palette.border).frame(height: 1)
                }
            }
            .font(.system(size: 14).monospacedDigit())
            .lineLimit(1)
        }
    }
}
