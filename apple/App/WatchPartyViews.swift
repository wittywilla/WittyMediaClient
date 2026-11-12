// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// Watch parties on screen: starting one from a film's or an episode's page, joining one with its code or from
// the list of invitations, and the room's panel in the player. The server's docs/SYNCPLAY.md has the words;
// the website's is web/src/remote/WatchParty.tsx.

/// A switch in a group of rows. Apple TV has no switch to flick, so there it is a row that says On or Off.
struct TogetherSwitch: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let title: String
    var detail = ""
    let isOn: Bool
    let set: (Bool) -> Void

    var body: some View {
        #if os(tvOS)
        Button { set(!isOn) } label: {
            HStack(spacing: Tokens.Space.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body).foregroundStyle(palette.text)
                    if !detail.isEmpty { Text(detail).font(.wmSecondary).foregroundStyle(palette.textSecondary) }
                }
                Spacer(minLength: Tokens.Space.s2)
                Text(say(isOn ? "on" : "off")).font(.wmSecondary).foregroundStyle(palette.textSecondary)
            }
            .padding(.horizontal, Tokens.Space.s4)
            .frame(minHeight: 72)
            .contentShape(Rectangle())
        }
        .rowStyle()
        .accessibilityValue(say(isOn ? "on" : "off"))
        #else
        Toggle(isOn: Binding(get: { isOn }, set: set)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).foregroundStyle(palette.text)
                if !detail.isEmpty { Text(detail).font(.wmSecondary).foregroundStyle(palette.textSecondary) }
            }
        }
        .tint(palette.accent)
        .padding(.horizontal, Tokens.Space.s4)
        .frame(minHeight: detail.isEmpty ? 52 : 64)
        #endif
    }
}

/// "Watch party" wherever a film or an episode is: a button that opens the party, or the way into one.
struct WatchPartyButton<Label: View>: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var hub: RemoteHub
    let item: Item?
    @ViewBuilder var label: Label
    @State private var shown: Shown?

    private struct Shown: Identifiable { let id = 0 }

    var body: some View {
        if hub.hasParties {
            Button { shown = Shown() } label: { label }
                .accessibilityIdentifier("watch-party")
                .togetherSheet(item: $shown) { _ in
                    TogetherFrame(model: model, close: { shown = nil }) {
                        PartyView(item: item, close: { shown = nil })
                    }
                }
        }
    }
}

/// The room, for someone in one; otherwise starting one and joining one.
struct PartyView: View {
    @EnvironmentObject private var model: AppModel
    let item: Item?
    let close: () -> Void

    var body: some View {
        Switcher(party: model.remote.party, item: item, close: close)
    }

    private struct Switcher: View {
        @ObservedObject var party: PartySession
        let item: Item?
        let close: () -> Void

        var body: some View {
            if let room = party.room {
                PartyRoomView(room: room, item: item, close: close)
            } else {
                PartyStartView(item: item, close: close)
            }
        }
    }
}

// MARK: - Starting and joining

/// The party's code, typed with the keyboard: capitals, spaces and dashes don't matter.
private struct PartyCodeEntry: View {
    @Environment(\.palette) private var palette
    @Binding var code: String
    let length: Int
    var checking = false
    var wrongTries = 0
    let onComplete: (String) -> Void
    @FocusState private var focused: Bool

    private func typed(_ text: String) {
        let cleaned = SyncCode.clean(text, length: length)
        if cleaned != code { code = cleaned }
    }

    var body: some View {
        #if os(tvOS)
        VStack(spacing: Tokens.Space.s5) {
            CodeBoxes(digits: code, count: length, checking: checking, wrongTries: wrongTries)
                .accessibilityLabel("Code")
                .accessibilityValue(code)
                .accessibilityIdentifier("party-code")
            // Letters and numbers under the remote's arrows: quicker than the system's keyboard for six of them.
            Grid(horizontalSpacing: Tokens.Space.s2, verticalSpacing: Tokens.Space.s2) {
                ForEach(SyncCode.padRows, id: \.self) { row in
                    GridRow {
                        ForEach(Array(row), id: \.self) { letter in
                            Button { typed(code + String(letter)) } label: {
                                Text(String(letter)).font(.title3.weight(.semibold)).frame(width: 84, height: 64)
                            }
                            .buttonStyle(CodeKeyStyle())
                            .accessibilityIdentifier("key-\(letter)")
                        }
                    }
                }
            }
            .remoteSection()
            Button { if !code.isEmpty { code.removeLast() } } label: { Label("Delete", systemImage: "delete.left") }
                .action()
                .accessibilityIdentifier("key-delete")
        }
        .frame(maxWidth: .infinity)
        #else
        CodeBoxes(digits: code, count: length, checking: checking, wrongTries: wrongTries)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .background {
                TextField("", text: Binding(get: { code }, set: typed))
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.join)
                    .onSubmit { if code.count == length { onComplete(code) } }
                    .focused($focused)
                    .frame(width: 1, height: 1)
                    .opacity(0.02)
                    .accessibilityLabel("Code")
                    .accessibilityIdentifier("party-code")
            }
        #endif
    }
}

