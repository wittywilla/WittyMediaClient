#if os(iOS) || os(visionOS)
import PDFKit
import SwiftUI
import WittyKit

// The rest of the website's Now Playing on a phone or a tablet: the visualizer behind it (backdrop.ts), the Sound
// panel (SoundPanel.tsx), Read (ReadPanel.tsx), Fix for the words (LyricsPanel.tsx), karaoke (Karaoke.tsx) and the
// volume (controls.tsx). The website's own player's colours: see NPInk.

// MARK: - Small parts

/// Things in a row that wrap onto the next line, centred, as the website's flex-wrap rows.
struct FlowRow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8
    var centred = true

    private func lines(_ sizes: [CGSize], width: CGFloat) -> [[Int]] {
        var all: [[Int]] = [[]]
        var used: CGFloat = 0
        for (index, size) in sizes.enumerated() {
            if !all[all.count - 1].isEmpty, used + spacing + size.width > width {
                all.append([])
                used = 0
            }
            used += (all[all.count - 1].isEmpty ? 0 : spacing) + size.width
            all[all.count - 1].append(index)
        }
        return all
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = lines(sizes, width: width)
        let height = rows.reduce(0) { $0 + ($1.map { sizes[$0].height }.max() ?? 0) } + CGFloat(max(0, rows.count - 1)) * lineSpacing
        let widest = rows.map { row in row.reduce(0) { $0 + sizes[$1].width } + CGFloat(max(0, row.count - 1)) * spacing }.max() ?? 0
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var y = bounds.minY
        for row in lines(sizes, width: bounds.width) {
            let rowWidth = row.reduce(0) { $0 + sizes[$1].width } + CGFloat(max(0, row.count - 1)) * spacing
            let rowHeight = row.map { sizes[$0].height }.max() ?? 0
            var x = centred ? bounds.minX + (bounds.width - rowWidth) / 2 : bounds.minX
            for index in row {
                subviews[index].place(at: CGPoint(x: x, y: y + (rowHeight - sizes[index].height) / 2), proposal: ProposedViewSize(sizes[index]))
                x += sizes[index].width + spacing
            }
            y += rowHeight + lineSpacing
        }
    }
}

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
                Capsule().fill(Color.white.opacity(0.28)).frame(height: 4)
                Capsule().fill(Color.white).frame(width: width * part, height: 4)
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

// MARK: - The visualizer

/// Bars, Waves and Drift, drawn from the sound as the website's backdrop does: 30 a second, or 20 when slow.
final class VisualizerDrawer {
    struct Mote { var x: Double, y: Double, r: Double, vx: Double, vy: Double, band: Int }
    var levels = [Double](repeating: 0, count: VisualizerLevels.count)
    var motes: [Mote] = (0..<14).map { i in
        Mote(x: .random(in: 0...1), y: .random(in: 0...1), r: 0.12 + .random(in: 0...0.2),
             vx: (.random(in: 0...1) - 0.5) * 0.02, vy: (.random(in: 0...1) - 0.5) * 0.02, band: i % 6)
    }
    var bins = [UInt8](repeating: 0, count: 1024)
    var last: Date?
    var t = 0.0

    func step(at now: Date, active: Bool, slow: Bool) -> Double {
        let dt = min(0.2, last.map { now.timeIntervalSince($0) } ?? 0.033)
        last = now
        let heard = active && SoundEngine.shared.spectrum(into: &bins)
        let rise = slow ? 2.5 : 14.0, fall = slow ? 1.0 : 3.2
        let ms = now.timeIntervalSinceReferenceDate * 1000
        for i in 0..<levels.count {
            var v = 0.0
            if heard {
                let range = VisualizerLevels.bins(i)
                var peak: UInt8 = 0
                for k in range where k < bins.count { peak = max(peak, bins[k]) }
                v = VisualizerLevels.level(peak: peak, at: i)
            } else if active {
                v = 0.18 + 0.1 * sin(ms / 1400 + Double(i) * 0.5) + 0.05 * sin(ms / 700 + Double(i))
            }
            let old = levels[i]
            levels[i] = v > old ? old + (v - old) * min(1, dt * rise) : old + (v - old) * min(1, dt * fall)
        }
        t += dt * (slow ? 0.35 : 1)
        return dt
    }

    func band(_ a: Int, _ b: Int) -> Double { levels[a..<min(b, levels.count)].reduce(0, +) / Double(max(1, b - a)) }
}

struct VisualizerBackground: View {
    let style: String
    let slow: Bool
    let colour: Color
    let playing: Bool
    @Environment(\.accessibilityReduceMotion) private var calm
    @State private var drawer = VisualizerDrawer()

