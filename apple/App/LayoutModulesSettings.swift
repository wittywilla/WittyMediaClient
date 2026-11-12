// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// Two pages of You (this app's Settings) for a server with module SDUI and layout options (the server's
// docs/SDUI.md, Layout options, and docs/SDUI-MODULES.md, Settings): Layout, the arrangement of the whole app on this
// device; and Modules, each module's settings drawn with this app's own rows. Neither is a server-driven page, and
// neither takes a module's colours: they are Settings.

// MARK: - Layout

/// A choice of the server's layout options for this device, the one in force ticked, with "As the server has it" to
/// follow the administrator's choice again. Saved at once; the menu and the page showing follow.
struct LayoutSettingsView: View {
    @EnvironmentObject private var center: SDUICenter
    @State private var busy = false
    @State private var problem = ""
    @State private var said = ""

    private func choose(_ layout: String?) {
        guard !busy else { return }
        busy = true
        problem = ""
        Task {
            do {
                try await center.chooseLayout(layout)
                said = "Layout: " + (center.navigation?.layouts?.currentLabel ?? "")
                announce(said)
            } catch let error as APIError where error.status == 403 {
                problem = "This profile can't choose its own layout, or the server doesn't offer that one."
                announce(problem)
            } catch {
                problem = plainWords(Problem.of(error))
                announce(problem)
            }
            busy = false
        }
    }

    var body: some View {
        let choice = center.navigation?.layouts
        SettingsScreen(title: "Layout", detail: "How the whole app is arranged on this device: where its menu is, and how pages show their titles.") {
            if let choice, !choice.options.isEmpty {
                ListGroup(title: "", footer: "Only this device changes. Your other devices keep their own.") {
                    SettingChoiceRow(title: "As the server has it", detail: choice.chosen == nil ? choice.currentLabel : "", chosen: choice.chosen == nil) {
                        choose(nil)
                    }
                    .accessibilityIdentifier("layout.server")
                    ForEach(choice.options) { option in
                        SettingChoiceRow(title: option.label, chosen: choice.chosen == option.value) { choose(option.value) }
                            .accessibilityIdentifier("layout." + option.value)
                            .accessibilityHint("One of \(choice.options.count) layouts")
                    }
                }
                if !problem.isEmpty { ProblemLine(problem) }
                if !said.isEmpty, problem.isEmpty { OutcomeLine(words: said).id(said) }
            } else {
                NoteCard(words: "This server offers no other layouts.", icon: "rectangle.3.group")
            }
        }
    }
}

// MARK: - Modules

/// The modules in use whose settings this profile may see.
struct ModulesSettingsView: View {
    @Environment(\.client) private var client
    @State private var list: [ModuleSettingsList.Entry]?
    @State private var problem = ""

    var body: some View {
        SettingsScreen(title: "Modules", detail: "Settings of the modules this server uses. Each module says what it has; they're shown here like the rest of Settings.") {
            if let list {
                if list.isEmpty {
                    NoteCard(words: "No module in use has settings for you.", icon: "puzzlepiece")
                } else {
                    ListGroup(title: "") {
                        ForEach(list) { entry in
                            NavigationLink(value: Route.moduleSettings(entry.module)) {
                                RowLabel(icon: SDUIIcon.symbol(entry.icon, or: "puzzlepiece"), tint: "#5d6474", title: PlainWords.clean(entry.label, limit: 80))
                            }
                            .rowStyle()
                            .accessibilityIdentifier("module." + entry.module)
                        }
                    }
                }
            } else if problem.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            }
            if !problem.isEmpty { ProblemLine(problem) }
        }
        .task {
            do {
                list = try await client.moduleSettingsList().modules
            } catch {
                problem = plainWords(Problem.of(error))
            }
        }
    }
}

/// One module's settings: each page a titled part, each group a list with its heading and footer, each row this app's
/// own control, saved as it changes. A row this profile can't change is its value, to read.
struct ModuleSettingsView: View {
    @Environment(\.client) private var client
    let module: String
    @State private var settings: ModuleSettings?
    @State private var problem = ""
    /// A row's own message, by key: what the server said was wrong with a value.
    @State private var rowProblems: [String: String] = [:]
    @State private var saving: Set<String> = []

    private func load() async {
        do {
            settings = try await client.moduleSettings(module)
        } catch {
            problem = plainWords(Problem.of(error))
        }
    }

    private func save(_ row: ModuleSettings.Row, _ value: JSONValue) {
        guard let key = row.key, let settings, !saving.contains(key) else { return }
        if value != .null, let wrong = ModuleSettings.problem(value, for: row) {
            rowProblems[key] = wrong
            announce(wrong)
            return
        }
        saving.insert(key)
        rowProblems[key] = nil
        Task {
            do {
                self.settings = try await client.setModuleSettings(settings.module, values: [key: value], personal: row.isProfile)
            } catch let error as APIError where error.status == 400 || error.status == 403 {
                rowProblems[key] = error.message
                announce(error.message)
            } catch {
                let words = plainWords(Problem.of(error))
                rowProblems[key] = words
                announce(words)
            }
            saving.remove(key)
        }
    }

