import SwiftUI
import WittyKit

// The pieces of the sign-in screens in docs/APP-DESIGN.md: the brand, the glow, people's tiles,
// server cards, code boxes and the number pad, the QR card. Android draws the same from the same page.

// MARK: - Brand

/// The server's icon, drawn rather than shipped as a picture so it's sharp at every size: a dark
/// rounded square with a ring and a play triangle in the brand's violet. The owner's own logo
/// replaces it when the server has one.
struct BrandMark: View {
    var size: CGFloat = 32
    var logo: URL?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 14 / 64, style: .continuous)
        Group {
            if let logo {
                ArtImage(url: logo, width: size, blank: true).clipShape(shape)
            } else {
                Canvas { context, canvas in
                    let scale = canvas.width / 64
                    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * scale, y: y * scale) }
                    let violet = Gradient(colors: [Color(hex: "#9d7bff"), Color(hex: "#5b3df5")])
                    let shading = GraphicsContext.Shading.linearGradient(violet, startPoint: .zero, endPoint: point(64, 64))
                    context.fill(Path(roundedRect: CGRect(origin: .zero, size: canvas), cornerRadius: 14 * scale, style: .continuous),
                                 with: .color(Color(hex: "#1b1e25")))
                    let ring = Path(ellipseIn: CGRect(x: 12 * scale, y: 12 * scale, width: 40 * scale, height: 40 * scale))
                    context.stroke(ring, with: shading, lineWidth: 5 * scale)
                    var play = Path()
                    play.move(to: point(27, 23))
                    play.addLine(to: point(41, 32))
                    play.addLine(to: point(27, 41))
                    play.closeSubpath()
                    context.fill(play, with: shading)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// "WittyMediaClient" for the app itself, or a server's own name: "WittyMediaServer", with "Media" in the accent,
/// unless the owner named it. A server's name only appears once it has been added (docs/APP-DESIGN.md, Brand).
struct Wordmark: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    /// The app's own name rather than a server's.
    var app = false
    var name = ""

    var body: some View {
        let last = app ? "Client" : "Server"
        Group {
            if app || name.isEmpty {
                Text("Witty").foregroundColor(palette.text)
                    + Text("Media").foregroundColor(palette.accentText)
                    + Text(last).foregroundColor(palette.text)
            } else {
                Text(name).foregroundColor(palette.text)
            }
        }
        // Read from across the room on a TV: the size of Display.
        .font(metrics.tv ? .system(size: 48, weight: .bold) : .wmHero.weight(.bold))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityLabel(app ? "WittyMediaClient" : (name.isEmpty ? "WittyMediaServer" : name))
    }
}

/// The mark and the name together, at the top of the sign-in screens: the app's before a server is added,
/// that server's on its own screens.
struct BrandLockup: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.metrics) private var metrics
    var app = false

    var body: some View {
        HStack(spacing: metrics.tv ? Tokens.Space.s5 : 10) {
            BrandMark(size: metrics.tv ? 72 : 32, logo: app ? nil : model.client.brandLogoURL(version: model.brandLogo))
            Wordmark(app: app, name: model.brandName)
        }
        .accessibilityElement(children: .combine)
    }
}

/// An added server's logo, from what the device kept, so a list of servers shows them without asking any.
struct ServerLogo: View {
    let server: SavedServer
    var size: CGFloat = 40

    var body: some View {
        if let image = LogoCache.image(server: server.url, version: server.brandLogo) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 14 / 64, style: .continuous))
                .accessibilityHidden(true)
        } else {
            BrandMark(size: size)
        }
    }
}

/// The owner's logo for each added server, kept on the device by its version, so the server list shows it at once
/// and a server that can't be reached still looks like itself.
enum LogoCache {
    private static var folder: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("logos", isDirectory: true)
    }

    private static func key(_ server: String) -> String {
        Data(server.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "=", with: "")
    }

    private static func file(server: String, version: String) -> URL? {
        let safe = version.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        guard !safe.isEmpty else { return nil }
        return folder?.appendingPathComponent("\(key(server))-\(safe)")
    }

    static func image(server: String, version: String) -> UIImage? {
        guard let file = file(server: server, version: version) else { return nil }
        return UIImage(contentsOfFile: file.path)
    }

    /// Replaces any older logo of the same server.
    static func keep(_ data: Data, server: String, version: String) {
        guard let folder, let file = file(server: server, version: version), UIImage(data: data) != nil else { return }
        let manager = FileManager.default
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let prefix = key(server) + "-"
        for old in (try? manager.contentsOfDirectory(atPath: folder.path)) ?? [] where old.hasPrefix(prefix) {
            try? manager.removeItem(at: folder.appendingPathComponent(old))
        }
        try? data.write(to: file, options: .atomic)
    }
}

