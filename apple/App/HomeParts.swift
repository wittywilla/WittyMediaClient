import SwiftUI
import WittyKit

// The smaller pieces of the website's Home at phone size (web/src/pages/HomePage.tsx, shell.css, styles.css): the
// plates on a card, small buttons, the centred card for an empty or unreachable Home, the main button for anything,
// and the hero's line of facts. PhonePages.swift puts them together.

// MARK: - Plates

/// A plate on a card's picture (`.badge`), 20 high in 11 bold: the kind of disc in white on `scrim`; a tick in a round
/// `scrim` once it's watched; how many episodes are left in `onAccent` on `accent`.
struct CardPlate: View {
    @Environment(\.palette) private var palette
    let badge: CardBadge

    var body: some View {
        switch badge {
        case .disc(let name):
            Text(name)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.22)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .frame(minHeight: 20)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.xs, style: .continuous).fill(palette.scrim))
        case .seen:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(palette.scrim))
        case .unwatched(let count):
            Text("\(count)")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.22)
                .foregroundStyle(palette.onAccent)
                .padding(.horizontal, 6)
                .frame(minWidth: 20, minHeight: 20)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.xs, style: .continuous).fill(palette.accent))
        }
    }
}

extension CardBadge {
    /// What a screen reader hears for it, as the website labels it.
    var spoken: String {
        switch self {
        case .disc(let name): return name
        case .seen: return "Watched"
        case .unwatched(let count): return "\(count) unwatched"
        }
    }
}

// MARK: - Previews in Customize home

private struct HomePreviewKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Drawn small in Customize home, where the bar above already names the section: no section titles, no moving
    /// hero, nothing to press.
    var homePreview: Bool {
        get { self[HomePreviewKey.self] }
        set { self[HomePreviewKey.self] = newValue }
    }
}

// MARK: - Small buttons

/// The website's `.btn.sm`: 44 high on a touch screen, 12 inside, the theme's medium radius, 13 semibold with a 16 icon 6
/// before the words. Primary in the accent, Ghost outlined in `text` at 20%, Secondary in `card`.
struct SmallButtonStyle: ButtonStyle {
    var kind: PageButtonKind = .secondary
    /// Only an icon: a 44 square.
    var square = false

    func makeBody(configuration: Configuration) -> some View {
        SmallButtonBody(label: configuration.label, pressed: configuration.isPressed, kind: kind, square: square)
    }
}

private struct SmallButtonBody<Label: View>: View {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let label: Label
    let pressed: Bool
    let kind: PageButtonKind
    let square: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
        let fill: Color = switch kind {
        case .primary: palette.accent
        case .secondary: palette.card
        case .ghost: .clear
        }
        label
            .font(.system(size: 13, weight: .semibold))
            .labelStyle(SmallLabelStyle())
            .foregroundStyle(kind == .primary ? palette.onAccent : palette.text)
            .lineLimit(1)
            .padding(.horizontal, square ? 0 : Tokens.Space.s3)
            .frame(minWidth: 44, minHeight: 44)
            .background(shape.fill(fill))
            .overlay { if kind == .ghost { shape.strokeBorder(palette.text.opacity(0.2), lineWidth: 1) } }
            .contentShape(shape)
            .scaleEffect(pressed && !reduceMotion ? 0.975 : 1)
            .opacity(enabled ? (pressed ? 0.85 : 1) : 0.45)
            .animation(.easeOut(duration: Tokens.Motion.press), value: pressed)
    }
}

private struct SmallLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 13, weight: .semibold)).frame(width: 16, height: 16)
            configuration.title
        }
    }
}

extension View {
    func smallButton(_ kind: PageButtonKind = .secondary, square: Bool = false) -> some View {
        buttonStyle(SmallButtonStyle(kind: kind, square: square))
    }
}

// MARK: - Home's own card

