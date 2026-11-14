// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// Design 2, songs, karaoke and visualizers (DESIGN-2.md sections 10 and 13). The parts every music view shares, on
// every platform and in every look: the three-way choice of what fills the place of the album art, the two ways to
// read lyrics, and the visualizer's effects picker. They draw with the look's palette and its `.action` finish, so
// a look's buttons stay the look's buttons.

// MARK: - What is chosen, kept on this device

@MainActor
final class MusicShowStore: ObservableObject {
    static let shared = MusicShowStore()

    @Published var show: MusicShow { didSet { show.save() } }
    @Published var lyrics: LyricsMode { didSet { lyrics.save() } }

    private init() {
        show = MusicShow.load()
        lyrics = LyricsMode.load()
    }
}

/// Whether the song or its album has a Canvas video, and whether it may play here and now.
@MainActor
final class CanvasStatus: ObservableObject {
    @Published private(set) var info: CanvasInfo?
    private var item: Int64?

    func load(item: Int64?, client: WittyClient, enabled: Bool) async {
        guard item != self.item || info == nil else { return }
        self.item = item
        info = nil
        guard let item, enabled else { return }
        let found = try? await client.canvas(item: item)
        if !Task.isCancelled { info = found }
    }

    func note(_ conditions: CanvasConditions) -> String? { MusicShow.canvasNote(info: info, conditions: conditions) }
    func plays(_ conditions: CanvasConditions) -> Bool { note(conditions) == nil }
}

// MARK: - The seam to the effects renderer

/// What an effect needs to draw itself.
struct VisualizerLook {
    var effect: String
    var colourFamily: String
    var intensity: Double
    var speed: Double
    var calm: Bool
    var accent: Color
    var playing: Bool
}

/// The Metal effects (the seventeen classics and Aurora Rings) are drawn by their own renderer. It sets `make` once,
/// at launch; until it has, an effect that only it can draw is shown as Bars, and the picker says so.
enum VisualizerEffectSeam {
    @MainActor static var make: ((VisualizerLook) -> AnyView)?
    @MainActor static var available: Bool { make != nil }
}

/// The visualizer as a layer: one of the app's own three, or an effect from the renderer.
struct MusicVisualizerLayer: View {
    let prefs: VisualizerPrefs
    /// The style being shown when auto-change is on; empty is the saved one.
    var shown = ""
    let colour: Color
    let playing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let id = shown.isEmpty ? prefs.effect.id : shown
        let effect = VisualizerEffects.named(id) ?? prefs.effect
        Group {
            if !effect.native, let make = VisualizerEffectSeam.make {
                make(VisualizerLook(effect: effect.id, colourFamily: prefs.colour, intensity: prefs.intensity, speed: prefs.speed,
                                    calm: prefs.calmNow(reduceMotion: reduceMotion), accent: colour, playing: playing))
            } else {
                VisualizerBackground(style: effect.native ? effect.id : "bars", slow: prefs.calmNow(reduceMotion: reduceMotion), colour: colour, playing: playing)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Album art, Canvas video, Visualizer

/// The three-way choice. Canvas video is dimmed with a note when there is none or it can't play here, never hidden.
struct MusicShowToggle: View {
    @ObservedObject private var store = MusicShowStore.shared
    @ObservedObject private var watch = CanvasWatch.shared
    @ObservedObject var canvas: CanvasStatus
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    /// False when the owner has taken the visualizer off the server.
    var visualizer = true
    var compact = false

    var body: some View {
        let note = canvas.note(watch.conditions(server: client.base))
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Behind the words")
                    .font(.system(size: 11, weight: .bold)).textCase(.uppercase).tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
                    .opacity(compact ? 0 : 1).frame(width: compact ? 0 : nil)
                ForEach(MusicShow.allCases, id: \.self) { choice in
                    let off = (choice == .canvas && note != nil) || (choice == .viz && !visualizer)
                    Button { store.show = choice } label: { Text(choice.words) }
                        .action(selected: store.show == choice, pill: true)
                        .opacity(off ? 0.45 : 1)
                        .overlay { if off { Capsule().strokeBorder(palette.textSecondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3])) } }
                        .accessibilityAddTraits(store.show == choice ? [.isSelected] : [])
                        .accessibilityHint(off ? (choice == .canvas ? (note ?? "") : "The visualizer is off on this server.") : "")
                }
            }
            if store.show == .canvas, let note {
                Text(note).font(.system(size: 12)).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { watch.watch() }
        .onDisappear { watch.stop() }
    }
}

/// Follow along (timed, press a line to jump) or Read (plain text at your own pace).
struct LyricsModeToggle: View {
    @ObservedObject private var store = MusicShowStore.shared
    @Environment(\.palette) private var palette
    let timed: Bool

