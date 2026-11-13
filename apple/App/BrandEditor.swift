// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import UniformTypeIdentifiers
import WittyKit

// The server's name and mark (docs/plans/DESIGN-2.md 7.6, the canvas's BrandEditor): Settings, Appearance, Name and logo, for
// administrators. Choose letters or words, give them a colour that follows the theme (the text colour, the accent, any theme
// colour), a fixed colour that stays in every theme, or a gradient; presets; the mark for small spaces; the name drawn live in
// every frame it appears in; and a warning, with the numbers, where a colour does not read on the surfaces it sits on. The rules
// are WittyKit's BrandDraft and BrandContrast; what is saved is what the server draws (`brandSpans`, `brandMark`).

struct BrandEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette

    @State private var draft = BrandDraft(name: "")
    @State private var loaded = false
    /// The letters chosen to be coloured.
    @State private var selection: Set<Int> = []
    @State private var bold = false
    @State private var hex = ""
    @State private var stops = ["#1e9be0", "#3aa84a"]
    @State private var angle = 90
    @State private var editingStops = false
    @State private var customMark = ""
    @State private var saving = false
    @State private var problem = ""
    @State private var saved = ""
    @State private var showingLogoPicker = false
    @State private var pickedLogo = false

    private var colors: [String: String] { model.themeStyle?.colors ?? [:] }
    private var name: String { draft.shown }

    // MARK: Loading

    private func load() async {
        guard !loaded else { return }
        let resolved = try? await client.resolvedTheme()
        let current = PlainWords.clean(model.brandName, limit: 80)
        let parts = resolved?.brand?.parts ?? []
        let mark = resolved?.brand?.mark
        let choice = BrandMarkChoice(kind: mark?.kind ?? "letter", text: mark?.kind == "text" ? mark?.text : nil)
        draft = parts.isEmpty ? BrandDraft(name: current) : BrandDraft(name: current, parts: parts, mark: choice)
        customMark = choice.kind == "text" ? (choice.text ?? "") : ""
        loaded = true
    }

    // MARK: Colours

    private func swatch(_ c: ResolvedTheme.BrandColour) -> Color {
        let accent = colors["brandAccent"].flatMap(ThemeColour.init(hex:)) ?? ThemeColour(hex: "#ffffff")!
        let fg = colors["fg"].flatMap(ThemeColour.init(hex:)) ?? .white
        let r = c.resolved(colors: colors, fg: fg, accent: accent).solid
        return Color(.sRGB, red: r.red, green: r.green, blue: r.blue, opacity: 1)
    }

    private func gradient(_ list: [String]) -> LinearGradient {
        LinearGradient(colors: list.map { Color(hex: $0) }, startPoint: .leading, endPoint: .trailing)
    }

    private func paint(_ colour: ResolvedTheme.BrandColour) {
        guard !selection.isEmpty else { announce("Choose letters first."); return }
        let ranges = selection.sorted()
        for index in ranges { draft.apply(colour, bold: bold ? true : nil, to: index..<(index + 1)) }
        announce("Colour applied to \(ranges.count) letters.")
    }

    private func applyFixed(_ value: String) {
        guard ThemeColour(hex: value) != nil, value.hasPrefix("#"), value.count == 7 else {
            problem = "A fixed colour is written #rrggbb."
            return
        }
        problem = ""
        paint(.init(kind: "static", hex: value.lowercased()))
    }

    private var currentHex: String {
        guard let first = selection.min(), draft.styles.indices.contains(first) else { return "" }
        let c = draft.styles[first].colour
        return c.kind == "static" ? (c.hex ?? "") : ""
    }

    private func isCurrent(_ colour: ResolvedTheme.BrandColour) -> Bool {
        guard let first = selection.min(), draft.styles.indices.contains(first) else { return false }
        return draft.styles[first].colour == colour
    }

    // MARK: Saving

    private func save() {
        guard !saving else { return }
        if let first = draft.problems.first { problem = first; return }
        saving = true
        problem = ""
        Task {
            do {
                try await client.saveBrand(draft)
                await model.refreshBrand()
                saved = "Saved. Every screen shows it now."
                announce(saved)
            } catch {
                problem = model.handle(error).isEmpty ? "That couldn't be saved." : model.handle(error)
            }
            saving = false
        }
    }

    // MARK: The page

    var body: some View {
        DesignPage(eyebrow: "Settings · Appearance · Name and logo", title: "Your server's name",
                   lead: "Pick the letters, then a colour. A colour that follows the theme changes with it; a fixed colour stays the same in every theme.",
                   identifier: "brand") {
            nameSection
            lettersSection
            colourSection
            presetsSection
            markSection
            previewSection
            contrastSection
            if !problem.isEmpty { ProblemLine(problem).padding(.top, Tokens.Space.s3).accessibilityIdentifier("brand.problem") }
            if !saved.isEmpty { Text(saved).font(.wm(size: 14, weight: .semibold)).foregroundStyle(palette.ok).padding(.top, Tokens.Space.s3) }
        } actions: {
            Button { save() } label: { Label(saving ? "Saving…" : "Save name", systemImage: "checkmark") }
                .action(primary: true)
                .disabled(saving || !draft.problems.isEmpty)
                .accessibilityIdentifier("brand.save")
            Button { Task { loaded = false; saved = ""; await load() } } label: { Label("Start again", systemImage: "arrow.uturn.backward") }
                .action(.secondary)
                .accessibilityIdentifier("brand.revert")
        }
        .task { await load() }
        #if !os(tvOS)
        .fileImporter(isPresented: $showingLogoPicker, allowedContentTypes: [.png, .jpeg]) { result in pickLogo(result) }
        #endif
    }

    private var nameSection: some View {
        DesignSection(title: "Name") {
            OutlinedField(label: "Name", text: Binding(get: { draft.name }, set: { draft.rename($0); selection = selection.filter { $0 < name.unicodeScalars.count } }), kind: .text)
                .accessibilityIdentifier("brand.name")
            DesignNote(text: "Leave it empty for WittyMediaServer. Up to \(BrandDraft.maxRunes) characters.")
        }
    }

    private var lettersSection: some View {
        DesignSection(title: "Choose letters or words to colour") {
            FlowLayout(spacing: 6, rowSpacing: 6) {
                ForEach(Array(draft.letters.enumerated()), id: \.offset) { index, letter in
                    let on = selection.contains(index)
                    Button {
                        if on { selection.remove(index) } else { selection.insert(index) }
                    } label: {
                        Text(String(letter) == " " ? "␣" : String(letter))
                            .font(.wm(size: 17, weight: .bold))
                            .foregroundStyle(on ? palette.onAccent : palette.text)
                            .frame(minWidth: 36, minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: Tokens.Radius.sm, style: .continuous).fill(on ? palette.accent : palette.card))
                            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.sm, style: .continuous).strokeBorder(on ? palette.accentText : palette.border, lineWidth: on ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Letter \(index + 1), \(letter == " " ? "space" : String(letter))")
                    .accessibilityAddTraits(on ? [.isSelected] : [])
                    .accessibilityHint("Selects it to be coloured")
                }
            }
            .remoteSection()
            DesignChips {
                let scalars = Array(name.unicodeScalars)
                ForEach(Array(BrandWords.ranges(name).enumerated()), id: \.offset) { _, range in
                    DesignChip(title: String(String.UnicodeScalarView(scalars[range])), on: Set(range).isSubset(of: selection)) {
                        if Set(range).isSubset(of: selection) { selection.subtract(range) } else { selection.formUnion(range) }
                    }
                }
                DesignChip(title: "All letters", on: selection.count == name.unicodeScalars.count) { selection = Set(0..<name.unicodeScalars.count) }
                DesignChip(title: "None", on: false) { selection = [] }
            }
            DesignNote(text: "Select a letter or a word; use the arrow keys or the remote to move between them, and Space or Select to choose.")
        }
    }

    private var colourSection: some View {
        DesignSection(title: "Colour for the selection") {
            Text("Follows the theme (changes with the theme)").font(.wm(size: 13, weight: .bold)).foregroundStyle(palette.textSecondary)
            HStack(spacing: 12) {
                ForEach(["fg", "accent", "ok", "warn", "danger"], id: \.self) { kind in
                    let c = kind == "ok" || kind == "warn" || kind == "danger" ? ResolvedTheme.BrandColour(kind: "token", token: kind) : ResolvedTheme.BrandColour(kind: kind)
                    swatchButton(AnyShapeStyle(swatch(c)), selected: isCurrent(c), label: kind == "fg" ? "Text colour" : kind == "accent" ? "Accent" : kind.capitalized + " colour") { paint(c) }
                }
            }
            .remoteSection()
            Text("Fixed colour (stays the same in every theme)").font(.wm(size: 13, weight: .bold)).foregroundStyle(palette.textSecondary).padding(.top, Tokens.Space.s2)
            HStack(spacing: 12) {
                ForEach(["#b4491f", "#1e9be0", "#3aa84a", "#ffd84a", "#ff4f9a"], id: \.self) { value in
                    swatchButton(AnyShapeStyle(Color(hex: value)), selected: currentHex == value, label: "Fixed colour \(value)") { applyFixed(value) }
                }
                #if !os(tvOS)
                ColorPicker("Any colour…", selection: Binding(get: { Color(hex: currentHex.isEmpty ? "#b4491f" : currentHex) }, set: { applyFixed(Self.hex(of: $0)) }), supportsOpacity: false)
                    .labelsHidden()
                    .accessibilityLabel("Any colour")
                #endif
            }
            .remoteSection()
            OutlinedField(label: "#rrggbb", text: $hex, kind: .text, onSubmit: { applyFixed(hex) })
                .frame(maxWidth: 220)
                .accessibilityIdentifier("brand.hex")
            Text("Gradient").font(.wm(size: 13, weight: .bold)).foregroundStyle(palette.textSecondary).padding(.top, Tokens.Space.s2)
            HStack(spacing: 12) {
                ForEach([["#1e9be0", "#3aa84a"], ["#ff4f9a", "#ffd84a"]], id: \.self) { list in
                    swatchButton(AnyShapeStyle(gradient(list)), wide: true, selected: false, label: "Gradient \(list.joined(separator: " to "))") {
                        paint(.init(kind: "gradient", stops: list, angle: 90))
                    }
                }
                DesignChip(title: editingStops ? "Done" : "Edit stops…", on: editingStops) { editingStops.toggle() }
            }
            .remoteSection()
            if editingStops { stopsEditor }
            Toggle("Bold", isOn: $bold)
                .font(.wm(size: 15, weight: .semibold))
                .onChange(of: bold) { value in for index in selection { draft.setBold(value, in: index..<(index + 1)) } }
                .padding(.top, Tokens.Space.s2)
                .accessibilityIdentifier("brand.bold")
        }
    }

    private var stopsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(stops.indices, id: \.self) { index in
                HStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color(hex: stops[index])).frame(width: 36, height: 36).accessibilityHidden(true)
                    OutlinedField(label: "Stop \(index + 1)", text: Binding(get: { stops[index] }, set: { stops[index] = $0 }), kind: .text)
                        .frame(maxWidth: 200)
                    if stops.count > 2 {
                        Button { stops.remove(at: index) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.plain).frame(minWidth: 44, minHeight: 44).accessibilityLabel("Remove stop \(index + 1)")
                    }
                }
            }
            HStack {
                if stops.count < 4 { Button { stops.append("#ffd84a") } label: { Label("Add a stop", systemImage: "plus") }.action(.secondary, pill: true) }
                Picker("Direction", selection: $angle) {
                    Text("Left to right").tag(90)
                    Text("Top to bottom").tag(180)
                    Text("Diagonal").tag(135)
                }
                #if !os(tvOS)
                .pickerStyle(.menu)
                #endif
                Button { applyGradient() } label: { Label("Use this gradient", systemImage: "checkmark") }.action(primary: true, pill: true)
            }
            .remoteSection()
        }
        .padding(Tokens.Space.s3)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(palette.card))
    }

    private func applyGradient() {
        let ok = stops.allSatisfy { $0.hasPrefix("#") && $0.count == 7 && ThemeColour(hex: $0) != nil }
        guard ok else { problem = "A gradient's stops are written #rrggbb."; return }
        problem = ""
        paint(.init(kind: "gradient", stops: stops.map { $0.lowercased() }, angle: angle))
    }

    private func swatchButton(_ paint: AnyShapeStyle, wide: Bool = false, selected: Bool, label: String, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: wide ? 12 : 20, style: .continuous)
        return Button(action: action) {
            shape.fill(paint)
                .frame(width: wide ? 120 : 40, height: 40)
                .overlay(shape.stroke(selected ? palette.text : palette.border, lineWidth: selected ? 3 : 1))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private static func hex(of color: Color) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return ThemeColour(red: Double(r), green: Double(g), blue: Double(b)).hex
    }

    // MARK: Presets and the mark

    private var presetsSection: some View {
        DesignSection(title: "Presets") {
            DesignChips {
                ForEach(BrandDraft.Preset.allCases, id: \.self) { preset in
                    DesignChip(title: preset.title, on: false) { draft.use(preset); selection = []; announce("\(preset.title) applied.") }
                        .accessibilityIdentifier("brand.preset." + preset.rawValue)
                }
            }
        }
    }

    private var markSection: some View {
        DesignSection(title: "Mark for the rail and small spaces") {
            HStack(spacing: 16) {
                MarkBadge(shown: draft.mark.shown(name: name), image: draft.mark.kind == "image" ? client.brandLogoURL(version: model.brandLogo) : nil, size: 64)
                DesignChips {
                    DesignChip(title: "Letter · \(BrandMarkChoice.letter.shown(name: name))", on: draft.mark.kind == "letter") { draft.mark = .letter }
                    DesignChip(title: "Initials · \(BrandMarkChoice(kind: "initials").shown(name: name))", on: draft.mark.kind == "initials") { draft.mark = BrandMarkChoice(kind: "initials") }
                    DesignChip(title: "Your own · 1 to 2 characters", on: draft.mark.kind == "text") { draft.mark = BrandMarkChoice.custom(customMark) ?? BrandMarkChoice(kind: "text", text: customMark) }
                    #if !os(tvOS)
                    DesignChip(title: "Upload a logo…", on: draft.mark.kind == "image") { showingLogoPicker = true }
                    #endif
                    if !model.brandLogo.isEmpty {
                        DesignChip(title: "Remove the logo", on: false) { removeLogo() }
                    }
                }
            }
            if draft.mark.kind == "text" {
                OutlinedField(label: "Your characters", text: Binding(get: { customMark }, set: { customMark = String($0.prefix(2)); draft.mark = BrandMarkChoice(kind: "text", text: customMark) }), kind: .text)
                    .frame(maxWidth: 220)
                    .accessibilityIdentifier("brand.mark.text")
            }
            DesignNote(text: "The mark is always centred in a square badge. A logo is a square PNG or JPEG up to 2 MB; it falls back to the letter on a server that can't load it. It follows the name's colours unless you choose fixed ones.")
        }
    }

    #if !os(tvOS)
    private func pickLogo(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { problem = "That picture can't be read."; return }
        guard data.count <= WittyClient.maxLogoBytes else { problem = "The logo must be 2 MB or smaller."; return }
        let ratio = image.size.width / max(1, image.size.height)
        guard abs(ratio - 1) < 0.05 else { problem = "A logo is square. This one is \(Int(image.size.width)) by \(Int(image.size.height))."; return }
        guard min(image.size.width, image.size.height) >= 16 else { problem = "The logo must be at least 16 pixels on a side."; return }
        problem = ""
        let png = data.starts(with: [0x89, 0x50, 0x4E, 0x47])
        Task {
            do {
                try await client.uploadBrandLogo(data, png: png)
                draft.mark = BrandMarkChoice(kind: "image")
                try await client.saveBrand(draft)
                await model.refreshBrand()
                saved = "The logo is on the server."
                announce(saved)
            } catch {
                problem = model.handle(error).isEmpty ? "That couldn't be saved." : model.handle(error)
            }
        }
    }
    #endif

    private func removeLogo() {
        Task {
            do {
                try await client.removeBrandLogo()
                if draft.mark.kind == "image" { draft.mark = .letter }
                try await client.saveBrand(draft)
                await model.refreshBrand()
                saved = "The logo is removed."
                announce(saved)
            } catch {
                problem = model.handle(error).isEmpty ? "That couldn't be saved." : model.handle(error)
            }
        }
    }

    // MARK: Live previews

    private var previewSection: some View {
        DesignSection(title: "Live preview, everywhere the name appears") {
            VStack(spacing: 12) {
                previewFrame("Side menu") { BrandName(parts: draft.parts, colors: colors, fg: palette.text, size: 26) }
                previewFrame("Top bar and TV bar") {
                    HStack(spacing: 16) {
                        BrandName(parts: draft.parts, colors: colors, fg: palette.text, size: 26)
                        Text("Home").font(.wm(size: 15, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Capsule().fill(palette.accent.opacity(0.25))).foregroundStyle(palette.accentText)
                        Text("Libraries").font(.wm(size: 15)).foregroundStyle(palette.textSecondary)
                        Text("Live TV").font(.wm(size: 15)).foregroundStyle(palette.textSecondary)
                    }
                }
                previewFrame("Rail header, when open") {
                    HStack(spacing: 12) {
                        MarkBadge(shown: draft.mark.shown(name: name), image: draft.mark.kind == "image" ? client.brandLogoURL(version: model.brandLogo) : nil, size: 40)
                        BrandName(parts: draft.parts, colors: colors, fg: palette.text, size: 20)
                    }
                }
                previewFrame("Sign-in") {
                    VStack(spacing: 14) {
                        BrandName(parts: draft.parts, colors: colors, fg: palette.text, size: 34)
                        Text("Sign in").font(.wm(size: 15, weight: .bold)).foregroundStyle(palette.onAccent)
                            .frame(maxWidth: 220, minHeight: 44).background(Capsule().fill(palette.accent))
                    }
                    .frame(maxWidth: .infinity)
                }
                HStack(spacing: 12) {
                    sample("In a light theme", ground: [Color(hex: "#bfeaff"), Color(hex: "#e1f8d6")], fg: Color(hex: "#0b3a5a"), tokens: ["bg": "#cfeeff", "bg2": "#ffffff", "bg3": "#e7f6ff", "fg": "#0b3a5a", "brandAccent": "#0a6aa8"])
                    sample("On black", ground: [.black, .black], fg: .white, tokens: ["bg": "#000000", "bg2": "#0a0a0a", "bg3": "#141414", "fg": "#ffffff", "brandAccent": "#8ab4ff"])
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func previewFrame<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.wm(size: 11, weight: .bold)).tracking(0.8).foregroundStyle(palette.textHint)
            content()
        }
        .padding(Tokens.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .finished(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous), fill: palette.panel, role: .card)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) preview: \(name)")
    }

    private func sample(_ title: String, ground: [Color], fg: Color, tokens: [String: String]) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.wm(size: 11, weight: .bold)).foregroundStyle(fg.opacity(0.8))
            BrandName(parts: draft.parts, colors: tokens, fg: fg, size: 22, accentHex: tokens["brandAccent"])
        }
        .frame(maxWidth: .infinity, minHeight: 90)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).fill(LinearGradient(colors: ground, startPoint: .top, endPoint: .bottom)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) preview: \(name)")
    }

    // MARK: Contrast

    private var warnings: [(theme: String, warning: BrandContrast.Warning)] {
        var out = BrandContrast.warnings(draft, colors: colors).map { (theme: "this theme", warning: $0) }
        // Every other theme the server has, on the colours its picture gives (the page and its surface).
        for theme in (model.themeList?.themes ?? []) where theme.id != model.effectiveThemeId {
            guard let bg = theme.preview?.bg, let surface = theme.preview?.surface, let text = theme.preview?.text, let accent = theme.preview?.accent else { continue }
            let tokens = ["bg": bg, "bg2": surface, "bg3": surface, "fg": text, "brandAccent": accent, "accentText": accent]
            for w in BrandContrast.warnings(draft, colors: tokens) where !out.contains(where: { $0.theme == theme.shownName && $0.warning.text == w.text }) {
                out.append((theme: theme.shownName, warning: w))
            }
        }
        return out
    }

    private var contrastSection: some View {
        DesignSection(title: "Contrast") {
            let list = warnings
            if list.isEmpty {
                DesignNote(text: "Every colour reads on the page, panels and cards of this theme and the others (4.5 to 1 or better).", tone: true)
            } else {
                DesignNote(text: "Some colours are hard to read. You can still save them; a colour that follows the theme won't have this problem.", tone: true)
                ForEach(Array(list.prefix(6).enumerated()), id: \.offset) { _, item in
                    Label(item.warning.words(theme: item.theme), systemImage: "exclamationmark.triangle")
                        .font(.wm(size: 14))
                        .foregroundStyle(palette.warn)
                        .accessibilityIdentifier("brand.warning")
                }
            }
        }
    }
}

