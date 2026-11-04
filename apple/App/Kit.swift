import SwiftUI
import WittyKit

// The pieces the Android app is built from (android/…/ui/Kit.kt and Theme.kt), so the two look and
// behave alike: filled buttons with the main one in the theme's accent, outlined fields, headings,
// poster cards and the same spacing. Apple TV gets what Android TV gets: a ring and a slightly larger
// button for focus, and no animation beyond that.

/// What differs between a phone in the hand, a tablet, and a TV across the room.
struct Metrics: Equatable {
    var tv: Bool
    var gutter: CGFloat
    var edge: CGFloat
    var cardWidth: CGFloat
    var minTarget: CGFloat
    var focusRing: CGFloat = 3
    var focusScale: CGFloat = 1

    static let phone = Metrics(tv: false, gutter: Tokens.Space.s4, edge: Tokens.Space.s2, cardWidth: 124, minTarget: 44)
    static let tablet = Metrics(tv: false, gutter: Tokens.Space.s8, edge: Tokens.Space.s2, cardWidth: 148, minTarget: 44)
    static let television = Metrics(tv: true, gutter: Tokens.gutter, edge: Tokens.edge, cardWidth: Tokens.cardWidth,
                                    minTarget: Tokens.minTarget, focusRing: 4, focusScale: 1.05)
}

private struct MetricsKey: EnvironmentKey {
    #if os(tvOS)
    static let defaultValue = Metrics.television
    #else
    static let defaultValue = Metrics.phone
    #endif
}

extension EnvironmentValues {
    var metrics: Metrics {
        get { self[MetricsKey.self] }
        set { self[MetricsKey.self] = newValue }
    }
}

/// Sets the metrics for whatever width the window has. A tablet, or a phone on a large screen,
/// gets the wider margins and cards.
struct MetricsForWidth: ViewModifier {
    #if os(iOS) || os(visionOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    func body(content: Content) -> some View {
        #if os(tvOS)
        content.environment(\.metrics, .television)
        #elseif os(iOS) || os(visionOS)
        content.environment(\.metrics, sizeClass == .regular ? .tablet : .phone)
        #else
        content.environment(\.metrics, .tablet)
        #endif
    }
}

// MARK: - The surface everything pressable is drawn on

/// Android's FocusBox: something pressable, optionally filled, that shows focus as a ring and a
/// slightly larger size on a TV. A finger gets no ring, as nothing is "focused" for someone touching.
struct SurfaceStyle: ButtonStyle {
    var fill: Color? = nil
    var radius: CGFloat = Tokens.Radius.md

    func makeBody(configuration: Configuration) -> some View {
        SurfaceBody(label: configuration.label, pressed: configuration.isPressed, fill: fill, radius: radius)
    }
}

private struct SurfaceBody<Label: View>: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let label: Label
    let pressed: Bool
    let fill: Color?
    let radius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let ring = metrics.tv && focused
        label
            .background(fill.map { shape.fill($0) })
            .contentShape(shape)
            .padding(metrics.tv ? metrics.focusRing : 0)
            .overlay {
                if metrics.tv {
                    RoundedRectangle(cornerRadius: radius + metrics.focusRing, style: .continuous)
                        .strokeBorder(ring ? palette.text : Color.clear, lineWidth: metrics.focusRing)
                }
            }
            .scaleEffect(ring && !reduceMotion ? metrics.focusScale : 1)
            .opacity(enabled ? (pressed ? 0.8 : 1) : 0.55)
    }
}

// MARK: - Buttons

/// Android's ActionButton. The one main action on a screen is `primary`, in the accent colour;
/// everything else is the card colour. `selected` marks the chosen one of a set, such as a season.
struct ActionStyle: ButtonStyle {
    var primary = false
    var selected = false
    var pill = false
    var wide = false

    func makeBody(configuration: Configuration) -> some View {
        ActionBody(label: configuration.label, pressed: configuration.isPressed, primary: primary, selected: selected, pill: pill, wide: wide)
    }
}

