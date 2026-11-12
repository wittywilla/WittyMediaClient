// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// You → Profiles and parental limits: the profiles this account manages, what each may see and do, its
// screen time, what a parent can look back on, and the parents' PIN (the server's docs/PROFILES.md). An
// administrator manages everyone; an adult manages Kids profiles where the administrator allows it. These
// pages are only the form: the server applies every limit, on every route. Limits are saved through
// `Access.changes(from:)`, so only what was changed here is sent and anything newer than this app stays.

/// The profiles being looked after, and the changes to their limits not yet saved. One for the signed-in
/// person, shared by every page here so a change made on one is still there on the next.
@MainActor
final class ProfileDesk: ObservableObject {
    /// Nil until the server has answered.
    @Published private(set) var users: [ManagedUser]?
    @Published private(set) var drafts: [Int64: Access] = [:]
    @Published private(set) var lists: ParentalLists?
    @Published private(set) var libraries: [Library] = []
    @Published private(set) var genres: [String] = []
    @Published private(set) var collections: [TitleCollection] = []
    @Published var problem = ""

    func forget() {
        users = nil
        drafts = [:]
        lists = nil
        libraries = []
        genres = []
        collections = []
        problem = ""
    }

    func load(_ client: WittyClient, household: Household) async {
        do {
            users = try await client.managedUsers()
            problem = ""
        } catch {
            if Problem.of(error) != .cancelled { problem = plainWords(Problem.of(error)) }
        }
        if lists == nil { lists = await household.lists() }
    }

    /// What the limits pages choose from. Asked for when one of them opens, not with the list of profiles.
    func loadChoices(_ client: WittyClient) async {
        async let libs = try? client.libraries()
        async let all = try? client.allGenres()
        async let made = try? client.collections()
        let (l, g, c) = await (libs, all, made)
        if let l { libraries = l }
        if let g { genres = g }
        // Only a collection that lists its titles can be a limit: one made from a rule holds whatever matches today.
        if let c { collections = c.filter { $0.kind == "manual" && ($0.system ?? "").isEmpty } }
    }

    func user(_ id: Int64) -> ManagedUser? { users?.first { $0.id == id } }

    private func saved(_ id: Int64) -> Access { user(id)?.access ?? Access() }

    /// The limits as they are being edited.
    func draft(_ id: Int64) -> Access { drafts[id] ?? saved(id) }

    func edit(_ id: Int64, _ change: (inout Access) -> Void) {
        var next = draft(id)
        change(&next)
        drafts[id] = next == saved(id) ? nil : next
    }

    func hasChanges(_ id: Int64) -> Bool { drafts[id] != nil }

    func discard(_ id: Int64) { drafts[id] = nil }

    /// Sends what changed. Answers the server's words when it refuses.
    func save(_ id: Int64, client: WittyClient) async -> String? {
        guard let draft = drafts[id] else { return nil }
        if let wrong = draft.time?.problem { return wrong }
        do {
            let fresh = try await client.saveAccess(userId: id, changes: draft.changes(from: saved(id)))
            replace(fresh)
            drafts[id] = nil
            return nil
        } catch {
            return plainWords(Problem.of(error))
        }
    }

    func replace(_ fresh: ManagedUser) {
        users = users?.map { $0.id == fresh.id ? fresh : $0 }
    }
}

// MARK: - Rows

/// A row with no icon: its words, a second line, and whatever it's set to at the end. The same height, hairline
/// and focus as the icon rows in SettingsKit.
struct SettingRow<Trailing: View>: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @Environment(\.displayScale) private var displayScale
    let title: String
    var detail = ""
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Tokens.Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(metrics.tv ? .body : .subheadline).foregroundStyle(palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                if !detail.isEmpty {
                    Text(detail).font(.wmSecondary).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Tokens.Space.s2)
            trailing
        }
        .padding(.horizontal, Tokens.Space.s4)
        .padding(.vertical, Tokens.Space.s2)
        .frame(minHeight: metrics.tv ? 72 : 52)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.border).frame(height: 1 / max(displayScale, 1)).padding(.leading, Tokens.Space.s4).accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}

/// On or off, changed by pressing the row: a finger and a remote both can.
struct SwitchRow: View {
    @Environment(\.palette) private var palette
    let title: String
    var detail = ""
    let isOn: Bool
    var fixed = false
    let flip: () -> Void

    var body: some View {
        Button(action: flip) {
            SettingRow(title: title, detail: detail) {
                Capsule()
                    .fill(isOn ? palette.accent : palette.border)
                    .frame(width: 46, height: 28)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle().fill(isOn ? palette.onAccent : palette.textSecondary).frame(width: 22, height: 22).padding(3)
                    }
                    .animation(.easeOut(duration: Tokens.Motion.press), value: isOn)
                    .accessibilityHidden(true)
            }
        }
        .rowStyle()
        .disabled(fixed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(detail.isEmpty ? title : "\(title). \(detail)")
        .accessibilityValue(say(isOn ? "on" : "off"))
        .accessibilityAddTraits(.isButton)
    }
}

