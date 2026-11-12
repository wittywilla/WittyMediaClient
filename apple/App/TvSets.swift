// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
#if os(tvOS)
import SwiftUI
import WittyKit

// What opens over the guide for a server with many channels: choosing a channel set, managing your own sets,
// adding a channel to one, finding a channel by name or going to it by number, and a recording's options. As the
// guide's other sheets (TvSheets.swift), these are in the app's own colours. WittyKit's ChannelSets.swift has the
// rules; every one of these is only offered when the server names its feature (`TvFeature`).

/// This device's own choices for the guide: how many channels a page, and which set, per server and account.
@MainActor
final class GuideDevice: ObservableObject {
    static let shared = GuideDevice()
    private let defaults = UserDefaults.standard

    /// 25, 50, 75, 100, or 0 for all of them in one list.
    @Published var pageSize: Int {
        didSet { defaults.set(pageSize, forKey: GuidePaging.storageKey) }
    }

    private init() {
        pageSize = GuidePaging.size(stored: defaults.object(forKey: GuidePaging.storageKey) as? Int)
    }

    /// The key this server and account's set is kept under.
    static func setKey(model: AppModel, client: WittyClient) -> String {
        let server = model.current.map(\.serverId).flatMap { $0.isEmpty ? nil : $0 } ?? client.base
        return ChannelSetRules.storageKey(server: server, account: model.user?.id)
    }

    func set(for key: String) -> String? { defaults.string(forKey: key) }

    func remember(_ id: String, for key: String) { defaults.set(id, forKey: key) }
}

// MARK: - Choosing a set

/// Every set this profile can show, in the picker's sections. The one on screen is ticked and has focus first.
struct ChannelSetPicker: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let sets: [ChannelSet]
    let chosen: String
    let onPick: (String) -> Void
    /// A set was made, changed, moved or deleted: the guide asks for them again.
    let onChanged: () -> Void
    @State private var managing = false
    @Namespace private var scope

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                Text("Channel sets").font(.wmPage).accessibilityAddTraits(.isHeader)
                Text("Which channels the guide shows, in which order. This TV remembers your choice.")
                    .foregroundStyle(palette.textSecondary)
                ForEach(ChannelSetRules.sections(sets), id: \.title) { section in
                    Text(section.title).font(.wmSection).padding(.top, Tokens.Space.s2).accessibilityAddTraits(.isHeader)
                    LazyVStack(alignment: .leading, spacing: Tokens.Space.s2) {
                        ForEach(section.sets) { set in
                            Button { onPick(set.id) } label: { SetRow(set: set, on: set.id == chosen) }
                                .buttonStyle(SurfaceStyle(fill: palette.card))
                                .firstFocus(in: scope, when: set.id == chosen)
                                .accessibilityAddTraits(set.id == chosen ? [.isSelected] : [])
                        }
                    }
                    .remoteSection()
                }
                HStack(spacing: Tokens.Space.s4) {
                    Button("Manage my sets") { managing = true }.action()
                    Button("Close") { dismiss() }.action(.quiet)
                }
                .remoteSection()
            }
            .padding(.horizontal, Tokens.gutter)
            .padding(.vertical, Tokens.edge)
            .frame(maxWidth: 1300, alignment: .leading)
        }
        .focusRoot(scope)
        .background(palette.background.ignoresSafeArea())
        .sheet(isPresented: $managing) { ChannelSetsManager(onChanged: onChanged) }
    }
}

/// A set's name, how many channels, and whether it's shared or the one on screen.
private struct SetRow: View {
    @Environment(\.palette) private var palette
    let set: ChannelSet
    let on: Bool

