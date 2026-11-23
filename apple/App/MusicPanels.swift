// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
#if os(iOS) || os(visionOS)
import PDFKit
import SwiftUI
import WittyKit

// The rest of the website's Now Playing on a phone or a tablet: the visualizer behind it (backdrop.ts), the Sound
// panel (SoundPanel.tsx), Read (ReadPanel.tsx), Fix for the words (LyricsPanel.tsx), karaoke (Karaoke.tsx) and the
// volume (controls.tsx). The website's own player's colours: see NPInk.

// MARK: - Small parts


/// The website's checkbox on black: white when it's on.
struct NPCheck: View {
    let words: String
    let on: Bool
    var enabled = true
    let flip: () -> Void

    var body: some View {
        Button(action: flip) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(on ? Color.white : Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.white.opacity(on ? 1 : 0.4), lineWidth: 1.5))
                    .overlay { if on { Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(Color.black) } }
                    .frame(width: 20, height: 20)
                Text(words).font(.system(size: 14)).foregroundStyle(NPInk.fg).multilineTextAlignment(.leading).lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

/// The website's small select on black: the choice, and the system's list to change it.
struct NPSelect<Value: Hashable>: View {
    let label: String
    let choices: [(Value, String)]
    let chosen: Value
    var enabled = true
    let choose: (Value) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 14)).foregroundStyle(NPInk.fg)
            Spacer(minLength: 0)
            Menu {
                ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                    Button { choose(choice.0) } label: {
                        if choice.0 == chosen { Label(choice.1, systemImage: "checkmark") } else { Text(choice.1) }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(choices.first { $0.0 == chosen }?.1 ?? "").lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 13))
                .foregroundStyle(NPInk.fg)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(NPInk.well))
                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
            }
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.5)
            .accessibilityLabel(label)
            .accessibilityValue(choices.first { $0.0 == chosen }?.1 ?? "")
        }
    }
}

/// The website's range for a value between two ends: a 4 high track, white to the value, and a 14 thumb.
struct NPSlider: View {
    @Environment(\.onBlack) private var onBlack
    @Environment(\.palette) private var palette
    let value: Double
    let range: ClosedRange<Double>
    var step = 1.0
    var enabled = true
    let label: String
    let spoken: String
    let change: (Double) -> Void

    private func snapped(_ raw: Double) -> Double {
        min(range.upperBound, max(range.lowerBound, (raw / step).rounded() * step))
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let part = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            ZStack(alignment: .leading) {
                Capsule().fill(onBlack ? Color.white.opacity(0.28) : palette.text.opacity(0.28)).frame(height: 4)
                Capsule().fill(onBlack ? Color.white : palette.accent).frame(width: width * part, height: 4)
                Circle().fill(.white).frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.45), radius: 1.5, y: 1)
                    .offset(x: part * max(width - 14, 0))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                guard enabled else { return }
                let at = range.lowerBound + Double(min(max(drag.location.x / max(width, 1), 0), 1)) * (range.upperBound - range.lowerBound)
                let next = snapped(at)
                if next != value { change(next) }
            })
        }
        .frame(height: 32)
        .opacity(enabled ? 1 : 0.5)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(spoken)
        .accessibilityAdjustableAction { direction in
            guard enabled else { return }
            switch direction {
            case .increment: change(snapped(value + step))
            case .decrement: change(snapped(value - step))
            @unknown default: break
            }
        }
    }
}

/// A panel's head: its name, something on the right, and Close.
struct NPSideHead<Extra: View>: View {
    let title: String
    let closeLabel: String
    let close: () -> Void
    @ViewBuilder var extra: Extra

    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(NPInk.fg).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            extra
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).foregroundStyle(NPInk.fg)
                    .frame(width: 44, height: 44).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(closeLabel)
        }
        .padding(.leading, 18).padding(.trailing, 8).padding(.top, 12).padding(.bottom, 8)
    }
}

/// A note on black: `np-note`.
struct NPNote: View {
    let words: String
    var body: some View {
        Text(words).font(.system(size: 13)).foregroundStyle(NPInk.fg).lineSpacing(3)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(NPInk.rule))
    }
}