    var body: some View {
        SettingsScreen(title: settings.map { PlainWords.clean($0.label, limit: 80) } ?? "", detail: "") {
            if let settings {
                ForEach(settings.pages) { page in
                    if settings.pages.count > 1 {
                        Text(PlainWords.clean(page.title, limit: 80))
                            .font(.wmSection)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.top, Tokens.Space.s3)
                    }
                    ForEach(Array(page.groups.enumerated()), id: \.offset) { _, group in
                        ListGroup(title: PlainWords.clean(group.title ?? "", limit: 80), footer: PlainWords.clean(group.footer ?? "", limit: 500)) {
                            ForEach(group.rows) { row in
                                ModuleSettingRow(row: row, settings: settings, problem: row.key.flatMap { rowProblems[$0] } ?? "") { save(row, $0) }
                            }
                        }
                    }
                }
            } else if problem.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            }
            if !problem.isEmpty { ProblemLine(problem) }
        }
        .task { await load() }
    }
}

/// One row of a module's settings, by its kind. Every one can be reached by a finger, a keyboard and the remote's
/// focus, and is read out with its label, value, unit and help.
private struct ModuleSettingRow: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let row: ModuleSettings.Row
    let settings: ModuleSettings
    let problem: String
    let save: (JSONValue) -> Void
    @State private var open = false
    @State private var text = ""
    @State private var editing = false

    private var help: String { PlainWords.clean(row.help ?? "", limit: 500) }
    private var label: String { PlainWords.clean(row.label, limit: 80) }
    private var value: JSONValue? { row.key.flatMap { settings.values[$0] } }

    /// A value to read: an `info` row, a row of a kind this app doesn't know, or one this profile can't change.
    private var readOnly: some View {
        Button {} label: {
            SettingRow(title: label, detail: help) {
                Text(settings.shown(row)).font(.wmSecondary).foregroundStyle(palette.textSecondary)
            }
        }
        .rowStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(row.kind == "info" ? "" : settings.shown(row) + ", read only")
        .accessibilityHint(help)
        .accessibilityAddTraits(.isStaticText)
    }

    private func number(_ by: Int) {
        let now = value?.int ?? row.min ?? 0
        var next = now + by
        if let min = row.min { next = max(min, next) }
        if let max = row.max { next = min(max, next) }
        if next != now { save(.number(Double(next))) }
    }

    @ViewBuilder private var control: some View {
        switch row.kind {
        case "bool":
            SwitchRow(title: label, detail: help, isOn: value?.bool == true) { save(.bool(!(value?.bool == true))) }
        case "enum":
            Button { open.toggle() } label: {
                SettingRow(title: label, detail: help) {
                    HStack(spacing: Tokens.Space.s1) {
                        Text(settings.shown(row)).font(.wmSecondary).foregroundStyle(palette.textSecondary)
                        Image(systemName: open ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(palette.textHint)
                    }
                    .accessibilityHidden(true)
                }
            }
            .rowStyle()
            .accessibilityLabel(label)
            .accessibilityValue(settings.shown(row))
            .accessibilityHint(help.isEmpty ? "Shows the choices" : help)
            if open {
                ForEach(row.options ?? [], id: \.value) { option in
                    SettingChoiceRow(title: "   " + PlainWords.clean(option.label, limit: 80), chosen: value?.string == option.value) {
                        open = false
                        save(.string(option.value))
                    }
                    .accessibilityLabel(PlainWords.clean(option.label, limit: 80))
                }
            }
        case "int":
            SettingRow(title: label, detail: help) {
                HStack(spacing: Tokens.Space.s2) {
                    Button { number(-1) } label: { Image(systemName: "minus").frame(width: metrics.tv ? 56 : 32, height: metrics.tv ? 48 : 32) }
                        .action(.quiet)
                        .disabled(row.min.map { (value?.int ?? $0) <= $0 } ?? false)
                        .accessibilityLabel("Less")
                    Text(settings.shown(row)).font(.wmSecondary.monospacedDigit()).foregroundStyle(palette.text).frame(minWidth: 44)
                    Button { number(1) } label: { Image(systemName: "plus").frame(width: metrics.tv ? 56 : 32, height: metrics.tv ? 48 : 32) }
                        .action(.quiet)
                        .disabled(row.max.map { (value?.int ?? $0) >= $0 } ?? false)
                        .accessibilityLabel("More")
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityValue(settings.shown(row))
            .accessibilityAdjustableAction { direction in number(direction == .increment ? 1 : -1) }
        case "string":
            VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                OutlinedField(label: label, text: $text, kind: .text, onSubmit: { save(.string(text)) })
                if !help.isEmpty { Secondary(help) }
            }
            .padding(.horizontal, Tokens.Space.s4)
            .padding(.vertical, Tokens.Space.s2)
            .onAppear { text = value?.string ?? "" }
            .onChange(of: value) { text = $0?.string ?? "" }
        case "secret":
            VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                SettingRow(title: label, detail: help) {
                    Text(settings.isSet(row) ? "Set" : "Not set").font(.wmSecondary).foregroundStyle(palette.textSecondary)
                }
                .accessibilityElement(children: .combine)
                // Never filled in: a new one is typed, or the one there is taken away.
                OutlinedField(label: settings.isSet(row) ? "A new one" : label, text: $text, kind: .password, onSubmit: {
                    guard !text.isEmpty else { return }
                    save(.string(text))
                    text = ""
                })
                .padding(.horizontal, Tokens.Space.s4)
                if settings.isSet(row) {
                    Button("Clear") { save(.null) }.action(.quiet).padding(.horizontal, Tokens.Space.s4)
                        .accessibilityLabel("Clear \(label)")
                }
            }
            .padding(.bottom, Tokens.Space.s2)
        default:
            readOnly
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if settings.canChange(row) { control } else { readOnly }
            if !problem.isEmpty { ProblemLine(problem).padding(.horizontal, Tokens.Space.s4).padding(.bottom, Tokens.Space.s2) }
        }
        .accessibilityIdentifier("module.setting." + row.id)
    }
}
