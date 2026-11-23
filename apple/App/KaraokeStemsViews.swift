// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// Karaoke's controls for a song's separate parts (WittyMediaServer #524): the Mix (Voice, Background Music and Track,
// Voice off, Guide voice, Reset, and which version is playing) and Voice settings (nine kinds of voice, and Advanced).
// Shown in the karaoke screen on a phone or tablet, and in Now Playing on Apple TV, in each one's own colours.

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

/// A small round-cornered choice in the screen's colours: on, it's filled.
struct KaraokeChip: View {
    let title: String
    var symbol: String?
    var on = false
    var ink: StemInk
    var enabled = true
    let action: () -> Void

    var body: some View {
        #if os(tvOS)
        Button(action: action) {
            if let symbol { Label(title, systemImage: symbol) } else { Text(title) }
        }
        .action(selected: on, pill: true)
        .disabled(!enabled)
        .accessibilityAddTraits(on ? [.isSelected] : [])
        #else
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 15, weight: .semibold)) }
                Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(on ? ink.onFill : ink.text)
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background(Capsule().fill(on ? ink.fill : ink.chip))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityAddTraits(on ? [.isSelected] : [])
        #endif
    }
}

/// The Mix (WittyMediaServer #524): Voice, Background Music and Track with their levels, Voice off, Guide voice and
/// Reset, and which version is playing. Until the parts play, the same Mix, still, saying how far along the karaoke
/// version is, so nothing changes shape when it arrives.
struct KaraokeStemsControl: View {
    @ObservedObject var stems: KaraokeStems
    let ink: StemInk

    /// What to say while there's nothing to mix yet, or why there won't be.
    private var words: String? {
        switch stems.machine.phase {
        case .idle, .asked: return StemMix.preparingWords(-1)
        case .preparing(let progress): return StemMix.preparingWords(progress)
        case .unavailable(let message), .fallback(let message): return message
        case .ready:
            return stems.loaded == nil ? "Getting the karaoke version…" : nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let loaded = stems.loaded, case .ready = stems.machine.phase {
                VStack(spacing: 4) {
                    ForEach(StemMix.sliders(loaded, stems.levels)) { slider in
                        StemLevelSlider(label: slider.label, level: slider.isVocals && stems.levels.sing ? 0 : slider.level, ink: ink) {
                            stems.setStem(slider.id, $0)
                        }
                        .accessibilityIdentifier("karaoke-\(slider.id)")
                    }
                }
                .remoteSection()
                FlowRow(spacing: 8, lineSpacing: 8) {
                    KaraokeChip(title: "Voice off", on: stems.levels.sing, ink: ink) { stems.toggleSing() }
                        .accessibilityHint("Takes the singer out, or puts them back")
                    KaraokeChip(title: "Guide voice", on: stems.guide, ink: ink) { stems.setVocals(StemMix.guideLevel) }
                        .accessibilityHint("Keeps the singer quietly, as a guide")
                    KaraokeChip(title: "Reset", ink: ink, enabled: !StemMix.pristine(loaded, stems.levels)) { stems.reset() }
                }
                .remoteSection()
                Text("\(StemMix.qualityWords(loaded)). The parts are separated on your server, so the levels are approximate.")
                    .font(.footnote).foregroundStyle(ink.quiet).fixedSize(horizontal: false, vertical: true)
                if stems.machine.improving {
                    Text(StemMix.improvingWords(stems.machine.progress)).font(.footnote).foregroundStyle(ink.quiet)
                }
            } else if let words {
                if stems.waiting {
                    VStack(spacing: 4) {
                        ForEach(["Voice", "Background Music", "Track"], id: \.self) { label in
                            StemLevelSlider(label: label, level: 1, ink: ink) { _ in }
                                .disabled(true).opacity(0.45)
                        }
                    }
                    .accessibilityHidden(true)
                }
                Text(words).font(.subheadline).foregroundStyle(ink.quiet).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("karaoke-stems-words")
            }
        }
        .frame(maxWidth: 720, alignment: .leading)
    }
}

/// Voice settings (WittyMediaServer #524, #518): nine kinds of voice as buttons a finger or a remote reaches, and As
/// recorded; Advanced holds every control. Changes are heard straight away and kept for the person on this device.
/// Advanced's sliders need a bigger screen: an iPad, a Mac or a Vision Pro shows them; a phone says where to change them,
/// and a TV does too (the server's TV levels keep `karaoke.voice-advanced` for a computer).
struct KaraokeVoiceFxPanel: View {
    @ObservedObject var stems: KaraokeStems
    let ink: StemInk
    /// Room for Advanced's sliders.
    var roomy = true
    @State private var advanced = false

    private var note: String {
        guard stems.loaded != nil else { return "These are heard once the karaoke version plays." }
        if let loaded = stems.loaded, StemMix.isBlend(loaded) {
            return "The quick version has no voice of its own, so the voice here is what's left of the song without the music: close, not exact."
        }
        return "The voice and the music are separate parts, so each is shaped on its own."
    }

