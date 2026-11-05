#if os(iOS) || os(visionOS)
import SwiftUI
import WittyKit

// The website's on-screen remote for the video player (web/src/player/Remote.tsx, player.css): a remote that floats
// over the picture, which can be moved by its top, made bigger or smaller by its edges and corners, and made more
// see-through; or the same keys in a strip above the seek bar. A video file has no menus, angles or numbers: those
// keys are there, greyed out, as on the website.

private let remoteText = Color(red: 0xE8 / 255, green: 0xE9 / 255, blue: 0xEE / 255)
private let keyTop = Color(red: 0x3A / 255, green: 0x3E / 255, blue: 0x48 / 255)
private let keyBottom = Color(red: 0x2A / 255, green: 0x2D / 255, blue: 0x35 / 255)
private let keyEdge = Color(red: 0x0C / 255, green: 0x0D / 255, blue: 0x10 / 255)

/// One key of the remote: raised, and pressed down while touched.
private struct RemoteKeyStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.palette) private var palette
    enum Look { case plain, round, pill, red, ghost, accent, dpad, enter, digit }
    var look = Look.plain
    var height: CGFloat = 30

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shape: AnyShape = {
            switch look {
            case .round, .ghost, .enter: return AnyShape(Circle())
            case .pill: return AnyShape(Capsule())
            case .digit: return AnyShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous))
            default: return AnyShape(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous))
            }
        }()
        let fill: AnyShapeStyle = {
            switch look {
            case .red: return AnyShapeStyle(LinearGradient(colors: [Color(red: 0xC0 / 255, green: 0x39 / 255, blue: 0x2B / 255),
                                                                    Color(red: 0x8E / 255, green: 0x2A / 255, blue: 0x20 / 255)], startPoint: .top, endPoint: .bottom))
            case .ghost, .dpad: return AnyShapeStyle(pressed ? Color.white.opacity(0.08) : Color.clear)
            case .accent, .enter: return AnyShapeStyle(palette.accent)
            default: return AnyShapeStyle(LinearGradient(colors: [keyTop, keyBottom], startPoint: .top, endPoint: .bottom))
            }
        }()
        let raised = look != .ghost && look != .dpad
        return configuration.label
            .font(.system(size: 11, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(look == .accent || look == .enter ? palette.onAccent : remoteText)
            .frame(maxWidth: look == .round || look == .ghost || look == .enter || look == .dpad ? nil : .infinity)
            .frame(height: height)
            .padding(.horizontal, look == .round || look == .ghost || look == .enter || look == .dpad ? 0 : 6)
            .background(shape.fill(fill))
            .background(shape.fill(raised ? keyEdge : .clear).offset(y: pressed ? 0 : 2))
            .offset(y: pressed && raised ? 2 : 0)
            .opacity(enabled ? 1 : 0.3)
            .contentShape(shape)
    }
}

/// The floating remote.
struct FloatingRemote: View {
    let enabled: (RemoteKey) -> Bool
    let press: (RemoteKey) -> Void
    let close: () -> Void
    /// Fainter while the player's controls are hidden, as on the website.
    let faint: Bool
    @State private var geometry = RemoteGeometry.load()
    @State private var dragFrom: RemoteGeometry?
    @State private var size = CGSize(width: 208, height: 600)

    private func key(_ key: RemoteKey, _ look: RemoteKeyStyle.Look = .plain, height: CGFloat = 30, label: String, @ViewBuilder _ face: () -> some View) -> some View {
        Button { press(key) } label: { face() }
            .buttonStyle(RemoteKeyStyle(look: look, height: height))
            .disabled(!enabled(key))
            .accessibilityLabel(label)
    }

    private func words(_ key: RemoteKey, _ text: String, label: String, _ look: RemoteKeyStyle.Look = .pill) -> some View {
        self.key(key, look, label: label) { Text(text) }
    }