/// One of a set: the chosen one has the tick.
struct SettingChoiceRow: View {
    @Environment(\.palette) private var palette
    let title: String
    var detail = ""
    let chosen: Bool
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            SettingRow(title: title, detail: detail) {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.accentText)
                    .opacity(chosen ? 1 : 0)
                    .accessibilityHidden(true)
            }
        }
        .rowStyle()
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
    }
}

/// A row that opens a page, with what it's set to beside the chevron.
private struct LinkRow: View {
    @Environment(\.palette) private var palette
    let title: String
    var detail = ""
    var value = ""
    let to: FamilyRoute

    var body: some View {
        NavigationLink(value: Route.family(to)) {
            SettingRow(title: title, detail: detail) {
                if !value.isEmpty { Text(value).font(.wmSecondary).foregroundStyle(palette.textSecondary).lineLimit(1) }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(palette.textHint).accessibilityHidden(true)
            }
        }
        .rowStyle()
    }
}

/// A value stepped down and up with two buttons, which is how a remote sets a time or a length of time.
private struct StepRow: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let title: String
    var detail = ""
    let value: String
    let less: (() -> Void)?
    let more: (() -> Void)?

    @ViewBuilder private func button(_ symbol: String, _ label: String, _ act: (() -> Void)?) -> some View {
        if metrics.tv {
            Button { act?() } label: {
                Image(systemName: symbol).font(.body.weight(.semibold)).frame(width: 56, height: 56)
            }
            .action(.secondary, pill: true)
            .disabled(act == nil)
            .accessibilityLabel("\(label): \(title)")
        } else {
            // A round button no wider than the thumb that presses it, so the row's words keep their room.
            Button { act?() } label: {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(act == nil ? palette.textHint : palette.text)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(palette.card))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(act == nil)
            .accessibilityLabel("\(label): \(title)")
        }
    }

    var body: some View {
        SettingRow(title: title, detail: detail) {
            HStack(spacing: metrics.tv ? Tokens.Space.s2 : 0) {
                button("minus", "Less", less)
                Text(value)
                    .font(.wmLabel.weight(.semibold))
                    .foregroundStyle(palette.text)
                    .frame(minWidth: metrics.tv ? 150 : 64)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityLabel("\(title): \(value)")
                button("plus", "More", more)
            }
        }
    }
}

/// Unsaved changes to a profile's limits, on every page that can make them.
private struct SaveBar: View {
    @EnvironmentObject private var desk: ProfileDesk
    @Environment(\.client) private var client
    let id: Int64
    @State private var busy = false
    @State private var problem = ""
    @State private var saved = false

    var body: some View {
        let changed = desk.hasChanges(id)
        let wrong = desk.draft(id).time?.problem ?? ""
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            if !wrong.isEmpty { ProblemLine(wrong) } else if !problem.isEmpty { ProblemLine(problem) }
            if saved && !changed { OutcomeLine(words: "Limits saved.") }
            if changed {
                Button {
                    busy = true
                    problem = ""
                    Task {
                        problem = await desk.save(id, client: client) ?? ""
                        saved = problem.isEmpty
                        busy = false
                    }
                } label: { BusyText(say("save"), busy: busy) }
                    .action(.primary, wide: true, tall: true)
                    .disabled(busy || !wrong.isEmpty)
                    .accessibilityIdentifier("limits-save")
                Button("Undo these changes") {
                    desk.discard(id)
                    problem = ""
                }
                .action(.quiet)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - The profiles

struct ProfilesView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var desk: ProfileDesk
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @Environment(\.client) private var client
    @State private var pinSet: Bool?

    private func row(_ user: ManagedUser) -> some View {
        let mine = user.id == model.user?.id
        let detail = mine ? "\(user.role) · you" : (user.canBeLimited(by: model.user?.id) ? "\(user.role) · \(LimitWords.summary(user.access))" : user.role)
        return NavigationLink(value: Route.family(.profile(user.id))) {
            HStack(spacing: Tokens.Space.s3) {
                AvatarTile(name: user.shownName, size: metrics.tv ? 48 : 36, picture: user.avatar)
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.shownName).font(metrics.tv ? .body : .subheadline).foregroundStyle(palette.text).lineLimit(1)
                    Text(detail).font(.wmSecondary).foregroundStyle(palette.textSecondary).lineLimit(2)
                }
                Spacer(minLength: Tokens.Space.s2)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(palette.textHint).accessibilityHidden(true)
            }
            .padding(.horizontal, Tokens.Space.s4)
            .padding(.vertical, Tokens.Space.s2)
            .frame(minHeight: metrics.tv ? 80 : 60)
            .contentShape(Rectangle())
        }
        .rowStyle()
        .accessibilityIdentifier("profile-\(user.name)")
    }