    var body: some View {
        let fx = stems.fx
        let preset = fx.presetId
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                KaraokeChip(title: "Presets", on: !advanced, ink: ink) { advanced = false }
                KaraokeChip(title: "Advanced", on: advanced, ink: ink) { advanced = true }
            }
            .remoteSection()
            Text(note).font(.footnote).foregroundStyle(ink.quiet).fixedSize(horizontal: false, vertical: true)
            if stems.loaded != nil, stems.voiceOut {
                VStack(alignment: .leading, spacing: 6) {
                    Text("The singer's voice is out, so these change only the music under it. Bring the voice back to hear them.")
                        .font(.footnote).foregroundStyle(ink.text).fixedSize(horizontal: false, vertical: true)
                    KaraokeChip(title: "Hear the voice", ink: ink) { stems.hearVoice() }
                }
                .remoteSection()
            }
            if !advanced {
                Text("Choose the voice closest to the singer's.").font(.subheadline.weight(.semibold)).foregroundStyle(ink.text)
                ForEach(VoiceFx.ranges, id: \.id) { range in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(range.name).font(.footnote.weight(.semibold)).foregroundStyle(ink.quiet)
                        HStack(spacing: 8) {
                            ForEach(VoiceFx.levels, id: \.id) { level in
                                if let p = VoiceFx.voicePreset(range: range.id, level: level.id) {
                                    KaraokeChip(title: level.name, on: preset == p.id, ink: ink) { stems.setFx(VoiceFx.preset(p.id)) }
                                        .accessibilityLabel(p.name)
                                }
                            }
                        }
                    }
                    .remoteSection()
                }
                HStack(spacing: 8) {
                    KaraokeChip(title: "As recorded", on: preset == "off", ink: ink) { stems.setFx(.off) }
                    if preset.isEmpty {
                        Text("Your own settings, from Advanced. Choose a voice to go back to a preset.")
                            .font(.footnote).foregroundStyle(ink.quiet).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .remoteSection()
            } else {
                HStack(spacing: 8) {
                    Text("Now: \(fx.presetName)").font(.subheadline.weight(.semibold)).foregroundStyle(ink.text)
                    Spacer(minLength: 0)
                    KaraokeChip(title: "Presets", ink: ink) { advanced = false }
                    KaraokeChip(title: "Reset", ink: ink, enabled: !fx.isOff) { stems.setFx(.off) }
                }
                .remoteSection()
                #if os(tvOS)
                // TV mode keeps this part for a computer (`karaoke.voice-advanced`, desktopOnly); the presets stay.
                Text("To change this, use the WittyMediaClient app on a Windows or Mac computer, or a web browser. What you choose there shows here too.")
                    .font(.subheadline).foregroundStyle(ink.quiet).fixedSize(horizontal: false, vertical: true)
                    .focusable()
                #else
                if roomy {
                    ForEach(VoiceFx.groups) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.title).font(.footnote.weight(.semibold)).textCase(.uppercase).foregroundStyle(ink.quiet)
                            ForEach(group.controls) { control in
                                FxControlRow(control: control, value: fx[control.id], ink: ink) { stems.setFx(fx.with(control.id, $0)) }
                            }
                        }
                    }
                } else {
                    Text("Voice settings need a bigger screen and a mouse or trackpad. Open it in the WittyMediaClient app on a computer, or in a web browser, to make changes. What you choose there shows here too.")
                        .font(.subheadline).foregroundStyle(ink.quiet).fixedSize(horizontal: false, vertical: true)
                }
                #endif
            }
        }
        .frame(maxWidth: 720, alignment: .leading)
    }
}

#if !os(tvOS)
/// One of Advanced's controls: its name, a slider, and what it's set to.
private struct FxControlRow: View {
    let control: FxControl
    let value: Double
    let ink: StemInk
    let set: (Double) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(control.label).font(.subheadline).foregroundStyle(ink.text).frame(minWidth: 110, alignment: .leading)
            Slider(value: Binding(get: { value }, set: { set($0) }), in: control.min...control.max, step: control.step)
                .tint(ink.fill)
            Text(VoiceFx.words(control, value)).font(.footnote.monospacedDigit()).foregroundStyle(ink.quiet)
                .frame(minWidth: 72, alignment: .trailing)
        }
        .help(control.help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(control.label)
        .accessibilityValue(VoiceFx.words(control, value))
        .accessibilityHint(control.help)
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 1 : -1
            set(VoiceFx().with(control.id, value).stepped(control.id, by: step)[control.id])
        }
    }
}
#endif

#if os(tvOS)
/// Apple TV's karaoke bar, as the website's: Guide voice, Mix and Voice settings, each opening its part below, all
/// reached with the remote's arrows.
struct KaraokeStemsPanels: View {
    @Environment(\.palette) private var palette
    @ObservedObject var stems: KaraokeStems
    @State private var panel: Panel?

    enum Panel { case mix, voice }

    var body: some View {
        let ink = StemInk(text: palette.text, quiet: palette.textSecondary, chip: palette.border, fill: palette.accent, onFill: palette.onAccent)
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            HStack(spacing: Tokens.Space.s2) {
                if stems.loaded != nil || stems.waiting {
                    KaraokeChip(title: "Guide voice", symbol: "music.mic", on: stems.guide, ink: ink, enabled: stems.loaded != nil) { stems.toggleGuide() }
                }
                KaraokeChip(title: "Mix", symbol: "slider.horizontal.3", on: panel == .mix, ink: ink) { panel = panel == .mix ? nil : .mix }
                KaraokeChip(title: "Voice settings", on: panel == .voice || !stems.fx.isOff, ink: ink) { panel = panel == .voice ? nil : .voice }
            }
            .remoteSection()
            switch panel {
            case .mix?: KaraokeStemsControl(stems: stems, ink: ink)
            case .voice?: KaraokeVoiceFxPanel(stems: stems, ink: ink)
            case nil: EmptyView()
            }
        }
    }
}

/// Apple TV's Now Playing: a Karaoke button for a song, and its bar once it's on.
struct KaraokeStemsRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @ObservedObject var stems: KaraokeStems
    let song: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
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
            if stems.isOpen { KaraokeStemsPanels(stems: stems) }
        }
    }
}
#endif