/// A soft light from the top of the screen, in the accent: the web's sign-in background.
struct SignInGlow: View {
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { geo in
            EllipticalGradient(stops: [.init(color: palette.accent.opacity(0.16), location: 0), .init(color: .clear, location: 0.7)],
                               center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                .frame(width: geo.size.width * 1.4, height: geo.size.height * 1.2)
                .position(x: geo.size.width / 2, y: 0)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A sign-in screen: the glow, and one column in the middle, no wider than reads well, a third of the
/// way down when it's short and scrolling when it isn't.
struct SignInPage<Content: View>: View {
    @Environment(\.palette) private var palette
    /// Somewhere to go back to, shown as the back button at the top left.
    var back: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            palette.background.ignoresSafeArea()
            SignInGlow()
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: Tokens.Space.s8)
                        VStack(alignment: .center, spacing: Tokens.Space.s4) { content }
                            .frame(maxWidth: 440)
                            .padding(.horizontal, Tokens.Space.s6)
                            // Clear of the back button.
                            .padding(.top, back == nil ? 0 : 52)
                        Spacer(minLength: Tokens.Space.s8)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
                .scrollDismissesKeyboardIfAvailable()
            }
            if let back { BackButton(action: back).padding(Tokens.Space.s4) }
        }
    }
}

/// The way back from a sign-in screen, where there's no bar to hold one: a round button at the top left.
struct BackButton: View {
    @Environment(\.palette) private var palette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.body.weight(.semibold))
                .foregroundStyle(palette.text)
                .frame(width: 44, height: 44)
                .background(Circle().fill(palette.card))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(say("back"))
    }
}

/// On a TV: what to read on the left and what to press on the right, with the glow behind.
struct TvSignInPage<Words: View, Actions: View>: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @ViewBuilder let words: Words
    @ViewBuilder let actions: Actions

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            SignInGlow()
            HStack(alignment: .center, spacing: Tokens.Space.s16) {
                VStack(alignment: .leading, spacing: Tokens.Space.s5) { words }
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: Tokens.Space.s4) { actions }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, metrics.gutter)
            .padding(.vertical, metrics.edge)
        }
    }
}

/// One centred column on a TV, for a screen about one person: their face stays where Who's watching had it.
struct TvCentredPage<Words: View, Actions: View>: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @ViewBuilder let words: Words
    @ViewBuilder let actions: Actions

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            SignInGlow()
            VStack(spacing: Tokens.Space.s8) {
                VStack(spacing: Tokens.Space.s5) { words }
                VStack(spacing: Tokens.Space.s4) { actions }
                    .frame(width: 640)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, metrics.gutter)
            .padding(.vertical, metrics.edge)
        }
    }
}

/// A sign-in screen in the right shape for the device: one column, or side by side on a TV, or one centred
/// column on a TV when `centred`.
struct SignInLayout<Words: View, Actions: View>: View {
    @Environment(\.metrics) private var metrics
    var back: (() -> Void)?
    var centred = false
    @ViewBuilder let words: Words
    @ViewBuilder let actions: Actions

    var body: some View {
        if metrics.tv && centred {
            TvCentredPage { words } actions: { actions }
        } else if metrics.tv {
            // The remote's Back button goes back on a TV.
            TvSignInPage { words } actions: { actions }
        } else {
            SignInPage(back: back) {
                words
                actions
            }
        }
    }
}