    var body: some View {
        let admin = model.user?.isAdmin == true
        SettingsScreen(title: say("rowProfiles"),
                       detail: admin ? "Everyone on this server. Limits are applied by the server, in every app."
                                     : "The Kids profiles you look after. Limits are applied by the server, in every app.") {
            if let users = desk.users {
                if users.isEmpty {
                    Secondary("There are no profiles here for you to manage yet. If adding one is refused, the administrator keeps that to themselves.")
                } else {
                    ListGroup(title: "") {
                        ForEach(users) { row($0) }
                    }
                }
                ListGroup(title: "") {
                    NavigationLink(value: Route.family(.addProfile)) {
                        RowLabel(icon: "plus", tint: "#2e7d3c", title: "Add a profile")
                    }
                    .rowStyle()
                    .accessibilityIdentifier("profile-add")
                    if admin {
                        NavigationLink(value: Route.family(.parentPin)) {
                            RowLabel(icon: "lock.rectangle", tint: "#3e5bd0", title: "Parents’ PIN", value: pinSet.map { $0 ? "Set" : "Not set" } ?? "")
                        }
                        .rowStyle()
                        .accessibilityIdentifier("parents-pin")
                    }
                }
            } else if desk.problem.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            }
            if !desk.problem.isEmpty { ProblemLine(desk.problem) }
        }
        .task {
            await desk.load(client, household: model.household)
            if admin { pinSet = try? await client.parentPinIsSet() }
        }
        #if os(iOS)
        .refreshable { await desk.load(client, household: model.household) }
        #endif
    }
}