    var body: some View {
        HStack(spacing: Tokens.Space.s3) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? palette.accent : palette.textSecondary)
                .accessibilityHidden(true)
            Text(set.name).font(.wmLabel).lineLimit(1)
            if set.shared == true { Text("Shared").font(.wmSecondary).foregroundStyle(palette.textSecondary) }
            Spacer(minLength: Tokens.Space.s4)
            if let count = set.count {
                Text(count == 1 ? "1 channel" : "\(count.formatted()) channels").font(.wmSecondary).foregroundStyle(palette.textSecondary)
            }
        }
        .padding(Tokens.Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Managing sets

/// A custom set being made or changed: its name, whether it's shared, and its channels in order.
@MainActor
final class SetDraft: ObservableObject {
    @Published var id: String?
    @Published var name = ""
    @Published var shared = false
    @Published var channels: [String] = []
    /// Every channel this profile can see, without its schedule, to choose from and to name the ones in the set.
    @Published private(set) var everything: [GuideChannel]?
    @Published var error = ""
    private(set) var byKey: [String: GuideChannel] = [:]

    func start(_ detail: ChannelSetDetail?) {
        id = detail?.id
        name = detail?.name ?? ""
        shared = detail?.shared ?? false
        channels = detail?.channels ?? []
        error = ""
    }

    func loadEverything(client: WittyClient) async {
        guard everything == nil else { return }
        do {
            let all = uniqued(try await client.channelList(limit: 20000).channels ?? [])
            byKey = Dictionary(all.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
            everything = all
        } catch {
            self.error = (error as? APIError)?.message ?? "The channels couldn't be loaded."
        }
    }

    func label(_ key: String) -> String { byKey[key]?.label ?? key }
}

/// Your own sets and the shared ones you see: their order, and making, changing and deleting them. On a TV every
/// change is a button: Move up and Move down rather than dragging.
struct ChannelSetsManager: View {
    enum Page: Hashable { case edit, pick }

    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    /// Something changed, so the guide asks for its sets again.
    let onChanged: () -> Void
    @StateObject private var draft = SetDraft()
    @State private var list: ChannelSetList?
    @State private var error = ""
    @State private var path: [Page] = []
    @State private var deleting: ChannelSet?
    @Namespace private var scope

    private var custom: [ChannelSet] { (list?.sets ?? []).filter(\.isCustom) }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                    Text("My channel sets").font(.wmPage).accessibilityAddTraits(.isHeader)
                    Text("Your own sets are yours alone" + (list?.canShare == true ? ", unless you share one with everyone on this server." : ".")
                         + " The order here is the order in the set picker.")
                        .foregroundStyle(palette.textSecondary)
                    if !error.isEmpty { Text(error).foregroundStyle(palette.danger) }
                    HStack(spacing: Tokens.Space.s4) {
                        Button { edit(nil) } label: { Label("New set", systemImage: "plus") }
                            .action(primary: true).firstFocus(in: scope)
                            .disabled(custom.filter(\.isMine).count >= ChannelSetRules.setLimit)
                        Button("Done") { dismiss() }.action(.quiet)
                    }
                    .remoteSection()
                    if list != nil {
                        if custom.isEmpty {
                            Text("No sets yet. A set is the channels you choose, in the order you choose, such as a few for the children or just the sport.")
                                .foregroundStyle(palette.textSecondary)
                        }
                        LazyVStack(alignment: .leading, spacing: Tokens.Space.s3) {
                            ForEach(Array(custom.enumerated()), id: \.element.id) { i, set in
                                row(set, at: i, of: custom.count)
                            }
                        }
                    } else if error.isEmpty {
                        LoadingView()
                    }
                }
                .padding(.horizontal, Tokens.gutter)
                .padding(.vertical, Tokens.edge)
                .frame(maxWidth: 1400, alignment: .leading)
            }
            .focusRoot(scope)
            .background(palette.background.ignoresSafeArea())
            .navigationDestination(for: Page.self) { page in
                switch page {
                case .edit: ChannelSetEditor(draft: draft, canShare: list?.canShare == true, sets: list?.sets ?? [], onPick: { path.append(.pick) }, onSaved: saved)
                case .pick: ChannelPickerList(draft: draft)
                }
            }
        }
        .task { await load() }
        .alert(item: $deleting) { set in
            Alert(title: Text("Delete “\(set.name)”?"),
                  message: Text(set.shared == true ? "Everyone on this server stops seeing it. The channels themselves stay." : "The channels themselves stay. This can't be undone."),
                  primaryButton: .destructive(Text("Delete set")) { remove(set) }, secondaryButton: .cancel())
        }
    }

    private func row(_ set: ChannelSet, at i: Int, of count: Int) -> some View {
        HStack(spacing: Tokens.Space.s4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(set.name).font(.wmLabel).lineLimit(1)
                Text([set.count.map { $0 == 1 ? "1 channel" : "\($0) channels" }, set.shared == true ? "Shared with everyone" : nil,
                      set.isMine ? nil : "Shared by this server's administrator"].compactMap { $0 }.joined(separator: " · "))
                    .font(.wmSecondary).foregroundStyle(palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if set.canEdit {
                Button("Edit") { Task { await open(set) } }.action()
            }
            Button { move(i, by: -1) } label: { Image(systemName: "chevron.up") }.action().disabled(i == 0)
                .accessibilityLabel("Move \(set.name) up")
            Button { move(i, by: 1) } label: { Image(systemName: "chevron.down") }.action().disabled(i == count - 1)
                .accessibilityLabel("Move \(set.name) down")
            if set.canEdit {
                Button("Delete") { deleting = set }.action(.destructive)
            }
        }
        .padding(Tokens.Space.s3)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.md, style: .continuous).fill(palette.card))
        .remoteSection()
    }

    private func load() async {
        do {
            list = try await client.channelSets()
            error = ""
        } catch {
            self.error = (error as? APIError)?.message ?? "Your sets couldn't be loaded."
        }
    }

    private func edit(_ detail: ChannelSetDetail?) {
        draft.start(detail)
        path.append(.edit)
    }

    private func open(_ set: ChannelSet) async {
        do {
            edit(try await client.channelSet(set.id))
        } catch {
            self.error = (error as? APIError)?.message ?? "That set couldn't be opened."
        }
    }

    private func move(_ i: Int, by step: Int) {
        guard let list else { return }
        let ids = ChannelSetRules.moved(ChannelSetRules.customOrder(list.sets), at: i, by: step)
        self.list = ChannelSetList(sets: ChannelSetRules.reordered(list.sets, ids: ids), canShare: list.canShare)
        Task {
            do {
                try await client.orderChannelSets(ids)
                onChanged()
            } catch {
                self.error = (error as? APIError)?.message ?? "The new order couldn't be kept."
                await load()
            }
        }
    }

    private func remove(_ set: ChannelSet) {
        Task {
            do {
                try await client.deleteChannelSet(set.id)
                await load()
                onChanged()
            } catch {
                self.error = (error as? APIError)?.message ?? "That set couldn't be deleted."
            }
        }
    }

    private func saved() {
        path = []
        Task { await load(); onChanged() }
    }
}