/// The words of a sign-in screen, centred on a phone and to the left on a TV.
struct SignInHeading: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let title: String
    var detail = ""
    var display = false
    /// Centred even on a TV, as Who's watching is: its whole screen is centred there.
    var centred = false

    var body: some View {
        let middle = centred || !metrics.tv
        VStack(alignment: middle ? .center : .leading, spacing: Tokens.Space.s2) {
            if !title.isEmpty {
                Text(title)
                    .font(display ? .wmDisplay : .wmPage)
                    .foregroundStyle(palette.text)
                    .multilineTextAlignment(middle ? .center : .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            if !detail.isEmpty {
                Text(detail)
                    .font(.body)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(middle ? .center : .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: middle ? .center : .leading)
    }
}

// MARK: - People

/// A person's tile: their initial on their colour, the same as in the browser. Small ones are circles.
struct AvatarTile: View {
    let name: String
    var size: CGFloat

    var body: some View {
        let shape: AnyShape = size <= 36 ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        Text(AvatarLook.initial(of: name))
            .font(.system(size: size * 0.43, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(shape.fill(Color(hex: AvatarLook.colour(for: name))))
            .accessibilityHidden(true)
    }
}

/// Shows a tile chosen: lifted, with the web's two rings, and its words brighter.
private struct ProfileTileStyle: ButtonStyle {
    let avatarSize: CGFloat
    let radius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        ProfileTileBody(label: configuration.label, pressed: configuration.isPressed, avatarSize: avatarSize, radius: radius)
    }
}

private struct ProfileTileBody<Label: View>: View {
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let label: Label
    let pressed: Bool
    let avatarSize: CGFloat
    let radius: CGFloat

    var body: some View {
        // Only the avatar grows and lifts (see ProfileTileContent); the names keep their size.
        label.environment(\.profileTileActive, pressed || focused)
    }
}

private struct ProfileTileActiveKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Inside a profile tile: whether it's pressed or has the remote's focus.
    fileprivate var profileTileActive: Bool {
        get { self[ProfileTileActiveKey.self] }
        set { self[ProfileTileActiveKey.self] = newValue }
    }
}

/// The face, profile name and username of one profile, as a button.
struct ProfileTile: View {
    let profile: Profile
    var avatarSize: CGFloat
    let action: () -> Void

    private var spoken: String {
        var words = [profile.shownName]
        if profile.showsUsername { words.append("@\(profile.name)") }
        if profile.isKids { words.append("\(say("kidsBadge")) profile") }
        if profile.isGuest { words.append("\(say("guestBadge")) profile") }
        return words.joined(separator: ", ")
    }

    var body: some View {
        Button(action: action) {
            ProfileTileContent(profile: profile, avatarSize: avatarSize)
        }
        .buttonStyle(ProfileTileStyle(avatarSize: avatarSize, radius: avatarSize * 0.22))
        .accessibilityLabel(spoken)
    }
}

private struct ProfileTileContent: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @Environment(\.profileTileActive) private var active
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let profile: Profile
    let avatarSize: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: avatarSize * 0.22, style: .continuous)
        // A `background` band, then the `text` ring, each `ring` wide. Insetting a rounded rectangle
        // outwards grows its corners by as much, so both stay concentric with the avatar's.
        let ring: CGFloat = metrics.tv ? 4 : 3
        VStack(spacing: Tokens.Space.s2) {
            AvatarTile(name: profile.shownName, size: avatarSize)
                .overlay {
                    if active {
                        shape.inset(by: -ring / 2).stroke(palette.background, lineWidth: ring)
                        shape.inset(by: -ring * 1.5).stroke(palette.text, lineWidth: ring)
                    }
                }
                .overlay(alignment: .bottom) {
                    if profile.isKids || profile.isGuest {
                        Text(profile.isKids ? say("kidsBadge") : say("guestBadge"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.text)
                            .padding(.horizontal, Tokens.Space.s2)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(palette.background))
                            .overlay(Capsule().stroke(palette.border, lineWidth: 1))
                            .offset(y: 10)
                    }
                }
                .scaleEffect(active && metrics.tv && !reduceMotion ? 1.06 : 1, anchor: .bottom)
                .offset(y: active && !reduceMotion ? (metrics.tv ? -6 : -3) : 0)
                // Every tile keeps the badge's room, so names in a row line up with or without one.
                .padding(.bottom, 6)
            // Centred under the avatar on every device, TVs included.
            VStack(alignment: .center, spacing: 2) {
                Text(profile.shownName)
                    .font(.wmLabel.weight(.semibold))
                    .foregroundStyle(active ? palette.text : palette.textSecondary)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                if profile.showsUsername {
                    Text("@\(profile.name)")
                        .font(.wmSecondary)
                        .foregroundStyle(palette.textHint)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: avatarSize + 32, alignment: .center)
        }
        .padding(Tokens.Space.s2)
        .contentShape(Rectangle())
        .animation(reduceMotion ? nil : .easeOut(duration: Tokens.Motion.focus), value: active)
    }
}

// MARK: - Servers

/// A server in a list: its mark, its name over its address, and where it goes.
struct ServerCard: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    /// An added server: its own logo and name. Without one, a server only found: its address and nothing it says.
    var saved: SavedServer?
    let url: String
    var lastUsed = false
    var connecting = false
    let action: () -> Void

    /// What a found server is called here: where it is, host and port.
    static func place(_ url: String) -> String {
        guard let parts = URLComponents(string: url), let host = parts.host else { return url }
        return parts.port.map { "\(host):\($0)" } ?? host
    }

    private var name: String {
        guard let saved else { return Self.place(url) }
        return saved.name.isEmpty ? "WittyMediaServer" : saved.name
    }

    private var detail: String { saved == nil ? say("foundOnNetwork") : url }

    var body: some View {
        let mark: CGFloat = metrics.tv ? 56 : 40
        Button(action: action) {
            HStack(spacing: Tokens.Space.s3) {
                if let saved {
                    ServerLogo(server: saved, size: mark)
                } else {
                    Image(systemName: "server.rack")
                        .font(.system(size: mark * 0.45, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: mark, height: mark)
                        .background(RoundedRectangle(cornerRadius: mark * 14 / 64, style: .continuous).fill(palette.border))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Tokens.Space.s2) {
                        Text(name).font(.wmLabel.weight(.semibold)).foregroundStyle(palette.text).lineLimit(1)
                        if lastUsed {
                            Text(say("lastUsed"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(palette.textSecondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(palette.border))
                        }
                    }
                    Text(detail).font(.wmSecondary).foregroundStyle(palette.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if connecting {
                    ProgressView().tint(palette.textSecondary)
                } else {
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(palette.textHint)
                }
            }
            .padding(Tokens.Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(SurfaceStyle(fill: palette.card, radius: Tokens.Radius.lg))
        .accessibilityLabel(lastUsed ? "\(name), \(detail), \(say("lastUsed"))" : "\(name), \(detail)")
    }
}

/// Something worth knowing that isn't a failure, in a quiet card, with a spinner while waiting.
struct NoteCard: View {
    @Environment(\.palette) private var palette
    let words: String
    var busy = false
    var icon = "info.circle"

    var body: some View {
        HStack(alignment: .center, spacing: Tokens.Space.s3) {
            if busy {
                ProgressView().tint(palette.textSecondary)
            } else {
                Image(systemName: icon).foregroundStyle(palette.textSecondary)
            }
            Text(words).font(.wmSecondary).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Tokens.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).fill(palette.panel))
        .accessibilityElement(children: .combine)
    }
}

/// A heading above a group, with a pulsing dot while something is still being looked for.
struct SearchingCaption: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let words: String
    var searching = false
    @State private var pulse = false

    var body: some View {
        HStack(spacing: Tokens.Space.s2) {
            Text(words.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(palette.textSecondary).kerning(0.6)
            if searching {
                Circle()
                    .fill(palette.accent)
                    .frame(width: 7, height: 7)
                    .opacity(pulse ? 0.25 : 1)
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
                    }
            }
            Spacer(minLength: 0)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Codes

/// Moves its content side to side, once for each wrong code, as a head shakes no.
private struct Shake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(animatableData * .pi * 4), y: 0))
    }
}

private struct ShakeOnChange: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let count: Int
    func body(content: Content) -> some View {
        content
            .modifier(Shake(animatableData: reduceMotion ? 0 : CGFloat(count)))
            .animation(.easeOut(duration: 0.4), value: count)
    }
}

extension View {
    /// A head-shake each time `count` goes up: a wrong password, a wrong code. Still when motion is reduced.
    func shake(_ count: Int) -> some View { modifier(ShakeOnChange(count: count)) }
}

/// Six boxes, filling as digits are typed, the next one outlined in the accent.
struct CodeBoxes: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let digits: String
    var count = 6
    /// The whole code is in and being checked.
    var checking = false
    /// Goes up by one for each wrong code, which shakes the boxes.
    var wrongTries = 0

    var body: some View {
        let width: CGFloat = metrics.tv ? 88 : 46
        let height: CGFloat = metrics.tv ? 100 : 56
        let typed = Array(digits)
        HStack(spacing: Tokens.Space.s2) {
            ForEach(0..<count, id: \.self) { place in
                let next = place == typed.count && !checking
                RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
                    .fill(palette.card)
                    .overlay {
                        RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
                            .strokeBorder(next || checking ? palette.accent : palette.border, lineWidth: next ? 2 : 1)
                    }
                    .overlay {
                        if place < typed.count {
                            Text(String(typed[place])).font(.system(.title, design: .monospaced).weight(.bold)).foregroundStyle(palette.text)
                        }
                    }
                    .frame(width: width, height: height)
            }
        }
        .modifier(Shake(animatableData: reduceMotion ? 0 : CGFloat(wrongTries)))
        .animation(.easeOut(duration: 0.4), value: wrongTries)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(say("codeLabel"))
        .accessibilityValue("\(typed.count) \(say("codeEntered"))")
    }
}

/// A key of the number pad. With a remote's focus it fills with `text`, its digit turns `background`
/// and it grows 1.06, as both TVs' own keyboards show it: a grid of rings would crowd the keys.
private struct PadKeyStyle: ButtonStyle {
    var quiet = false
    func makeBody(configuration: Configuration) -> some View {
        PadKeyBody(label: configuration.label, pressed: configuration.isPressed, quiet: quiet)
    }
}

private struct PadKeyBody<Label: View>: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let label: Label
    let pressed: Bool
    let quiet: Bool

    var body: some View {
        let lit = metrics.tv && focused
        label
            .foregroundStyle(lit ? palette.background : (quiet ? palette.textSecondary : palette.text))
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).fill(lit ? palette.text : palette.card))
            .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous))
            .scaleEffect(lit && !reduceMotion ? 1.06 : 1)
            .opacity(pressed ? 0.8 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: Tokens.Motion.focus), value: lit)
    }
}

