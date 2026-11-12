// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// Removing servers a device remembers: the cards under "Used before" (a swipe, the card's menu, Edit),
// the Manage servers screen (from the list of servers, and from You's "On this device"), and the
// "Removed … Undo" line. What a removal takes with it is in ForgetServerModel.swift.
// On Apple TV there is no swipe and no undo: the card's menu and Manage servers ask first.

/// Words about a remembered server.
enum ServerWords {
    /// A sentence from the shared wording with its `{name}`s filled in.
    static func fill(_ key: String, _ values: [String: String]) -> String {
        values.reduce(say(key)) { $0.replacingOccurrences(of: "{\($1.key)}", with: $1.value) }
    }

    static func name(_ server: SavedServer) -> String { server.name.isEmpty ? "WittyMediaServer" : server.name }

    static func address(_ server: SavedServer) -> String { PeerInfo.isPlaceholder(server.url) ? say("awayOnly") : server.url }

    static func names(_ servers: [SavedServer]) -> String { servers.map(name).joined(separator: ", ") }

    static func reached(_ server: SavedServer, now: Int64 = ServerBook.now()) -> String {
        switch ServerBook.lastReached(server.lastSeen, now: now) {
        case .unknown: return say("lastReachedUnknown")
        case .today: return say("lastReachedToday")
        case .yesterday: return say("lastReachedYesterday")
        case .days(let days): return fill("lastReachedDays", ["days": "\(days)"])
        }
    }

    static func removeNamed(_ server: SavedServer) -> String { fill("removeServerNamed", ["name": name(server)]) }

    static func removed(_ servers: [SavedServer]) -> String {
        servers.count == 1 ? fill("removedServer", ["name": name(servers[0])]) : fill("removedCount", ["count": "\(servers.count)"])
    }
}

extension View {
    /// Asks before a server is removed, where there is no undo: Apple TV, and the server in use.
    func confirmRemoval(of server: Binding<SavedServer?>, inUse: @escaping (SavedServer) -> Bool = { _ in false },
                        perform: @escaping (SavedServer) -> Void) -> some View {
        let values = ["name": server.wrappedValue.map(ServerWords.name) ?? "", "address": server.wrappedValue.map(ServerWords.address) ?? ""]
        return confirmationDialog(ServerWords.fill("removeConfirmTitle", values),
                                  isPresented: Binding(get: { server.wrappedValue != nil }, set: { if !$0 { server.wrappedValue = nil } }),
                                  titleVisibility: .visible, presenting: server.wrappedValue) { asked in
            Button(say("remove"), role: .destructive) { perform(asked) }
            Button(say("cancel"), role: .cancel) {}
        } message: { asked in
            Text(ServerWords.fill("removeConfirmBody", values) + (inUse(asked) ? " " + say("removeConfirmInUse") : ""))
        }
    }

    /// "Removed … Undo" along the bottom, on the screens a server can be removed from.
    func serverUndo(lift: CGFloat = 0) -> some View { modifier(ServerUndoBanner(lift: lift)) }
}

// MARK: - Used before

/// The "Used before" section of the list of servers: each card can be removed. The card itself is the
/// caller's, so it keeps the caller's focus and what pressing it does.
struct RememberedServers<Card: View>: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    let servers: [SavedServer]
    /// One has just gone, for focus to move on.
    let removed: (SavedServer) -> Void
    @ViewBuilder let card: (SavedServer) -> Card
    @State private var editing = false
    @State private var asking: SavedServer?

    private func remove(_ server: SavedServer) {
        #if os(tvOS)
        asking = server
        #else
        model.forgetServers([server], undoable: true)
        announce(ServerWords.removed([server]) + " " + say("undo"))
        removed(server)
        #endif
    }

    @ViewBuilder private func row(_ server: SavedServer) -> some View {
        let menu = card(server)
            .contextMenu {
                Button(role: .destructive) { remove(server) } label: { Label(say("removeServer"), systemImage: "trash") }
            }
            // The swipe and the long press, for a screen reader and a switch.
            .accessibilityAction(named: Text(ServerWords.removeNamed(server))) { remove(server) }
        #if os(tvOS)
        menu
        #else
        HStack(spacing: Tokens.Space.s2) {
            if editing {
                Button { remove(server) } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(palette.danger)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ServerWords.removeNamed(server))
                .accessibilityIdentifier("remove." + server.url)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
            menu.modifier(SwipeToRemove(enabled: !editing, label: ServerWords.removeNamed(server)) { remove(server) })
        }
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            HStack(spacing: Tokens.Space.s2) {
                SearchingCaption(words: say("recentServers"))
                Spacer(minLength: 0)
                #if !os(tvOS)
                Button(say(editing ? "editServersDone" : "editServers")) { withAnimation(.easeOut(duration: 0.2)) { editing.toggle() } }
                    .action(.quiet)
                    .accessibilityIdentifier("editServers")
                #endif
            }
            .padding(.top, Tokens.Space.s2)
            ForEach(servers) { row($0) }
        }
        .confirmRemoval(of: $asking) { server in
            model.forgetServers([server])
            announce(ServerWords.removed([server]))
            removed(server)
        }
    }
}