/// One set: its name, whether everyone sees it, and its channels in their order.
struct ChannelSetEditor: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @ObservedObject var draft: SetDraft
    let canShare: Bool
    let sets: [ChannelSet]
    let onPick: () -> Void
    let onSaved: () -> Void
    @State private var saving = false
    @Namespace private var scope

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                Text(draft.id == nil ? "New set" : "Change “\(draft.name)”").font(.wmPage).accessibilityAddTraits(.isHeader)
                TextField("The set's name", text: $draft.name).plainEntry().firstFocus(in: scope, when: draft.id == nil)
                if canShare {
                    Button { draft.shared.toggle() } label: {
                        Label("Share it with everyone on this server", systemImage: draft.shared ? "checkmark.square.fill" : "square")
                    }
                    .action(selected: draft.shared)
                    .accessibilityAddTraits(draft.shared ? [.isSelected] : [])
                }
                if !draft.error.isEmpty { Text(draft.error).foregroundStyle(palette.danger) }
                HStack(spacing: Tokens.Space.s4) {
                    Button(action: save) { Text(saving ? "Saving…" : "Save") }.action(primary: true).disabled(saving)
                    Button { onPick() } label: { Label("Add or remove channels", systemImage: "checklist") }.action()
                        .firstFocus(in: scope, when: draft.id != nil)
                }
                .remoteSection()
                Text(draft.channels.isEmpty ? "No channels in it yet." : draft.channels.count == 1 ? "1 channel, in this order:" : "\(draft.channels.count) channels, in this order:")
                    .font(.wmSection)
                LazyVStack(alignment: .leading, spacing: Tokens.Space.s2) {
                    ForEach(Array(draft.channels.enumerated()), id: \.element) { i, key in
                        HStack(spacing: Tokens.Space.s4) {
                            Text(draft.label(key)).font(.wmLabel).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            Button { draft.channels = ChannelSetRules.moved(draft.channels, at: i, by: -1) } label: { Image(systemName: "chevron.up") }
                                .action().disabled(i == 0).accessibilityLabel("Move \(draft.label(key)) up")
                            Button { draft.channels = ChannelSetRules.moved(draft.channels, at: i, by: 1) } label: { Image(systemName: "chevron.down") }
                                .action().disabled(i == draft.channels.count - 1).accessibilityLabel("Move \(draft.label(key)) down")
                            Button("Remove") { draft.channels = ChannelSetRules.toggled(draft.channels, key) }.action(.quiet)
                                .accessibilityLabel("Remove \(draft.label(key))")
                        }
                        .padding(.horizontal, Tokens.Space.s3)
                        .remoteSection()
                    }
                }
            }
            .padding(.horizontal, Tokens.gutter)
            .padding(.vertical, Tokens.edge)
            .frame(maxWidth: 1400, alignment: .leading)
        }
        .focusRoot(scope)
        .background(palette.background.ignoresSafeArea())
        .task { await draft.loadEverything(client: client) }
    }

    private func save() {
        if let problem = ChannelSetRules.nameProblem(draft.name, among: sets, renaming: draft.id) { draft.error = problem; return }
        if draft.channels.count > ChannelSetRules.channelLimit {
            draft.error = "A set can have \(ChannelSetRules.channelLimit) channels at most."
            return
        }
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        saving = true
        Task {
            defer { saving = false }
            do {
                if let id = draft.id {
                    try await client.updateChannelSet(id, name: name, channels: draft.channels, shared: canShare ? draft.shared : nil)
                } else {
                    _ = try await client.createChannelSet(name: name, channels: draft.channels, shared: canShare && draft.shared)
                }
                draft.error = ""
                onSaved()
            } catch {
                draft.error = (error as? APIError)?.message ?? "The set couldn't be saved."
            }
        }
    }
}