    var body: some View {
        let note = LyricsMode.followNote(timed: timed)
        let mode = store.lyrics.effective(timed: timed)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Lyrics")
                    .font(.system(size: 11, weight: .bold)).textCase(.uppercase).tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
                ForEach(LyricsMode.allCases, id: \.self) { choice in
                    let off = choice == .follow && !timed
                    Button { store.lyrics = choice } label: { Text(choice.words) }
                        .action(selected: mode == choice, pill: true)
                        .opacity(off ? 0.45 : 1)
                        .overlay { if off { Capsule().strokeBorder(palette.textSecondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3])) } }
                        .accessibilityAddTraits(mode == choice ? [.isSelected] : [])
                        .accessibilityHint(off ? (note ?? "") : "")
                }
            }
            if let note { Text(note).font(.system(size: 12)).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

/// The picture a music view puts behind its words: nothing for Album art (the view's own art stays), the looping
/// silent Canvas video, or the visualizer.
struct MusicBackdrop: View {
    @ObservedObject private var store = MusicShowStore.shared
    let item: Int64?
    let prefs: VisualizerPrefs
    let shownStyle: String
    let colour: Color
    let playing: Bool
    var visualizer = true
    var shade = Color.black.opacity(0.5)
    var active = true

    var body: some View {
        ZStack {
            if store.show == .canvas { CanvasLayer(item: item, active: active, shade: shade) }
            if store.show == .viz, visualizer, active { MusicVisualizerLayer(prefs: prefs, shown: shownStyle, colour: colour, playing: playing) }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - The effects picker

/// A level (intensity, speed) as a row of steps: it works with a finger, a pointer and a TV remote alike.
private struct LevelRow: View {
    @Environment(\.palette) private var palette
    let name: String
    let value: Double
    var range: ClosedRange<Double> = 0...1
    let set: (Double) -> Void

    private var share: Double { max(0, min(1, (value - range.lowerBound) / (range.upperBound - range.lowerBound))) }
    private func step(_ by: Double) { set(max(range.lowerBound, min(range.upperBound, ((value + by) * 10).rounded() / 10))) }

    var body: some View {
        HStack(spacing: 10) {
            Text(name).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textSecondary).frame(width: 78, alignment: .leading)
            Button { step(-0.1) } label: { Image(systemName: "minus") }
                .action(pill: true).accessibilityLabel("Less \(name.lowercased())")
            ZStack(alignment: .leading) {
                Capsule().fill(palette.control)
                GeometryReader { geo in Capsule().fill(palette.accent).frame(width: geo.size.width * share) }
            }
            .frame(height: 8)
            Button { step(0.1) } label: { Image(systemName: "plus") }
                .action(pill: true).accessibilityLabel("More \(name.lowercased())")
            Text("\(Int((value * 100).rounded()))%").font(.system(size: 13).monospacedDigit()).foregroundStyle(palette.textSecondary).frame(width: 44, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
    }
}

/// Effects, colours, options, intensity and speed (the board's `vizpick`), as WittyVisualizer offers them. Choices are
/// kept in the profile's own WittyVisualizer settings, the same ones the website and its Settings page use, and
/// applied as they are made.
struct VisualizerPickerView: View {
    @Environment(\.palette) private var palette
    @ObservedObject private var watch = CanvasWatch.shared
    let prefs: VisualizerPrefs
    var choices = VisualizerChoices.fallback
    let change: ((inout VisualizerPrefs) -> Void) -> Void
    let close: () -> Void

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.text).accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func effectTile(_ e: VisualizerEffect) -> some View {
        let on = prefs.style == e.id
        return Button { change { $0.style = e.id; $0.viz = true } } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(e.name).font(.system(size: 14, weight: .bold)).foregroundStyle(on ? palette.onAccent : palette.text).lineLimit(1)
                Text(e.about).font(.system(size: 11)).foregroundStyle(on ? palette.onAccent.opacity(0.85) : palette.textSecondary).lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(on ? palette.accent : palette.card))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).strokeBorder(on ? palette.focus : palette.border, lineWidth: on ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(e.name)
        .accessibilityHint(e.about)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Effects").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.text).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Done", action: close).action(primary: true, pill: true)
                }
                Text("Pick an effect, or let it change by itself. Calm mode leaves out the lively ones. Your choices are the same on every device and in WittyVisualizer's settings.")
                    .font(.system(size: 13)).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                if !VisualizerEffectSeam.available {
                    Text("The full effects draw on the next update of this app. Until then they show as Bars.")
                        .font(.system(size: 12)).foregroundStyle(palette.warn).fixedSize(horizontal: false, vertical: true)
                }
                section("Effects") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                        ForEach(choices.effects) { effectTile($0) }
                    }
                }
                section("Colours") {
                    FlowRow(spacing: 6, lineSpacing: 6, centred: false) {
                        ForEach(choices.colours, id: \.id) { c in
                            Button(c.name) { change { $0.colour = c.id } }.action(selected: prefs.colour == c.id, pill: true)
                                .accessibilityAddTraits(prefs.colour == c.id ? [.isSelected] : [])
                        }
                    }
                }
                section("Calm mode") {
                    FlowRow(spacing: 6, lineSpacing: 6, centred: false) {
                        ForEach(choices.calm, id: \.id) { c in
                            Button(c.name) { change { $0.calm = c.id } }.action(selected: prefs.calm == c.id, pill: true)
                                .accessibilityAddTraits(prefs.calm == c.id ? [.isSelected] : [])
                        }
                    }
                }
                section("Options") {
                    FlowRow(spacing: 6, lineSpacing: 6, centred: false) {
                        Button { watch.wanted.toggle() } label: { Text(watch.wanted ? "Canvas video: on" : "Canvas video: off") }
                            .action(selected: watch.wanted, pill: true)
                    }
                    Text("Auto-change").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textSecondary)
                    FlowRow(spacing: 6, lineSpacing: 6, centred: false) {
                        ForEach(choices.every, id: \.self) { seconds in
                            Button(seconds == 0 ? "Off" : seconds < 60 ? "\(seconds) s" : "\(seconds / 60) min") { change { $0.shuffleEvery = seconds } }
                                .action(selected: prefs.shuffleEvery == seconds, pill: true)
                        }
                    }
                }
                section("Intensity and speed") {
                    LevelRow(name: "Intensity", value: prefs.intensity, range: choices.intensity) { v in change { $0.intensity = v } }
                    LevelRow(name: "Speed", value: prefs.speed, range: choices.speed) { v in change { $0.speed = v } }
                    Text("The picture is drawn on this device and is off until you turn it on.")
                        .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                }
            }
            .padding(20)
        }
        .background(palette.panel.ignoresSafeArea())
    }
}