/// The website's `.home-card`: centred on `panel` with a hairline and the extra-large radius, 32 by 24 inside, no wider
/// than 560; a 52 circle of `accent` at 14% with its icon in `accentText`, the title in 20 semibold, the words in
/// `textHint`, and what to do about it.
struct HomeCard<Action: View>: View {
    @Environment(\.palette) private var palette
    let icon: String
    let title: String
    let words: String
    @ViewBuilder var action: Action

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.xl, style: .continuous)
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.accentText)
                .frame(width: 52, height: 52)
                .background(Circle().fill(palette.accent.opacity(0.14)))
                .accessibilityHidden(true)
            Text(title)
                .pageFont(.section)
                .foregroundStyle(palette.text)
                .multilineTextAlignment(.center)
                .padding(.top, Tokens.Space.s1)
                .accessibilityAddTraits(.isHeader)
            Text(words)
                .pageFont(.body)
                .lineSpacing(5)
                .foregroundStyle(palette.textHint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Tokens.Space.s2)
            action
        }
        .padding(.vertical, Tokens.Space.s8)
        .padding(.horizontal, Tokens.Space.s6)
        .frame(maxWidth: 560)
        .background(shape.fill(palette.panel))
        .overlay(shape.strokeBorder(palette.border, lineWidth: 1))
        .frame(maxWidth: .infinity)
    }
}

// MARK: - The main button

/// The main button for anything, worded for what it is and going where the website's goes (web/src/openItem.tsx):
/// Play or Resume in this app's player, Listen from the album, Read, Insert disc and a disc's Play on the server's
/// own pages. Style it where it's used.
struct OpenItemButton: View {
    @EnvironmentObject private var model: AppModel
    let item: Item

    /// The website's icon: a book, a note, or Play.
    static func symbol(_ item: Item) -> String {
        switch item.kind {
        case "book": return "book.closed.fill"
        case "audio": return "music.note"
        default: return "play.fill"
        }
    }

    var body: some View {
        let label = Label(OpenLook.label(item), systemImage: Self.symbol(item))
        switch OpenLook.action(item) {
        case .listen: Button { model.playTrack(item) } label: { label }
        case .player(let startOver): NavigationLink(value: Route.player(item.id, startOver: startOver)) { label }
        case .item: NavigationLink(value: Route.item(item.id)) { label }
        case .page(let path): NavigationLink(value: Route.page(path)) { label }
        }
    }
}

// MARK: - The hero's facts

/// The line of facts under the hero's title (`.meta`): 14 `textSecondary`, 16 apart, wrapping 2 apart, with a dot in
/// `textHint` in each gap. The age rating sits in an outlined box with no dots beside it, and the score follows a star in
/// `warn`. A dot that would start a line falls outside the row and isn't drawn.
struct HeroFactsRow: View {
    @Environment(\.palette) private var palette
    let facts: [HeroFact]

    var body: some View {
        FlowLayout(spacing: Tokens.Space.s4, rowSpacing: 2) {
            ForEach(Array(facts.enumerated()), id: \.offset) { place, fact in
                let dotted = !isRating(fact) && !(place > 0 && isRating(facts[place - 1]))
                factView(fact)
                    .frame(minHeight: 22)
                    .overlay(alignment: .leading) {
                        if dotted {
                            Text("·").font(.system(size: 14)).foregroundStyle(palette.textHint).offset(x: -10).accessibilityHidden(true)
                        }
                    }
            }
        }
        .clipped()
        .accessibilityElement(children: .combine)
    }

    private func isRating(_ fact: HeroFact) -> Bool {
        if case .rating = fact { return true }
        return false
    }

    @ViewBuilder private func factView(_ fact: HeroFact) -> some View {
        switch fact {
        case .text(let words):
            Text(words).font(.system(size: 14)).foregroundStyle(palette.textSecondary).lineLimit(1)
        case .rating(let rating):
            Text(rating)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.22)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, Tokens.Space.s2)
                .frame(minHeight: 20)
                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.xs, style: .continuous).strokeBorder(palette.text.opacity(0.2), lineWidth: 1))
                .accessibilityLabel("Rated \(rating)")
        case .score(let score):
            HStack(spacing: 3) {
                Image(systemName: "star.fill").font(.system(size: 12)).foregroundStyle(palette.warn).frame(width: 14, height: 14)
                Text(" " + score).font(.system(size: 14)).foregroundStyle(palette.textSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Score \(score)")
        }
    }
}