/// Every channel, ticked when it's in the set. Typing narrows the list; a new tick goes at the end of the set.
struct ChannelPickerList: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var draft: SetDraft
    @State private var words = ""

    var body: some View {
        let chosen = Set(draft.channels)
        let shown = (draft.everything ?? []).filter { ChannelSetRules.matches($0, words) }
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                Text("Channels in “\(draft.name.isEmpty ? "the new set" : draft.name)”").font(.wmPage).accessibilityAddTraits(.isHeader)
                HStack(spacing: Tokens.Space.s4) {
                    TextField("A channel's name or number", text: $words).plainEntry()
                    Text("\(draft.channels.count) chosen").foregroundStyle(palette.textSecondary).fixedSize()
                    Button("Done") { dismiss() }.action(primary: true)
                }
                .remoteSection()
                if !draft.error.isEmpty { Text(draft.error).foregroundStyle(palette.danger) }
                if draft.everything == nil, draft.error.isEmpty { LoadingView() }
                if draft.everything != nil, shown.isEmpty { Text("No channels match that.").foregroundStyle(palette.textSecondary) }
                LazyVStack(alignment: .leading, spacing: Tokens.Space.s2) {
                    ForEach(shown) { channel in
                        let on = chosen.contains(channel.key)
                        Button { draft.channels = ChannelSetRules.toggled(draft.channels, channel.key) } label: {
                            HStack(spacing: Tokens.Space.s3) {
                                Image(systemName: on ? "checkmark.square.fill" : "square").foregroundStyle(on ? palette.accent : palette.textSecondary)
                                    .accessibilityHidden(true)
                                Text(channel.label).font(.wmLabel).lineLimit(1)
                                Spacer(minLength: 0)
                                if let group = channel.group, !group.isEmpty { Text(group).font(.wmSecondary).foregroundStyle(palette.textSecondary).lineLimit(1) }
                            }
                            .padding(Tokens.Space.s3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(SurfaceStyle(fill: palette.card))
                        .accessibilityAddTraits(on ? [.isSelected] : [])
                    }
                }
            }
            .padding(.horizontal, Tokens.gutter)
            .padding(.vertical, Tokens.edge)
            .frame(maxWidth: 1400, alignment: .leading)
        }
        .background(palette.background.ignoresSafeArea())
        .task { await draft.loadEverything(client: client) }
    }
}

// MARK: - Add to set