    private func icon(_ key: RemoteKey, _ symbol: String, label: String, _ look: RemoteKeyStyle.Look = .plain, size: CGFloat = 13) -> some View {
        self.key(key, look, label: label) { Image(systemName: symbol).font(.system(size: size, weight: .bold)) }
    }

    private var remote: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                icon(.eject, "eject.fill", label: "Stop and close", .red, size: 12).frame(width: 30)
                Text("WITTYMEDIA").font(.system(size: 9, weight: .bold)).tracking(0.9).foregroundStyle(Color.white.opacity(0.62))
                    .lineLimit(1).frame(maxWidth: .infinity)
                Button { geometry.alpha = geometry.nextAlpha; geometry.save() } label: {
                    Image(systemName: "circle.lefthalf.filled").font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(RemoteKeyStyle(look: .ghost, height: 28)).frame(width: 28)
                .accessibilityLabel("Change how see-through the remote is")
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)) }
                    .buttonStyle(RemoteKeyStyle(look: .ghost, height: 28)).frame(width: 28)
                    .accessibilityLabel("Close the Remote")
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("player"))
                .onChanged { drag in
                    let from = dragFrom ?? geometry
                    dragFrom = from
                    geometry.x = (from.x ?? 0) + drag.translation.width
                    geometry.y = (from.y ?? 0) + drag.translation.height
                }
                .onEnded { _ in dragFrom = nil; geometry.save() })
            HStack(spacing: 8) {
                words(.topmenu, "TOP MENU", label: "Top menu")
                words(.menu, "MENU", label: "Menu")
            }
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0x3B / 255, green: 0x3F / 255, blue: 0x4A / 255), Color(red: 0x1C / 255, green: 0x1E / 255, blue: 0x24 / 255)],
                                         center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: 75))
                    .shadow(color: .black.opacity(0.6), radius: 3, y: 2)
                key(.up, .dpad, height: 42, label: "Up") { Image(systemName: "chevron.up").font(.system(size: 18, weight: .bold)) }.frame(width: 46).offset(y: -48)
                key(.down, .dpad, height: 42, label: "Down") { Image(systemName: "chevron.down").font(.system(size: 18, weight: .bold)) }.frame(width: 46).offset(y: 48)
                key(.left, .dpad, height: 42, label: "Left") { Image(systemName: "chevron.left").font(.system(size: 18, weight: .bold)) }.frame(width: 46).offset(x: -46)
                key(.right, .dpad, height: 42, label: "Right") { Image(systemName: "chevron.right").font(.system(size: 18, weight: .bold)) }.frame(width: 46).offset(x: 46)
                key(.enter, .enter, height: 64, label: "Enter") { Text("ENTER") }.frame(width: 64)
            }
            .frame(width: 150, height: 150)
            .padding(.vertical, 4)
            HStack(spacing: 8) {
                words(.return, "RETURN", label: "Return")
                words(.angle, "ANGLE", label: "Video version")
            }
            HStack(spacing: 8) {
                words(.audio, "AUDIO", label: "Audio & language")
                words(.subtitle, "SUBTITLE", label: "Subtitles")
            }
            HStack(spacing: 6) {
                icon(.prev, "backward.end.fill", label: "Previous chapter")
                icon(.rew, "backward.fill", label: "Rewind 10 s")
                icon(.ff, "forward.fill", label: "Forward 30 s")
                icon(.next, "forward.end.fill", label: "Next chapter")
            }
            HStack(spacing: 8) {
                icon(.stop, "stop.fill", label: "Stop", size: 11)
                icon(.play, "play.fill", label: "Play", .accent)
                icon(.pause, "pause.fill", label: "Pause")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(1...9, id: \.self) { digit in
                    words(RemoteKey(rawValue: "digit\(digit)")!, "\(digit)", label: "Button or chapter \(digit)", .digit)
                }
                Color.clear.frame(height: 30)
                words(.digit0, "0", label: "0", .digit)
                Color.clear.frame(height: 30)
            }
        }
        .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 16)
        .frame(width: 208)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 42 / 255, green: 45 / 255, blue: 53 / 255).opacity(geometry.alpha),
                                              Color(red: 21 / 255, green: 23 / 255, blue: 28 / 255).opacity(geometry.alpha)], startPoint: .top, endPoint: .bottom))
                .background(.ultraThinMaterial.opacity(geometry.alpha), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                .shadow(color: .black.opacity(0.6), radius: 20, y: 18)
        )
        .overlay(alignment: .bottomTrailing) { grip.padding(8) }
        .overlay { handles }
        .background(GeometryReader { box in Color.clear.onAppear { size = box.size } })
    }

    /// The two lines in the corner that say it can be made bigger.
    private var grip: some View {
        Path { path in
            path.move(to: CGPoint(x: 14, y: 6)); path.addLine(to: CGPoint(x: 6, y: 14))
            path.move(to: CGPoint(x: 14, y: 10)); path.addLine(to: CGPoint(x: 10, y: 14))
        }
        .stroke(Color.white.opacity(0.35), lineWidth: 1.2)
        .frame(width: 14, height: 14)
        .allowsHitTesting(false)
    }

    /// Edges and corners that make it bigger or smaller, as the website's handles. Two taps on one put it back.
    private var handles: some View {
        GeometryReader { box in
            let w = box.size.width, h = box.size.height
            let sides = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]
            ForEach(0..<sides.count, id: \.self) { at in
                let (dx, dy) = sides[at]
                let corner = dx != 0 && dy != 0
                Color.clear
                    .frame(width: corner ? 22 : dx == 0 ? max(w - 36, 0) : 10, height: corner ? 22 : dy == 0 ? max(h - 36, 0) : 10)
                    .contentShape(Rectangle())
                    .position(x: dx < 0 ? 1 : dx > 0 ? w - 1 : w / 2, y: dy < 0 ? 1 : dy > 0 ? h - 1 : h / 2)
                    .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("player"))
                        .onChanged { drag in resize(dx: dx, dy: dy, drag.translation) }
                        .onEnded { _ in dragFrom = nil; geometry.save() })
                    .onTapGesture(count: 2) { geometry.scale = 1; geometry.save() }
                    .accessibilityHidden(true)
            }
        }
    }

    private func resize(dx: Int, dy: Int, _ moved: CGSize) {
        let from = dragFrom ?? geometry
        dragFrom = from
        let gx = dx != 0 ? Double(CGFloat(dx) * moved.width / max(size.width, 1)) : 0
        let gy = dy != 0 ? Double(CGFloat(dy) * moved.height / max(size.height, 1)) : 0
        let scale = min(1.6, max(0.6, from.scale + (abs(gx) > abs(gy) ? gx : gy)))
        geometry.scale = scale
        if dx < 0 { geometry.x = (from.x ?? 0) + (from.scale - scale) * Double(size.width) }
        if dy < 0 { geometry.y = (from.y ?? 0) + (from.scale - scale) * Double(size.height) }
    }

    var body: some View {
        GeometryReader { space in
            let scale = CGFloat(geometry.scale)
            let w = size.width * scale, h = size.height * scale
            // Where it is: 18 from the right and 96 from the bottom until it's moved, and always on the screen.
            let x = min(max(CGFloat(geometry.x ?? Double(space.size.width - w - 18)), 4), max(4, space.size.width - w - 4))
            let y = min(max(CGFloat(geometry.y ?? Double(space.size.height - h - 96)), 4), max(4, space.size.height - h - 4))
            remote
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: w, height: h, alignment: .topLeading)
                .offset(x: x, y: y)
                .opacity(faint ? 0.45 : 1)
                .onAppear {
                    if geometry.x == nil { geometry.x = Double(x) }
                    if geometry.y == nil { geometry.y = Double(y) }
                }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("WittyMedia remote")
    }
}