/// The name drawn in a frame, a part at a time, each in its own colour: the theme's text or accent, a theme token, a fixed colour or
/// a gradient across the part. The colours are the theme's tokens, so a preview on another theme's colours is just other tokens.
struct BrandName: View {
    let parts: [ResolvedTheme.Brand.Part]
    let colors: [String: String]
    let fg: Color
    let size: CGFloat
    var accentHex: String?

    private func colour(_ c: ThemeColour) -> Color { Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha) }

    var body: some View {
        let accent = (accentHex ?? colors["brandAccent"]).flatMap(ThemeColour.init(hex:)) ?? ThemeColour(hex: "#ffffff")!
        let base = colors["fg"].flatMap(ThemeColour.init(hex:)) ?? .white
        HStack(spacing: 0) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                let resolved = (part.color ?? .init(kind: "fg")).resolved(colors: colors, fg: base, accent: accent)
                let text = Text(part.text).font(.wm(size: size, weight: part.bold == true ? .heavy : .bold))
                if part.color?.kind == "gradient", resolved.stops.count >= 2 {
                    text.foregroundStyle(LinearGradient(colors: resolved.stops.map(colour), startPoint: .leading, endPoint: .trailing))
                } else if part.color?.kind == "fg" || part.color == nil {
                    text.foregroundColor(fg)
                } else {
                    text.foregroundColor(colour(resolved.solid))
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}

/// The mark in its square badge: its characters centred, or the owner's picture fitted inside.
struct MarkBadge: View {
    @Environment(\.palette) private var palette
    let shown: String
    var image: URL?
    var size: CGFloat = 48

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
        ZStack {
            shape.fill(palette.card)
            if let image {
                ArtImage(url: image, width: size, blank: true).padding(size * 0.1).clipShape(shape)
            } else {
                Text(shown).font(.wm(size: size * (shown.count > 1 ? 0.36 : 0.5), weight: .heavy)).foregroundStyle(palette.accentText).minimumScaleFactor(0.5)
            }
        }
        .overlay(shape.strokeBorder(palette.border, lineWidth: 1))
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
