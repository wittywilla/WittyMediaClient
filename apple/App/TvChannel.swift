#if os(tvOS)
import AVKit
import SwiftUI
import WittyKit

// Watching a channel, as the server's page does it (web/src/pages/tv/TvPlayer.tsx and MiniGuide.tsx),
// in the account's WittyTV look: the banner that drops in on every change of channel, and the mini
// guide over the picture. Up and down change channel; Select brings up the mini guide, where up and
// down move and Select tunes; left and right go back and on in what the server keeps of the channel;
// Play/Pause pauses; Back closes the mini guide, then goes back to the guide.

struct ChannelPlayer: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var live = LiveTv.shared
    @ObservedObject private var looks = TvLookStore.shared
    @State private var key: String
    @State private var banner = true
    @State private var mini = false
    @State private var lineup: [GuideChannel] = []
    @State private var bannerShown = 0
    @FocusState private var focused: Bool

    init(start: String) { _key = State(initialValue: start) }

    private var dress: TvDress { looks.dress }
    private var channel: GuideChannel? { lineup.first { $0.key == key } ?? model.channels.first { $0.key == key } }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            LivePicture(player: live.player).ignoresSafeArea()
            if live.key == key, live.playing, live.info?.now?.kind == "slate" {
                SlateCard(name: live.info?.name ?? channel?.name ?? "", next: live.info?.next).frame(maxHeight: .infinity)
            }
            if case .failed(let why) = live.state, live.key == key {
                failure(why)
            } else if live.key != key || !live.playing {
                LoadingView()
            }
            if mini {
                MiniGuide(dress: dress, tuned: key, onTune: tune, onClose: closeMini, onFull: toGuide)
                    .padding(.horizontal, 77).padding(.bottom, 92)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            } else if banner {
                TimelineView(.periodic(from: .now, by: 5)) { time in
                    ChannelBanner(dress: dress, channel: channel, info: live.key == key ? live.info : nil, behind: live.behind,
                                  now: Int64(time.date.timeIntervalSince1970))
                }
                .padding(.horizontal, 77).padding(.bottom, 92)
                .transition(.opacity)
            }
            if live.behind > 20, !mini {
                Text("\(Int((live.behind / 60).rounded())) min behind live · Play/Pause twice for live")
                    .font(.wmLabel).foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(.black.opacity(0.6)))
                    .frame(maxHeight: .infinity, alignment: .top).padding(.top, 60)
            }
        }
        .focusable(!mini)
        .focused($focused)
        .onMoveCommand { direction in
            guard !mini else { return }
            switch direction {
            case .up: step(1)
            case .down: step(-1)
            case .left: live.seek(by: -10); showBanner()
            case .right: live.seek(by: 10); showBanner()
            @unknown default: break
            }
        }
        .onPlayPauseCommand {
            if live.playing { live.pause() } else if live.behind > 20, bannerShown > 0 { live.goLive() } else { live.resume() }
            showBanner()
        }
        .onTapGesture { if !mini { mini = true } }
        .onExitCommand(perform: mini ? { closeMini() } : nil)
        .onAppear {
            focused = true
            GuideReturn.key = key
            live.muted = false
            live.watch(key, client: client)
            LastChannel.remember(key)
        }
        .task {
            await TvLookStore.shared.load(client: client, themeId: model.effectiveThemeId, app: model.tvAppColours)
            if let all = try? await client.lineup() { lineup = uniqued(all.channels ?? []) }
        }
        .task(id: key) {
            await TvLogos.shared.ask(channel?.brand.map { [$0] } ?? [], client: client)
        }
        // What's on says itself for a moment on every change, then gets out of the way.
        .task(id: bannerShown) {
            guard banner else { return }
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            if !Task.isCancelled { withAnimation { banner = false } }
        }
        // When a programme ends the banner moves on to the next.
        .task(id: live.info?.now?.end) {
            guard let end = live.info?.now?.end else { return }
            let wait = end - Int64(Date().timeIntervalSince1970)
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait + 2) * 1_000_000_000) }
            if Task.isCancelled { return }
            await live.refreshInfo()
            showBanner()
        }
        .onChange(of: live.playing) { on in if on { showBanner() } }
        .onChange(of: scenePhase) { phase in
            if phase == .active { live.resume() } else { live.pause() }
        }
        .onDisappear {
            live.muted = !looks.look.previewSound
            // Back to the guide: the preview carries on with this channel. Anywhere else: it stops.
            DispatchQueue.main.async {
                if !model.path.contains(.guide) { live.stop() }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .navigationBarHidden(true)
    }

    private func failure(_ why: String) -> some View {
        let p = dress.paint
        return VStack(spacing: 16) {
            Text(channel.map { "Channel \($0.number ?? "") \($0.name)" } ?? "This channel").font(.wmSection)
            Text(why).multilineTextAlignment(.center)
            HStack(spacing: 16) {
                if let alt = channel?.alternative {
                    Button("Watch \(alt.number) \(alt.name) instead") { tune(alt.key) }.buttonStyle(TvButtonStyle(dress: dress, on: true))
                }
                Button("Try again") { live.retry() }.buttonStyle(TvButtonStyle(dress: dress))
                Button("Next channel") { step(1) }.buttonStyle(TvButtonStyle(dress: dress))
                Button("Back to the guide", action: toGuide).buttonStyle(TvButtonStyle(dress: dress))
            }
        }
        .foregroundStyle(p.text)
        .padding(32)
        .background(RoundedRectangle(cornerRadius: 14).fill(p.panel))
        .frame(maxHeight: .infinity)
        .focusSection()
    }

    /// Back to the guide this came from, or to one in this player's place: leaving a guide opened from
    /// here mustn't lead back into the player, or Back could never get out.
    private func toGuide() {
        if model.path.dropLast().contains(.guide) {
            model.path.removeLast()
        } else if !model.path.isEmpty {
            model.path[model.path.count - 1] = .guide
        }
    }

    private func showBanner() {
        withAnimation { banner = true }
        bannerShown += 1
    }

    private func tune(_ next: String) {
        closeMini()
        guard next != key else { return }
        key = next
        GuideReturn.key = next
        LastChannel.remember(next)
        live.watch(next, client: client)
        showBanner()
    }

    private func closeMini() {
        mini = false
        DispatchQueue.main.async { focused = true }
    }

    private func step(_ by: Int) {
        let list = lineup.isEmpty ? model.channels : lineup
        guard let next = ServerPages.channel(from: key, by: by, in: list), next.key != key else { return }
        tune(next.key)
    }
}