/// The website's buttons inside Now Playing, where its accent is white: primary is white with black words.
struct NPButtonStyle: ButtonStyle {
    enum Kind { case primary, plain, ghost }
    var kind = Kind.plain
    var big = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: big ? 17 : 13, weight: .semibold))
            .foregroundStyle(kind == .primary ? Color.black : NPInk.fg)
            .padding(.horizontal, big ? 16 : 12)
            .frame(minHeight: big ? 68 : 44)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
                .fill(kind == .primary ? Color.white : kind == .ghost ? Color.clear : NPInk.well))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
                .strokeBorder(kind == .ghost ? Color.white.opacity(0.26) : .clear, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

// MARK: - Sound

struct SoundPanelView: View {
    @EnvironmentObject private var listening: Listening
    let close: () -> Void

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(NPInk.fg).accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(.top, 10).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { NPInk.line.frame(height: 1) }
    }

    private func hint(_ words: String) -> some View {
        Text(words).font(.system(size: 13)).foregroundStyle(NPInk.fg2).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
    }

    private func eqRow(_ name: String, value: Double, label: String, change: @escaping (Double) -> Void) -> some View {
        let on = listening.sound.eqOn
        return HStack(spacing: 10) {
            Text(name).font(.system(size: 12, weight: .semibold)).foregroundStyle(NPInk.fg2).frame(width: 44, alignment: .leading)
            NPSlider(value: value, range: -12...12, enabled: on, label: label, spoken: "\(Int(value)) decibels", change: change)
            Text(Equaliser.decibels(value)).font(.system(size: 12).monospacedDigit()).foregroundStyle(NPInk.fg2).frame(width: 34, alignment: .trailing)
        }
        .frame(minHeight: 32)
        .opacity(on ? 1 : 0.5)
    }

    var body: some View {
        let s = listening.sound
        VStack(spacing: 0) {
            NPSideHead(title: "Sound", closeLabel: "Close sound settings", close: close) { EmptyView() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    section("Between songs") {
                        NPCheck(words: "No gaps: start the next song right as this one ends", on: s.gapless) { listening.setSound { $0.gapless.toggle() } }
                        NPSelect(label: "Crossfade", choices: SoundSettings.crossfades.map { ($0, SoundSettings.crossfadeWords($0)) }, chosen: s.crossfade) { seconds in
                            listening.setSound { $0.crossfade = seconds }
                        }
                        if s.crossfade > 0 {
                            NPCheck(words: "Also within an album. Off keeps songs that run together as they were made", on: s.crossfadeAlbums) {
                                listening.setSound { $0.crossfadeAlbums.toggle() }
                            }
                        }
                        hint("Works for files sent as they are. Formats converted while playing, and CD images, follow their own rules.")
                    }
                    section("Volume leveling") {
                        NPSelect(label: "ReplayGain", choices: SoundSettings.Leveling.allCases.map { ($0, SoundSettings.levelingWords($0)) }, chosen: s.replayGain) { choice in
                            listening.setSound { $0.replayGain = choice }
                        }
                        hint("Uses the loudness tags in your files, which tagging tools such as MusicBrainz Picard or foobar2000 can add. Songs without them play as they are.")
                    }
                    section("Equaliser") {
                        NPCheck(words: "Use the equaliser", on: s.eqOn) { listening.setSound { $0.eqOn.toggle() } }
                        NPSelect(label: "Preset", choices: Equaliser.presets.map { ($0.id, $0.name) } + (s.presetShown == "custom" ? [("custom", "Your own")] : []),
                                 chosen: s.presetShown, enabled: s.eqOn) { id in
                            guard let preset = Equaliser.presets.first(where: { $0.id == id }) else { return }
                            listening.setSound {
                                $0.eqPreset = preset.id
                                $0.eqGains = preset.gains
                            }
                        }
                        VStack(spacing: 4) {
                            ForEach(Array(Equaliser.frequencies.enumerated()), id: \.offset) { index, frequency in
                                eqRow(Equaliser.hertz(frequency), value: s.eqGains[index], label: "\(Equaliser.hertz(frequency)) hertz") { gain in
                                    listening.setSound {
                                        $0.eqGains[index] = gain
                                        $0.eqPreset = "custom"
                                    }
                                }
                            }
                            eqRow("Level", value: s.preamp, label: "Overall level") { gain in listening.setSound { $0.preamp = gain } }
                        }
                        hint("If boosting makes loud parts crackle, lower the overall level a little.")
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 16)
            }
        }
    }
}

// MARK: - Volume

/// A tablet's volume, as the website's pop-up: mute, and how loud.
struct VolumeCard: View {
    @EnvironmentObject private var listening: Listening
    @Environment(\.onBlack) private var onBlack
    @Environment(\.palette) private var palette

