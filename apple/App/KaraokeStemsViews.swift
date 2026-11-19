// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// Karaoke's controls for a song's separate parts: a big Vocals slider, Sing, and under More a slider for each part,
// Reset, and which version is playing. Shown in the karaoke screen on a phone or tablet, and in Now Playing on Apple
// TV, in each one's own colours. While the server prepares, or can't, it says so in the same place.

/// The colours of the screen it's shown in.
struct StemInk {
    var text: Color
    var quiet: Color
    var chip: Color
    var fill: Color
    var onFill: Color
}

/// A level from 0 to 100%. A finger drags it; a remote's left and right move it 5% at a time.
struct StemLevelSlider: View {
    let label: String
    let level: Double
    let ink: StemInk
    var big = false
    let set: (Double) -> Void
    #if os(tvOS)
    @FocusState private var focused: Bool
    #endif

    var body: some View {
        HStack(spacing: 12) {
            Text(label).font(big ? .headline : .subheadline).fontWeight(.semibold).foregroundStyle(ink.text).lineLimit(1)
                .frame(minWidth: big ? nil : 96, alignment: .leading)
            #if os(tvOS)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(ink.chip).frame(height: focused ? 12 : 8)
                    Capsule().fill(ink.fill).frame(width: geo.size.width * level, height: focused ? 12 : 8)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 44)
            #else
            Slider(value: Binding(get: { level }, set: { set($0) }), in: 0...1)
                .tint(ink.fill)
                .frame(minWidth: 120)
            #endif
            Text(StemMix.percent(level)).font(.subheadline.monospacedDigit()).foregroundStyle(ink.quiet)
                .frame(minWidth: 52, alignment: .trailing)
        }
        #if os(tvOS)
        .padding(.horizontal, 20).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(focused ? ink.chip : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(focused ? ink.text : Color.clear, lineWidth: 4))
        .focusable()
        .focused($focused)
        .onMoveCommand { direction in
            if direction == .left { set(StemMix.stepped(level, by: -1)) }
            if direction == .right { set(StemMix.stepped(level, by: 1)) }
        }
        #endif
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(StemMix.percent(level))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(StemMix.stepped(level, by: 1))
            case .decrement: set(StemMix.stepped(level, by: -1))
            @unknown default: break
            }
        }
    }
}

struct KaraokeStemsControl: View {
    @ObservedObject var stems: KaraokeStems
    let ink: StemInk
    @State private var more = false

    /// What to say in place of the sliders. Nil once the parts are playing.
    private var words: String? {
        switch stems.machine.phase {
        case .idle, .asked: return StemMix.preparingWords(-1)
        case .preparing(let progress): return StemMix.preparingWords(progress)
        case .unavailable(let message), .fallback(let message): return message
        case .ready:
            return stems.loaded == nil ? StemMix.preparingWords(-1) : nil
        }
    }

    private func pill(_ title: String, on: Bool = false, action: @escaping () -> Void) -> some View {
        #if os(tvOS)
        Button(title, action: action).action(selected: on, pill: true)
            .accessibilityAddTraits(on ? [.isSelected] : [])
        #else
        Button(action: action) {
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(on ? ink.onFill : ink.text)
                .padding(.horizontal, 16).frame(minHeight: 44)
                .background(Capsule().fill(on ? ink.fill : ink.chip))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
        #endif
    }

    var body: some View {
        VStack(spacing: 8) {
            if let words {
                Text(words).font(.subheadline).foregroundStyle(ink.quiet).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("karaoke-stems-words")
            }
            if let loaded = stems.loaded, case .ready = stems.machine.phase {
                let vocals = StemLevelSlider(label: "Voice", level: StemMix.vocalsLevel(loaded, stems.levels), ink: ink, big: true) { stems.setVocals($0) }
                    .accessibilityIdentifier("karaoke-vocals")
                let buttons = Group {
                    pill("Sing", on: stems.levels.sing) { stems.toggleSing() }
                        .accessibilityHint("Turns the singer's voice off, and back to where it was")
                    pill("Mix", on: more) { more.toggle() }
                        .accessibilityHint("Voice, Background Music and Track")
                }
                // One line where there's room; on a phone the slider has the width and the buttons go under it.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { vocals; buttons }
                    VStack(spacing: 8) {
                        vocals
                        HStack(spacing: 8) { buttons }
                    }
                }
                .remoteSection()
                if more {
                    VStack(spacing: 4) {
                        ForEach(StemMix.sliders(loaded, stems.levels)) { slider in
                            StemLevelSlider(label: slider.label, level: slider.level, ink: ink) { stems.setStem(slider.id, $0) }
                        }
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(StemMix.qualityWords(loaded)).font(.footnote.weight(.semibold)).foregroundStyle(ink.quiet)
                                if stems.machine.improving {
                                    Text(StemMix.improvingWords(stems.machine.progress)).font(.footnote).foregroundStyle(ink.quiet)
                                }
                            }
                            Spacer(minLength: 0)
                            pill("Reset") { stems.reset() }
                        }
                        .remoteSection()
                    }
                    .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }
}

#if os(tvOS)
/// Apple TV's Now Playing: a Karaoke button for a song, and the controls once it's on.
struct KaraokeStemsRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @ObservedObject var stems: KaraokeStems
    let song: Int64

    var body: some View {
        VStack(spacing: Tokens.Space.s2) {
            Button(stems.isOpen ? "Karaoke on" : "Karaoke") {
                if stems.isOpen {
                    stems.close()
                } else {
                    stems.open(song: song, client: client, profile: String(model.user?.id ?? 0))
                }
            }
            .action(selected: stems.isOpen, pill: true)
            .accessibilityAddTraits(stems.isOpen ? [.isSelected] : [])
            .remoteSection()
            if stems.isOpen {
                KaraokeStemsControl(stems: stems, ink: StemInk(text: palette.text, quiet: palette.textSecondary, chip: palette.border,
                                                               fill: palette.accent, onFill: palette.onAccent))
            }
        }
    }
}
#endif