/// "Add to set…" from a channel's details: any set this account may change, or a new one with just this channel.
struct AddToSetSheet: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let channel: GuideChannel
    let onSaid: (String) -> Void
    @State private var list: ChannelSetList?
    @State private var error = ""
    @State private var newName = ""
    @Namespace private var scope

    private var editable: [ChannelSet] { (list?.sets ?? []).filter(\.canEdit) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                Text("Add \(channel.label) to a set").font(.wmPage).accessibilityAddTraits(.isHeader)
                if !error.isEmpty { Text(error).foregroundStyle(palette.danger) }
                if list == nil, error.isEmpty { LoadingView() }
                LazyVStack(alignment: .leading, spacing: Tokens.Space.s2) {
                    ForEach(editable) { set in
                        Button { add(to: set) } label: { SetRow(set: set, on: false) }
                            .buttonStyle(SurfaceStyle(fill: palette.card))
                            .firstFocus(in: scope, when: set.id == editable.first?.id)
                    }
                }
                .remoteSection()
                if list != nil {
                    Text("Or a new set with just this channel").font(.wmSection).padding(.top, Tokens.Space.s2)
                    HStack(spacing: Tokens.Space.s4) {
                        TextField("The new set's name", text: $newName).plainEntry().onSubmit(make)
                        Button("Make the set", action: make).action(primary: editable.isEmpty)
                    }
                    .remoteSection()
                }
                Button("Close") { dismiss() }.action(.quiet)
            }
            .padding(.horizontal, Tokens.gutter)
            .padding(.vertical, Tokens.edge)
            .frame(maxWidth: 1300, alignment: .leading)
        }
        .focusRoot(scope)
        .background(palette.background.ignoresSafeArea())
        .task {
            do { list = try await client.channelSets() } catch { self.error = (error as? APIError)?.message ?? "Your sets couldn't be loaded." }
        }
    }

    private func add(to set: ChannelSet) {
        Task {
            do {
                try await client.changeChannelSet(set.id, add: [channel.key])
                onSaid("\(channel.name) added to \(set.name)")
                dismiss()
            } catch {
                self.error = (error as? APIError)?.message ?? "It couldn't be added."
            }
        }
    }

    private func make() {
        if let problem = ChannelSetRules.nameProblem(newName, among: list?.sets ?? []) { error = problem; return }
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                _ = try await client.createChannelSet(name: name, channels: [channel.key], shared: false)
                onSaid("\(name) made, with \(channel.name) in it")
                dismiss()
            } catch {
                self.error = (error as? APIError)?.message ?? "The set couldn't be made."
            }
        }
    }
}

// MARK: - Finding a channel

/// A channel by its name or the start of its number, in the set on screen: go straight to one, or have the guide
/// show only the channels that match.
struct FindChannelSheet: View {
    @Environment(\.client) private var client
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let set: String
    let current: String
    let onGo: (GuideChannel) -> Void
    let onFilter: (String) -> Void
    @State private var words = ""
    @State private var found: Guide?
    @State private var error = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                Text("Find a channel").font(.wmPage).accessibilityAddTraits(.isHeader)
                TextField("A channel's name or number", text: $words).plainEntry().onSubmit { Task { await search() } }
                HStack(spacing: Tokens.Space.s4) {
                    Button("Show only these in the guide") { onFilter(words.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        .action(primary: true).disabled(words.trimmingCharacters(in: .whitespaces).isEmpty)
                    if !current.isEmpty {
                        Button("Show every channel again") { onFilter("") }.action()
                    }
                    Button("Close") { dismiss() }.action(.quiet)
                }
                .remoteSection()
                if !error.isEmpty { Text(error).foregroundStyle(palette.danger) }
                if let found {
                    let channels = found.channels ?? []
                    if channels.isEmpty { Text("No channel matches that.").foregroundStyle(palette.textSecondary) }
                    if let total = found.total, total > channels.count {
                        Text("The first \(channels.count) of \(total.formatted()):").foregroundStyle(palette.textSecondary)
                    }
                    LazyVStack(alignment: .leading, spacing: Tokens.Space.s2) {
                        ForEach(channels) { channel in
                            Button { onGo(channel) } label: {
                                HStack {
                                    Text(channel.label).font(.wmLabel).lineLimit(1)
                                    Spacer(minLength: 0)
                                    if let group = channel.group, !group.isEmpty { Text(group).font(.wmSecondary).foregroundStyle(palette.textSecondary) }
                                }
                                .padding(Tokens.Space.s3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(SurfaceStyle(fill: palette.card))
                        }
                    }
                }
            }
            .padding(.horizontal, Tokens.gutter)
            .padding(.vertical, Tokens.edge)
            .frame(maxWidth: 1300, alignment: .leading)
        }
        .background(palette.background.ignoresSafeArea())
        .onAppear { words = current }
    }

    private func search() async {
        let q = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { found = nil; return }
        do {
            found = try await client.channelList(set: set == ChannelSetRules.all ? "" : set, q: q, limit: FindChannelSheet.shown)
            error = ""
        } catch {
            self.error = (error as? APIError)?.message ?? "The channels couldn't be searched."
        }
    }

    static let shown = 60
}

/// A channel's number, typed with the remote's keyboard: the guide goes to it.
struct GoToChannelSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let onGo: (String) -> Void
    @State private var typed = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s4) {
            Text("Go to channel").font(.wmPage).accessibilityAddTraits(.isHeader)
            TextField("Channel number", text: $typed).plainEntry().keyboardType(.numbersAndPunctuation)
                .onSubmit(go)
            HStack(spacing: Tokens.Space.s4) {
                Button("Go", action: go).action(primary: true).disabled(LocateRules.number(typed).isEmpty)
                Button("Close") { dismiss() }.action(.quiet)
            }
            .remoteSection()
            Spacer()
        }
        .padding(.horizontal, Tokens.gutter)
        .padding(.vertical, Tokens.edge)
        .frame(maxWidth: 1000, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.background.ignoresSafeArea())
    }

    private func go() {
        let number = LocateRules.number(typed)
        if !number.isEmpty { onGo(number) }
    }
}