    var body: some View {
        let shown = listening.sound.muted ? 0 : listening.sound.volume
        HStack(spacing: 8) {
            Button { listening.setSound { $0.muted.toggle() } } label: {
                Image(systemName: shown == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(onBlack ? NPInk.fg : palette.text)
                    .frame(width: 44, height: 44).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(listening.sound.muted ? "Turn the sound back on" : "Mute")
            NPSlider(value: (shown * 100).rounded(), range: 0...100, step: 2, label: "Volume", spoken: "\(Int((shown * 100).rounded()))%") { value in
                listening.setSound {
                    $0.volume = value / 100
                    $0.muted = false
                }
            }
        }
        .padding(.leading, 2).padding(.trailing, 8).padding(.vertical, 2)
        .frame(minWidth: 240)
    }
}

// MARK: - Read

struct ReadPanelView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    let item: Item
    let extras: [Extra]
    let lyrics: Lyrics?
    let loading: Bool
    let close: () -> Void
    @State private var shown: (name: String, text: String)?
    @State private var busy = false
    @State private var error = ""
    @State private var booklet: Booklet?

    struct Booklet: Identifiable {
        let name: String
        let document: PDFDocument
        var id: String { name }
    }

    private func open(_ extra: Extra) async {
        busy = true
        error = ""
        do {
            if extra.isBooklet {
                guard let url = client.extraFile(item: item.id, name: extra.name) else { return }
                let data = try await client.imageData(url)
                if let document = PDFDocument(data: data) { booklet = Booklet(name: extra.name, document: document) }
            } else {
                shown = (extra.name, try await client.extraText(item: item.id, name: extra.name))
            }
        } catch {
            self.error = model.handle(error)
        }
        busy = false
    }

    var body: some View {
        let words = lyrics?.plain ?? ""
        VStack(spacing: 0) {
            NPSideHead(title: shown?.name ?? "Read", closeLabel: "Close", close: close) {
                if shown != nil {
                    Button("Back") { shown = nil }.buttonStyle(NPChipLook(small: true))
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !error.isEmpty { NPNote(words: error).padding(.horizontal, 18) }
                    if let shown {
                        readText(shown.text)
                    } else {
                        if !extras.isEmpty {
                            FlowRow(spacing: 6, lineSpacing: 6, centred: false) {
                                ForEach(extras) { extra in
                                    Button { Task { await open(extra) } } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "doc").font(.system(size: 16))
                                            Text(extra.name)
                                        }
                                    }
                                    .buttonStyle(NPChipLook())
                                    .disabled(busy)
                                }
                            }
                            .padding(.horizontal, 18)
                        }
                        if loading {
                            Text("Looking for the words…").font(.system(size: 13)).foregroundStyle(NPInk.fg2).padding(.horizontal, 18)
                        }
                        if !words.isEmpty {
                            readText(words)
                            if let source = lyrics?.sourceName, !source.isEmpty {
                                Group {
                                    if let link = lyrics?.creditUrl.flatMap(URL.init(string:)) {
                                        Text("Words from ") + Text(.init("[\(source)](\(link.absoluteString))")) + Text(".")
                                    } else {
                                        Text("Words from \(source).")
                                    }
                                }
                                .font(.system(size: 12)).foregroundStyle(NPInk.fg2).tint(NPInk.fg2)
                                .padding(.horizontal, 18).padding(.top, 2)
                            }
                        } else if !loading, extras.isEmpty {
                            Text("Nothing to read for this one yet: no words were found, and no booklet is beside the album. A PDF or a text file in the album's folder appears here.")
                                .font(.system(size: 13)).foregroundStyle(NPInk.fg2).lineSpacing(3).padding(.horizontal, 18)
                        }
                    }
                }
                .padding(.top, 4).padding(.bottom, 14)
            }
        }
        .sheet(item: $booklet) { shown in
            NavigationStack {
                PDFReader(document: shown.document)
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle(shown.name)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { booklet = nil } } }
            }
        }
    }

    private func readText(_ text: String) -> some View {
        Text(text).font(.system(size: 17)).foregroundStyle(NPInk.fg).lineSpacing(17 * 0.55 - 4)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
    }
}

/// A booklet, in the system's PDF reader.
private struct PDFReader: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = document
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
    }
}

/// The website's chip, for panels outside MusicPlayerUI.swift.
struct NPChipLook: ButtonStyle {
    var on = false
    var small = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: small ? 13 : 14, weight: .semibold))
            .foregroundStyle(on ? Color.black : NPInk.fg)
            .lineLimit(1)
            .padding(.horizontal, small ? 12 : 16)
            .frame(minHeight: small ? 36 : 44)
            .background(Capsule().fill(on ? Color.white : configuration.isPressed ? NPInk.chip2 : NPInk.chip))
    }
}

// MARK: - Fix the words

struct FixLyricsView: View {
    @EnvironmentObject private var listening: Listening
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    let item: Item
    let lyrics: Lyrics
    let close: () -> Void
    let saved: (String) -> Void
    enum Tab { case search, edit, tap }
    @State private var tab: Tab
    @State private var query: String
    @State private var found: [FoundLyrics]?
    @State private var busy = false
    @State private var draft: String
    @State private var error = ""
    @FocusState private var typing: Bool

    init(item: Item, lyrics: Lyrics, close: @escaping () -> Void, saved: @escaping (String) -> Void) {
        self.item = item
        self.lyrics = lyrics
        self.close = close
        self.saved = saved
        _tab = State(initialValue: lyrics.online == true ? .search : .edit)
        _query = State(initialValue: [item.artist ?? "", item.title].filter { !$0.isEmpty }.joined(separator: " "))
        _draft = State(initialValue: LyricFile.draft(lyrics))
    }

    private func run(_ work: @escaping () async throws -> Void) {
        busy = true
        error = ""
        Task {
            do { try await work() } catch { self.error = model.handle(error) }
            busy = false
        }
    }