/// The banner every box of the era showed on a change of channel: the channel, what's on and how far
/// through, what's next and the time.
struct ChannelBanner: View {
    let dress: TvDress
    let channel: GuideChannel?
    let info: Tuned?
    let behind: Double
    let now: Int64

    var body: some View {
        let p = dress.paint
        let shape = dress.shape
        let programme = info?.now
        let radius: CGFloat = [.receiver, .teletext, .listings].contains(shape) ? 0 : shape == .outline ? 14 : 6
        HStack(alignment: .center, spacing: 14) {
            VStack(spacing: 2) {
                if let channel { ChannelLogo(dress: dress, channel: channel, size: CGSize(width: 80, height: 40), highlighted: false) }
                Text(info?.number ?? channel?.number ?? "").font(dress.font(37.5, .bold, digits: shape == .receiver)).foregroundStyle(p.accent)
                Text(info?.name ?? channel?.name ?? "").font(dress.font(17.5, .bold)).lineLimit(2).multilineTextAlignment(.center).frame(maxWidth: 140)
            }
            .frame(minWidth: 100)
            .padding(.trailing, 14)
            .overlay(alignment: .trailing) { p.line.frame(width: shape == .receiver || shape == .listings ? 1 : 2) }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(programme?.title ?? info?.name ?? channel?.name ?? "").font(dress.font(25, .bold)).lineLimit(1)
                        .textCase(shape == .teletext ? .uppercase : nil)
                    if let rating = programme?.rating {
                        Text(rating).font(dress.font(15)).padding(.horizontal, 5).overlay(RoundedRectangle(cornerRadius: dress.radius).strokeBorder(p.soft, lineWidth: 1))
                    }
                }
                Text(programme?.sub ?? (info == nil ? "Tuning…" : programme == nil ? "No guide data" : ""))
                    .font(dress.font(18.75, .bold)).foregroundStyle(p.accent).lineLimit(1)
                if let programme {
                    HStack(spacing: 8) {
                        Text(tvClock(programme.start))
                        GeometryReader { box in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(.black.opacity(0.5)).overlay(Rectangle().strokeBorder(p.line, lineWidth: 1))
                                Rectangle().fill(p.accent).frame(width: box.size.width * programme.fraction(at: now))
                            }
                        }
                        .frame(height: 8)
                        Text(tvClock(programme.end))
                    }
                    .font(dress.font(16.25)).foregroundStyle(p.soft)
                    .padding(.top, 4)
                }
                if let next = info?.next {
                    Text("Next: \(next.title) · \(GuideRules.span(next.start, next.end))").font(dress.font(16.25)).foregroundStyle(p.soft).lineLimit(1)
                }
                if let playing = info?.playing {
                    Text("Playing now: \(playing.title)").font(dress.font(16.25)).foregroundStyle(p.soft).lineLimit(1)
                }
                ForEach(info?.notices ?? channel?.notices ?? [], id: \.self) { n in
                    Text(n).font(dress.font(16.25)).foregroundStyle(p.accent).lineLimit(2)
                }
                Text("Select: now and next · ▲▼ channel · Back: the guide").font(dress.font(15)).foregroundStyle(p.soft).padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(tvClock(now)).font(dress.font(25, .bold, digits: shape == .receiver)).monospacedDigit().foregroundStyle(p.accent)
        }
        .foregroundStyle(p.text)
        .padding(.vertical, 10).padding(.horizontal, 14)
        .background {
            switch shape {
            case .receiver, .teletext, .listings, .outline, .compact: p.bg
            default: LinearGradient(colors: [p.panel2, p.bg], startPoint: .top, endPoint: .bottom)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            if shape != .teletext {
                RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(p.line, lineWidth: [.receiver, .listings, .outline, .compact].contains(shape) ? 1 : 2)
            }
        }
        .overlay { if shape == .box { Bevel().clipShape(RoundedRectangle(cornerRadius: radius)) } }
        .shadow(color: .black.opacity(0.5), radius: 13, y: 8)
        .accessibilityElement(children: .combine)
    }
}