/// The remote's keys in a strip above the seek bar, scrolling sideways when it's narrow. The numbers are left
/// off a phone, as on the website.
struct RemoteStrip: View {
    let enabled: (RemoteKey) -> Bool
    let press: (RemoteKey) -> Void
    let wide: Bool

    private func key(_ key: RemoteKey, label: String, accent: Bool = false, red: Bool = false, @ViewBuilder _ face: () -> some View) -> some View {
        Button { press(key) } label: { face() }
            .buttonStyle(StripKeyStyle(accent: accent, red: red))
            .disabled(!enabled(key))
            .accessibilityLabel(label)
    }

    private var rule: some View { Rectangle().fill(Color.white.opacity(0.14)).frame(width: 1, height: 22).padding(.horizontal, 2) }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                key(.topmenu, label: "Top menu") { Text("TOP MENU") }
                key(.menu, label: "Menu") { Text("MENU") }
                key(.return, label: "Return") { Text("RETURN") }
                rule
                key(.left, label: "Left") { Image(systemName: "chevron.left") }
                key(.up, label: "Up") { Image(systemName: "chevron.up") }
                key(.enter, label: "Enter", accent: true) { Text("OK") }
                key(.down, label: "Down") { Image(systemName: "chevron.down") }
                key(.right, label: "Right") { Image(systemName: "chevron.right") }
                rule
                key(.audio, label: "Audio & language") { Text("AUDIO") }
                key(.subtitle, label: "Subtitles") { Text("SUBTITLE") }
                key(.angle, label: "Video version") { Text("ANGLE") }
                if wide {
                    rule
                    ForEach([1, 2, 3, 4, 5, 6, 7, 8, 9, 0], id: \.self) { digit in
                        key(RemoteKey(rawValue: "digit\(digit)")!, label: "Button or chapter \(digit)") { Text("\(digit)") }
                    }
                }
                key(.eject, label: "Stop and close", red: true) { Image(systemName: "eject.fill") }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
        }
        .fixedSize(horizontal: true, vertical: false)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(Color.black.opacity(0.9)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Remote")
    }
}

