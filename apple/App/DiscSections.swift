import SwiftUI
import WittyKit

// A DVD's or a Blu-ray's sections on its page, below the facts, as the website's DiscSections.tsx shows them (and the
// disc page's rules in styles.css): Feature Presentation with its scenes, Bonus Features, Disc Menus, and a table of
// every title on the disc. An administrator can name the feature, the scenes and the bonus features; the names are
// the server's, and its player shows them too. Each plays in the server's own disc player, as Insert does. The words
// and the addresses are WittyKit's DiscPage (TitlePage.swift).

struct DiscSections: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    let item: Item
    /// The disc's own description, for the table of its titles.
    let disc: DiscInfo?
    let admin: Bool
    let playable: Bool
    /// The page's width, for the website's rules at 700 across, and the column's, which the grids fill.
    let page: CGFloat
    let column: CGFloat
    /// A short message at the bottom of the page, as the website's toast.
    let say: (String) -> Void

    @State private var view: DiscView?
    @State private var labels = DiscLabels()
    @State private var editing = false
    @State private var allTitles = false

    private var narrow: Bool { TitleLook.isNarrow(width: Double(page)) }
    /// clamp(28px, 3.4vw, 44px) above each section's heading.
    private var sectionGap: CGFloat { CGFloat(TitleLook.sectionGap(width: Double(page))) }

    private func go(_ path: String) { model.path.append(.page(path)) }
    private func play(_ ttn: Int, scene: Int? = nil) { go(DiscPage.titlePath(item.id, ttn: ttn, chapter: scene)) }

    /// A disc that can't be read shows only the table of its titles.
    private func load() async {
        do {
            let fresh = try await client.discView(item.id)
            view = fresh
            labels = DiscLabels(fresh)
        } catch {
            if !Task.isCancelled { view = DiscView.none }
        }
    }

    private func save() async {
        do {
            _ = try await client.setDiscLabels(item.id, labels)
            editing = false
            say("Names saved")
        } catch {
            say(model.handle(error))
        }
    }

    private func titleName(_ ttn: Int) -> Binding<String> {
        Binding(get: { labels.title(ttn) }, set: { labels.setTitle(ttn, $0) })
    }

    private func sceneName(_ ttn: Int, _ scene: Int) -> Binding<String> {
        Binding(get: { labels.chapter(ttn, scene) }, set: { labels.setChapter(ttn, scene, $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let view { sections(view) } else { Color.clear.frame(height: 0) }
        }
        .task(id: item.id) { await load() }
    }

    /// Each part as far below the one before as the website's margins come to: 20 for the bar of names, the section
    /// gap before a section's heading, and 24 before the table.
    @ViewBuilder private func sections(_ view: DiscView) -> some View {
        if admin { editBar.padding(.top, Tokens.Space.s5) }
        if let main = view.main { feature(main) }
        if !view.extras.isEmpty { extras(view.extras) }
        if !view.menus.isEmpty { menus(view.menus) }
        if let summary = DiscPage.allTitlesSummary(disc) { titles(summary).padding(.top, Tokens.Space.s6) }
    }

    /// An administrator's "Name scenes & extras" on the right, or Save names and Cancel while naming.
    private var editBar: some View {
        HStack(spacing: Tokens.Space.s2) {
            Spacer(minLength: 0)
            if editing {
                Button("Save names") { Task { await save() } }.buttonStyle(TitleSmallButtonStyle(kind: .primary))
                Button("Cancel") { editing = false }.buttonStyle(TitleSmallButtonStyle(kind: .ghost))
            } else {
                Button { editing = true } label: { Label("Name scenes & extras", systemImage: "pencil") }
                    .buttonStyle(TitleSmallButtonStyle(kind: .ghost))
                    .accessibilityHint("Give the feature, scenes and bonus features your own names")
            }
        }
    }

    /// The website's `.section-title`: 20 semibold (17 for a heading inside a section), 12 above what it names.
    private func heading(_ words: String, top: CGFloat, size: CGFloat = 20) -> some View {
        Text(words)
            .font(.system(size: size, weight: .semibold))
            .tracking(-0.012 * size)
            .foregroundStyle(palette.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, top)
            .padding(.bottom, Tokens.Space.s3)
    }

    /// A scene's start or a bonus feature's length, at the bottom right of its picture.
    private func time(_ words: String) -> some View {
        Text(words)
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(Color.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.xs, style: .continuous).fill(palette.scrim))
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private func grid(_ count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Tokens.Space.s4, alignment: .top), count: count)
    }

    // MARK: Feature Presentation

    private func feature(_ main: DiscView.Title) -> some View {
        let name = DiscPage.name(main, labels, otherwise: item.title)
        let languages = DiscPage.featureLanguages(main)
        let card = RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            heading("Feature Presentation", top: sectionGap)
            DiscFeatureCard(stacked: narrow) {
                Button { play(main.ttn) } label: {
                    DiscPicture(item: item.id, ttn: main.ttn, scene: 0) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(palette.onAccent)
                            .frame(width: 56, height: 56)
                            .background(Circle().fill(palette.accent))
                            .shadow(color: .black.opacity(0.45), radius: 15, y: 10)
                    }
                }
                .buttonStyle(TitlePress())
                .disabled(!playable)
                .accessibilityLabel("Play \(name)")
                VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                    if editing {
                        DiscNameField(placeholder: item.title, text: titleName(main.ttn), label: "Feature name")
                    } else {
                        Text(name)
                            .font(.system(size: 20, weight: .semibold))
                            .tracking(-0.24)
                            .foregroundStyle(palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                    }
                    Text(DiscPage.featureLine(main))
                        .font(.system(size: 13))
                        .foregroundStyle(palette.textHint)
                        .fixedSize(horizontal: false, vertical: true)
                    if languages.isEmpty {
                        // The website's line is there when it's empty, and keeps its place in the card.
                        Color.clear.frame(height: 0)
                    } else {
                        Text(languages)
                            .font(.system(size: 13))
                            .foregroundStyle(palette.textHint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button { play(main.ttn) } label: { Label("Play feature", systemImage: "play.fill") }
                        .pageButton(.primary)
                        .disabled(!playable)
                        .fixedSize()
                }
                .padding(.trailing, Tokens.Space.s2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // 12 inside its 1-wide border, in `panel`.
            .padding(Tokens.Space.s3 + 1)
            .background(card.fill(palette.panel))
            .overlay(card.strokeBorder(palette.border, lineWidth: 1))
            if DiscPage.showsScenes(main) {
                heading("Scenes", top: Tokens.Space.s6, size: 17)
                scenes(main)
            }
        }
    }

    /// Two across a phone; wider, as many of at least 170 as fit. 16 apart.
    private func scenes(_ main: DiscView.Title) -> some View {
        LazyVGrid(columns: grid(DiscPage.sceneColumns(page: Double(page), column: Double(column))), alignment: .leading, spacing: Tokens.Space.s4) {
            ForEach(main.chapters, id: \.n) { chapter in
                VStack(alignment: .leading, spacing: 0) {
                    Button { play(main.ttn, scene: chapter.n) } label: {
                        DiscPicture(item: item.id, ttn: main.ttn, scene: chapter.n) { time(TitleLook.clock(chapter.start)) }
                    }
                    .buttonStyle(TitlePress())
                    .disabled(!playable)
                    .accessibilityLabel(DiscPage.scenePlayLabel(labels, ttn: main.ttn, scene: chapter.n))
                    if editing {
                        DiscNameField(placeholder: "Scene \(chapter.n)", text: sceneName(main.ttn, chapter.n), small: true, label: "Name of scene \(chapter.n)")
                            .padding(.top, 6)
                    } else {
                        (Text("\(chapter.n).").foregroundColor(palette.textHint) + Text(" " + DiscPage.sceneName(labels, ttn: main.ttn, scene: chapter.n)))
                            .font(.system(size: 13))
                            .foregroundColor(palette.text)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                    }
                }
            }
        }
    }

    // MARK: Bonus Features

    /// As many of at least 210 as fit, 16 apart, at every width.
    private func extras(_ extras: [DiscView.Title]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("Bonus Features", top: sectionGap)
            LazyVGrid(columns: grid(DiscPage.extraColumns(column: Double(column))), alignment: .leading, spacing: Tokens.Space.s4) {
                ForEach(Array(extras.enumerated()), id: \.element.ttn) { index, title in
                    VStack(alignment: .leading, spacing: 0) {
                        Button { play(title.ttn) } label: {
                            DiscPicture(item: item.id, ttn: title.ttn, scene: 0) { time(TitleLook.clock(title.durationSec)) }
                        }
                        .buttonStyle(TitlePress())
                        .disabled(!playable)
                        .accessibilityLabel(DiscPage.bonusPlayLabel(title, labels, index: index))
                        if editing {
                            DiscNameField(placeholder: DiscPage.bonusName(index), text: titleName(title.ttn), small: true, label: "Name of title \(title.ttn)")
                                .padding(.top, 6)
                        } else {
                            (Text(DiscPage.name(title, labels, otherwise: DiscPage.bonusName(index))) + Text(" · title \(title.ttn)").foregroundColor(palette.textHint))
                                .font(.system(size: 13))
                                .foregroundColor(palette.text)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 6)
                        }
                    }
                }
            }
        }
    }

    // MARK: Disc Menus

    /// Shortcuts into the disc's own menus: tiles in `card` with a 1-wide border, 44 high, 16 inside, 8 apart.
    private func menus(_ menus: [DiscView.Menu]) -> some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            heading("Disc Menus", top: sectionGap)
            TitleWrapRow(spacing: Tokens.Space.s2, rowSpacing: Tokens.Space.s2) {
                ForEach(Array(menus.enumerated()), id: \.offset) { _, menu in
                    Button { go(DiscPage.menuPath(item.id, menu)) } label: {
                        HStack(spacing: Tokens.Space.s2) {
                            Image(systemName: "line.3.horizontal").font(.system(size: 15, weight: .semibold)).frame(width: 18, height: 18).opacity(0.8)
                            Text(menu.label)
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                        .padding(.horizontal, Tokens.Space.s4)
                        .frame(minHeight: 44)
                        .background(shape.fill(palette.card))
                        .overlay(shape.strokeBorder(palette.border, lineWidth: 1))
                        .contentShape(shape)
                    }
                    .buttonStyle(TitlePress())
                    .disabled(!playable)
                }
            }
        }
    }

    // MARK: Every title

    /// "All 12 titles on the disc", which opens the table under it, as the website's `<details>`.
    private func titles(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { allTitles.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrowtriangle.right.fill")
                        .font(.system(size: 8))
                        .rotationEffect(.degrees(allTitles ? 90 : 0))
                        .accessibilityHidden(true)
                    Text(summary)
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .padding(.vertical, Tokens.Space.s3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(allTitles ? "Expanded" : "Collapsed")
            if allTitles { table.padding(.top, Tokens.Space.s3) }
        }
    }

    private func cell<Content: View>(_ row: DiscPage.TitleRow, small: Bool = false, @ViewBuilder _ content: () -> Content) -> some View {
        TitleTableCell(line: palette.border) {
            content()
                .font(.system(size: small ? 13 : 14, weight: row.feature ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(row.feature ? palette.accentText : palette.text)
        }
    }

    /// The titles a second long or more: its number (and "Feature" for the film), length, chapters, first three sound
    /// tracks, subtitles, and Play. Sideways on a phone, each on one line; wider, the column's width up to 900, where
    /// the sound tracks and subtitles wrap.
    @ViewBuilder private var table: some View {
        let rows = DiscPage.titleRows(disc)
        let all = TitleTableLayout(columns: 6, maxWidth: narrow ? .infinity : CGFloat(TitleLook.tableWidth)) {
            TitleTableHead(words: "#")
            TitleTableHead(words: "Length")
            TitleTableHead(words: "Chapters")
            TitleTableHead(words: "Audio")
            TitleTableHead(words: "Subtitles")
            TitleTableHead(words: "")
            ForEach(rows, id: \.ttn) { row in
                cell(row) { Text(row.number).fixedSize() }
                cell(row) { Text(row.length).fixedSize() }
                cell(row) { Text(row.chapters).fixedSize() }
                cell(row, small: true) { Text(row.audio).fixedSize(horizontal: narrow, vertical: true) }
                cell(row, small: true) { Text(row.subtitles).fixedSize(horizontal: narrow, vertical: true) }
                TitleTableCell(line: palette.border) {
                    Button { play(row.ttn) } label: { Label("Play", systemImage: "play.fill") }
                        .buttonStyle(TitleSmallButtonStyle())
                        .disabled(!playable)
                        .fixedSize()
                        .accessibilityLabel("Play title \(row.ttn)")
                }
            }
        }
        if narrow {
            ScrollView(.horizontal, showsIndicators: false) { all }
        } else {
            all
        }
    }
}

/// The feature's card (`.feature-card`): its picture and the words beside it, 20 apart and each in the middle of the
/// other's height, the picture between 220 and 420 wide as the words leave room. At 700 across or less, the picture
/// across the card and the words 20 under it.
private struct DiscFeatureCard: Layout {
    let stacked: Bool

    private func sizes(_ width: CGFloat, _ subviews: Subviews) -> (picture: CGSize, words: CGSize) {
        if stacked {
            let words = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil))
            return (CGSize(width: width, height: width * 9 / 16), CGSize(width: width, height: words.height))
        }
        // What the words can't do without: their button, which doesn't wrap.
        let need = subviews[1].sizeThatFits(ProposedViewSize(width: 0, height: nil)).width
        let picture = CGFloat(DiscPage.featurePictureWidth(card: Double(width), wordsNeed: Double(need)))
        let wordsWidth = max(width - Tokens.Space.s5 - picture, 0)
        let words = subviews[1].sizeThatFits(ProposedViewSize(width: wordsWidth, height: nil))
        return (CGSize(width: picture, height: picture * 9 / 16), CGSize(width: wordsWidth, height: words.height))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let width = proposal.width ?? 640
        let (picture, words) = sizes(width, subviews)
        return CGSize(width: width, height: stacked ? picture.height + Tokens.Space.s5 + words.height : max(picture.height, words.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let (picture, words) = sizes(bounds.width, subviews)
        if stacked {
            subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(picture))
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + picture.height + Tokens.Space.s5), proposal: ProposedViewSize(words))
        } else {
            subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(picture))
            subviews[1].place(at: CGPoint(x: bounds.minX + picture.width + Tokens.Space.s5, y: bounds.midY), anchor: .leading,
                              proposal: ProposedViewSize(words))
        }
    }
}