#if os(tvOS)
/// A key of the code pad: with the remote's highlight it fills, as the number pad's keys do.
private struct CodeKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        KeyBody(label: configuration.label, pressed: configuration.isPressed)
    }

    private struct KeyBody<Label: View>: View {
        @Environment(\.palette) private var palette
        @Environment(\.isFocused) private var focused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        let label: Label
        let pressed: Bool

        var body: some View {
            label
                .foregroundStyle(focused ? palette.background : palette.text)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(focused ? palette.text : palette.card))
                .scaleEffect(focused && !reduceMotion ? 1.06 : 1)
                .opacity(pressed ? 0.8 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: Tokens.Motion.focus), value: focused)
        }
    }
}
#endif

struct PartyStartView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let item: Item?
    let close: () -> Void
    @State private var info: SyncInfo?
    @State private var asked = false
    @State private var name = ""
    @State private var everyone = false
    @State private var waitForAll = true
    @State private var wholeSeason = true
    @State private var season: [Int64] = []
    @State private var code = ""
    @State private var busy = ""
    @State private var problem = ""
    @State private var wrong = ""
    @State private var wrongTries = 0

    private var hub: RemoteHub { model.remote }
    private var length: Int { info?.limits.codeLength ?? 6 }

    private func load() async {
        info = await hub.refreshParties()
        asked = true
        // From an episode, the rest of its season can follow it.
        if let item, let show = item.showId, item.isPlayable, let detail = try? await client.show(show) {
            let rest = SyncQueue.restOfSeason(from: item, among: detail.episodes ?? [], limit: info?.limits.queue ?? 200)
            if rest.count > 1 { season = rest }
        }
    }

    private func start() async {
        guard let item else { return }
        busy = "start"
        problem = ""
        defer { busy = "" }
        let items = wholeSeason && season.count > 1 ? season : [item.id]
        do {
            try await hub.party.create(SyncStart(items: items, index: 0, name: name, everyone: everyone, waitForAll: waitForAll, device: hub.party.device))
            close()
        } catch {
            problem = SyncWords.refusal(error)
        }
    }

    private func join(code typed: String? = nil, room: String? = nil) async {
        busy = room ?? "join"
        wrong = ""
        defer { busy = "" }
        do {
            if let room {
                try await hub.party.join(room: room)
            } else {
                try await hub.party.join(code: typed ?? code)
            }
            close()
        } catch {
            wrong = SyncWords.refusal(error)
            wrongTries += 1
        }
    }

    @ViewBuilder private func startPart(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            SectionTitle("Start one for “\(item.title)”")
            Secondary("You get a code to give to the people you want to watch with. It starts paused, so you can wait for them.")
            OutlinedField(label: "A name for it, if you like", text: $name, icon: "person.2")
            ListGroup(title: "") {
                TogetherSwitch(title: "Everyone can play, pause and seek", isOn: everyone) { everyone = $0 }
                TogetherSwitch(title: "Wait for everyone when someone's video stalls", isOn: waitForAll) { waitForAll = $0 }
                if season.count > 1 {
                    TogetherSwitch(title: "Carry on with the rest of the season", detail: "\(season.count) episodes, one after another", isOn: wholeSeason) { wholeSeason = $0 }
                }
            }
            if !problem.isEmpty { ProblemLine(problem) }
            Button { Task { await start() } } label: {
                Label { BusyText("Start a watch party", busy: busy == "start") } icon: { Image(systemName: "person.2.fill") }
            }
            .action(.primary, wide: true, tall: true)
            .disabled(!busy.isEmpty)
            .accessibilityIdentifier("party-start")
        }
    }

    @ViewBuilder private func joinPart(_ info: SyncInfo) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            SectionTitle("Join one")
            Secondary("\(length == 6 ? "Six" : "\(length)") letters and numbers, from whoever started it.")
            PartyCodeEntry(code: $code, length: length, checking: busy == "join", wrongTries: wrongTries) { typed in
                Task { await join(code: typed) }
            }
            if !wrong.isEmpty { ProblemLine(wrong) }
            Button { Task { await join() } } label: { BusyText("Join", busy: busy == "join") }
                .action(item == nil || !info.canCreate ? .primary : .secondary, wide: true, tall: true)
                .disabled(!busy.isEmpty || code.count < length)
                .accessibilityIdentifier("party-join")
            let listed = info.rooms.filter { $0.invited == true || $0.seated }
            if !listed.isEmpty {
                ListGroup(title: "Your watch parties") {
                    ForEach(listed) { room in
                        Button { Task { await join(room: room.id) } } label: {
                            RowLabel(icon: "person.2", tint: "#bd2f85", title: room.name, value: room.seated ? "Go back in" : "Join", detail: room.line)
                        }
                        .rowStyle()
                        .disabled(!busy.isEmpty)
                    }
                }
            }
        }
    }

    var body: some View {
        SettingsScreen(title: "Watch party", detail: "Watch with other people at the same moment, each on your own screen.") {
            if let info {
                if !info.enabled {
                    EmptyState(icon: "person.2.slash", title: "Watch parties are turned off",
                               detail: "An administrator can turn them on under Settings, Sharing & photos.")
                } else {
                    if let item, item.isPlayable, info.canCreate { startPart(item) }
                    joinPart(info)
                }
            } else if asked {
                ProblemLine("The server couldn't be reached.")
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .task { await load() }
    }
}

// MARK: - The room

struct PartyRoomView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let room: SyncRoom
    let item: Item?
    let close: () -> Void
    @State private var problem = ""
    @State private var confirmEnd = false
    @State private var copied = false
    @State private var people: [Profile] = []
    @State private var invited = Set<Int64>()

    private var hub: RemoteHub { model.remote }
    private var party: PartySession { hub.party }

    private func attempt(_ work: @escaping () async throws -> Void) {
        problem = ""
        Task {
            do {
                try await work()
            } catch {
                problem = SyncWords.refusal(error)
            }
        }
    }

    private var codeCard: some View {
        HStack(spacing: Tokens.Space.s4) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CODE").font(.caption.weight(.medium)).foregroundStyle(palette.textSecondary)
                Text(SyncCode.spaced(room.code))
                    .font(.system(size: metrics.tv ? 64 : 34, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.text)
                    .accessibilityLabel("Code \(room.code.map(String.init).joined(separator: " "))")
                    .accessibilityIdentifier("party-code-shown")
            }
            Spacer(minLength: 0)
            if Clipboard.available {
                Button {
                    Clipboard.copy(room.code)
                    copied = true
                    announce("Code copied")
                } label: { Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") }
                    .action()
                    .accessibilityLabel("Copy the code")
            }
        }
        .padding(Tokens.Space.s4)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).fill(palette.panel))
    }

    @ViewBuilder private func person(_ member: SyncMember) -> some View {
        HStack(spacing: Tokens.Space.s3) {
            AvatarTile(name: member.name.isEmpty ? "?" : member.name, size: metrics.tv ? 48 : 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Tokens.Space.s2) {
                    Text(member.name).font(metrics.tv ? .body : .subheadline).foregroundStyle(palette.text).lineLimit(1)
                    if member.you || member.id == room.you { pill("You") }
                    if member.host { pill("Host") }
                }
                Text(SyncWords.member(member.state)).font(.wmSecondary).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: Tokens.Space.s2)
            if room.isHost, member.id != room.you {
                Menu {
                    Button("Make host") { attempt { try await party.makeHost(member.id) } }
                    Button("Remove from the party", role: .destructive) { attempt { try await party.remove(member.id) } }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold)).frame(minWidth: 44, minHeight: 36)
                }
                .action()
                .accessibilityLabel("More for \(member.name)")
            }
        }
        .padding(.horizontal, Tokens.Space.s4)
        .frame(minHeight: metrics.tv ? 76 : 56)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("member-\(member.name)")
    }

    private func pill(_ words: String) -> some View {
        Text(words)
            .font(.caption.weight(.medium))
            .foregroundStyle(palette.text)
            .padding(.horizontal, Tokens.Space.s2)
            .padding(.vertical, 3)
            .background(Capsule().fill(palette.border))
    }

    @ViewBuilder private var queue: some View {
        ListGroup(title: "Queue") {
            ForEach(Array(room.queue.enumerated()), id: \.offset) { place, id in
                let now = place == room.state.index
                let title = room.items.indices.contains(place) ? (room.items[place].title ?? "") : ""
                Button {
                    if !now { attempt { try await party.command("select", index: place) } }
                } label: {
                    HStack(spacing: Tokens.Space.s3) {
                        Text("\(place + 1)").font(.caption.monospacedDigit()).foregroundStyle(palette.textHint).frame(width: 28, alignment: .trailing)
                        Text(id > 0 && !title.isEmpty ? title : "Something you can't watch")
                            .font(metrics.tv ? .body : .subheadline)
                            .foregroundStyle(now ? palette.accentText : palette.text)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if now { Image(systemName: "play.fill").font(.footnote).foregroundStyle(palette.accentText).accessibilityLabel("Playing now") }
                    }
                    .padding(.horizontal, Tokens.Space.s4)
                    .frame(minHeight: metrics.tv ? 64 : 48)
                    .contentShape(Rectangle())
                }
                .rowStyle()
                .disabled(!room.canControl)
            }
        }
    }

    /// The accounts the host may invite by name, when the server lets its profiles be listed.
    @ViewBuilder private var invitations: some View {
        let others = people.filter { person in person.id != model.user?.id && !room.members.contains { $0.userId == person.id } }
        if room.isHost, !others.isEmpty {
            ListGroup(title: "Invite", footer: "They find this party under Watch party, and join it without the code.") {
                ForEach(others) { person in
                    Button {
                        attempt {
                            try await party.invite([person.id])
                            invited.insert(person.id)
                        }
                    } label: {
                        RowLabel(icon: "person.badge.plus", tint: "#0a6fb8", title: ProfileNames.shown(name: person.name, displayName: person.displayName),
                                 value: invited.contains(person.id) ? "Invited" : "Invite", chevron: false)
                    }
                    .rowStyle()
                    .disabled(invited.contains(person.id))
                }
            }
        }
    }

    var body: some View {
        SettingsScreen(title: room.name.isEmpty ? "Watch party" : room.name) {
            codeCard
            if room.blocked {
                Secondary(SyncWords.blocked)
            } else if !room.line.isEmpty {
                Secondary(room.line)
            }
            if !room.blocked {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    if let behind = hub.driftSeconds {
                        Text(abs(behind) < 0.12 ? "In step" : String(format: "%.1f seconds %@, catching up", abs(behind), behind > 0 ? "behind" : "ahead"))
                            .font(.caption).foregroundStyle(palette.textHint)
                            .accessibilityIdentifier("party-step")
                    }
                }
            }
            if !problem.isEmpty { ProblemLine(problem) }
            ListGroup(title: "People") {
                ForEach(room.members) { member in person(member) }
            }
            if room.isHost {
                ListGroup(title: "Host") {
                    TogetherSwitch(title: "Everyone can play, pause and seek", isOn: room.policy == "everyone") { on in
                        attempt { try await party.set(everyone: on) }
                    }
                    TogetherSwitch(title: "Wait for everyone when someone's video stalls", isOn: room.waitForAll) { on in
                        attempt { try await party.set(waitForAll: on) }
                    }
                }
            } else if !room.canControl, !room.blocked {
                Secondary(SyncWords.hostOnly)
            }
            invitations
            if room.queue.count > 1 { queue }
            if let item, item.isPlayable, room.canControl, room.state.itemId != item.id {
                Button {
                    attempt {
                        try await party.command("queue", index: 0, items: [item.id])
                        close()
                    }
                } label: { Label("Watch “\(item.title)” in the party", systemImage: "play.fill") }
                    .action(.secondary, wide: true)
            }
            HStack(spacing: Tokens.Space.s2) {
                Button("Leave") {
                    party.leave()
                    close()
                }
                .action(.secondary, wide: true, tall: true)
                .accessibilityIdentifier("party-leave")
                if room.isHost {
                    Button("End party for everyone") { confirmEnd = true }
                        .action(.destructive, wide: true, tall: true)
                        .accessibilityIdentifier("party-end")
                }
            }
            .remoteSection()
        }
        .confirmationDialog("End the watch party for everyone?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End party", role: .destructive) {
                attempt {
                    try await party.end()
                    close()
                }
            }
        } message: {
            Text("Everyone's player carries on by itself, out of step.")
        }
        .task {
            guard room.isHost else { return }
            people = (try? await client.profiles())?.profiles ?? []
        }
    }
}