private struct StripKeyStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.palette) private var palette
    var accent = false
    var red = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(accent ? palette.onAccent : Color.white)
            .padding(.horizontal, 9)
            .frame(minWidth: 30, minHeight: 30)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
                .fill(accent ? palette.accent : red ? Color(red: 0xC0 / 255, green: 0x39 / 255, blue: 0x2B / 255)
                      : Color.white.opacity(configuration.isPressed ? 0.2 : 0.1)))
            .opacity(enabled ? 1 : 0.3)
            .frame(minHeight: 44)
    }
}

/// "Keyboard shortcuts": the website's list, for a keyboard on an iPad.
struct ShortcutsDialog: View {
    @Environment(\.palette) private var palette
    let close: () -> Void

    var body: some View {
        ZStack {
            palette.scrim.ignoresSafeArea().onTapGesture(perform: close).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("Keyboard shortcuts").font(.system(size: 20, weight: .bold)).foregroundStyle(palette.text)
                    .accessibilityAddTraits(.isHeader)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(PlayerShortcuts.file, id: \.keys) { shortcut in
                            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s3) {
                                Text(shortcut.keys)
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(palette.text)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(RoundedRectangle(cornerRadius: Tokens.Radius.sm).fill(palette.card))
                                    .frame(width: 170, alignment: .leading)
                                Text(shortcut.what).font(.system(size: 14)).foregroundStyle(palette.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, Tokens.Space.s2)
                            .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 1) }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.top, 8).padding(.bottom, 14)
                }
                Text("Game controllers and TV remotes work too: the D-pad moves, A or OK chooses, B goes back.")
                    .font(.system(size: 13)).foregroundStyle(palette.textSecondary)
                HStack {
                    Spacer()
                    Button("Close", action: close).pageButton(.primary)
                }
                .padding(.top, Tokens.Space.s4)
            }
            .padding(Tokens.Space.s6)
            .frame(maxWidth: 520)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.xl, style: .continuous).fill(palette.panel))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.xl, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
            .padding(16)
            .padding(.vertical, 20)
        }
    }
}
#endif