/// A title's or a scene's picture: 16:9 in `card`, the theme's radius, a hairline inside its edge so a dark picture
/// keeps its shape, and what goes over it.
private struct DiscPicture<Over: View>: View {
    @Environment(\.palette) private var palette
    let item: Int64
    let ttn: Int
    let scene: Int
    @ViewBuilder let over: Over

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay { DiscThumb(item: item, ttn: ttn, scene: scene) }
            .overlay { over }
            .background(palette.card)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .contentShape(shape)
    }
}

/// A picture the server makes from the disc the first time it's asked for. One that doesn't come is asked for again
/// 3 and then 6 seconds later before the tile says "Preview not available"; it shows only once it has come.
private struct DiscThumb: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.displayScale) private var displayScale
    let item: Int64
    let ttn: Int
    let scene: Int
    @State private var image: CGImage?
    @State private var failed = false

    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                } else if failed {
                    Text("Preview not available")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textHint)
                        .multilineTextAlignment(.center)
                        .padding(Tokens.Space.s2)
                }
            }
            .clipped()
            .accessibilityHidden(true)
            .task(id: "\(item)/\(ttn)/\(scene)") { await load() }
    }

    private func load() async {
        image = nil
        failed = false
        let pixels = Int(420 * displayScale)
        for retry in 0...DiscPage.thumbRetries.count {
            if retry > 0 { try? await Task.sleep(nanoseconds: UInt64(DiscPage.thumbRetries[retry - 1] * 1_000_000_000)) }
            if Task.isCancelled { return }
            if let picture = await titlePicture(client, client.discThumbURL(item, ttn: ttn, scene: scene, retry: retry), pixels: pixels) {
                image = picture
                return
            }
        }
        if !Task.isCancelled { failed = true }
    }
}

/// A name being given (`.input`): 44 high, 12 inside, in `card` with a 1-wide `control` outline that turns
/// `accentText` while typing; 14, or 13 under a scene.
private struct DiscNameField: View {
    @Environment(\.palette) private var palette
    let placeholder: String
    @Binding var text: String
    var small = false
    let label: String
    @FocusState private var focused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
        TextField("", text: $text, prompt: Text(placeholder).foregroundColor(palette.textHint))
            .font(.system(size: small ? 13 : 14))
            .foregroundStyle(palette.text)
            .tint(palette.accentText)
            .focused($focused)
            .submitLabel(.done)
            .padding(.horizontal, Tokens.Space.s3)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(shape.fill(palette.card))
            .overlay(shape.strokeBorder(focused ? palette.accentText : palette.control, lineWidth: focused ? 2 : 1))
            .accessibilityLabel(label)
    }
}