    private func tabButton(_ words: String, _ which: Tab) -> some View {
        Button(words) { tab = which }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tab == which ? Color.black : NPInk.fg)
            .padding(.horizontal, 14).frame(minHeight: 40)
            .background(Capsule().fill(tab == which ? Color.white : NPInk.chip))
            .accessibilityAddTraits(tab == which ? [.isSelected] : [])
    }

    var body: some View {
        VStack(spacing: 0) {
            NPSideHead(title: "Fix the lyrics", closeLabel: "Close", close: close) { EmptyView() }
            HStack(spacing: 4) {
                if lyrics.online == true { tabButton("Other versions", .search) }
                tabButton("Edit", .edit)
                tabButton("Tap along", .tap)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.bottom, 8)
            if !error.isEmpty { NPNote(words: error).padding(.horizontal, 18).padding(.vertical, 8) }
            switch tab {
            case .search: search
            case .edit: edit
            case .tap: TapAlongView(text: lyrics.timed.isEmpty ? (lyrics.plain ?? "") : lyrics.timed.map(\.text).joined(separator: "\n"), busy: busy) { file in
                run {
                    try await client.saveLyrics(item: item.id, text: file)
                    saved("Timing saved")
                }
            }
            }
        }
        .background(NPInk.pop.ignoresSafeArea())
    }

    private var search: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    NPField(placeholder: "", text: $query, label: "Search for lyrics")
                        .onSubmit { find() }
                    Button("Search") { find() }
                        .buttonStyle(NPButtonStyle(kind: .primary))
                        .disabled(busy || query.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if found?.isEmpty == true {
                    Text("Nothing found. Try fewer words.").font(.system(size: 13)).foregroundStyle(NPInk.fg2)
                }
                ForEach(found ?? []) { version in
                    Button {
                        run {
                            try await client.chooseLyrics(item: item.id, provider: version.provider, id: version.id)
                            saved("Lyrics changed")
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(version.title).font(.system(size: 14, weight: .bold))
                            Text([version.artist, version.album ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 12)).foregroundStyle(NPInk.fg2)
                            Text(version.facts(songSeconds: item.runtimeSec)).font(.system(size: 12)).foregroundStyle(NPInk.fg2)
                        }
                        .foregroundStyle(NPInk.fg)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(NPInk.chip))
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                }
            }
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 14)
        }
    }

    private func find() {
        let asked = query.trimmingCharacters(in: .whitespaces)
        guard !asked.isEmpty else { return }
        run { found = try await client.searchLyrics(item: item.id, query: asked) }
    }

    private var edit: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $draft)
                        .focused($typing)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(NPInk.fg)
                        .scrollContentBackground(.hidden)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(6)
                        .frame(minHeight: 200)
                        .accessibilityLabel("The lyrics")
                    if draft.isEmpty {
                        Text("[00:12.50]A line, with the time it starts\nor plain words with no times")
                            .font(.system(size: 13, design: .monospaced)).foregroundStyle(NPInk.fg3)
                            .padding(.horizontal, 11).padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                }
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(NPInk.well))
                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
                Text("Kept on this server and used in place of everything else. Nothing is written beside your music.")
                    .font(.system(size: 13)).foregroundStyle(NPInk.fg2)
                FlowRow(spacing: 6, lineSpacing: 6, centred: false) {
                    Button("Save") {
                        run {
                            try await client.saveLyrics(item: item.id, text: draft)
                            saved("Lyrics saved")
                        }
                    }
                    .buttonStyle(NPButtonStyle(kind: .primary))
                    .disabled(busy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("This song has no words") {
                        run {
                            try await client.markInstrumental(item: item.id)
                            saved("Marked as having no words")
                        }
                    }
                    .buttonStyle(NPButtonStyle())
                    .disabled(busy)
                    if ["override", "lrclib", "mirror", "musixmatch"].contains(lyrics.source ?? "") {
                        Button {
                            run {
                                try await client.forgetLyrics(item: item.id)
                                saved("Back to what was found")
                            }
                        } label: {
                            Label("Start over", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(NPButtonStyle(kind: .ghost))
                        .disabled(busy)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 14)
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
    }
}

/// A text box on black: `.input`.
struct NPField: View {
    let placeholder: String
    @Binding var text: String
    let label: String

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.system(size: 14))
            .foregroundStyle(NPInk.fg)
            .submitLabel(.search)
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(NPInk.well))
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
            .accessibilityLabel(label)
    }
}

/// The simple way to fix the timing: it plays from the start, and a press marks each line as it begins.
private struct TapAlongView: View {
    @EnvironmentObject private var listening: Listening
    let text: String
    let busy: Bool
    let save: (String) -> Void
    @State private var times: [Double] = []
    @State private var started = false