/// The number pad: arrows and OK on a TV, a finger on a phone, and number keys on a keyboard.
/// The zero is twice as wide, so the focus engine finds something below every digit.
struct NumberPad: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let onDigit: (Character) -> Void
    let onDelete: () -> Void
    var scope: Namespace.ID?

    private func key(_ digit: Character) -> some View {
        Button { onDigit(digit) } label: {
            Text(String(digit))
                .font(.wmHero)
                .frame(maxWidth: .infinity, minHeight: metrics.tv ? 96 : 60)
        }
        .buttonStyle(PadKeyStyle())
        .digitShortcut(digit)
    }

    var body: some View {
        // On a TV the keys sit 16 apart, so a focused key never crowds its neighbours.
        let gap = metrics.tv ? Tokens.Space.s4 : Tokens.Space.s2
        Grid(horizontalSpacing: gap, verticalSpacing: gap) {
            GridRow {
                if let scope { key("1").firstFocus(in: scope) } else { key("1") }
                key("2"); key("3")
            }
            GridRow { key("4"); key("5"); key("6") }
            GridRow { key("7"); key("8"); key("9") }
            GridRow {
                Button(action: onDelete) {
                    Image(systemName: "delete.left")
                        .font(.wmHero)
                        .frame(maxWidth: .infinity, minHeight: metrics.tv ? 96 : 60)
                }
                .buttonStyle(PadKeyStyle(quiet: true))
                .accessibilityLabel(say("codeDelete"))
                key("0").gridCellColumns(2)
            }
        }
        .remoteSection()
    }
}

/// A code a phone's camera can read: black on white with its own margin, whatever the theme.
struct QRCard: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let image: CGImage
    let caption: String

    var body: some View {
        VStack(spacing: Tokens.Space.s2) {
            Image(image, scale: 1, label: Text(caption))
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: metrics.tv ? 280 : 180, height: metrics.tv ? 280 : 180)
                .padding(Tokens.Space.s4)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).fill(Color.white))
            Text(caption).font(.caption.weight(.medium)).foregroundStyle(palette.textSecondary)
        }
    }
}