#if !os(tvOS)
/// A card pulled to the left shows Remove behind it; pulled far, it goes. iPhone and iPad.
private struct SwipeToRemove: ViewModifier {
    @Environment(\.palette) private var palette
    let enabled: Bool
    let label: String
    let action: () -> Void
    @State private var offset: CGFloat = 0
    @State private var open = false
    /// A finger is pulling the card sideways. The card's own press must not count when it lifts.
    @State private var pulling = false
    private let width: CGFloat = 80

    private func settle(_ to: CGFloat) {
        withAnimation(.easeOut(duration: 0.18)) {
            offset = to
            open = to != 0
        }
    }

    func body(content: Content) -> some View {
        content
            .disabled(pulling)
            .overlay {
                // Open, a tap on the card closes it again rather than connecting.
                if open { Color.clear.contentShape(Rectangle()).onTapGesture { settle(0) } }
            }
            .offset(x: offset)
            .background(alignment: .trailing) {
                if offset < 0 {
                    Button {
                        settle(0)
                        action()
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).fill(palette.danger))
                    }
                    .buttonStyle(.plain)
                    .frame(width: max(-offset - Tokens.Space.s2, 0))
                    .accessibilityLabel(label)
                }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 16)
                .onChanged { drag in
                    guard enabled, pulling || abs(drag.translation.width) > abs(drag.translation.height) else { return }
                    pulling = true
                    offset = min(0, (open ? -width : 0) + drag.translation.width)
                }
                .onEnded { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { pulling = false }
                    guard enabled else { return }
                    if offset < -width * 2 {
                        settle(0)
                        action()
                    } else {
                        settle(offset < -width / 2 ? -width : 0)
                    }
                })
            .onChange(of: enabled) { on in if !on { settle(0) } }
    }
}
#endif

// MARK: - Removed, Undo

private struct ServerUndoBanner: ViewModifier {
    @ObservedObject private var removals = ServerRemovals.shared
    @Environment(\.palette) private var palette
    @Environment(\.scenePhase) private var phase
    let lift: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let held = removals.held {
                    HStack(spacing: Tokens.Space.s3) {
                        Text(ServerWords.fill("removedServer", ["name": held.name]))
                            .font(.subheadline)
                            .foregroundStyle(palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button(say("undo")) { removals.undo() }
                            .action(.quiet)
                            .accessibilityIdentifier("undoRemove")
                            #if !os(tvOS)
                            .keyboardShortcut("z", modifiers: .command)
                            #endif
                    }
                    .padding(.leading, Tokens.Space.s4)
                    .padding(.trailing, Tokens.Space.s2)
                    .padding(.vertical, Tokens.Space.s1)
                    .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).fill(palette.card))
                    .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                    .frame(maxWidth: 440)
                    .padding(.horizontal, Tokens.Space.s4)
                    .padding(.bottom, Tokens.Space.s4 + lift)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(held.id)
                }
            }
            .animation(.easeOut(duration: 0.2), value: removals.held?.id)
            // Off the screen, or on to another: there is nobody left to press Undo.
            .onChange(of: phase) { now in if now != .active { removals.finish() } }
            .onDisappear { removals.finish() }
    }
}

// MARK: - Manage servers

