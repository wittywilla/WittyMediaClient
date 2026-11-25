// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
#if os(tvOS)
import AVKit
import SwiftUI
import WittyKit

// Watching a channel, as the server's page does it (web/src/pages/tv/TvPlayer.tsx and MiniGuide.tsx),
// in the account's WittyTV look: the banner that drops in on every change of channel, and the mini
// guide over the picture. Select shows the banner; up and down change channel; left brings up the mini guide,
// where up and down move and Select tunes; right brings up the Dock (ten seconds back or on in what the server keeps of
// the channel, audio, subtitles, Look); Play/Pause pauses; Back closes the topmost, then goes back to the guide.

struct ChannelPlayer: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var live = LiveTv.shared
    @ObservedObject private var looks = TvLookStore.shared
    @State private var key: String
    @State private var banner = true
    @State private var mini = false
    @State private var dockOpen = false
    @State private var lookOpen = false
    /// WittyTV More info: the channel and a moment in the programme (Unix seconds).
    @State private var info: MoreInfoAsk?
    @State private var lineup: [GuideChannel] = []
    @State private var bannerShown = 0
    @FocusState private var focused: Bool
    @FocusState private var failureFocused: Bool

    init(start: String) { _key = State(initialValue: start) }

    private var dress: TvDress { looks.dress }
    private var channel: GuideChannel? { lineup.first { $0.key == key } ?? model.channels.first { $0.key == key } }
    private var failedHere: Bool { live.isFailed && live.key == key }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            LivePicture(player: live.player).ignoresSafeArea()
            if live.key == key, live.playing, live.info?.now?.kind == "slate" {
                SlateCard(name: live.info?.name ?? channel?.name ?? "", next: live.info?.next).frame(maxHeight: .infinity)
            }
            if !failedHere, live.key != key || !live.playing {
                LoadingView()
            }
            if mini {
                MiniGuide(dress: dress, tuned: key, set: chosenSet, onTune: tune, onClose: closeMini, onFull: toGuide,
                          onInfo: { c in info = MoreInfoAsk(channel: c, start: Int64(Date().timeIntervalSince1970)) },
                          onLive: live.fromStart == nil ? nil : { closeMini(); live.backToLive(); showBanner() })
                    .padding(.horizontal, 77).padding(.bottom, 92)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            } else if banner, !dockOpen {
                TimelineView(.periodic(from: .now, by: 5)) { time in
                    ChannelBanner(dress: dress, channel: channel, info: live.key == key ? live.info : nil, behind: live.behind,
                                  now: Int64(time.date.timeIntervalSince1970))
                }
                .padding(.horizontal, 77).padding(.bottom, 92)
                .transition(.opacity)
            }
            if dockOpen {
                ChannelDock(dress: dress, live: live, onGuide: toGuide, onLook: { lookOpen = true }, onClose: closeDock,
                            onInfo: { info = MoreInfoAsk(channel: key, start: live.info?.now?.start ?? Int64(Date().timeIntervalSince1970)) })
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            if live.inBreak != nil, live.key == key, !mini, !dockOpen {
                // Remote words only: Right opens the Dock, where Skip break is first.
                Text("Ad break · Right, then Skip break")
                    .font(.wmLabel).foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(.black.opacity(0.6)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(.bottom, 152).padding(.trailing, 157)
            }
            if let programme = live.fromStart, !mini, !dockOpen {
                Text(live.shiftFrom != nil && live.behind >= 60
                     ? "\(programme.title) · \(Int((live.behind / 60).rounded())) min behind live · Right, then Back to live"
                     : live.shiftFrom != nil ? "\(programme.title) · Right, then Back to live"
                     : "From the start of \(programme.title) · Right, then Back to live")
                    .font(.wmLabel).foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(.black.opacity(0.6)))
                    .frame(maxHeight: .infinity, alignment: .top).padding(.top, 60)
            } else if live.behind > 20, !mini, !dockOpen {
                Text("\(Int((live.behind / 60).rounded())) min behind live · Play/Pause twice for live")
                    .font(.wmLabel).foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(.black.opacity(0.6)))
                    .frame(maxHeight: .infinity, alignment: .top).padding(.top, 60)
            }
        }
        // A channel that failed gives the focus to its buttons, which the remote couldn't reach inside a focusable player.
        .focusable(!mini && !dockOpen && !failedHere)
        .focused($focused)
        // None when it failed, so the arrows move between its buttons.
        .onMoveCommand(perform: failedHere ? nil : { direction in
            guard !mini, !dockOpen else { return }
            switch direction {
            case .up: step(1)
            case .down: step(-1)
            // Left opens the mini guide and Right the Dock, as in every WittyTV look and on the web.
            case .left: mini = true
            case .right: dockOpen = true
            @unknown default: break
            }
        })
        .onPlayPauseCommand {
            if live.playing { live.pause() } else if live.fromStart == nil, live.behind > 20, bannerShown > 0 { live.goLive() } else { live.resume() }
            showBanner()
        }
        // OK shows what's on (the banner); the mini guide is a press to the left.
        .onTapGesture { if !mini, !dockOpen, !failedHere { showBanner() } }
        .onExitCommand(perform: mini ? { closeMini() } : nil)
        .sheet(isPresented: $lookOpen) { TvLookPanel() }
        .sheet(item: $info) { ask in
            MoreInfoSheet(channel: ask.channel, start: ask.start, onWatch: { _ in info = nil }, onFromStart: { _, _ in info = nil })
        }
        // Over the player, not in it: inside the focusable player its buttons were out of the remote's reach.
        .overlay {
            if case .failed(let why) = live.state, live.key == key { failure(why) }
        }
        .onAppear {
            focused = true
            GuideReturn.key = key
            live.muted = false
            live.watch(key, client: client)
            LastChannel.remember(key)
        }
        .task {
            await TvLookStore.shared.load(client: client, themeId: model.effectiveThemeId, app: model.tvAppColours)
            // Up and down go through the set the guide shows.
            if !chosenSet.isEmpty {
                if let inSet = try? await client.channelList(set: chosenSet, limit: 20000) { lineup = uniqued(inSet.channels ?? []) }
            } else if let all = try? await client.lineup() {
                lineup = uniqued(all.channels ?? [])
            }
        }
        .task(id: key) {
            await TvLogos.shared.ask(channel?.brand.map { [$0] } ?? [], client: client)
        }
        // What's on says itself for a moment on every change, then gets out of the way.
        .task(id: bannerShown) {
            guard banner else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000) // the banner shows for three seconds
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
        .onChange(of: failedHere) { failed in
            DispatchQueue.main.async { if failed { failureFocused = true } else { focused = true } }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { live.resume() } else { live.pause() }
        }
        .onDisappear {
            live.muted = !looks.look.previewSound
            // Back to the guide: the preview carries on with this channel exactly where it is, started over or gone
            // back included (a programme from its start used to end with the player). Anywhere else: it stops.
            DispatchQueue.main.async {
                if !model.path.contains(.guide) { live.stop() }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .navigationBarHidden(true)
    }

    /// The set this TV shows in the guide, as the server is asked for it; empty for all channels.
    private var chosenSet: String {
        guard let id = GuideDevice.shared.set(for: GuideDevice.setKey(model: model, client: client)),
              id != ChannelSetRules.all else { return "" }
        return id
    }

    /// When the channel can't play: what happened in the server's words and always a way forward (a Design 2 page).
    private func failure(_ why: String) -> some View {
        let ch = channel
        let kind = TvProblem.kind(why: why, security: ch?.security?.state)
        let spec = TvProblem.spec(why: why, kind: kind, number: ch?.number ?? "", name: ch?.name ?? "This channel",
                                  alternative: ch?.alternative.map { .init(number: "\($0.number)", name: $0.name) },
                                  fromStart: live.fromStart?.title, security: ch?.security.map { ($0.label, $0.detail) })
        return DesignSpecPage(spec: spec, onPress: { id in
            switch id {
            case "alternative": if let alt = ch?.alternative { tune(alt.key) }
            case "try-again": live.retry()
            case "back-to-live": live.backToLive(); showBanner()
            case "next-channel": step(1)
            case "back-to-the-guide": toGuide()
            default: break
            }
        }, onBack: toGuide)
        .background(model.palette.background.ignoresSafeArea())
        .focusSection()
        .accessibilityIdentifier("tv.channel.problem")
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

    private func closeDock() {
        dockOpen = false
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
        // In a bumper or a gap the channel's "programme" is its slate: the banner names what comes next instead, and Next is
        // the next real programme, never another slate (#85).
        let slate = programme?.kind == "slate"
        let upcoming = GuideRules.upcoming(after: programme, on: channel, told: info?.next)
        let headline = GuideRules.headline(programme, upcoming: upcoming, fallback: info?.name ?? channel?.name ?? "")
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
                    Text(headline).font(dress.font(25, .bold)).lineLimit(1)
                        .textCase(shape == .teletext ? .uppercase : nil)
                    if let rating = programme?.rating {
                        Text(rating).font(dress.font(15)).padding(.horizontal, 5).overlay(RoundedRectangle(cornerRadius: dress.radius).strokeBorder(p.soft, lineWidth: 1))
                    }
                }
                Text(slate ? upcoming.map { "At \(tvClock($0.start))" } ?? "Back soon" : programme?.sub ?? (info == nil ? "Tuning…" : programme == nil ? "No guide data" : ""))
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
                if !slate, let next = upcoming {
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
    /// The guide's set, or empty for all channels.
    let set: String
    let onTune: (String) -> Void
    let onClose: () -> Void
    let onFull: () -> Void
    /// More info about what is on a channel of the list (a menu item on its row).
    var onInfo: ((String) -> Void)? = nil
    /// Back to the channel as it is now, while watching a programme from its start.
    let onLive: (() -> Void)?
    @State private var rows: [GuideChannel]?
    @State private var error = ""
    @FocusState private var focused: String?
    private static let full = " full guide", close = " close", live = " live"

    var body: some View {
        let p = dress.paint
        let shape = dress.shape
        let radius: CGFloat = [.teletext, .listings, .receiver].contains(shape) ? 0 : 6
        let now = Int64(Date().timeIntervalSince1970)
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text("Now and next").font(dress.font(21.25, .bold)).foregroundStyle(p.accent).frame(maxWidth: .infinity, alignment: .leading)
                if let onLive {
                    Button("Back to live", action: onLive).buttonStyle(TvButtonStyle(dress: dress, on: true)).focused($focused, equals: MiniGuide.live)
                }
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
                                    .contextMenu { if let onInfo { Button("More info") { onInfo(c.key) } } }
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
                let g = try await client.guidePage("/guide?hours=4&offset=0&limit=500" + (set.isEmpty ? "" : "&set=\(WittyClient.queryValue(set))"))
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
