// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// The layout editor (docs/plans/DESIGN-2.md 7.3 and 7.5, the canvas's LayoutEditor): the shell's regions (the server's name, the
// menu, search, You, the clock, the Dock, the key legend, the spotlight) and the page's sections as dashed cards. Press one to pick
// it up, move it with the arrows (remote, keyboard, or the arrow buttons), press again to drop, Back to cancel. "For me" changes
// this profile's layout on this device (`/sdui/placements`, and the page's `personal`); "For everyone" (administrators) changes the
// experience's layer on the server (`/sdui/config/experience`). Undo, redo, reset, presets. Every move is announced; nothing needs a
// pointer. The rules are WittyKit's LayoutDraft.

struct LayoutEditorView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @Environment(\.dismiss) private var dismiss

    enum Scope: String, CaseIterable { case me = "For me", everyone = "For everyone" }

    @State private var scope = Scope.me
    @State private var draft: LayoutDraft?
    @State private var experience = ""
    @State private var everyone: (whole: [String: JSONValue], etag: String)?
    @State private var picked: String?
    @State private var beforePickup: LayoutDraft?
    @State private var selected = "r:brand"
    @State private var saving = false
    @State private var problem = ""
    @State private var saved = ""
    @State private var confirmReset = false
    @State private var presets: [LayoutPreset] = []
    @State private var presetName = ""
    @State private var importText = ""
    @State private var loading = true

    private var isAdmin: Bool { model.user?.isAdmin == true }
    private var presetsKey: String { "layoutPresets|" + client.base }

    // MARK: Loading and saving

    private func load() async {
        loading = true
        problem = ""
        saved = ""
        picked = nil
        let device = center.device
        do {
            let answer = try await client.layoutPlacements(device: device)
            experience = await client.layoutExperienceName(device: device) ?? answer.experience.capitalized
            var layer = answer.own
            var page: SDUICustomise?
            if scope == .everyone {
                let everyoneNow = try await client.layoutEveryone(experience: answer.experience)
                layer = everyoneNow.layer
                everyone = (everyoneNow.whole, everyoneNow.etag)
            } else if answer.editable, case .new(let document, _, _)? = try? await client.sduiPage("home", params: [:], device: device) {
                let stored = (try? await client.sduiPersonal(page: "home")) ?? SDUIPersonal()
                let edit = SDUICustomise(document: document, stored: stored)
                page = edit.offersAnything ? edit : nil
            }
            guard answer.editable || scope == .everyone else {
                problem = "This profile isn't allowed to rearrange the layout."
                draft = nil
                loading = false
                return
            }
            var inferred = ["brand": "start", "clock": "top", "dock": "bottom"]
            let menu = LayoutDraft.menuPosition(forStyle: center.shell?.nav ?? "")
            inferred["nav"] = menu
            inferred["search"] = menu == "start" ? "nav" : "top"
            inferred["profile"] = menu == "start" ? "nav" : "top"
            draft = LayoutDraft(regions: answer.regions, placements: answer.placements, layer: layer, page: page, inferred: inferred)
            if draft?.region(selectedRegion) == nil { selected = draft.map { "r:" + ($0.regions.first?.id ?? "") } ?? selected }
        } catch {
            problem = model.handle(error).isEmpty ? "The layout couldn't be read." : model.handle(error)
        }
        loading = false
    }

    private func loadPresets() {
        guard let data = UserDefaults.standard.data(forKey: presetsKey), let list = try? JSONDecoder().decode([LayoutPreset].self, from: data) else { return }
        presets = list
    }

    private func keepPresets() {
        if let data = try? JSONEncoder().encode(presets) { UserDefaults.standard.set(data, forKey: presetsKey) }
    }

    private func save() {
        guard let draft, !saving else { return }
        saving = true
        problem = ""
        Task {
            do {
                let device = center.device
                if scope == .me {
                    if draft.layerToSave.isEmpty && !draft.layer.isEmpty {
                        try await client.resetLayoutPlacements(device: device)
                    } else if draft.layerToSave != draft.layer || draft.changed {
                        try await client.saveLayoutPlacements(draft.layerToSave, device: device)
                    }
                    if let page = draft.now.page, page.changed { try await client.setSDUIPersonal(page.personal, page: "home") }
                } else if let everyone {
                    try await client.saveLayoutEveryone(experience: (try await client.layoutPlacements(device: device)).experience, layer: draft.layerToSave,
                                                        whole: everyone.whole, etag: everyone.etag)
                }
                await center.loadMenu()
                center.changed()
                saved = scope == .me ? "Saved for you on this device." : "Saved for everyone."
                announce(saved)
                await load()
            } catch {
                let refused = (error as? APIError)?.status == 403
                problem = refused ? "This profile isn't allowed to rearrange the layout." : (model.handle(error).isEmpty ? "That couldn't be saved." : model.handle(error))
            }
            saving = false
        }
    }

    /// Back to the look's own layout: this profile's changes (or the administrator's) taken away.
    private func reset(everything: Bool) {
        guard !saving else { return }
        saving = true
        Task {
            do {
                let device = center.device
                if scope == .me {
                    try await client.resetLayoutPlacements(device: device)
                    try? await client.resetSDUIPersonal(page: "home")
                    if everything { try? await client.resetSDUIPersonal(page: nil) }
                } else if let everyone {
                    try await client.saveLayoutEveryone(experience: (try await client.layoutPlacements(device: device)).experience, layer: [:], whole: everyone.whole, etag: everyone.etag)
                }
                await center.loadMenu()
                center.changed()
                saved = "Back to \(experience)."
                announce(saved)
                await load()
            } catch {
                problem = model.handle(error).isEmpty ? "That couldn't be reset." : model.handle(error)
            }
            saving = false
        }
    }

    // MARK: Picking up, moving, dropping

    private var selectedRegion: String { selected.hasPrefix("r:") ? String(selected.dropFirst(2)) : "" }
    private var selectedSection: String { selected.hasPrefix("s:") ? String(selected.dropFirst(2)) : "" }

    private func canMove(_ item: String) -> Bool {
        guard let draft else { return false }
        if item.hasPrefix("r:") { return !(draft.region(String(item.dropFirst(2)))?.positions.isEmpty ?? true) }
        return draft.now.page?.canMove(String(item.dropFirst(2))) ?? false
    }

    private func press(_ item: String) {
        if picked == item { drop(); return }
        if picked != nil { drop() }
        selected = item
        guard canMove(item), let draft else {
            announce(title(of: item) + " selected.")
            return
        }
        beforePickup = draft
        picked = item
        announce("\(title(of: item)) picked up. Use the arrow keys to move it, press again to drop, Back to cancel.")
    }

    private func drop() {
        guard let item = picked else { return }
        picked = nil
        beforePickup = nil
        announce(draft.map { item.hasPrefix("r:") ? $0.announcement(String(item.dropFirst(2))) : title(of: item) + " dropped." } ?? "")
    }

    private func cancelPickup() {
        guard let before = beforePickup, let item = picked else { picked = nil; return }
        draft = before
        picked = nil
        beforePickup = nil
        announce("\(title(of: item)) put back.")
    }

    private func step(_ direction: LayoutStep) {
        guard let item = picked, draft != nil else { return }
        if item.hasPrefix("r:") {
            let id = String(item.dropFirst(2))
            guard let target = draft?.target(of: id, direction) else { announce("It can't go that way."); return }
            draft?.move(id, to: target)
            announce(draft?.announcement(id) ?? "")
        } else {
            let id = String(item.dropFirst(2))
            let by = (direction == .up || direction == .left) ? -1 : 1
            guard draft?.now.page?.canMove(id, by: by) == true else { announce("It can't go that way."); return }
            draft?.editPage { $0.move(id, by: by) }
            if let rows = draft?.now.page?.rows, let at = rows.firstIndex(where: { $0.id == id }) {
                announce("\(title(of: item)) moved. Place \(at + 1) of \(rows.count).")
            }
        }
    }

    private func title(of item: String) -> String {
        guard let draft else { return "" }
        if item.hasPrefix("r:") { return draft.region(String(item.dropFirst(2)))?.label ?? "" }
        return draft.now.page?.rows.first { $0.id == String(item.dropFirst(2)) }?.title ?? "Section"
    }

    // MARK: The page

    var body: some View {
        VStack(spacing: 0) {
            header
            if loading {
                LoadingView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let draft {
                editor(draft)
            } else {
                VStack(spacing: Tokens.Space.s4) {
                    if !problem.isEmpty { ProblemLine(problem) }
                    Button { Task { await load() } } label: { Label("Try again", systemImage: "arrow.clockwise") }.action(.secondary, pill: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .pageGround()
        .task {
            loadPresets()
            await load()
        }
        .sduiOnChange(of: scope) { _ in Task { await load() } }
        .onRemoteBack(picked != nil ? { cancelPickup() } : nil)
        .confirmationDialog("Put the layout back to \(experience)?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset to \(experience)", role: .destructive) { reset(everything: false) }
            if scope == .me { Button("Reset everything, menu and pages too", role: .destructive) { reset(everything: true) } }
            Button("Cancel", role: .cancel) {}
        }
        .accessibilityIdentifier("layout.editor")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            HStack(alignment: .center, spacing: Tokens.Space.s4) {
                Text("Edit layout").font(.wm(size: metrics.tv ? 40 : 24, weight: .heavy)).foregroundStyle(palette.text).accessibilityAddTraits(.isHeader)
                if isAdmin {
                    DesignChips {
                        ForEach(Scope.allCases, id: \.self) { s in
                            DesignChip(title: s.rawValue, on: scope == s) { if picked == nil { scope = s } }
                                .accessibilityIdentifier("layout.scope." + (s == .me ? "me" : "everyone"))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            DesignChips {
                DesignChip(title: "Undo", on: false, symbol: "arrow.uturn.backward") { draft?.undoLast() }
                    .disabled(draft?.canUndo != true).accessibilityIdentifier("layout.undo")
                DesignChip(title: "Redo", on: false, symbol: "arrow.uturn.forward") { draft?.redoLast() }
                    .disabled(draft?.canRedo != true).accessibilityIdentifier("layout.redo")
                DesignChip(title: "Reset to \(experience)", on: false, symbol: "arrow.counterclockwise") { confirmReset = true }
                    .accessibilityIdentifier("layout.reset")
                Button { save() } label: { Label(saving ? "Saving…" : (scope == .me ? "Save for me" : "Save for everyone"), systemImage: "checkmark") }
                    .action(primary: true, pill: true)
                    .disabled(saving || draft?.changed != true)
                    .accessibilityIdentifier("layout.save")
            }
            if !saved.isEmpty { Text(saved).font(.wm(size: 14, weight: .semibold)).foregroundStyle(palette.ok) }
            if !problem.isEmpty && draft != nil { ProblemLine(problem) }
        }
        .padding(.horizontal, metrics.tv ? Tokens.gutter : metrics.gutter)
        .padding(.vertical, Tokens.Space.s3)
        .finished(Rectangle(), fill: palette.panel.opacity(0.6), role: .bar)
    }

    @ViewBuilder
    private func editor(_ draft: LayoutDraft) -> some View {
        let wide = metrics.tv || metrics.cardWidth > 124
        ScrollView {
            Group {
                if wide {
                    HStack(alignment: .top, spacing: Tokens.Space.s6) {
                        VStack(alignment: .leading, spacing: Tokens.Space.s4) { map(draft); legend }.frame(maxWidth: .infinity)
                        panel(draft).frame(width: metrics.tv ? 640 : 340)
                    }
                } else {
                    VStack(alignment: .leading, spacing: Tokens.Space.s5) { map(draft); legend; panel(draft) }
                }
            }
            .padding(.horizontal, metrics.tv ? Tokens.gutter : metrics.gutter)
            .padding(.vertical, Tokens.Space.s4)
        }
        .background { shortcuts }
        #if os(tvOS)
        .onMoveCommand { direction in
            guard picked != nil else { return }
            switch direction {
            case .left: step(.left)
            case .right: step(.right)
            case .up: step(.up)
            case .down: step(.down)
            @unknown default: break
            }
        }
        #endif
    }

    /// The arrow keys, Return and Escape of a keyboard, only while something is picked up.
    @ViewBuilder private var shortcuts: some View {
        #if !os(tvOS)
        if picked != nil {
            Group {
                Button("Move left") { step(.left) }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("Move right") { step(.right) }.keyboardShortcut(.rightArrow, modifiers: [])
                Button("Move up") { step(.up) }.keyboardShortcut(.upArrow, modifiers: [])
                Button("Move down") { step(.down) }.keyboardShortcut(.downArrow, modifiers: [])
                Button("Drop") { drop() }.keyboardShortcut(.return, modifiers: [])
                Button("Cancel") { cancelPickup() }.keyboardShortcut(.escape, modifiers: [])
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        #endif
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            HStack(spacing: Tokens.Space.s4) {
                key("OK", picked == nil ? "pick up" : "drop")
                key("▲ ▼ ◀ ▶", "move")
                key("Back", "cancel")
            }
            Text("Moves are announced to screen readers. The arrow buttons in the panel move the selected part too, for a pointer or touch.")
                .font(.wm(size: 13)).foregroundStyle(palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func key(_ keys: String, _ words: String) -> some View {
        HStack(spacing: 8) {
            Text(keys).font(.wm(size: 14, weight: .bold)).padding(.horizontal, 10).frame(minHeight: 32)
                .finished(RoundedRectangle(cornerRadius: Tokens.Radius.sm, style: .continuous), fill: palette.card, role: .chip(on: false))
                .foregroundStyle(palette.text)
            Text(words).font(.wm(size: 14)).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: The map

    private func card(_ item: String, subtitle: String, height: CGFloat = 60) -> some View {
        let isPicked = picked == item, isSelected = selected == item
        let hidden = item.hasPrefix("r:") ? !(draft?.shown(String(item.dropFirst(2))) ?? true) : (draft?.now.page?.rows.first { "s:" + $0.id == item }?.hidden ?? false)
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous)
        return Button { press(item) } label: {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(of: item)).font(.wm(size: metrics.tv ? 24 : 15, weight: .bold)).foregroundStyle(isPicked ? palette.text : palette.accentText)
                    Text(isPicked ? "picked up" : subtitle).font(.wm(size: metrics.tv ? 20 : 12)).foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                if canMove(item) {
                    Image(systemName: isPicked ? "hand.point.up.left.fill" : "square.grid.3x3.fill")
                        .font(.wm(size: 14, weight: .bold))
                        .foregroundStyle(palette.onAccent)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(isPicked ? palette.text : palette.accent))
                        .accessibilityHidden(true)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
            .background(shape.fill(isPicked ? palette.card : palette.accent.opacity(isSelected ? 0.2 : 0.08)))
            .overlay(shape.strokeBorder(isPicked ? palette.text : palette.accent, style: StrokeStyle(lineWidth: isPicked || isSelected ? 3 : 2, dash: isPicked ? [] : [6, 4])))
            .opacity(hidden ? 0.5 : 1)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        #if os(tvOS)
        .disabled(picked != nil && picked != item)
        #endif
        .accessibilityLabel("\(title(of: item)), \(subtitle)\(hidden ? ", hidden" : "")")
        .accessibilityValue(isPicked ? "picked up" : isSelected ? "selected" : "")
        .accessibilityHint(canMove(item) ? (isPicked ? "Press to drop" : "Press to pick up, then move with the arrow keys") : "Press to select")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("layout." + item)
    }

    private func regionCard(_ id: String, height: CGFloat = 60) -> some View {
        guard let draft, let region = draft.region(id) else { return AnyView(EmptyView()) }
        var words = draft.shown(id) ? "" : "hidden"
        if draft.shown(id), let position = draft.position(id), !region.positions.isEmpty { words = LayoutWords.title(position) }
        if draft.shown(id), words.isEmpty { words = draft.style(id).map(LayoutWords.style) ?? "shown" }
        if region.id == "hero", draft.shown(id), let style = draft.style(id) { words = LayoutWords.style(style) }
        return AnyView(card("r:" + id, subtitle: words, height: height))
    }

    private func map(_ draft: LayoutDraft) -> some View {
        let nav = draft.position("nav") ?? "top", dock = draft.position("dock") ?? "bottom"
        let brand = draft.position("brand") ?? "start"
        let columnFirst = nav == "start" || nav == "end"
        func at(_ id: String, _ positions: String...) -> Bool { draft.shown(id) ? positions.contains(draft.position(id) ?? "") : false }
        return VStack(spacing: 10) {
            // The bar across the top: the name, the menu when it is on top, and what the others put there.
            let topItems = [at("brand", "top") ? "brand" : "", nav == "top" ? "nav" : "", at("search", "top") || (nav == "top" && at("search", "nav")) ? "search" : "",
                            at("profile", "top") || (nav == "top" && at("profile", "nav")) ? "profile" : "",
                            at("clock", "top") ? "clock" : "", at("dock", "top") ? "dock" : ""].filter { !$0.isEmpty }
            let brandInBar = (brand == "start" || brand == "center") && !columnFirst
            if !topItems.isEmpty || brandInBar {
                HStack(alignment: .top, spacing: 10) {
                    if brandInBar && brand == "center" { Spacer(minLength: 0) }
                    if brandInBar { regionCard("brand").frame(maxWidth: 220) }
                    if brandInBar && brand == "center" { Spacer(minLength: 0) }
                    ForEach(topItems, id: \.self) { regionCard($0).frame(maxWidth: $0 == "nav" ? .infinity : 200) }
                }
            }
            HStack(alignment: .top, spacing: 10) {
                if columnFirst && nav == "start" { column(draft, brandHere: brand == "start") }
                VStack(spacing: 10) {
                    regionCard("hero", height: 120)
                    if let rows = draft.now.page?.rows {
                        ForEach(rows) { row in card("s:" + row.id, subtitle: sectionWords(row), height: 52) }
                    } else {
                        DesignNote(text: scope == .me ? "This page's sections can't be rearranged by this profile." : "Page sections are arranged for you; choose For me to move them.")
                    }
                    HStack(spacing: 10) {
                        if dock == "bottom" && draft.shown("dock") { regionCard("dock").frame(maxWidth: .infinity) }
                        if draft.shown("legend") { regionCard("legend").frame(maxWidth: 180) }
                        if at("clock", "dock") { regionCard("clock").frame(maxWidth: 140) }
                    }
                    if at("search", "floating") { HStack { Spacer(); regionCard("search").frame(maxWidth: 220) } }
                    if !draft.shown("dock") || !draft.shown("legend") {
                        // Hidden parts stay on the map, so they can be shown again.
                        HStack(spacing: 10) {
                            if !draft.shown("dock") { regionCard("dock") }
                            if !draft.shown("legend") { regionCard("legend") }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                if dock == "side" && draft.shown("dock") { regionCard("dock", height: 120).frame(maxWidth: 140) }
                if columnFirst && nav == "end" { column(draft, brandHere: brand == "start") }
            }
            if nav == "bottom" {
                HStack(alignment: .top, spacing: 10) {
                    regionCard("nav").frame(maxWidth: .infinity)
                    if at("search", "nav") { regionCard("search").frame(maxWidth: 180) }
                    if at("profile", "nav") { regionCard("profile").frame(maxWidth: 140) }
                }
            }
            // Parts that are hidden or have no place on this map yet are listed so each can be reached.
            let shown = Set(["brand", "nav", "hero", "dock", "legend", "clock", "search", "profile"])
            let leftover = draft.regions.map(\.id).filter { id in
                guard shown.contains(id) else { return true }
                return false
            }
            if !leftover.isEmpty {
                HStack(spacing: 10) { ForEach(leftover, id: \.self) { regionCard($0) } }
            }
            let strayed = ["brand", "profile", "search", "clock"].filter { !draft.shown($0) }
            if !strayed.isEmpty {
                HStack(spacing: 10) { ForEach(strayed, id: \.self) { regionCard($0) } }
            }
        }
        .padding(Tokens.Space.s3)
        .finished(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous), fill: palette.panel, role: .card)
        .remoteSection()
    }

    private func column(_ draft: LayoutDraft, brandHere: Bool) -> some View {
        VStack(spacing: 10) {
            if brandHere && draft.shown("brand") { regionCard("brand") }
            regionCard("nav", height: 140)
            if draft.shown("search") && draft.position("search") == "nav" { regionCard("search") }
            if draft.shown("profile") && draft.position("profile") == "nav" { regionCard("profile") }
        }
        .frame(width: metrics.tv ? 200 : 130)
    }

    private func sectionWords(_ row: SDUICustomise.Row) -> String {
        var words: [String] = []
        if row.hidden { words.append("hidden") }
        if row.pinned { words.append("pinned") }
        if row.locked { words.append("always shown") }
        if let size = row.cardSize { words.append(["s": "small cards", "m": "medium cards", "l": "large cards"][size] ?? size) }
        return words.isEmpty ? "Shelf" : words.joined(separator: " · ")
    }

    // MARK: The panel

    private func panel(_ draft: LayoutDraft) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s4) {
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                Text("SELECTED").font(.wm(size: 11, weight: .bold)).tracking(0.8).foregroundStyle(palette.accentText)
                Text(title(of: selected)).font(.wm(size: metrics.tv ? 34 : 22, weight: .heavy)).foregroundStyle(palette.text)
            }
            .accessibilityElement(children: .combine)
            if selected.hasPrefix("r:"), let region = draft.region(selectedRegion) { regionControls(draft, region) } else { sectionControls(draft) }
            moveButtons
            Divider().overlay(palette.border)
            shellControls(draft)
            Divider().overlay(palette.border)
            presetControls(draft)
            Text("Settings and You can't be hidden. Reset puts everything back to the \(experience) look.")
                .font(.wm(size: 12)).foregroundStyle(palette.textSecondary)
        }
        .padding(Tokens.Space.s4)
        .finished(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous), fill: palette.panel, role: .card)
        .remoteSection()
    }

    private func regionControls(_ draft: LayoutDraft, _ region: LayoutRegion) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            DesignRow(title: "Show", value: draft.shown(region.id) ? "On" : "Off", on: draft.shown(region.id), detail: region.locked ? "Always shown" : "",
                      action: region.locked ? nil : { self.draft?.setShown(region.id, !draft.shown(region.id)); announce(self.draft?.announcement(region.id) ?? "") })
                .accessibilityIdentifier("layout.show")
            if !region.positions.isEmpty {
                Text("Where").font(.wm(size: 13, weight: .bold)).foregroundStyle(palette.textSecondary)
                DesignChips {
                    ForEach(region.positions, id: \.self) { position in
                        DesignChip(title: LayoutWords.title(position), on: draft.position(region.id) == position) {
                            self.draft?.move(region.id, to: position)
                            announce(self.draft?.announcement(region.id) ?? "")
                        }
                    }
                }
            }
            if !region.styles.isEmpty {
                Text("Style").font(.wm(size: 13, weight: .bold)).foregroundStyle(palette.textSecondary)
                DesignChips {
                    ForEach(region.styles, id: \.self) { style in
                        DesignChip(title: LayoutWords.style(style), on: draft.style(region.id) == style) { self.draft?.setStyle(region.id, style) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func sectionControls(_ draft: LayoutDraft) -> some View {
        if let page = draft.now.page, let row = page.rows.first(where: { "s:" + $0.id == selected }) {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                DesignRow(title: "Show", value: row.hidden ? "Off" : "On", on: !row.hidden, detail: row.locked ? "Always shown" : "",
                          action: page.canHide && !row.locked ? { self.draft?.editPage { $0.setHidden(row.id, !row.hidden) } } : nil)
                if page.canPin {
                    DesignRow(title: "Pin to top", value: row.pinned ? "On" : "Off", on: row.pinned,
                              action: row.locked ? nil : { self.draft?.editPage { $0.setPinned(row.id, !row.pinned) } })
                }
                if page.canCardSize, row.cardSize != nil {
                    Text("Card size").font(.wm(size: 13, weight: .bold)).foregroundStyle(palette.textSecondary)
                    DesignChips {
                        ForEach(SDUICustomise.cardSizes, id: \.self) { size in
                            DesignChip(title: ["s": "Small", "m": "Medium", "l": "Large"][size] ?? size, on: row.cardSize == size) { self.draft?.editPage { $0.setCardSize(row.id, size) } }
                        }
                    }
                }
                if page.canDensity {
                    Text("Density").font(.wm(size: 13, weight: .bold)).foregroundStyle(palette.textSecondary)
                    DesignChips {
                        ForEach(SDUICustomise.densities, id: \.self) { value in
                            DesignChip(title: value.capitalized, on: page.density == value) { self.draft?.editPage { $0.setDensity(value) } }
                        }
                    }
                }
            }
        }
    }

    private var moveButtons: some View {
        let id = selected
        return VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text("Move").font(.wm(size: 13, weight: .bold)).foregroundStyle(palette.textSecondary)
            HStack(spacing: 8) {
                let moves: [(String, LayoutStep, String)] = [("chevron.left", .left, "left"), ("chevron.up", .up, "up"), ("chevron.down", .down, "down"), ("chevron.right", .right, "right")]
                ForEach(moves, id: \.2) { symbol, direction, name in
                    Button { nudge(id, direction) } label: { Image(systemName: symbol).frame(width: 44, height: 44) }
                        .action(.secondary)
                        .disabled(!canMove(id))
                        .accessibilityLabel("Move \(name)")
                        .accessibilityIdentifier("layout.move." + name)
                }
            }
            .remoteSection()
        }
    }

    /// A step from the arrow buttons: it picks the selected part up for one move and puts it down.
    private func nudge(_ item: String, _ direction: LayoutStep) {
        guard canMove(item) else { return }
        let was = picked
        picked = item
        step(direction)
        picked = was
    }

    private func shellControls(_ draft: LayoutDraft) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text("SHELL").font(.wm(size: 11, weight: .bold)).tracking(0.8).foregroundStyle(palette.accentText)
            ForEach(["nav", "search", "dock"], id: \.self) { id in
                if let region = draft.region(id), draft.shown(id) {
                    DesignRow(title: region.label, value: draft.position(id).map(LayoutWords.title) ?? "") { selected = "r:" + id }
                }
            }
            if isAdmin {
                NavigationLink(value: Route.brandEditor) {
                    HStack { Text("Server name").font(.wm(size: 15, weight: .bold)); Spacer(); Text("Edit name…").font(.wm(size: 14, weight: .bold)).foregroundStyle(palette.accentText) }
                        .frame(minHeight: 44)
                }
                .buttonStyle(DesignRowButton())
                .accessibilityIdentifier("layout.editName")
            }
        }
    }

    private func presetControls(_ draft: LayoutDraft) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text("PRESETS").font(.wm(size: 11, weight: .bold)).tracking(0.8).foregroundStyle(palette.accentText)
            ForEach(presets) { preset in
                HStack {
                    DesignChip(title: preset.name, on: false, symbol: "rectangle.3.group") {
                        self.draft?.apply(preset)
                        announce("\(preset.name) applied.")
                    }
                    #if !os(tvOS)
                    if let text = try? preset.exported() {
                        ShareLink(item: text, subject: Text(preset.name)) { Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44) }
                            .accessibilityLabel("Share \(preset.name)")
                    }
                    #endif
                    Button { presets.removeAll { $0.name == preset.name }; keepPresets() } label: { Image(systemName: "trash").frame(width: 44, height: 44) }
                        .buttonStyle(.plain).foregroundStyle(palette.danger).accessibilityLabel("Delete \(preset.name)")
                }
            }
            OutlinedField(label: "Name this layout", text: $presetName, kind: .text)
            Button {
                let name = presetName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { problem = "Give the preset a name."; return }
                presets.removeAll { $0.name == name }
                presets.append(draft.preset(named: name))
                keepPresets()
                presetName = ""
                announce("\(name) kept.")
            } label: { Label("Keep as a preset", systemImage: "plus") }
                .action(.secondary, pill: true)
                .accessibilityIdentifier("layout.preset.keep")
            OutlinedField(label: "Paste a preset to import", text: $importText, kind: .text, onSubmit: { importPreset() })
            if !importText.isEmpty {
                Button { importPreset() } label: { Label("Import", systemImage: "square.and.arrow.down") }.action(.secondary, pill: true)
            }
        }
    }

    private func importPreset() {
        guard let draft else { return }
        do {
            let preset = try LayoutPreset.imported(importText, regions: draft.regions)
            presets.removeAll { $0.name == preset.name }
            presets.append(preset)
            keepPresets()
            importText = ""
            problem = ""
            announce("\(preset.name) imported.")
        } catch {
            problem = (error as? APIError)?.message ?? "That isn't a layout preset."
        }
    }
}