struct ManagedProfileView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var desk: ProfileDesk
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @Environment(\.client) private var client
    @Environment(\.dismiss) private var dismiss
    let id: Int64
    @State private var confirmRemove = false
    @State private var problem = ""
    @State private var busy = false

    private func remove(_ user: ManagedUser) {
        guard !busy else { return }
        busy = true
        Task {
            do {
                try await client.removeProfile(user.id)
                await desk.load(client, household: model.household)
                dismiss()
            } catch {
                problem = model.handle(error)
            }
            busy = false
        }
    }

    private func timeSummary(_ access: Access) -> String {
        guard let time = access.time, !time.isEmpty else { return "No limit" }
        if time.schoolDayMinutes > 0 { return TimeRules.allowanceLabel(time.schoolDayMinutes) }
        if time.weekendMinutes > 0 { return TimeRules.allowanceLabel(time.weekendMinutes) }
        return "Set hours"
    }

    var body: some View {
        let user = desk.user(id)
        let access = desk.draft(id)
        SettingsScreen(title: user?.shownName ?? "") {
            if let user {
                HStack(spacing: Tokens.Space.s4) {
                    AvatarTile(name: user.shownName, size: metrics.tv ? 120 : 72, picture: user.avatar)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("@\(user.name)").font(.wmLabel).foregroundStyle(palette.textSecondary)
                        Text(user.role).font(.wmSecondary).foregroundStyle(palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                ListGroup(title: "") {
                    LinkRow(title: "Name and picture", to: .look(id))
                    if user.canBeLimited(by: model.user?.id) {
                        LinkRow(title: user.isAdult ? "Password" : "Password or PIN", value: user.hasPassword == true ? "Set" : "None", to: .secret(id))
                    }
                }
                if user.canBeLimited(by: model.user?.id) {
                    ListGroup(title: "Limits") {
                        LinkRow(title: "What they see", value: LimitWords.ageLabel(access.maxAge), to: .limits(id, .see))
                        LinkRow(title: "What they can do", value: access.off.isEmpty ? "Everything" : "\(access.off.count) off", to: .limits(id, .allowed))
                        LinkRow(title: "Screen time", value: timeSummary(access), to: .limits(id, .time))
                    }
                    SaveBar(id: id)
                    ListGroup(title: "", footer: "What they watched and when, and what was refused. Kept only for profiles with limits.") {
                        LinkRow(title: "Report", to: .report(id))
                    }
                    if !problem.isEmpty { ProblemLine(problem) }
                    Button { confirmRemove = true } label: { Label("Remove profile", systemImage: "trash") }
                        .action(.destructive, wide: true, tall: true)
                        .disabled(busy)
                }
            } else if desk.users == nil {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Secondary("That profile is no longer here.")
            }
        }
        .task { if desk.users == nil { await desk.load(client, household: model.household) } }
        .confirmationDialog("Remove “\(user?.shownName ?? "")”? Their watch history is deleted too. This can’t be undone.",
                            isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove profile", role: .destructive) { if let user { remove(user) } }
        }
    }
}

// MARK: - Limits

struct ProfileLimitsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var desk: ProfileDesk
    @Environment(\.client) private var client
    let id: Int64
    let page: LimitsPage
    @State private var tags = ""

    private var access: Access { desk.draft(id) }
    private var name: String { desk.user(id)?.shownName ?? "" }

    private func toggle(_ list: WritableKeyPath<Access, [String]>, _ word: String) {
        desk.edit(id) { a in
            if a[keyPath: list].contains(word) { a[keyPath: list].removeAll { $0 == word } } else { a[keyPath: list].append(word) }
        }
    }

    // What they see

    /// The levels to choose from. An age set somewhere else that isn't one of them keeps its place among them.
    private var ageLevels: [(age: Int, label: String, hint: String)] {
        var levels = LimitWords.ageLevels
        let now = access.maxAge
        if !levels.contains(where: { $0.age == now }) {
            levels.append((age: now, label: LimitWords.ageLabel(now), hint: "set on the website"))
            levels.sort { ($0.age < 0 ? 99 : $0.age) < ($1.age < 0 ? 99 : $1.age) }
        }
        return levels
    }

    @ViewBuilder private var see: some View {
        let a = access
        let levels = ageLevels
        ListGroup(title: "What may they watch?") {
            ForEach(levels, id: \.age) { level in
                SettingChoiceRow(title: level.label, detail: level.hint, chosen: a.maxAge == level.age) { desk.edit(id) { $0.maxAge = level.age } }
                    .accessibilityIdentifier("age-\(level.age)")
            }
        }
        if a.maxAge >= 0 {
            ListGroup(title: "", footer: "Home videos and unmatched files have no rating. They stay hidden under an age limit unless this is on.") {
                SwitchRow(title: "Also show titles without a rating", isOn: a.allowUnrated) { desk.edit(id) { $0.allowUnrated.toggle() } }
            }
        }
        ListGroup(title: "") {
            LinkRow(title: "A different age for some kinds", detail: "Films, TV shows, games, music or books.",
                    value: a.kinds.isEmpty ? "" : "\(a.kinds.count)", to: .limits(id, .kinds))
            LinkRow(title: "Hide genres", value: a.blockGenres.isEmpty ? "" : "\(a.blockGenres.count)", to: .limits(id, .hideGenres))
            LinkRow(title: "Show only these genres", value: a.onlyGenres.isEmpty ? "" : "\(a.onlyGenres.count)", to: .limits(id, .onlyGenres))
            LinkRow(title: "Collections", detail: "Always or never allow everything in a collection.",
                    value: (a.allowCollections.count + a.blockCollections.count) == 0 ? "" : "\(a.allowCollections.count + a.blockCollections.count)",
                    to: .limits(id, .collections))
        }
        if !desk.libraries.isEmpty {
            ListGroup(title: "Libraries", footer: "Only the libraries turned on. Leave them all off for every library.") {
                ForEach(desk.libraries) { library in
                    SwitchRow(title: library.name, isOn: a.libraries.contains(library.id)) {
                        desk.edit(id) { access in
                            if access.libraries.contains(library.id) { access.libraries.removeAll { $0 == library.id } } else { access.libraries.append(library.id) }
                        }
                    }
                }
            }
        }
        ListGroup(title: "Live TV") {
            SwitchRow(title: "Live TV", isOn: a.liveTv) { desk.edit(id) { $0.liveTv.toggle() } }
            SwitchRow(title: "Channels made from this server’s libraries", isOn: a.liveTv && a.libraryChannels, fixed: !a.liveTv) {
                desk.edit(id) { $0.libraryChannels.toggle() }
            }
            SwitchRow(title: "Antenna, cable and internet TV channels", detail: "Tuners and IPTV.", isOn: a.liveTv && a.tunerChannels, fixed: !a.liveTv) {
                desk.edit(id) { $0.tunerChannels.toggle() }
            }
        }
        VStack(alignment: .leading, spacing: Tokens.Space.s2) {
            OutlinedField(label: "Hide videos with these tags", text: $tags, icon: "tag") {
                desk.edit(id) { $0.blockTags = Access.tags(from: tags) }
            }
            Secondary("For video libraries whose videos have tags. Commas between them.")
        }
        .whenChanged(tags) { typed in
            let next = Access.tags(from: typed)
            if next != access.blockTags { desk.edit(id) { $0.blockTags = next } }
        }
    }

    @ViewBuilder private var kinds: some View {
        let a = access
        let systems = desk.lists?.systems ?? []
        Secondary("A kind left alone follows the age limit for everything else.")
        ForEach(desk.lists?.kinds ?? ["film", "tv", "game", "music", "book"], id: \.self) { kind in
            let mine = a.kinds[kind]
            ListGroup(title: LimitWords.kindLabel(kind)) {
                SettingChoiceRow(title: "The same as everything else", chosen: mine == nil) { desk.edit(id) { $0.kinds[kind] = nil } }
                ForEach(LimitWords.ages(for: kind, in: systems, including: mine?.maxAge), id: \.self) { age in
                    SettingChoiceRow(title: LimitWords.ageChoice(age, kind: kind, in: systems), chosen: mine?.maxAge == age) {
                        desk.edit(id) { $0.kinds[kind] = KindLimit(maxAge: age, allowUnrated: mine?.allowUnrated ?? a.allowUnrated) }
                    }
                }
                SettingChoiceRow(title: "No age limit", chosen: mine?.maxAge == -1) {
                    desk.edit(id) { $0.kinds[kind] = KindLimit(maxAge: -1, allowUnrated: mine?.allowUnrated ?? a.allowUnrated) }
                }
                if let mine, mine.maxAge >= 0 {
                    SwitchRow(title: "Also those with no rating", isOn: mine.allowUnrated) {
                        desk.edit(id) { $0.kinds[kind] = KindLimit(maxAge: mine.maxAge, allowUnrated: !mine.allowUnrated) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func genres(_ list: WritableKeyPath<Access, [String]>, hint: String) -> some View {
        let chosen = access[keyPath: list]
        // One that was chosen and is no longer in any library can still be taken off.
        let all = desk.genres + chosen.filter { !desk.genres.contains($0) }
        Secondary(hint)
        if all.isEmpty {
            Secondary("This server’s films and shows have no genres yet.")
        } else {
            ListGroup(title: "") {
                ForEach(all, id: \.self) { genre in
                    SwitchRow(title: genre, isOn: chosen.contains(genre)) { toggle(list, genre) }
                }
            }
        }
    }

    @ViewBuilder private var collections: some View {
        let a = access
        Secondary("Never allow wins. Then always allow. Then everything else has to pass the age, the library and the genres.")
        if desk.collections.isEmpty {
            Secondary("There are no collections yet. Make one under Collections, add titles to it, and it can be allowed or hidden here as a whole.")
        } else {
            ListGroup(title: "", footer: "Press a collection to change how its titles are treated.") {
                ForEach(desk.collections) { collection in
                    let rule = a.rule(forCollection: collection.id)
                    let count = collection.count ?? 0
                    Button {
                        // By their rating, then always, then never, and round again.
                        desk.edit(id) { $0.setRule(rule.isEmpty ? "allow" : (rule == "allow" ? "block" : ""), forCollection: collection.id) }
                    } label: {
                        SettingRow(title: collection.name, detail: count == 1 ? "1 title" : "\(count) titles") {
                            Text(rule == "allow" ? "Always allow" : (rule == "block" ? "Never allow" : "By their rating"))
                                .font(.wmLabel.weight(.semibold))
                        }
                    }
                    .rowStyle()
                }
            }
        }
    }

    // What they can do

    @ViewBuilder private var allowed: some View {
        let a = access
        let kind = desk.user(id)?.kind
        ListGroup(title: "", footer: "Installing modules, changing settings and managing libraries are always for administrators. Signing in a TV is always for adults.") {
            ForEach(LimitWords.featureSwitches(profileKind: kind, offered: desk.lists?.features), id: \.feature.id) { entry in
                SwitchRow(title: entry.feature.label, detail: entry.feature.hint, isOn: !entry.fixedOff && a.allows(entry.feature.id), fixed: entry.fixedOff) {
                    desk.edit(id) { $0.set(entry.feature.id, on: !a.allows(entry.feature.id)) }
                }
                .accessibilityIdentifier("switch-\(entry.feature.id)")
            }
        }
    }

    // Screen time

    private func stepAllowance(_ key: WritableKeyPath<TimeRules, Int>, by: Int) -> (() -> Void)? {
        let now = (access.time ?? TimeRules())[keyPath: key]
        let choices = TimeRules.allowanceChoices(including: now)
        guard let at = choices.firstIndex(of: now), choices.indices.contains(at + by) else { return nil }
        return { desk.edit(id) { a in
            var rules = a.time ?? TimeRules()
            rules[keyPath: key] = choices[at + by]
            a.time = rules.isEmpty ? nil : rules
        } }
    }

    /// A time of day in quarter hours. Below the first one is "Off", and up from "Off" starts at `first`.
    private func stepTime(_ key: WritableKeyPath<TimeRules, String>, by: Int, first: Int) -> (() -> Void)? {
        let now = TimeRules.minutes((access.time ?? TimeRules())[keyPath: key])
        if now == nil && by < 0 { return nil }
        if let now, by > 0, now + 15 > 23 * 60 + 45 { return nil }
        return { desk.edit(id) { a in
            var rules = a.time ?? TimeRules()
            if let now {
                let next = now + by * 15
                rules[keyPath: key] = next < 0 ? "" : TimeRules.clock(next)
            } else {
                rules[keyPath: key] = TimeRules.clock(first)
            }
            a.time = rules.isEmpty ? nil : rules
        } }
    }

    private func timeRow(_ title: String, _ detail: String, _ key: WritableKeyPath<TimeRules, String>, first: Int) -> some View {
        let value = (access.time ?? TimeRules())[keyPath: key]
        return StepRow(title: title, detail: detail, value: value.isEmpty ? "Off" : value,
                       less: stepTime(key, by: -1, first: first), more: stepTime(key, by: 1, first: first))
    }

    @ViewBuilder private var time: some View {
        let rules = access.time ?? TimeRules()
        Secondary("Time is counted by the server while this profile is playing something, on any device. When it runs out, what is playing stops and the profile is told why. A parent can give more.")
        ListGroup(title: "How long each day") {
            StepRow(title: "School days", detail: "Monday to Friday.", value: TimeRules.allowanceLabel(rules.schoolDayMinutes),
                    less: stepAllowance(\.schoolDayMinutes, by: -1), more: stepAllowance(\.schoolDayMinutes, by: 1))
            StepRow(title: "Weekends", detail: "Saturday and Sunday.", value: TimeRules.allowanceLabel(rules.weekendMinutes),
                    less: stepAllowance(\.weekendMinutes, by: -1), more: stepAllowance(\.weekendMinutes, by: 1))
        }
        ListGroup(title: "When", footer: "School holidays aren’t known to the server: change these when they start.") {
            timeRow("Not before", "With a bedtime and nothing here, the day starts at 6:00.", \.from, first: 7 * 60)
            timeRow("Bedtime on school nights", "Sunday to Thursday evenings.", \.schoolNightUntil, first: 20 * 60)
            timeRow("Bedtime on Fridays and Saturdays", "", \.weekendUntil, first: 21 * 60)
        }
    }

    private var title: String {
        switch page {
        case .see: return "What \(name) sees"
        case .kinds: return "A different age for some kinds"
        case .hideGenres: return "Hide genres"
        case .onlyGenres: return "Show only these genres"
        case .collections: return "Collections"
        case .allowed: return "What \(name) can do"
        case .time: return "Screen time for \(name)"
        }
    }

    var body: some View {
        SettingsScreen(title: title) {
            if desk.user(id) == nil {
                if desk.users == nil { ProgressView().frame(maxWidth: .infinity) } else { Secondary("That profile is no longer here.") }
            } else {
                switch page {
                case .see: see
                case .kinds: kinds
                case .hideGenres: genres(\.blockGenres, hint: "Titles of these genres are hidden.")
                case .onlyGenres: genres(\.onlyGenres, hint: "When any is on, only titles with one of them are shown.")
                case .collections: collections
                case .allowed: allowed
                case .time: time
                }
                SaveBar(id: id)
            }
        }
        .task {
            if desk.users == nil { await desk.load(client, household: model.household) }
            tags = access.blockTags.joined(separator: ", ")
            if page != .allowed && page != .time { await desk.loadChoices(client) }
        }
    }
}

// MARK: - Name, picture and password

struct ProfileLookView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var desk: ProfileDesk
    @Environment(\.client) private var client
    let id: Int64
    @State private var display = ""
    @State private var username = ""
    @State private var picture = ""
    @State private var loaded = false
    @State private var busy = false
    @State private var problem = ""
    @State private var saved = false

    private func save(_ user: ManagedUser) {
        guard !busy else { return }
        busy = true
        problem = ""
        saved = false
        Task {
            do {
                let name = username.trimmingCharacters(in: .whitespaces)
                let fresh = try await client.setProfileLook(userId: user.id, displayName: display.trimmingCharacters(in: .whitespaces),
                                                            username: name == user.name ? nil : name, avatar: picture)
                if fresh.id == model.user?.id { model.user = fresh }
                await desk.load(client, household: model.household)
                saved = true
            } catch {
                problem = model.handle(error)
            }
            busy = false
        }
    }

    var body: some View {
        let user = desk.user(id)
        SettingsScreen(title: "Name and picture") {
            if let user {
                OutlinedField(label: "Profile name", text: $display, icon: "person.text.rectangle")
                Secondary("What they’re called around the app.")
                OutlinedField(label: say("usernameLabel"), text: $username, kind: .name, icon: "person")
                Secondary("What they sign in with.")
                SectionTitle("Picture")
                PicturePicker(name: display.isEmpty ? user.shownName : display, value: $picture, lists: desk.lists)
                if !problem.isEmpty { ProblemLine(problem) }
                if saved { OutcomeLine(words: "Saved.") }
                Button { save(user) } label: { BusyText(say("save"), busy: busy) }
                    .action(.primary, wide: true, tall: true)
                    .disabled(busy || username.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("look-save")
            } else if desk.users == nil {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .task {
            if desk.users == nil { await desk.load(client, household: model.household) }
            guard !loaded, let user = desk.user(id) else { return }
            loaded = true
            display = user.displayName ?? ""
            username = user.name
            picture = user.avatar ?? ""
        }
    }
}

struct ProfileSecretView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var desk: ProfileDesk
    @Environment(\.client) private var client
    let id: Int64
    @State private var password = ""
    @State private var busy = false
    @State private var problem = ""
    @State private var done = ""

    private func run(_ words: String, _ work: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        problem = ""
        done = ""
        Task {
            do {
                try await work()
                password = ""
                await desk.load(client, household: model.household)
                done = words
            } catch {
                problem = model.handle(error)
            }
            busy = false
        }
    }

    var body: some View {
        let user = desk.user(id)
        let adult = user?.isAdult ?? true
        SettingsScreen(title: adult ? "Password" : "Password or PIN",
                       detail: adult ? "A new password for \(user?.shownName ?? "this account"). Its other devices are signed out."
                                     : "A Kids or Guest profile can have a short PIN, or nothing: with none it opens with a tap on your home network only.") {
            if let user {
                OutlinedField(label: adult ? "New password" : "New password or PIN", text: $password, kind: .password, icon: "lock")
                if !problem.isEmpty { ProblemLine(problem) }
                if !done.isEmpty { OutcomeLine(words: done) }
                Button { run("Saved.") { try await client.setProfilePassword(userId: user.id, password: password) } } label: {
                    BusyText(say("save"), busy: busy)
                }
                .action(.primary, wide: true, tall: true)
                .disabled(busy || password.isEmpty)
                if !adult, user.hasPassword == true {
                    Button("Remove it") {
                        run("Removed. \(user.shownName) now signs in with a tap at home.") {
                            desk.replace(try await client.saveAccess(userId: user.id, changes: nil, clearPassword: true))
                        }
                    }
                    .action(.secondary, wide: true, tall: true)
                    .disabled(busy)
                }
            } else if desk.users == nil {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .task { if desk.users == nil { await desk.load(client, household: model.household) } }
    }
}

// MARK: - A new profile

struct AddProfileView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var desk: ProfileDesk
    @Environment(\.client) private var client
    @Environment(\.dismiss) private var dismiss
    @State private var kind = "kids"
    @State private var username = ""
    @State private var display = ""
    @State private var password = ""
    @State private var age = 7
    @State private var picture = ""
    @State private var busy = false
    @State private var problem = ""
    @State private var wantName = false

    private var kinds: [String] { model.user?.isAdmin == true ? ["kids", "guest", "adult"] : ["kids"] }
    private var ready: Bool { !username.trimmingCharacters(in: .whitespaces).isEmpty && (kind != "adult" || !password.isEmpty) }

    private func add() {
        guard ready, !busy else { return }
        busy = true
        problem = ""
        Task {
            do {
                try await client.addProfile(name: username.trimmingCharacters(in: .whitespaces), password: password, kind: kind,
                                            displayName: display.trimmingCharacters(in: .whitespaces), avatar: picture,
                                            limits: NewProfileLimits(kind: kind, maxAge: age))
                await desk.load(client, household: model.household)
                dismiss()
            } catch {
                problem = model.handle(error)
            }
            busy = false
        }
    }

    var body: some View {
        SettingsScreen(title: "Add a profile", detail: "Each person gets their own watch progress, history, lists and picture.") {
            if kinds.count > 1 {
                HStack(spacing: Tokens.Space.s2) {
                    ForEach(kinds, id: \.self) { choice in
                        Button(LimitWords.profileKind(choice)) { kind = choice }.action(selected: kind == choice, pill: true)
                            .accessibilityIdentifier("kind-\(choice)")
                    }
                }
                .remoteSection()
            }
            OutlinedField(label: say("usernameLabel"), text: $username, kind: .name, icon: "person", request: $wantName)
            Secondary("What they sign in with. It has to be theirs alone.")
            OutlinedField(label: "Profile name (optional)", text: $display, icon: "person.text.rectangle")
            OutlinedField(label: kind == "adult" ? say("passwordLabel") : "Password or PIN (optional)", text: $password, kind: .password, icon: "lock")
            if kind != "adult" {
                Secondary("With none, the profile opens with a tap on your home network only.")
                ListGroup(title: "What may they watch?", footer: "Everything else about their limits can be set once the profile is made.") {
                    ForEach(LimitWords.ageLevels, id: \.age) { level in
                        SettingChoiceRow(title: level.label, detail: level.hint, chosen: age == level.age) { age = level.age }
                    }
                }
            }
            SectionTitle("Picture")
            PicturePicker(name: display.isEmpty ? (username.isEmpty ? "?" : username) : display, value: $picture, lists: desk.lists)
            if !problem.isEmpty { ProblemLine(problem) }
            Button { add() } label: { BusyText("Add profile", busy: busy) }
                .action(.primary, wide: true, tall: true)
                .disabled(!ready || busy)
                .accessibilityIdentifier("add-save")
        }
        .task {
            #if !os(tvOS)
            wantName = true
            #endif
        }
    }
}

// MARK: - The report

struct ProfileReportView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var desk: ProfileDesk
    @Environment(\.palette) private var palette
    @Environment(\.client) private var client
    let id: Int64
    @State private var activity: ProfileActivity?
    @State private var problem = ""
    @State private var said = ""
    @State private var confirmClear = false
    @State private var busy = false

    private static let dayName: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter
    }()

    private static let moment: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEjmm")
        return formatter
    }()

    private func load() async {
        do {
            activity = try await client.profileActivity(id)
            problem = ""
        } catch {
            problem = model.handle(error)
        }
    }

    private func give(_ minutes: Int) {
        guard !busy else { return }
        busy = true
        said = ""
        Task {
            do {
                _ = try await client.giveTime(to: id, minutes: minutes)
                said = "\(desk.user(id)?.shownName ?? "They") has \(ScreenTimeRules.extraLabel(minutes)) more today."
                await load()
            } catch {
                problem = model.handle(error)
            }
            busy = false
        }
    }

    private func clear() {
        Task {
            do {
                try await client.clearProfileActivity(id)
                await load()
            } catch {
                problem = model.handle(error)
            }
        }
    }

    private func line(_ words: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s3) {
            Text(words).font(.subheadline).foregroundStyle(palette.text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Tokens.Space.s2)
            Text(value).font(.wmSecondary).foregroundStyle(palette.textSecondary)
        }
        .padding(.horizontal, Tokens.Space.s4)
        .padding(.vertical, Tokens.Space.s3)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func report(_ a: ProfileActivity) -> some View {
        SectionTitle("Today")
        Text(ReportWords.today(a.screenTime)).font(.subheadline).foregroundStyle(palette.text).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("report-today")
        Secondary("Give more time today:")
        HStack(spacing: Tokens.Space.s2) {
            ForEach(ScreenTimeRules.extras, id: \.self) { minutes in
                Button(ScreenTimeRules.extraLabel(minutes)) { give(minutes) }.action(pill: true).disabled(busy)
                    .accessibilityIdentifier("give-\(minutes)")
            }
        }
        .remoteSection()
        if !said.isEmpty { OutcomeLine(words: said) }
        SectionTitle("What they watched")
        let days = ReportWords.days(a)
        if days.isEmpty {
            Secondary("Nothing yet. This is kept only for profiles with limits, and they can’t clear it themselves.")
        }
        ForEach(days, id: \.self) { day in
            let name = ReportWords.date(day: day, calendar: .current).map { Self.dayName.string(from: $0) } ?? "\(day)"
            ListGroup(title: name, footer: ReportWords.dayTotal((a.days ?? []).first { $0.day == day })) {
                ForEach(Array((a.watched ?? []).filter { $0.day == day }.enumerated()), id: \.offset) { _, row in
                    line(ReportWords.watched(row), ReportWords.duration(row.seconds ?? 0))
                }
            }
        }
        SectionTitle("What was refused, and extra time")
        if (a.events ?? []).isEmpty {
            Secondary("Nothing.")
        } else {
            ListGroup(title: "") {
                ForEach(Array((a.events ?? []).enumerated()), id: \.offset) { _, event in
                    line(ReportWords.event(event), event.at.map { Self.moment.string(from: Date(timeIntervalSince1970: TimeInterval($0))) } ?? "")
                }
            }
        }
        Button("Clear") { confirmClear = true }.action(.destructive, wide: true, tall: true)
    }

    var body: some View {
        let name = desk.user(id)?.shownName ?? "This profile"
        SettingsScreen(title: "\(name): the last two weeks") {
            if let activity { report(activity) } else if problem.isEmpty { ProgressView().frame(maxWidth: .infinity) }
            if !problem.isEmpty { ProblemLine(problem) }
        }
        .task {
            if desk.users == nil { await desk.load(client, household: model.household) }
            await load()
        }
        #if os(iOS)
        .refreshable { await load() }
        #endif
        .confirmationDialog("Clear what’s written down about \(name)? What they watched and what was refused is forgotten. Today’s screen time stays.",
                            isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { clear() }
        }
    }
}

// MARK: - The parents' PIN

struct ParentPinView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @State private var isSet: Bool?
    @State private var pin = ""
    @State private var current = ""
    @State private var code = ""
    @State private var busy = false
    @State private var problem = ""
    @State private var done = ""

    private var twoStep: Bool { model.user?.twoFactor == true }
    private var ready: Bool { ScreenTimeRules.pinIsValid(pin) && !current.isEmpty && (!twoStep || !code.isEmpty) }

    private func save(_ value: String) {
        guard !busy else { return }
        busy = true
        problem = ""
        done = ""
        Task {
            do {
                let now = try await client.setParentPin(value, current: current, code: code)
                isSet = now
                pin = ""
                current = ""
                code = ""
                done = now ? "The parents’ PIN is set." : "The parents’ PIN is removed."
            } catch {
                problem = model.handle(error)
            }
            busy = false
        }
    }

    var body: some View {
        let detail = "When a profile’s screen time runs out, a parent can type this PIN on that device to give it more time today. It does nothing else, so it can be short. "
            + (isSet == true ? "A PIN is set." : "No PIN is set: a parent’s own username and password work instead.")
        SettingsScreen(title: "Parents’ PIN", detail: detail) {
            OutlinedField(label: isSet == true ? "New PIN" : "PIN", text: Binding(get: { pin }, set: { pin = ScreenTimeRules.cleanPin($0) }),
                          kind: .password, icon: "lock.rectangle")
            Secondary("4 to 12 digits.")
            OutlinedField(label: "Your password", text: $current, kind: .password, icon: "lock")
            if twoStep { OutlinedField(label: "Code from your authenticator app", text: $code, icon: "lock.shield") }
            if !problem.isEmpty { ProblemLine(problem) }
            if !done.isEmpty { OutcomeLine(words: done) }
            Button { save(pin) } label: { BusyText(isSet == true ? "Change PIN" : "Set PIN", busy: busy) }
                .action(.primary, wide: true, tall: true)
                .disabled(!ready || busy)
                .accessibilityIdentifier("pin-save")
            if isSet == true {
                Button("Remove it") { save("") }
                    .action(.secondary, wide: true, tall: true)
                    .disabled(busy || current.isEmpty || (twoStep && code.isEmpty))
            }
        }
        .task { isSet = try? await client.parentPinIsSet() }
    }
}