    var body: some View {
        let gentle = slow || calm
        TimelineView(.animation(minimumInterval: gentle ? 1.0 / 20 : 1.0 / 30, paused: !playing && drawer.levels.allSatisfy { $0 < 0.004 })) { timeline in
            Canvas { context, size in
                let dt = drawer.step(at: timeline.date, active: playing, slow: gentle)
                switch style {
                case "waves": waves(&context, size)
                case "drift": drift(&context, size, dt: dt, gentle: gentle)
                default: bars(&context, size)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func bars(_ g: inout GraphicsContext, _ size: CGSize) {
        let n = VisualizerLevels.count
        let gap = size.width / CGFloat(n * 2)
        let width = gap * 0.62
        let base = size.height * 0.62, tall = size.height * 0.46
        let shading = GraphicsContext.Shading.linearGradient(Gradient(colors: [colour.opacity(0.55), colour.opacity(0)]),
                                                             startPoint: CGPoint(x: 0, y: base - tall), endPoint: CGPoint(x: 0, y: base))
        for i in 0..<n {
            let v = 0.12 + drawer.levels[i] * 0.88
            let height = min(tall, CGFloat(v) * tall)
            let off = (CGFloat(i) + 0.5) * gap
            var layer = g
            layer.opacity = 1 - Double(i) / Double(n) * 0.72
            layer.fill(Path(CGRect(x: size.width / 2 + off - width / 2, y: base - height, width: width, height: height)), with: shading)
            layer.fill(Path(CGRect(x: size.width / 2 - off - width / 2, y: base - height, width: width, height: height)), with: shading)
        }
    }

    private func waves(_ g: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        let low = drawer.band(0, 4), mid = drawer.band(4, 12), high = drawer.band(12, 23)
        let layers: [(a: Double, f: Double, s: Double, y: Double, o: Double)] = [
            (0.2 + low * 0.3, 1.2, 0.5, 0.62, 0.3), (0.12 + mid * 0.28, 2.1, -0.7, 0.6, 0.22), (0.07 + high * 0.22, 3.4, 1, 0.58, 0.16),
        ]
        for layer in layers {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: h))
            var x = 0.0
            while x <= Double(w) {
                let u = x / Double(w)
                let envelope = sin(u * .pi) * 0.8 + 0.2
                let y = Double(h) * layer.y - envelope * Double(h) * 0.42 * layer.a * (0.6 + 0.4 * sin(u * layer.f * 6.283 + drawer.t * layer.s * 1.4))
                    - Double(h) * 0.02 * sin(u * 3 + drawer.t * layer.s)
                path.addLine(to: CGPoint(x: x, y: y))
                x += 8
            }
            path.addLine(to: CGPoint(x: w, y: h))
            path.closeSubpath()
            g.fill(path, with: .linearGradient(Gradient(colors: [colour.opacity(layer.o), colour.opacity(0)]),
                                               startPoint: CGPoint(x: 0, y: h * 0.2), endPoint: CGPoint(x: 0, y: h * 0.8)))
        }
    }

    private func drift(_ g: inout GraphicsContext, _ size: CGSize, dt: Double, gentle: Bool) {
        let w = Double(size.width), h = Double(size.height)
        let push = gentle ? 0.35 : 1
        var layer = g
        layer.blendMode = .plusLighter
        for index in drawer.motes.indices {
            var m = drawer.motes[index]
            let level = drawer.levels[min(drawer.levels.count - 1, m.band * 3)]
            m.x += m.vx * dt * push * (1 + level * 2)
            m.y += m.vy * dt * push * (1 + level * 2)
            if m.x < -0.2 { m.x = 1.2 } else if m.x > 1.2 { m.x = -0.2 }
            if m.y < -0.2 { m.y = 1.2 } else if m.y > 1.2 { m.y = -0.2 }
            drawer.motes[index] = m
            let side = (m.r + level * 0.1) * max(w, h)
            let rect = CGRect(x: m.x * w - side / 2, y: m.y * h - side / 2, width: side, height: side)
            var mote = layer
            mote.opacity = 0.45 + min(0.45, level * 0.5)
            mote.fill(Path(ellipseIn: rect), with: .radialGradient(
                Gradient(stops: [.init(color: colour.opacity(0.5), location: 0), .init(color: colour.opacity(0.16), location: 0.5),
                                 .init(color: colour.opacity(0), location: 1)]),
                center: CGPoint(x: rect.midX, y: rect.midY), startRadius: 0, endRadius: side / 2))
        }
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

    var body: some View {
        let shown = listening.sound.muted ? 0 : listening.sound.volume
        HStack(spacing: 8) {
            Button { listening.setSound { $0.muted.toggle() } } label: {
                Image(systemName: shown == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(NPInk.fg)
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

/// Big words that fill in as they're sung, a count-in before each line after a break, the next line waiting below,
/// the voice turned down and the key moved to suit the singer.
struct KaraokeView: View {
    @EnvironmentObject private var listening: Listening
    @Environment(\.client) private var client
    let item: Item
    let lyrics: Lyrics?
    let loading: Bool
    let glow: Color
    let offset: Double
    let setOffset: (Double) -> Void
    let close: () -> Void
    /// The screen's safe area: it's shown over Now Playing, which already reaches the edges.
    var insets = EdgeInsets()
    @State private var mono = false
    private let monoCheck = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    private var lines: [LyricLine] { lyrics?.timed ?? [] }

    private func goLine(_ by: Int, from index: Int) {
        let to = max(0, index + by)
        guard lines.indices.contains(to) else { return }
        listening.seek(to: max(0, (lines[to].t + offset) / 1000))
    }

    private func setKey(_ key: Double) { listening.setSound { $0.keyShift = max(-6, min(6, key)) } }

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let compact = geo.size.width <= 700
            ZStack {
                Color(red: 6 / 255, green: 6 / 255, blue: 10 / 255).ignoresSafeArea()
                EllipticalGradient(colors: [glow.opacity(0.28), glow.opacity(0)], center: UnitPoint(x: 0.5, y: 0.4), startRadiusFraction: 0, endRadiusFraction: 0.8)
                    .ignoresSafeArea()
                VStack(spacing: 0) {
                    top(h)
                    stage(h)
                        .frame(maxHeight: .infinity)
                    controls(compact: compact)
                    Text(note).font(.system(size: 13)).foregroundStyle(NPInk.fg2).multilineTextAlignment(.center)
                        .frame(minHeight: 18)
                        .padding(.horizontal, 16).padding(.bottom, max(10, insets.bottom))
                }
                .padding(.top, insets.top)
            }
        }
        .environment(\.colorScheme, .dark)
        .onReceive(monoCheck) { _ in
            guard listening.sound.vocalCut > 0 else { if mono { mono = false }; return }
            if let found = SoundEngine.shared.nearlyMono() { mono = found }
        }
        // Coming back, the voice and key are as they were: this was for the song, not for good.
        .onDisappear { listening.setSound { $0.vocalCut = 0; $0.keyShift = 0 } }
        .accessibilityAction(.escape) { close() }
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

    private func controls(compact: Bool) -> some View {
        let index = Karaoke.lineIndex(lines, listening.positionSec() * 1000 - offset)
        return FlowRow(spacing: 8, lineSpacing: 8) {
            NPRoundButton(symbol: "backward.end.fill", label: "Previous line", size: 52) { goLine(-1, from: index) }
            Button { listening.toggle() } label: {
                Image(systemName: listening.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 26, weight: .bold)).foregroundStyle(Color.black)
                    .frame(width: 64, height: 64).background(Circle().fill(Color.white))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(listening.isPlaying ? "Pause" : "Play")
            NPRoundButton(symbol: "forward.end.fill", label: "Next line", size: 52) { goLine(1, from: index) }
            if !compact { NPInk.line.frame(width: 1, height: 34).padding(.horizontal, 4) }
            HStack(spacing: 2) {
                ForEach(Array(Karaoke.vocals.enumerated()), id: \.offset) { _, choice in
                    let on = listening.sound.vocalCut == choice.0
                    Button(choice.1) { listening.setSound { $0.vocalCut = choice.0 } }
                        .font(.system(size: compact ? 13 : 15, weight: .semibold))
                        .foregroundStyle(on ? Color.black : Color.white)
                        .padding(.horizontal, compact ? 10 : 16).frame(minHeight: 46)
                        .background(Capsule().fill(on ? Color.white : .clear))
                        .accessibilityAddTraits(on ? [.isSelected] : [])
                }
            }
            .padding(3)
            .background(Capsule().fill(NPInk.chip))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Singer's voice")
            stepper(words: Karaoke.keyWords(listening.sound.keyShift), compact: compact,
                    lower: ("Lower key", listening.sound.keyShift > -6, { setKey(listening.sound.keyShift - 1) }),
                    raise: ("Raise key", listening.sound.keyShift < 6, { setKey(listening.sound.keyShift + 1) }))
            stepper(words: Karaoke.timingWords(offset), compact: compact,
                    lower: ("Words sooner", true, { setOffset(offset - 100) }),
                    raise: ("Words later", true, { setOffset(offset + 100) }))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func stepper(words: String, compact: Bool, lower: (String, Bool, () -> Void), raise: (String, Bool, () -> Void)) -> some View {
        HStack(spacing: 4) {
            Button(action: lower.2) {
                Text("−").font(.system(size: 20, weight: .bold)).foregroundStyle(Color.white)
                    .frame(width: 46, height: 46).background(Circle().fill(NPInk.chip))
            }
            .buttonStyle(.plain).disabled(!lower.1).opacity(lower.1 ? 1 : 0.4).accessibilityLabel(lower.0)
            Text(words).font(.system(size: compact ? 13 : 14, weight: .semibold).monospacedDigit()).foregroundStyle(Color.white)
                .frame(minWidth: compact ? 74 : 92)
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
