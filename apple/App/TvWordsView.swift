// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
#if os(tvOS)
import SwiftUI
import WittyKit

// Apple TV's Lyrics and Karaoke (board: "TV · karaoke", "TV · lyrics with Canvas"): the same two ways to read
// the words as on every platform, Follow along (a line to press, to jump) and Read, over the choice of Album art,
// Canvas video or Visualizer. Every control is a button, so the D-pad reaches all of them.

struct TvWordsView: View {
    enum Kind { case lyrics, karaoke }

    let kind: Kind
    let item: Item
    let glow: Color
    let viz: VisualizerPrefs
    let vizHere: Bool
    @ObservedObject var canvas: CanvasStatus
    let close: () -> Void

    @EnvironmentObject private var listening: Listening
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @ObservedObject private var store = MusicShowStore.shared
    @StateObject private var words = LyricsModel()
    @State private var index = -1
    private let tick = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    private var lines: [LyricLine] { words.lyrics?.timed ?? [] }
    private var timed: Bool { !lines.isEmpty }
    private var readable: String {
        words.lyrics?.plain.flatMap { $0.isEmpty ? nil : $0 } ?? lines.map(\.text).joined(separator: "\n")
    }

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            EllipticalGradient(colors: [glow.opacity(0.3), glow.opacity(0)], center: UnitPoint(x: 0.5, y: 0.4), startRadiusFraction: 0, endRadiusFraction: 0.8)
                .ignoresSafeArea()
            MusicBackdrop(item: item.id, prefs: viz, shownStyle: "", colour: glow, playing: listening.isPlaying, visualizer: vizHere,
                          shade: palette.background.opacity(0.55))
                .ignoresSafeArea()
            VStack(spacing: Tokens.Space.s3) {
                header
                HStack(alignment: .top, spacing: Tokens.Space.s6) {
                    MusicShowToggle(canvas: canvas, visualizer: vizHere)
                    LyricsModeToggle(timed: timed)
                }
                .remoteSection()
                stage.frame(maxWidth: .infinity, maxHeight: .infinity)
                controls
            }
            .padding(.horizontal, 90).padding(.vertical, 40)
        }
        .task { words.want(item.id, wanted: true, client: client, model: model) }
        .onReceive(tick) { _ in
            guard let lyrics = words.lyrics else { return }
            let at = lyrics.lineAt(seconds: listening.positionSec(), offset: words.offset)
            if at != index { index = at }
        }
        .onExitCommand(perform: close)
        .onPlayPauseCommand { listening.toggle() }
        .onDisappear { listening.stems.close() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 38, weight: .bold)).foregroundStyle(palette.text).lineLimit(1)
                Text(item.artist ?? item.albumArtist ?? "").font(.system(size: 29)).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Spacer()
            Button(kind == .karaoke ? "Leave karaoke" : "Close", action: close).action(pill: true)
        }
    }

    @ViewBuilder private var stage: some View {
        if words.lyrics == nil || words.loading {
            Text(words.failed.isEmpty ? "Looking for the words…" : words.failed).font(.system(size: 38, weight: .semibold)).foregroundStyle(palette.textSecondary)
        } else if !words.lyrics!.hasWords {
            Text("No words for this song.").font(.system(size: 38, weight: .semibold)).foregroundStyle(palette.textSecondary)
        } else if store.lyrics.effective(timed: timed) == .read {
            ScrollView {
                Button {} label: {
                    Text(readable).font(.system(size: 38, weight: .semibold)).foregroundStyle(palette.text)
                        .lineSpacing(10).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        } else if kind == .karaoke {
            TimelineView(.animation) { _ in
                let ms = listening.positionSec() * 1000 - words.offset
                let at = Karaoke.lineIndex(lines, ms)
                let now = at >= 0 ? lines[at] : nil
                let next = at + 1 < lines.count ? lines[at + 1] : nil
                VStack(spacing: 24) {
                    if let now, !now.text.isEmpty {
                        FlowRow(spacing: 0, lineSpacing: 10) {
                            ForEach(Array(Karaoke.words(now, next: next?.t).enumerated()), id: \.offset) { _, word in
                                let fill = Karaoke.fill(word, at: ms)
                                Text(word.text).font(.system(size: 76, weight: .heavy))
                                    .foregroundStyle(LinearGradient(stops: [.init(color: palette.accentText, location: 0), .init(color: palette.accentText, location: fill),
                                                                            .init(color: palette.text.opacity(0.4), location: fill), .init(color: palette.text.opacity(0.4), location: 1)],
                                                                    startPoint: .leading, endPoint: .trailing))
                            }
                        }
                        .accessibilityElement(children: .ignore).accessibilityLabel(now.text)
                    } else {
                        Text("♪").font(.system(size: 76, weight: .heavy)).foregroundStyle(palette.textHint)
                    }
                    Text(next?.text ?? " ").font(.system(size: 38, weight: .semibold)).foregroundStyle(palette.textSecondary).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { at, line in
                            Button { listening.seek(to: max(0, (line.t + words.offset) / 1000)) } label: {
                                Text(line.text.isEmpty ? "♪" : line.text)
                                    .font(.system(size: at == index ? 52 : 40, weight: .bold))
                                    .foregroundStyle(at == index ? palette.accentText : at < index ? palette.textHint : palette.textSecondary)
                                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(PlayerTime.format(line.t / 1000)): \(line.text.isEmpty ? "a break" : line.text)")
                            .accessibilityAddTraits(at == index ? [.isSelected] : [])
                            .id(at)
                        }
                    }
                    .padding(.vertical, 120)
                }
                .onChange(of: index) { at in
                    guard at >= 0 else { return }
                    withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(at, anchor: .center) }
                }
            }
            .remoteSection()
        }
    }

    @ViewBuilder private var controls: some View {
        VStack(spacing: Tokens.Space.s2) {
            if kind == .karaoke, model.has("karaoke-auto") {
                KaraokeStemsControl(stems: listening.stems, ink: StemInk(text: palette.text, quiet: palette.textSecondary, chip: palette.border,
                                                                         fill: palette.accent, onFill: palette.onAccent))
            }
            HStack(spacing: Tokens.Space.s2) {
                Button { listening.seek(by: -10) } label: { Image(systemName: "gobackward.10") }.action(pill: true).accessibilityLabel("Back 10 seconds")
                Button { listening.toggle() } label: { Image(systemName: listening.isPlaying ? "pause.fill" : "play.fill") }
                    .action(primary: true, pill: true).accessibilityLabel(listening.isPlaying ? "Pause" : "Play")
                Button { listening.seek(by: Listening.forwardSeconds) } label: { Image(systemName: "goforward.30") }.action(pill: true).accessibilityLabel("Forward 30 seconds")
                if timed {
                    Button("Sooner") { words.setOffset(LyricWords.nudge(words.offset, by: -250), client: client) }.action(pill: true)
                    Text(LyricWords.offset(words.offset)).font(.system(size: 25).monospacedDigit()).foregroundStyle(palette.textSecondary)
                    Button("Later") { words.setOffset(LyricWords.nudge(words.offset, by: 250), client: client) }.action(pill: true)
                    if words.offset != 0 { Button("Reset") { words.setOffset(0, client: client) }.action(pill: true) }
                }
                if kind == .karaoke {
                    Button("Key −") { listening.setSound { $0.keyShift = max(-6, $0.keyShift - 1) } }.action(pill: true)
                    Text("Key \(Int(listening.sound.keyShift))").font(.system(size: 25).monospacedDigit()).foregroundStyle(palette.textSecondary)
                    Button("Key +") { listening.setSound { $0.keyShift = min(6, $0.keyShift + 1) } }.action(pill: true)
                }
            }
            .remoteSection()
            if kind == .karaoke {
                Text("Vocals are separated on your server, so the cut is approximate. A microphone isn't used on Apple TV.")
                    .font(.system(size: 25)).foregroundStyle(palette.textSecondary).multilineTextAlignment(.center)
            }
        }
    }
}
#endif

#if os(tvOS)
extension TvWordsView.Kind: Identifiable { var id: Self { self } }
#endif