    var body: some View {
        let lines = LyricFile.lines(text)
        let at = times.count
        let done = at >= lines.count && !lines.isEmpty
        ScrollView {
            VStack(spacing: 8) {
                if lines.isEmpty {
                    Text("Add the words under Edit first, then come back to time them.").font(.system(size: 13)).foregroundStyle(NPInk.fg2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if !started {
                    Text("The song starts from the beginning. Press the big button as each line starts.")
                        .font(.system(size: 15)).foregroundStyle(NPInk.fg).multilineTextAlignment(.center)
                    Button("Start") { start() }.buttonStyle(NPButtonStyle(kind: .primary))
                } else {
                    Text(at > 0 ? lines[at - 1] : " ").foregroundStyle(NPInk.fg3).frame(minHeight: 20)
                    Text(done ? "That's all of them." : lines[at]).font(.system(size: 20, weight: .bold)).foregroundStyle(NPInk.fg).frame(minHeight: 52)
                    Text(at + 1 < lines.count ? lines[at + 1] : " ").foregroundStyle(NPInk.fg3).frame(minHeight: 20)
                    Button("This line starts now (\(min(at + 1, lines.count)) of \(lines.count))") {
                        if !done { times.append((listening.positionSec() * 1000).rounded()) }
                    }
                    .buttonStyle(NPButtonStyle(kind: .primary, big: true))
                    .frame(maxWidth: .infinity)
                    .disabled(done)
                    FlowRow(spacing: 6, lineSpacing: 6) {
                        Button("Undo the last one") {
                            let back = times.count >= 2 ? times[times.count - 2] : 0
                            times.removeLast()
                            listening.seek(to: max(0, back / 1000))
                        }
                        .buttonStyle(NPButtonStyle())
                        .disabled(at == 0)
                        Button("Start again") { start() }.buttonStyle(NPButtonStyle(kind: .ghost))
                        Button("Save") { save(LyricFile.lrc(times: times, lines: lines)) }
                            .buttonStyle(NPButtonStyle(kind: .primary))
                            .disabled(!done || busy)
                    }
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 14)
        }
    }

    private func start() {
        times = []
        started = true
        listening.seek(to: 0)
        if !listening.isPlaying { listening.toggle() }
    }
}

// MARK: - Karaoke

/// Big words that fill in as they're sung, a count-in before each line after a break, the next line waiting below.
/// The first screen is the website's since WittyMediaServer #524: the words, the previous and next line and Play, Guide
/// voice, Mix and Voice settings. The sliders, Reset, Key and the words' timing are in the Mix, at the side on a wide
/// screen and a sheet on a phone. The singer starts out every time; the top row and what's behind the words step aside
/// when nothing is touched for a while (a tap brings them back, and another hides them), but never for VoiceOver.
struct KaraokeView: View {
    @EnvironmentObject private var listening: Listening
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    let item: Item
    let lyrics: Lyrics?
    let loading: Bool
    let glow: Color
    let offset: Double
    let setOffset: (Double) -> Void
    let close: () -> Void
    /// The screen's safe area: it's shown over Now Playing, which already reaches the edges.
    var insets = EdgeInsets()
    var viz = VisualizerPrefs()
    var vizHere = true
    /// Choosing the visualizer's style here chooses it for Now Playing too: one setting.
    var setVizStyle: ((String) -> Void)?
    @ObservedObject var canvas: CanvasStatus
    @ObservedObject private var store = MusicShowStore.shared
    @State private var mono = false
    @State private var panel: KaraokePanel?
    @State private var idle = false
    @State private var idleTimer: Task<Void, Never>?
    private let monoCheck = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    enum KaraokePanel: String, Identifiable {
        case mix, voice
        var id: String { rawValue }
    }

    private var lines: [LyricLine] { lyrics?.timed ?? [] }

    /// A server that makes a song's separate parts: the Mix's sliders take the place of the old Voice lower.
    private var auto: Bool { model.has("karaoke-auto") }

    private var ink: StemInk { StemInk(text: NPInk.fg, quiet: NPInk.fg2, chip: NPInk.chip, fill: .white, onFill: .black) }

    private func goLine(_ by: Int, from index: Int) {
        let to = max(0, index + by)
        guard lines.indices.contains(to) else { return }
        listening.seek(to: max(0, (lines[to].t + offset) / 1000))
    }

    private func setKey(_ key: Double) { listening.setSound { $0.keyShift = max(-6, min(6, key)) } }

    // MARK: Stepping aside

    /// The top row and what's behind the words show again, and step aside after four seconds of nothing.
    private func wake() {
        if idle { withAnimation(.easeOut(duration: 0.3)) { idle = false } }
        idleTimer?.cancel()
        idleTimer = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, panel == nil, !voiceOver else { return }
            withAnimation(.easeOut(duration: 0.6)) { idle = true }
        }
    }

    private func togglePanel(_ which: KaraokePanel) {
        panel = panel == which ? nil : which
        wake()
    }

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let compact = geo.size.width <= 700
            ZStack {
                Color(red: 6 / 255, green: 6 / 255, blue: 10 / 255).ignoresSafeArea()
                EllipticalGradient(colors: [glow.opacity(0.28), glow.opacity(0)], center: UnitPoint(x: 0.5, y: 0.4), startRadiusFraction: 0, endRadiusFraction: 0.8)
                    .ignoresSafeArea()
                MusicBackdrop(item: item.id, prefs: viz, shownStyle: "", colour: glow, playing: listening.isPlaying, visualizer: vizHere,
                              shade: Color.black.opacity(0.45))
                    .ignoresSafeArea()
                VStack(spacing: 0) {
                    top(h)
                        .opacity(idle ? 0 : 1)
                    behind(compact: compact)
                        .opacity(idle ? 0 : 1)
                        .padding(.horizontal, 16).padding(.top, 8)
                    stage(h)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if idle || panel != nil { wake() } else if !voiceOver { withAnimation(.easeOut(duration: 0.3)) { idle = true } }
                        }
                    bar(compact: compact)
                        .padding(.bottom, max(10, insets.bottom))
                }
                // Never wider than the screen, whatever a row inside would like.
                .frame(width: geo.size.width)
                .padding(.top, insets.top)
                // A wide screen: the panel at the side, the words still in view.
                .overlay(alignment: .trailing) {
                    if let panel, !compact {
                        panelView(panel, compact: false)
                            .frame(width: min(400, geo.size.width * 0.42))
                            .frame(maxHeight: .infinity)
                            .background(NPInk.panel.ignoresSafeArea())
                            .overlay(alignment: .leading) { NPInk.line.frame(width: 1).ignoresSafeArea() }
                            .transition(.move(edge: .trailing))
                    }
                }
                .sheet(item: Binding(get: { compact ? panel : nil }, set: { panel = $0 })) { which in
                    panelView(which, compact: true)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                        .background(NPInk.pop.ignoresSafeArea())
                        .environment(\.colorScheme, .dark)
                }
            }
            .animation(.easeOut(duration: 0.25), value: panel)
        }
        .environment(\.colorScheme, .dark)
        .onReceive(monoCheck) { _ in
            guard listening.sound.vocalCut > 0 else { if mono { mono = false }; return }
            if let found = SoundEngine.shared.nearlyMono() { mono = found }
        }
        .onAppear { wake() }
        // Coming back, the voice and key are as they were: this was for the song, not for good.
        .onDisappear {
            idleTimer?.cancel()
            listening.stems.close()
            listening.setSound { $0.vocalCut = 0; $0.keyShift = 0 }
        }
        .task(id: auto) {
            if auto { listening.stems.open(song: item.id, client: client, profile: String(model.user?.id ?? 0)) }
        }
        .accessibilityAction(.escape) { if panel != nil { panel = nil } else { close() } }
    }

    private var note: String {
        Karaoke.note(mono: mono, vocalCut: listening.sound.vocalCut, keyShift: listening.sound.keyShift,
                     timed: !lines.isEmpty, hasWordTimes: lines.contains { $0.words?.isEmpty == false })
    }

    private func top(_ h: CGFloat) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title).font(.system(size: clampValue(16, h * 0.024, 24), weight: .bold)).lineLimit(1)
                Text(item.artist ?? item.albumArtist ?? "").font(.system(size: clampValue(14.4, h * 0.019, 19.2))).foregroundStyle(NPInk.fg2).lineLimit(1)
            }
            .foregroundStyle(NPInk.fg)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).foregroundStyle(NPInk.fg)
                    .frame(width: 44, height: 44).background(Circle().fill(NPInk.chip))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Leave karaoke")
        }
        .padding(.horizontal, 16).padding(.top, 14)
    }

    /// What's behind the words, and the visualizer's style while it's the one (the same setting as Now Playing's); the
    /// Follow along or Read choice beside it where there's room (in the Mix on a phone).
    private func behind(compact: Bool) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                MusicShowToggle(canvas: canvas, visualizer: vizHere, compact: compact)
                if store.show == .viz, vizHere, let setVizStyle { styles(setVizStyle) }
            }
            if !compact { LyricsModeToggle(timed: !lines.isEmpty) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Bars, Waves, Drift, and More for the rest.
    private func styles(_ choose: @escaping (String) -> Void) -> some View {
        let native = VisualizerEffects.all.filter(\.native)
        let other = VisualizerEffects.named(viz.style).flatMap { $0.native ? nil : $0 }
        return HStack(spacing: 6) {
            ForEach(native) { effect in
                Button { choose(effect.id) } label: { Text(effect.name) }
                    .action(selected: viz.style == effect.id, pill: true)
                    .accessibilityAddTraits(viz.style == effect.id ? [.isSelected] : [])
            }
            Menu {
                ForEach(VisualizerEffects.picker) { effect in
                    Button { choose(effect.id) } label: {
                        if viz.style == effect.id { Label(effect.name, systemImage: "checkmark") } else { Text(effect.name) }
                    }
                }
            } label: { Text(other?.name ?? "More") }
            .action(selected: other != nil, pill: true)
            .accessibilityLabel("More visualizer styles")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Visualizer style")
    }

    @ViewBuilder
    private func stage(_ h: CGFloat) -> some View {
        if lyrics == nil || loading {
            Text("Looking for the words…").font(.system(size: clampValue(17.6, h * 0.028, 32), weight: .semibold)).foregroundStyle(NPInk.fg2)
        } else if lines.isEmpty {
            GeometryReader { box in
            ScrollView {
                VStack(spacing: 12) {
                    Text(lyrics?.plain?.isEmpty == false ? "These words have no times, so they can't follow the music yet." : "No words for this song.")
                        .font(.system(size: clampValue(17.6, h * 0.028, 32), weight: .semibold)).foregroundStyle(NPInk.fg2)
                    if let plain = lyrics?.plain, !plain.isEmpty {
                        Text(plain).font(.system(size: 17)).foregroundStyle(Color.white)
                    }
                    Text(.init("A timed `.lrc` file beside the song gives karaoke what it needs, or use Lyrics, then Fix, then Tap along."))
                        .font(.system(size: 14)).foregroundStyle(NPInk.fg2)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16).padding(.vertical, 24)
                .frame(maxWidth: .infinity, minHeight: box.size.height)
            }
            }
        } else if store.lyrics.effective(timed: true) == .read {
            ScrollView {
                Text(lines.map(\.text).joined(separator: "\n"))
                    .font(.system(size: clampValue(19, h * 0.032, 34), weight: .semibold))
                    .foregroundStyle(Color.white).lineSpacing(8).multilineTextAlignment(.center)
                    .padding(.horizontal, 24).padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            }
        } else {
            TimelineView(.animation) { _ in
                let ms = listening.positionSec() * 1000 - offset
                let index = Karaoke.lineIndex(lines, ms)
                let now = index >= 0 ? lines[index] : nil
                let next = index + 1 < lines.count ? lines[index + 1] : nil
                let count = Karaoke.countIn(lines, at: ms)
                let big = clampValue(32, h * 0.074, 86.4)
                VStack(spacing: clampValue(10, h * 0.03, 34)) {
                    ZStack {
                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: clampValue(32, h * 0.074, 80), weight: .heavy).monospacedDigit())
                                .foregroundStyle(Color.white)
                                .frame(width: clampValue(64, h * 0.13, 130), height: clampValue(64, h * 0.13, 130))
                                .background(Circle().fill(Color.white.opacity(0.12)))
                                .overlay(Circle().strokeBorder(Color.white, lineWidth: 3))
                                .id(count)
                                .transition(.scale(scale: 1.18).combined(with: .opacity))
                        } else if index < 0, (lines.first?.t ?? 0) > 5000 {
                            Text("Get ready…").font(.system(size: clampValue(17.6, h * 0.028, 32), weight: .semibold)).foregroundStyle(NPInk.fg2)
                        }
                    }
                    .frame(height: clampValue(64, h * 0.13, 130))
                    .animation(.easeOut(duration: 0.3), value: count)
                    Group {
                        if let now, !now.text.isEmpty {
                            FlowRow(spacing: 0, lineSpacing: big * 0.14) {
                                ForEach(Array(Karaoke.words(now, next: next?.t).enumerated()), id: \.offset) { _, word in
                                    let fill = Karaoke.fill(word, at: ms)
                                    Text(word.text)
                                        .font(.system(size: big, weight: .heavy))
                                        .foregroundStyle(LinearGradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: fill),
                                                                                .init(color: Color.white.opacity(0.34), location: fill),
                                                                                .init(color: Color.white.opacity(0.34), location: 1)],
                                                                        startPoint: .leading, endPoint: .trailing))
                                }
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(now.text)
                        } else {
                            Text("♪").font(.system(size: big, weight: .heavy)).foregroundStyle(NPInk.fg3).accessibilityHidden(true)
                        }
                    }
                    .frame(minHeight: big * 2.3)
                    Text(next?.text ?? " ")
                        .font(.system(size: clampValue(19.2, h * 0.034, 40), weight: .semibold))
                        .foregroundStyle(NPInk.fg3)
                        .multilineTextAlignment(.center)
                        .frame(minHeight: clampValue(19.2, h * 0.034, 40) * 1.3)
                }
                .padding(.horizontal, 20)
            }
        }
    }

    /// The first screen's bar: the previous line, Play, the next line, then Guide voice, Mix and Voice settings.
    private func bar(compact: Bool) -> some View {
        let index = Karaoke.lineIndex(lines, listening.positionSec() * 1000 - offset)
        return FlowRow(spacing: 8, lineSpacing: 8) {
            NPRoundButton(symbol: "backward.end.fill", label: "Previous line", size: 52) { goLine(-1, from: index); wake() }
            Button { listening.toggle(); wake() } label: {
                Image(systemName: listening.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 26, weight: .bold)).foregroundStyle(Color.black)
                    .frame(width: 64, height: 64).background(Circle().fill(Color.white))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(listening.isPlaying ? "Pause" : "Play")
            NPRoundButton(symbol: "forward.end.fill", label: "Next line", size: 52) { goLine(1, from: index); wake() }
            if !compact { NPInk.line.frame(width: 1, height: 34).padding(.horizontal, 4) }
            KaraokeBarChips(stems: listening.stems, auto: auto, compact: compact, panel: panel, ink: ink, toggle: togglePanel, woke: wake)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    // MARK: The Mix and Voice settings

    private func panelView(_ which: KaraokePanel, compact: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(which == .mix ? "Mix" : "Voice settings").font(.title3.weight(.bold)).foregroundStyle(NPInk.fg)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    NPRoundButton(symbol: "xmark", label: which == .mix ? "Close" : "Close voice settings") { panel = nil }
                }
                if which == .mix { mix(compact: compact) } else { KaraokeVoiceFxPanel(stems: listening.stems, ink: ink, roomy: !compact) }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func mix(compact: Bool) -> some View {
        if auto {
            KaraokeStemsControl(stems: listening.stems, ink: ink)
        } else {
            // A server without separate parts: the voice turned down from the song itself.
            HStack(spacing: 2) {
                ForEach(Array(Karaoke.vocals.enumerated()), id: \.offset) { _, choice in
                    let on = listening.sound.vocalCut == choice.0
                    Button(choice.1) { listening.setSound { $0.vocalCut = choice.0 } }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(on ? Color.black : Color.white)
                        .padding(.horizontal, 14).frame(minHeight: 46)
                        .background(Capsule().fill(on ? Color.white : .clear))
                        .accessibilityAddTraits(on ? [.isSelected] : [])
                }
            }
            .padding(3)
            .background(Capsule().fill(NPInk.chip))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Singer's voice")
        }
        FlowRow(spacing: 8, lineSpacing: 8) {
            stepper(words: Karaoke.keyWords(listening.sound.keyShift),
                    lower: ("Lower key", listening.sound.keyShift > -6, { setKey(listening.sound.keyShift - 1) }),
                    raise: ("Raise key", listening.sound.keyShift < 6, { setKey(listening.sound.keyShift + 1) }))
                .accessibilityElement(children: .contain).accessibilityLabel("Musical key")
            stepper(words: Karaoke.timingWords(offset),
                    lower: ("Words sooner", true, { setOffset(offset - 100) }),
                    raise: ("Words later", true, { setOffset(offset + 100) }))
                .accessibilityElement(children: .contain).accessibilityLabel("Timing of the words")
        }
        if compact {
            LyricsModeToggle(timed: !lines.isEmpty)
            if auto {
                KaraokeChip(title: "Voice settings", on: !listening.stems.fx.isOff, ink: ink) { panel = .voice }
            }
        }
        if !note.isEmpty {
            Text(note).font(.system(size: 13)).foregroundStyle(NPInk.fg2).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stepper(words: String, lower: (String, Bool, () -> Void), raise: (String, Bool, () -> Void)) -> some View {
        HStack(spacing: 4) {
            Button(action: lower.2) {
                Text("−").font(.system(size: 20, weight: .bold)).foregroundStyle(Color.white)
                    .frame(width: 46, height: 46).background(Circle().fill(NPInk.chip))
            }
            .buttonStyle(.plain).disabled(!lower.1).opacity(lower.1 ? 1 : 0.4).accessibilityLabel(lower.0)
            Text(words).font(.system(size: 14, weight: .semibold).monospacedDigit()).foregroundStyle(Color.white)
                .frame(minWidth: 92)
            Button(action: raise.2) {
                Text("+").font(.system(size: 20, weight: .bold)).foregroundStyle(Color.white)
                    .frame(width: 46, height: 46).background(Circle().fill(NPInk.chip))
            }
            .buttonStyle(.plain).disabled(!raise.1).opacity(raise.1 ? 1 : 0.4).accessibilityLabel(raise.0)
        }
        .padding(3)
        .background(Capsule().fill(NPInk.chip))
    }
}

/// Guide voice, Mix and Voice settings on karaoke's bar, drawn again as the parts arrive and the levels move.
private struct KaraokeBarChips: View {
    @ObservedObject var stems: KaraokeStems
    let auto: Bool
    let compact: Bool
    let panel: KaraokeView.KaraokePanel?
    let ink: StemInk
    let toggle: (KaraokeView.KaraokePanel) -> Void
    let woke: () -> Void

    var body: some View {
        // The singer starts out; the guide voice brings them back quietly, and takes them out again.
        if auto, stems.loaded != nil || stems.waiting {
            KaraokeChip(title: "Guide voice", symbol: "music.mic", on: stems.guide, ink: ink, enabled: stems.loaded != nil) { stems.toggleGuide(); woke() }
                .accessibilityHint("Keeps the singer quietly, as a guide")
        }
        KaraokeChip(title: "Mix", symbol: "slider.horizontal.3", on: panel == .mix, ink: ink) { toggle(.mix) }
            .accessibilityHint("The voice, the music and the track, the key and the words' timing")
        if auto, !compact {
            KaraokeChip(title: "Voice settings", on: panel == .voice || !stems.fx.isOff, ink: ink) { toggle(.voice) }
                .accessibilityHint("Echo, reverb, tone and more, for the voice and the music")
        }
    }
}

/// A round button on black, white at 10%.
struct NPRoundButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(Color.white)
                .frame(width: size, height: size).background(Circle().fill(NPInk.chip)).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

func clampValue(_ low: CGFloat, _ value: CGFloat, _ high: CGFloat) -> CGFloat { min(max(value, low), high) }
#endif