private struct ActionBody<Label: View>: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let label: Label
    let pressed: Bool
    let primary: Bool
    let selected: Bool
    let pill: Bool
    let wide: Bool

    var body: some View {
        let fill = primary ? palette.accent : (selected ? palette.border : palette.card)
        SurfaceBody(
            label: label
                .font(.wmLabel)
                .labelStyle(ActionLabelStyle())
                .foregroundStyle(primary ? palette.onAccent : palette.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, pill ? Tokens.Space.s5 : Tokens.Space.s4)
                .padding(.vertical, Tokens.Space.s2)
                .frame(maxWidth: wide ? .infinity : nil, minHeight: metrics.minTarget),
            pressed: pressed, fill: fill, radius: pill ? 999 : Tokens.Radius.md
        )
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// An icon and its words side by side, as on Android's buttons.
private struct ActionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Tokens.Space.s2) {
            configuration.icon
            configuration.title
        }
    }
}

extension View {
    /// A filled button, as on Android: see `ActionStyle`.
    func action(primary: Bool = false, selected: Bool = false, pill: Bool = false, wide: Bool = false) -> some View {
        buttonStyle(ActionStyle(primary: primary, selected: selected, pill: pill, wide: wide))
    }
}

// MARK: - Words

/// The one heading of a page, which is what a screen reader jumps between.
struct Heading: View {
    @Environment(\.palette) private var palette
    let words: String
    init(_ words: String) { self.words = words }

    var body: some View {
        Text(words).font(.wmPage).foregroundStyle(palette.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The heading above a row or a group.
struct SectionTitle: View {
    @Environment(\.palette) private var palette
    let words: String
    init(_ words: String) { self.words = words }

    var body: some View {
        Text(words).font(.wmSection).foregroundStyle(palette.text).accessibilityAddTraits(.isHeader)
    }
}

/// A sentence that explains something, in the quieter colour.
struct Secondary: View {
    @Environment(\.palette) private var palette
    let words: String
    var lines: Int?
    init(_ words: String, lines: Int? = nil) {
        self.words = words
        self.lines = lines
    }

    var body: some View {
        Text(words).font(.wmSecondary).foregroundStyle(palette.textSecondary)
            .lineLimit(lines)
            .fixedSize(horizontal: false, vertical: lines == nil)
    }
}

// MARK: - Fields

/// Android's outlined text field: a box with its label, which moves up onto the border while it's
/// in use or has something in it. Apple TV opens its own keyboard for a field, and keeps its own look.
struct OutlinedField: View {
    enum Kind { case text, address, name, password }

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let label: String
    @Binding var text: String
    var kind: Kind = .text
    /// Set to true by the screen to put the focus here; the field sets it back once it has it.
    var request: Binding<Bool>?
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    private func takeFocusIfAsked() {
        guard request?.wrappedValue == true else { return }
        // The box may not be on screen yet in this update.
        DispatchQueue.main.async {
            focused = true
            request?.wrappedValue = false
        }
    }

    @ViewBuilder private var field: some View {
        if kind == .password {
            SecureField("", text: $text)
                .textContentType(.password)
        } else {
            TextField("", text: $text)
                #if os(iOS) || os(visionOS)
                .textInputAutocapitalization(.never)
                .keyboardType(kind == .address ? .URL : .default)
                #endif
                .textContentType(kind == .name ? .username : (kind == .address ? .URL : nil))
                .autocorrectionDisabled()
        }
    }

    var body: some View {
        #if os(tvOS)
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Secondary(label)
            field.focused($focused).onSubmit(onSubmit).accessibilityLabel(label)
        }
        .onAppear(perform: takeFocusIfAsked)
        .onChange(of: request?.wrappedValue ?? false) { _ in takeFocusIfAsked() }
        #else
        let raised = focused || !text.isEmpty
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
        ZStack(alignment: .leading) {
            // The outline is underneath, so the raised label sits over it as on Android.
            shape.strokeBorder(focused ? palette.accent : palette.border, lineWidth: focused ? 2 : 1)
            field
                .focused($focused)
                .onSubmit(onSubmit)
                .foregroundStyle(palette.text)
                .padding(.horizontal, Tokens.Space.s4)
                .padding(.top, raised ? 2 : 0)
                .frame(minHeight: 56)
                .accessibilityLabel(label)
            Text(label)
                .font(raised ? .caption : .body)
                .foregroundStyle(focused ? palette.accentText : palette.textSecondary)
                .padding(.horizontal, Tokens.Space.s1)
                .background(raised ? palette.background : Color.clear)
                .offset(x: Tokens.Space.s3, y: raised ? -28 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .contentShape(shape)
        .onTapGesture { focused = true }
        .animation(reduceMotion ? nil : .easeOut(duration: Tokens.Motion.focus), value: raised)
        .padding(.top, Tokens.Space.s1)
        .onAppear(perform: takeFocusIfAsked)
        .onChange(of: request?.wrappedValue ?? false) { _ in takeFocusIfAsked() }
        #endif
    }
}

// MARK: - Layout

/// Things in a row that wraps, as Android's FlowRow: profiles, for one.
struct FlowLayout: Layout {
    var spacing: CGFloat = Tokens.Space.s3

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[(Int, CGSize)]] {
        var rows: [[(Int, CGSize)]] = [[]]
        var used: CGFloat = 0
        for (index, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
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
        let all = rows(subviews, width: width)
        let height = all.map { $0.map(\.1.height).max() ?? 0 }.reduce(0, +) + spacing * CGFloat(max(all.count - 1, 0))
        let widest = all.map { row in row.map(\.1.width).reduce(0, +) + spacing * CGFloat(max(row.count - 1, 0)) }.max() ?? 0
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            var x = bounds.minX
            let height = row.map(\.1.height).max() ?? 0
            for (index, size) in row {
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += height + spacing
        }
    }
}

/// The sign-in screens: one column in the middle, no wider than reads well.
struct Centred<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) { content }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(Tokens.Space.s8)
                .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboardIfAvailable()
    }
}

/// What to read and what to press: side by side on a TV, where a tall screen would scroll its
/// beginning out of sight, and one above the other everywhere else.
struct SideBySide<Words: View, Actions: View>: View {
    @Environment(\.metrics) private var metrics
    @ViewBuilder let words: Words
    @ViewBuilder let actions: Actions

