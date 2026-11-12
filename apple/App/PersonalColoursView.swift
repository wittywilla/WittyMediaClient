// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

/// You → Your colours: this profile's own colours over the server's theme, on every device it uses (the server's
/// docs/THEMES.md, A profile's own colours). Each colour by what it's for, in the website's groups; a picker on a phone
/// and a tablet, a choice of swatches on Apple TV; nothing changes until Save. The server refuses colours that would
/// make text hard to read, and says which: that answer is shown as it is, and nothing is saved.
struct PersonalColoursView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    /// The colours as the profile sees them now, every layer applied: what a row shows until it's changed.
    @State private var seen: [String: String] = [:]
    /// The profile's own, as saved, and as being changed.
    @State private var saved = PersonalColours()
    @State private var edits: [String: String] = [:]
    @State private var loaded = false
    @State private var busy = false
    @State private var problem = ""
    @State private var refused: [ContrastRefusal.Pair] = []
    @State private var said = ""
    @State private var open: String?

    private var changed: Bool { edits != saved.tokens }

    private func load() async {
        do {
            async let mine = client.personalColours()
            async let theme = client.resolvedTheme()
            let (m, t) = try await (mine, theme)
            saved = m
            edits = m.tokens
            seen = t.colors(dark: scheme == .dark)
            loaded = true
        } catch {
            problem = plainWords(Problem.of(error))
        }
    }

    private func save() {
        guard !busy else { return }
        busy = true
        problem = ""
        refused = []
        said = ""
        Task {
            do {
                var next = saved
                next.tokens = edits
                try await client.setPersonalColours(next)
                saved = next
                said = "Saved. Your colours are on every device you use."
                announce(said)
                model.refreshTheme()
            } catch let error as APIError where error.status == 400 {
                let answer = try? JSONDecoder().decode(ContrastRefusal.self, from: error.body)
                refused = answer?.contrast ?? []
                problem = error.message
                announce(problem)
            } catch {
                problem = plainWords(Problem.of(error))
                announce(problem)
            }
            busy = false
        }
    }

    private func resetAll() {
        guard !busy else { return }
        busy = true
        Task {
            do {
                try await client.resetPersonalColours()
                saved = PersonalColours()
                edits = [:]
                refused = []
                problem = ""
                said = "Back to the theme's colours."
                announce(said)
                model.refreshTheme()
                await load()
            } catch {
                problem = plainWords(Problem.of(error))
            }
            busy = false
        }
    }

    private func shown(_ token: String) -> ThemeColour? {
        ThemeColour(hex: edits[token] ?? seen[token] ?? "")
    }

    private func swatch(_ colour: ThemeColour?, size: CGFloat = 28) -> some View {
        RoundedRectangle(cornerRadius: Tokens.Radius.xs, style: .continuous)
            .fill(colour.map { Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue, opacity: $0.alpha) } ?? .clear)
            .frame(width: size, height: size)
            .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.xs, style: .continuous).stroke(palette.border, lineWidth: 1))
            .accessibilityHidden(true)
    }

    @ViewBuilder private func row(_ token: String) -> some View {
        let label = PersonalColours.label(token)
        let mine = edits[token] != nil
        #if os(tvOS)
        Button { open = open == token ? nil : token } label: {
            SettingRow(title: label, detail: mine ? "Yours: \(edits[token] ?? "")" : "The theme's") { swatch(shown(token)) }
        }
        .rowStyle()
        .accessibilityLabel(label)
        .accessibilityValue(mine ? "Your colour, \(edits[token] ?? "")" : "The theme's colour")
        if open == token {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Tokens.Space.s3) {
                    Button("The theme's") { edits[token] = nil; open = nil }.action(.quiet)
                    ForEach(PersonalColoursView.presets(for: token), id: \.self) { hex in
                        Button { edits[token] = hex; open = nil } label: { swatch(ThemeColour(hex: hex), size: 48) }
                            .buttonStyle(.card)
                            .accessibilityLabel(hex)
                    }
                }
                .padding(Tokens.Space.s3)
            }
            .unclippedScroll()
        }
        #else
        SettingRow(title: label, detail: mine ? "Yours" : "The theme's") {
            HStack(spacing: Tokens.Space.s3) {
                if mine {
                    Button("Reset") { edits[token] = nil }.action(.quiet).accessibilityLabel("Reset \(label)")
                }
                ColorPicker(label, selection: Binding(
                    get: { shown(token).map { Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue, opacity: $0.alpha) } ?? .gray },
                    set: { edits[token] = PersonalColoursView.hex($0) }
                ), supportsOpacity: false)
                .labelsHidden()
                .accessibilityLabel(label)
            }
        }
        #endif
    }

    var body: some View {
        SettingsScreen(title: "Your colours", detail: "Colours of your own over the server's theme, for this profile on every device. Text has to stay easy to read: colours that don't are refused, with what's wrong.") {
            if loaded {
                ForEach(PersonalColours.groups, id: \.title) { group in
                    ListGroup(title: group.title) {
                        ForEach(group.tokens, id: \.self) { row($0) }
                    }
                }
                if !refused.isEmpty {
                    VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                        Text("Hard to read").font(.wmLabel).foregroundStyle(palette.danger).accessibilityAddTraits(.isHeader)
                        ForEach(Array(refused.enumerated()), id: \.offset) { _, pair in
                            Text(ContrastRefusal.words(pair)).font(.wmSecondary).foregroundStyle(palette.textSecondary)
                        }
                    }
                    .padding(Tokens.Space.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(palette.danger.opacity(0.11)))
                    .accessibilityElement(children: .combine)
                }
                if !problem.isEmpty, refused.isEmpty { ProblemLine(problem) }
                if !said.isEmpty { OutcomeLine(words: said).id(said) }
                Button { save() } label: { BusyText("Save", busy: busy) }
                    .action(.primary, wide: true, tall: true)
                    .disabled(!changed)
                    .accessibilityIdentifier("personalColours.save")
                if !saved.tokens.isEmpty || !saved.modules.isEmpty {
                    Button("Use the theme's colours") { resetAll() }.action(.secondary, wide: true)
                }
            } else if problem.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ProblemLine(problem)
            }
        }
        .task { await load() }
    }

    /// A colour as `#RRGGBB`.
    static func hex(_ colour: Color) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(colour).getRed(&r, green: &g, blue: &b, alpha: &a)
        func part(_ v: CGFloat) -> String { String(format: "%02X", Int((min(max(v, 0), 1) * 255).rounded())) }
        return "#" + part(r) + part(g) + part(b)
    }

    /// Apple TV has no colour picker: a choice of swatches that suit what the colour is for.
    static func presets(for token: String) -> [String] {
        switch token {
        case "bg", "bg2", "bg3", "bg4":
            return ["#0F1115", "#151820", "#1F232C", "#262B36", "#101820", "#1A1A1A", "#FFFFFF", "#F4F5F7", "#EBEDF2"]
        case "fg", "fg2", "fg3":
            return ["#FFFFFF", "#E8EAF0", "#C9CDD6", "#A9AFBC", "#0E1013", "#2B2F38", "#4A505C"]
        case "border", "borderStrong", "controlLine":
            return ["#2B303B", "#3A404D", "#555C6B", "#C9CDD6", "#8A909C"]
        default:
            return ["#7955FF", "#9174FF", "#2A6FDB", "#3AD29F", "#FF8800", "#FF5C6C", "#F5C542", "#E040A0", "#00B8D9"]
        }
    }
}