/// A few channels over the picture, with what's on them now and next, without leaving what's
/// playing. Up and down move, Select tunes, Back closes.
struct MiniGuide: View {
    @Environment(\.client) private var client
    let dress: TvDress
    let tuned: String
    let onTune: (String) -> Void
    let onClose: () -> Void
    let onFull: () -> Void
    @State private var rows: [GuideChannel]?
    @State private var error = ""
    @FocusState private var focused: String?
    private static let full = " full guide", close = " close"

    var body: some View {
        let p = dress.paint
        let shape = dress.shape
        let radius: CGFloat = [.teletext, .listings, .receiver].contains(shape) ? 0 : 6
        let now = Int64(Date().timeIntervalSince1970)
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text("Now and next").font(dress.font(21.25, .bold)).foregroundStyle(p.accent).frame(maxWidth: .infinity, alignment: .leading)
                Button("Full guide", action: onFull).buttonStyle(TvButtonStyle(dress: dress)).focused($focused, equals: MiniGuide.full)
                Button("Close", action: onClose).buttonStyle(TvButtonStyle(dress: dress)).focused($focused, equals: MiniGuide.close)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(p.panel)
            .focusSection()
            if !error.isEmpty {
                Text(error).foregroundStyle(p.err).padding(16)
            } else if let rows {
                ScrollViewReader { scroller in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { c in
                                Button { if c.canTune { onTune(c.key) } } label: { row(c, now: now) }
                                    .buttonStyle(MiniRowStyle(dress: dress))
                                    .focused($focused, equals: c.key)
                                    // A scroll view keeps Up at its top row: from there it goes to the buttons above.
                                    .onMoveCommand { if $0 == .up, c.key == rows.first?.key { focused = MiniGuide.full } }
                                    .disabled(!c.canTune)
                                    .id(c.key)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .frame(height: 7 * 60 + 16)
                    .focusSection()
                    .onAppear {
                        scroller.scrollTo(tuned, anchor: .center)
                        DispatchQueue.main.async { focused = tuned }
                    }
                }
            } else {
                Text("Loading…").foregroundStyle(p.soft).padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: 980)
        .background(p.bg)
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(p.line, lineWidth: 2))
        .shadow(color: .black.opacity(0.5), radius: 13, y: 8)
        .focusSection()
        .task {
            do {
                let g = try await client.guidePage("/guide?hours=4&offset=0&limit=500")
                rows = uniqued(g.channels ?? [])
            } catch { self.error = (error as? APIError)?.message ?? "The guide couldn't be loaded." }
        }
    }

