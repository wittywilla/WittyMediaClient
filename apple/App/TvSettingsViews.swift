// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

#if os(tvOS)
// The desktop Settings pages Apple TV draws itself (docs/TV-SETTINGS-PARITY.md): Video quality, Skipping and content,
// Playback, Appearance, Activity, Sharing and About, from shared/data/tv-settings.json (WittyKit's TvSettings.swift). In
// Apple TV's own Settings design, with the same rows as a module's settings (LayoutModulesSettings.swift): a switch
// says On or Off and a press changes it, a choice opens its list, a number has − and +. Every change is saved as it is
// made, through the same endpoints the server's own pages use. A page the server keeps as `view` on a TV shows its
// values, each row a stop for the remote; a part kept for a computer is a row that opens its card, never a dead end.

enum TvSettingsData {
    static let file: TvSettingsFile = {
        guard let url = Bundle.main.url(forResource: "tv-settings", withExtension: "json", subdirectory: "data"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(TvSettingsFile.self, from: data) else { return TvSettingsFile() }
        return file
    }()

    /// A key of strings.en.json, or the words themselves (a language's own name).
    static func words(_ key: String) -> String { key.isEmpty ? "" : SharedData.strings[key] ?? key }
}

struct TvSettingsPageView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    let pageId: String
    @State private var stores: [String: JSONValue]?
    @State private var problem = ""
    @State private var rowProblems: [String: String] = [:]
    @State private var saving: Set<String> = []
    @State private var said = ""

    private var file: TvSettingsFile { TvSettingsData.file }
    private var admin: Bool { model.user?.isAdmin == true }
    private var page: TvSettingsPage? { file.page(pageId).flatMap { TvSettingsRules.pageVisible($0, admin: admin) ? $0 : nil } }
    private func w(_ key: String?) -> String { TvSettingsData.words(key ?? "") }

    private func load(_ groups: [TvSettingsGroup]) async {
        var got: [String: JSONValue] = [:]
        for id in TvSettingsRules.stores(groups) {
            guard let store = file.stores[id] else { continue }
            do {
                got[id] = try await client.tvSettingsStore(store)
            } catch {
                problem = plainWords(Problem.of(error))
            }
        }
        stores = got
    }

    private func save(_ spec: TvSettingsRow, _ value: JSONValue) {
        guard let store = file.stores[spec.store ?? ""], !saving.contains(spec.rowKey), value != .null else { return }
        saving.insert(spec.rowKey)
        rowProblems[spec.rowKey] = nil
        said = ""
        Task {
            do {
                // A merge starts from what is there now: other screens and devices write there too.
                let fresh = store.write == "merge" ? try await client.tvSettingsStore(store) : nil
                try await client.saveTvSetting(store, TvSettingsRules.body(store, fresh: fresh, row: spec, value: value))
                let now = try await client.tvSettingsStore(store)
                var next = stores ?? [:]
                next[spec.store ?? ""] = now
                stores = next
                said = w("moduleSaved")
                announce(said)
            } catch let error as APIError where error.status == 400 || error.status == 403 {
                rowProblems[spec.rowKey] = error.message
                announce(error.message)
            } catch {
                let words = plainWords(Problem.of(error))
                rowProblems[spec.rowKey] = words
                announce(words)
            }
            saving.remove(spec.rowKey)
        }
    }

    var body: some View {
        if let page {
            let groups = TvSettingsRules.visible(file, page, admin: admin)
            SettingsScreen(title: w(page.title), detail: w(page.lead)) {
                if let stores {
                    if page.level == TvLevel.view {
                        NoteCard(words: w("tvsReadOnlyHere"), icon: "desktopcomputer")
                    }
                    let module = TvSettingsRules.asModule(file, page, groups, stores, words: TvSettingsData.words)
                    ForEach(Array(groups.enumerated()), id: \.offset) { gi, group in
                        let drawn = module.pages[0].groups[gi]
                        ListGroup(title: drawn.title ?? "", footer: drawn.footer ?? "") {
                            ForEach(Array(group.rows.enumerated()), id: \.offset) { ri, spec in
                                rowView(page, spec, drawn.rows[ri], module, stores)
                            }
                        }
                    }
                    if !said.isEmpty { Secondary(said) }
                } else if problem.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 80)
                }
                if !problem.isEmpty { ProblemLine(problem) }
            }
            .task(id: "\(pageId)|\(admin)") { await load(groups) }
        } else {
            SettingsScreen(title: w("groupServer")) { ProblemLine(w("errLost")) }
        }
    }

    @ViewBuilder private func rowView(_ page: TvSettingsPage, _ spec: TvSettingsRow, _ row: ModuleSettings.Row, _ module: ModuleSettings, _ stores: [String: JSONValue]) -> some View {
        switch spec.kind {
        case "link":
            NavigationLink(value: link(spec, title: row.label)) {
                RowLabel(icon: "chevron.right.circle", tint: "#5d6474", title: row.label, detail: row.help ?? "")
            }
            .rowStyle()
            .accessibilityIdentifier("tvs." + spec.rowKey)
        case "desktopOnly":
            NavigationLink(value: Route.onComputer(spec.to ?? "/settings", title: row.label)) {
                RowLabel(icon: "desktopcomputer", tint: "#5d6474", title: row.label,
                         value: module.values[row.key ?? ""]?.string ?? "",
                         detail: [row.help ?? "", w("tvsOnAComputer")].filter { !$0.isEmpty }.joined(separator: " · "))
            }
            .rowStyle()
            .accessibilityIdentifier("tvs." + spec.rowKey)
        case "list":
            ForEach(Array(TvSettingsRules.items(spec, stores).enumerated()), id: \.offset) { _, item in
                Button {} label: {
                    SettingRow(title: item.0) {
                        Text(item.1).font(.wmSecondary).foregroundStyle(palette.textSecondary)
                    }
                }
                .rowStyle()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.0)
                .accessibilityValue(item.1)
            }
        default:
            // A row a view page only shows needs no note of its own: the page says it at its top.
            let note = TvSettingsRules.level(page, spec) == TvLevel.full || page.level == TvLevel.view ? "" : w("tvsReadOnlyHere")
            ModuleSettingRow(row: row, settings: module, problem: rowProblems[spec.rowKey] ?? "", readOnlyNote: note) { save(spec, $0) }
        }
    }

    private func link(_ spec: TvSettingsRow, title: String) -> Route {
        let to = spec.to ?? ""
        if to == "app:theme" || to == "app:look" { return .theme }
        if to.hasPrefix("tv:") { return .tvSettings(String(to.dropFirst(3))) }
        return .onComputer(to, title: title)
    }
}
#endif