// MARK: - Recording options

/// How long before and after to record, and for a series which airings and how many to keep.
struct RecordOptionsSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let title: String
    let series: Bool
    let start: RecordingOptions
    /// Answers what went wrong, or nil when it's done.
    let onSave: (RecordingOptions) async -> String?
    var saveWords = "Record"
    @State private var options = RecordingOptions()
    @State private var error = ""
    @State private var saving = false
    @Namespace private var scope

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s5) {
                Text(series ? "Record every airing of \(title)" : "Record \(title)").font(.wmPage).accessibilityAddTraits(.isHeader)
                pills("Start early", options.padBefore, RecordingOptions.paddings, name: { $0 == 0 ? "On time" : "\($0) min" }) { options.padBefore = $0 }
                pills("Finish late", options.padAfter, RecordingOptions.paddings, name: { $0 == 0 ? "On time" : "\($0) min" }) { options.padAfter = $0 }
                if series {
                    VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                        toggle("New episodes only: skip one this series already recorded", options.newOnly) { options.newOnly.toggle() }
                        toggle("On any channel, not only this one", options.anyChannel) { options.anyChannel.toggle() }
                    }
                    .remoteSection()
                    pills("How many to keep", options.keep, RecordingOptions.keeps, name: { $0 == 0 ? "All" : "The newest \($0)" }) { options.keep = $0 }
                    if options.keep > 0 {
                        Text("Older recordings this series made are deleted by the server once there are more than \(options.keep).")
                            .font(.wmSecondary).foregroundStyle(palette.textSecondary)
                    }
                }
                if !error.isEmpty { Text(error).foregroundStyle(palette.danger) }
                HStack(spacing: Tokens.Space.s4) {
                    Button(action: save) { Text(saving ? "Saving…" : saveWords) }.action(primary: true).disabled(saving).firstFocus(in: scope)
                    Button("Cancel") { dismiss() }.action(.quiet)
                }
                .remoteSection()
            }
            .padding(.horizontal, Tokens.gutter)
            .padding(.vertical, Tokens.edge)
            .frame(maxWidth: 1300, alignment: .leading)
        }
        .focusRoot(scope)
        .background(palette.background.ignoresSafeArea())
        .onAppear { options = start }
    }

    private func pills(_ heading: String, _ value: Int, _ choices: [Int], name: @escaping (Int) -> String, set: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            Text(heading).font(.wmSection)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Tokens.Space.s4) {
                    ForEach(choices, id: \.self) { n in
                        Button(name(n)) { set(n) }.action(selected: value == n, pill: true)
                            .accessibilityAddTraits(value == n ? [.isSelected] : [])
                    }
                }
                .padding(.vertical, Tokens.Space.s6)
                .padding(.horizontal, Tokens.Space.s2)
            }
            .remoteSection()
        }
    }

    private func toggle(_ words: String, _ on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(words, systemImage: on ? "checkmark.square.fill" : "square") }
            .action(selected: on)
            .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private func save() {
        saving = true
        Task {
            let problem = await onSave(options)
            saving = false
            if let problem { error = problem } else { dismiss() }
        }
    }
}
#endif