    private func row(_ c: GuideChannel, now: Int64) -> some View {
        let on = c.on(at: now)
        let next = c.programmes?.filter { $0.start > now && $0.kind != "slate" }.min { $0.start < $1.start }
        return MiniRowContent(dress: dress, channel: c, on: on, next: next, now: now, tuned: c.key == tuned)
    }
}

private struct MiniRowContent: View {
    @Environment(\.isFocused) private var focused
    let dress: TvDress
    let channel: GuideChannel
    let on: GuideProgramme?
    let next: GuideProgramme?
    let now: Int64
    let tuned: Bool

    var body: some View {
        let p = dress.paint
        HStack(spacing: 10) {
            (Text(channel.number ?? "").foregroundColor(focused ? p.hiText : p.accent).bold() + Text(" " + channel.name + (tuned ? " ●" : "")))
                .lineLimit(1).frame(width: 260, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(on?.title ?? (channel.kind == "library" ? "Off air" : "No guide data")).bold().lineLimit(1)
                if let on { Text(GuideRules.left(on.end - now) + " left").font(dress.font(17.5)).foregroundStyle(focused ? p.hiText : p.soft).fixedSize() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                if let next { Text(tvClock(next.start) + " " + next.title) } else { Text("") }
            }
            .font(dress.font(17.5)).foregroundStyle(focused ? p.hiText : p.soft).lineLimit(1).frame(width: 260, alignment: .leading)
        }
        .font(dress.font(21.25))
        .foregroundStyle(focused ? p.hiText : p.text)
        .padding(.horizontal, 10)
        .frame(minHeight: 56)
        .accessibilityElement(children: .combine)
    }
}

private struct MiniRowStyle: ButtonStyle {
    let dress: TvDress

    func makeBody(configuration: Configuration) -> some View {
        MiniRowBody(label: configuration.label, dress: dress, pressed: configuration.isPressed)
    }
}

private struct MiniRowBody<Label: View>: View {
    @Environment(\.isFocused) private var focused
    @Environment(\.isEnabled) private var enabled
    let label: Label
    let dress: TvDress
    let pressed: Bool

    var body: some View {
        label
            .background(focused ? dress.paint.hi : .clear)
            .overlay(alignment: .top) { dress.paint.panel2.frame(height: 1) }
            .opacity(enabled ? (pressed ? 0.85 : 1) : 0.5)
    }
}
#endif
