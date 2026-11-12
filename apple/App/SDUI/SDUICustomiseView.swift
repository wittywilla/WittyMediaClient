// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

/// "Customise" for one page: what the page says a profile may change about it (`document.personal`), and nothing
/// else. On a phone and a tablet the sections are a list in edit mode, dragged by their handles; on Apple TV each
/// row has its own buttons, which a remote reaches one press at a time. Saving sends the profile's arrangement
/// to the page's own address; Reset takes it away. All the rules are WittyKit's `SDUICustomise`.
struct SDUICustomiseView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @Environment(\.palette) private var palette
    let document: SDUIDocument
    let page: String
    /// Called when it closes, with whether anything was changed.
    let done: (Bool) -> Void
    @State private var edit: SDUICustomise?
    @State private var menu: SDUINavCustomise?
    @State private var problem = ""
    @State private var saving = false

    private func load() async {
        // What was stored before, so that what this page doesn't show isn't lost; a profile with nothing stored has nothing.
        let stored = (try? await center.client.sduiPersonal(page: page)) ?? SDUIPersonal()
        edit = SDUICustomise(document: document, stored: stored)
        if document.page.kind == "home", center.features.contains("sdui-navigation"), let navigation = center.navigation,
           navigation.personal?.editable != false {
            let storedMenu = (try? await center.client.sduiPersonal(page: nil)) ?? SDUIPersonal()
            menu = SDUINavCustomise(shown: navigation.items, stored: storedMenu, listed: navigation.personal)
        }
    }

    private func refusal(_ error: Error) -> String {
        if let refused = error as? APIError, refused.status == 403 { return "This profile isn't allowed to rearrange pages." }
        let words = model.handle(error)
        return words.isEmpty ? "That couldn't be saved." : words
    }

    private func save() {
        guard let edit, !saving else { return }
        let menu = menu
        guard edit.changed || menu?.changed == true else { return done(false) }
        saving = true
        Task {
            do {
                if edit.changed { try await center.client.setSDUIPersonal(edit.personal, page: page) }
                if let menu, menu.changed {
                    try await center.client.setSDUIPersonal(menu.personal, page: nil)
                    await center.loadMenu()
                }
                done(true)
            } catch {
                problem = refusal(error)
            }
            saving = false
        }
    }

    private func reset() {
        guard !saving else { return }
        saving = true
        Task {
            do {
                try await center.client.resetSDUIPersonal(page: page)
                if menu != nil {
                    try await center.client.resetSDUIPersonal(page: nil)
                    await center.loadMenu()
                }
                done(true)
            } catch {
                problem = refusal(error)
            }
            saving = false
        }
    }

    var body: some View {
        Group {
            if let edit {
                #if os(tvOS)
                television(edit)
                #else
                touch(edit)
                #endif
            } else {
                LoadingView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(palette.background.ignoresSafeArea())
        .task { await load() }
    }

    private func sizeName(_ size: String) -> String { ["s": "Small", "m": "Medium", "l": "Large"][size] ?? size }
    private func densityName(_ density: String) -> String { ["compact": "Compact", "comfortable": "Comfortable", "spacious": "Spacious"][density] ?? density }

    private func state(_ row: SDUICustomise.Row) -> String {
        var words: [String] = []
        if row.locked { words.append("Always shown") }
        if row.pinned { words.append("Pinned") }
        if row.hidden { words.append("Hidden") }
        if row.empty, !row.hidden { words.append("Nothing in it now") }
        return words.joined(separator: " · ")
    }

    #if !os(tvOS)
    private func touch(_ edit: SDUICustomise) -> some View {
        NavigationStack {
            List {
                if !problem.isEmpty { Section { ProblemLine(problem) } }
                if !edit.rows.isEmpty, edit.canReorder || edit.canHide || edit.canPin || edit.canCardSize {
                    Section {
                        ForEach(edit.rows) { row in touchRow(row, edit) }
                            .onMove { from, to in
                                guard let first = from.first else { return }
                                self.edit?.move(from: first, to: to)
                            }
                    } header: {
                        Text("Sections")
                    } footer: {
                        Text(edit.canReorder ? "Drag to change the order. Pinned sections come first." : "This page's order is fixed.")
                    }
                }
                if edit.canDensity {
                    Section("Spacing") {
                        Picker("Spacing", selection: Binding(get: { edit.density }, set: { self.edit?.setDensity($0) })) {
                            ForEach(SDUICustomise.densities, id: \.self) { Text(densityName($0)).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("sdui.customise.density")
                    }
                }
                if edit.canDefaultTab {
                    Section("Opens on") {
                        ForEach(edit.tabs) { choice in
                            Picker(choice.title, selection: Binding(get: { choice.chosen }, set: { self.edit?.setDefaultTab(choice.id, $0) })) {
                                ForEach(choice.tabs) { Text($0.label).tag($0.value) }
                            }
                        }
                    }
                }
                if let menu {
                    Section {
                        ForEach(menu.rows) { row in
                            HStack {
                                Image(systemName: SDUIIcon.symbol(row.icon, or: "square")).foregroundStyle(palette.textSecondary).frame(width: 28)
                                Text(row.label).foregroundStyle(row.hidden ? palette.textHint : palette.text)
                                Spacer()
                                if !row.fixed {
                                    Button { self.menu?.setHidden(row.id, !row.hidden) } label: {
                                        Image(systemName: row.hidden ? "eye.slash" : "eye").frame(width: 44, height: 44)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel(row.hidden ? "Show \(row.label)" : "Hide \(row.label)")
                                }
                            }
                        }
                        .onMove { from, to in
                            guard let first = from.first else { return }
                            self.menu?.move(from: first, to: to)
                        }
                    } header: {
                        Text("Menu")
                    } footer: {
                        Text("Settings is always in the menu.")
                    }
                }
                Section {
                    Button("Reset to how it came", role: .destructive, action: reset)
                        .accessibilityIdentifier("sdui.customise.reset")
                }
            }
            .environment(\.editMode, .constant(edit.canReorder || menu != nil ? .active : .inactive))
            .navigationTitle("Customise \(document.page.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { done(false) } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: save).disabled(saving).accessibilityIdentifier("sdui.customise.done")
                }
            }
        }
    }

    private func touchRow(_ row: SDUICustomise.Row, _ edit: SDUICustomise) -> some View {
        HStack(spacing: Tokens.Space.s2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).foregroundStyle(row.hidden ? palette.textHint : palette.text)
                if !state(row).isEmpty { Text(state(row)).font(.caption).foregroundStyle(palette.textSecondary) }
            }
            Spacer(minLength: 0)
            if edit.canCardSize, let size = row.cardSize {
                Menu {
                    ForEach(SDUICustomise.cardSizes, id: \.self) { choice in
                        Button { self.edit?.setCardSize(row.id, choice) } label: {
                            if choice == size { Label(sizeName(choice), systemImage: "checkmark") } else { Text(sizeName(choice)) }
                        }
                    }
                } label: {
                    Text(size.uppercased()).font(.footnote.weight(.semibold)).frame(width: 36, height: 44)
                }
                .accessibilityLabel("Card size for \(row.title): \(sizeName(size))")
            }
            if edit.canPin, !row.locked {
                Button { self.edit?.setPinned(row.id, !row.pinned) } label: {
                    Image(systemName: row.pinned ? "pin.fill" : "pin").frame(width: 36, height: 44)
                }
                .buttonStyle(.borderless)
                .disabled(row.hidden)
                .accessibilityLabel(row.pinned ? "Unpin \(row.title)" : "Pin \(row.title) to the top")
            }
            if edit.canHide, !row.locked {
                Button { self.edit?.setHidden(row.id, !row.hidden) } label: {
                    Image(systemName: row.hidden ? "eye.slash" : "eye").frame(width: 36, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(row.hidden ? "Show \(row.title)" : "Hide \(row.title)")
                .accessibilityIdentifier("sdui.customise.hide." + row.id)
            }
        }
        .moveDisabled(!edit.canMove(row.id))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sdui.customise.row." + row.id)
    }
    #else
    private func pill(_ words: String, _ symbol: String, on: Bool = false, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(words, systemImage: symbol).labelStyle(.iconOnly).frame(minWidth: 44) }
            .action(selected: on, pill: true)
            .disabled(!enabled)
            .accessibilityLabel(words)
    }

    private func television(_ edit: SDUICustomise) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s6) {
                Heading("Customise \(document.page.title)")
                if !problem.isEmpty { ProblemLine(problem) }
                if !edit.rows.isEmpty, edit.canReorder || edit.canHide || edit.canPin || edit.canCardSize {
                    ListGroup(title: "Sections") {
                        ForEach(edit.rows) { row in
                            HStack(spacing: Tokens.Space.s3) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.title).font(.wmLabel).foregroundStyle(row.hidden ? palette.textHint : palette.text).lineLimit(1)
                                    if !state(row).isEmpty { Text(state(row)).font(.wmCardSub).foregroundStyle(palette.textSecondary) }
                                }
                                Spacer(minLength: Tokens.Space.s4)
                                if edit.canReorder, !row.locked {
                                    pill("Move \(row.title) up", "chevron.up", enabled: edit.canMove(row.id, by: -1)) { self.edit?.move(row.id, by: -1) }
                                    pill("Move \(row.title) down", "chevron.down", enabled: edit.canMove(row.id, by: 1)) { self.edit?.move(row.id, by: 1) }
                                }
                                if edit.canCardSize, let size = row.cardSize {
                                    Button(sizeName(size)) {
                                        let all = SDUICustomise.cardSizes
                                        self.edit?.setCardSize(row.id, all[((all.firstIndex(of: size) ?? 1) + 1) % all.count])
                                    }
                                    .action(pill: true)
                                    .accessibilityLabel("Card size for \(row.title): \(sizeName(size)). Press to change.")
                                }
                                if edit.canPin, !row.locked {
                                    pill(row.pinned ? "Unpin \(row.title)" : "Pin \(row.title) to the top", row.pinned ? "pin.fill" : "pin", on: row.pinned, enabled: !row.hidden) {
                                        self.edit?.setPinned(row.id, !row.pinned)
                                    }
                                }
                                if edit.canHide, !row.locked {
                                    pill(row.hidden ? "Show \(row.title)" : "Hide \(row.title)", row.hidden ? "eye.slash" : "eye", on: row.hidden) {
                                        self.edit?.setHidden(row.id, !row.hidden)
                                    }
                                }
                            }
                            .padding(.horizontal, Tokens.Space.s4)
                            .padding(.vertical, Tokens.Space.s2)
                            .focusSection()
                        }
                    }
                }
                if edit.canDensity {
                    ListGroup(title: "Spacing") {
                        HStack(spacing: Tokens.Space.s3) {
                            ForEach(SDUICustomise.densities, id: \.self) { density in
                                Button(densityName(density)) { self.edit?.setDensity(density) }.action(selected: edit.density == density, pill: true)
                            }
                        }
                        .padding(Tokens.Space.s4)
                        .focusSection()
                    }
                }
                if edit.canDefaultTab {
                    ListGroup(title: "Opens on") {
                        ForEach(edit.tabs) { choice in
                            HStack(spacing: Tokens.Space.s3) {
                                ForEach(choice.tabs) { tab in
                                    Button(tab.label) { self.edit?.setDefaultTab(choice.id, tab.value) }.action(selected: choice.chosen == tab.value, pill: true)
                                }
                            }
                            .padding(Tokens.Space.s4)
                            .focusSection()
                        }
                    }
                }
                if let menu {
                    ListGroup(title: "Menu") {
                        ForEach(menu.rows) { row in
                            HStack(spacing: Tokens.Space.s3) {
                                Label(row.label, systemImage: SDUIIcon.symbol(row.icon, or: "square")).font(.wmLabel)
                                    .foregroundStyle(row.hidden ? palette.textHint : palette.text)
                                Spacer(minLength: Tokens.Space.s4)
                                pill("Move \(row.label) up", "chevron.up", enabled: row.id != menu.rows.first?.id) { self.menu?.move(row.id, by: -1) }
                                pill("Move \(row.label) down", "chevron.down", enabled: row.id != menu.rows.last?.id) { self.menu?.move(row.id, by: 1) }
                                if !row.fixed {
                                    pill(row.hidden ? "Show \(row.label)" : "Hide \(row.label)", row.hidden ? "eye.slash" : "eye", on: row.hidden) {
                                        self.menu?.setHidden(row.id, !row.hidden)
                                    }
                                }
                            }
                            .padding(.horizontal, Tokens.Space.s4)
                            .padding(.vertical, Tokens.Space.s2)
                            .focusSection()
                        }
                    }
                }
                HStack(spacing: Tokens.Space.s3) {
                    Button("Done", action: save).action(primary: true, pill: true).disabled(saving)
                    Button("Cancel") { done(false) }.action(pill: true)
                    Button("Reset to how it came", action: reset).action(.destructive, pill: true).disabled(saving)
                }
                .focusSection()
            }
            .padding(.horizontal, Tokens.gutter)
            .padding(.vertical, Tokens.Space.s8)
        }
        .onExitCommand { done(false) }
    }
    #endif
}