/// Every server the device remembers, each with Remove, and the two ways to remove several.
struct ManageServersList: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.metrics) private var metrics
    /// The last one went. The list of servers closes this on a TV, where an empty page has nothing to focus.
    var emptied: () -> Void = {}
    @State private var asking: SavedServer?
    @State private var askingAll = false
    @State private var choosing = false
    @State private var old: [SavedServer] = []
    @State private var oldDays = 0
    @State private var said = ""
    @FocusState private var focus: String?

    private var servers: [SavedServer] { uniqued(model.recent) }

    private func forget(_ gone: [SavedServer], undoable: Bool = false) {
        let before = servers
        let next = gone.count == 1 ? ServerBook.focusAfter(removing: gone[0].url, in: before.map(\.url)) : nil
        model.forgetServers(gone, undoable: undoable)
        said = undoable ? "" : ServerWords.removed(gone)
        if undoable { announce(ServerWords.removed(gone) + " " + say("undo")) }
        choosing = false
        if servers.isEmpty {
            emptied()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focus = next ?? servers.first?.url }
        }
    }

    private func remove(_ server: SavedServer) {
        #if os(tvOS)
        asking = server
        #else
        if model.isInUse(server) { asking = server } else { forget([server], undoable: true) }
        #endif
    }

    private func choose(_ days: Int) {
        let found = ServerBook.notReached(for: days, in: servers, now: ServerBook.now())
        if found.isEmpty {
            said = say("removeOldNone")
        } else {
            said = ""
            oldDays = days
            old = found
        }
    }

    private func inUseNote(_ list: [SavedServer]) -> String {
        list.contains(where: model.isInUse) ? " " + say("removeConfirmInUse") : ""
    }

    @ViewBuilder private func row(_ server: SavedServer) -> some View {
        let stale = ServerBook.isStale(server, now: ServerBook.now())
        let mark = model.isInUse(server) ? say("groupThisServer") : stale ? say("staleServer") : ""
        // A TV has the width for one line and a pill. A phone has two lines, the mark leading the second.
        let detail = metrics.tv ? "\(ServerWords.address(server)) · \(ServerWords.reached(server))"
            : ServerWords.address(server) + "\n" + [mark, ServerWords.reached(server)].filter { !$0.isEmpty }.joined(separator: " · ")
        let badge = metrics.tv ? mark : ""
        Button { remove(server) } label: {
            RowLabel(icon: "server.rack", tint: "#0a6fb8", title: ServerWords.name(server), value: say("remove"), detail: detail,
                     badge: badge, chevron: false)
        }
        .rowStyle()
        .focused($focus, equals: server.url)
        .accessibilityLabel(([ServerWords.name(server), detail.replacingOccurrences(of: "\n", with: ", "), badge].filter { !$0.isEmpty }).joined(separator: ", "))
        .accessibilityHint(ServerWords.removeNamed(server))
        .accessibilityIdentifier("server." + server.url)
    }

    var body: some View {
        let all = servers
        Group {
            if all.isEmpty {
                NoteCard(words: say("noServersRemembered"), icon: "server.rack")
            } else {
                ListGroup(title: "") {
                    ForEach(all) { row($0) }
                }
                Button {
                    choosing.toggle()
                    said = ""
                } label: {
                    Label(say("removeOldServers"), systemImage: "clock.arrow.circlepath")
                }
                .action(.secondary, wide: true, tall: true)
                if choosing {
                    ListGroup(title: say("removeOldTitle"), footer: say("removeOldHint")) {
                        ForEach(ServerBook.periods, id: \.self) { days in
                            Button { choose(days) } label: {
                                RowLabel(icon: "calendar", tint: "#5d6474", title: say("staleDays\(days)"), chevron: false)
                            }
                            .rowStyle()
                        }
                    }
                }
                Button { askingAll = true } label: { Label(say("removeAllServers"), systemImage: "trash") }
                    .action(.destructive, wide: true, tall: true)
            }
            if !said.isEmpty { OutcomeLine(words: said).id(said) }
        }
        .confirmRemoval(of: $asking, inUse: model.isInUse) { forget([$0]) }
        .confirmationDialog(say("removeAllTitle"), isPresented: $askingAll, titleVisibility: .visible) {
            Button(say("removeAllServers"), role: .destructive) { forget(all) }
            Button(say("cancel"), role: .cancel) {}
        } message: {
            Text(ServerWords.fill("removeAllBody", ["count": "\(all.count)", "names": ServerWords.names(all)]) + inUseNote(all))
        }
        .confirmationDialog(say("removeOldConfirmTitle"), isPresented: Binding(get: { !old.isEmpty }, set: { if !$0 { old = [] } }),
                            titleVisibility: .visible) {
            Button(say("remove"), role: .destructive) { forget(old) }
            Button(say("cancel"), role: .cancel) {}
        } message: {
            Text(ServerWords.fill("removeOldConfirmBody", ["period": say("staleDays\(oldDays)"), "count": "\(old.count)",
                                                           "names": ServerWords.names(old)]) + inUseNote(old))
        }
    }
}

/// Manage servers, from You: the server in use is in the list too.
struct ManageServersView: View {
    @Environment(\.metrics) private var metrics

    var body: some View {
        SettingsScreen(title: say("manageServers"), detail: say("manageServersHint")) {
            ManageServersList()
        }
        .serverUndo(lift: metrics.tv ? 0 : barRoom(metrics) - Tokens.Space.s4)
    }
}

/// Manage servers, from the list of servers, before anyone is signed in.
struct ManageServersPanel: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let back: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            palette.background.ignoresSafeArea()
            SettingsScreen(title: say("manageServers"), detail: say("manageServersHint")) {
                ManageServersList(emptied: { if metrics.tv { back() } })
            }
            .padding(.top, metrics.tv ? metrics.edge : 60)
            if !metrics.tv { BackButton(action: back).padding(Tokens.Space.s4) }
        }
    }
}