    var body: some View {
        if metrics.tv {
            HStack(alignment: .center, spacing: Tokens.Space.s16) {
                VStack(alignment: .leading, spacing: Tokens.Space.s3) { words }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: Tokens.Space.s3) { actions }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, metrics.gutter)
            .padding(.vertical, metrics.edge)
        } else {
            Centred {
                words
                actions
            }
        }
    }
}

extension View {
    @ViewBuilder func scrollDismissesKeyboardIfAvailable() -> some View {
        #if os(iOS)
        self.scrollDismissesKeyboard(.interactively)
        #else
        self
        #endif
    }
}

// MARK: - Rows and pictures

/// A server in a list: its name, and the address it's at.
struct ServerRow: View {
    @Environment(\.palette) private var palette
    let name: String
    let url: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).foregroundStyle(palette.text)
                Secondary(url, lines: 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
        }
        .buttonStyle(SurfaceStyle(fill: palette.card))
        .accessibilityLabel("\(name), \(url)")
    }
}

/// How far through something is: a thin bar in the accent colour.
struct ProgressStrip: View {
    @Environment(\.palette) private var palette
    let fraction: Double
    var track: Color?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track ?? Color.black.opacity(0.6))
                Capsule().fill(palette.accent).frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: Tokens.Space.s1)
        .accessibilityHidden(true)
    }
}

/// The wide picture behind the top of an item or a show, dimmed and fading into the page, as on
/// Android. It runs up under the clock.
struct PageBackdrop: View {
    @Environment(\.palette) private var palette
    let url: URL?
    var height: CGFloat = 340
    var dim: Double = 0.4

    var body: some View {
        ArtImage(url: url, width: 1280, blank: true)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .opacity(dim)
            .overlay(
                LinearGradient(stops: [.init(color: .clear, location: 0.2), .init(color: palette.background, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            )
            .clipped()
            .accessibilityHidden(true)
    }
}

extension View {
    /// A screen pushed onto a tab: the system's bar keeps only its Back, over the page.
    @ViewBuilder func plainNavigation() -> some View {
        #if os(iOS) || os(visionOS)
        self.navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }

    /// A tab's first screen, which has its own heading and no bar.
    @ViewBuilder func noNavigationBar() -> some View {
        #if os(iOS) || os(visionOS)
        self.toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }
}
