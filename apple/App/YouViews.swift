// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// You: the person, their account, this device's choices and, for an administrator, the server.
// docs/APP-DESIGN.md, You and settings, is the contract; Android builds the same screens.
// What belongs to the person is native here. What the owner manages opens the server's own page,
// inside the app on iPhone, iPad and Vision Pro, and as a code for a phone on Apple TV.

private enum RowTint {
    static let account = "#0a6fb8", password = "#3e5bd0", twoStep = "#2e7d3c", devices = "#7f46b8"
    static let tv = "#bd2f85", family = "#b8500d", year = "#c9302f", teal = "#0e7c6f", gold = "#99690a"
    static let quiet = "#5d6474"
}

extension User {
    var isAdult: Bool { isAdmin == true || (kind ?? "adult") == "adult" }

    var roleName: String {
        if isAdmin == true { return say("roleAdmin") }
        switch kind {
        case "kids": return say("roleKids")
        case "guest": return say("roleGuest")
        default: return say("roleAdult")
        }
    }
}

struct YouView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var center: SDUICenter
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @Environment(\.client) private var client
    @State private var twoStep: TwoFactorState?
    @State private var deviceCount: Int?
    @State private var hasGames = false
    @State private var serverVersion = ""
    @State private var confirmSignOut = false
    @State private var summaries: [String: String] = [:]
    @Namespace private var scope

    private var user: User? { model.user }
    private var isAdmin: Bool { user?.isAdmin == true }
    private var isAdult: Bool { user?.isAdult ?? false }

    private func load() async {
        async let state = try? client.twoFactorState()
        async let devices = try? client.signedInDevices()
        async let libraries = try? client.libraries()
        async let status = try? client.status()
        let (s, d, l, st) = await (state, devices, libraries, status)
        twoStep = s
        deviceCount = d?.count
        hasGames = l?.contains { $0.type == "games" && !$0.isRigGames } ?? false
        serverVersion = PlainWords.clean(st?.version ?? "", limit: 40)
        if let fresh = st?.user { model.user = fresh }
    }

    // MARK: Rows

    /// The settings menu every client draws (the server's, else this app's copy): Android's You page, so the
    /// groups, rows, order and words are the same here, on Android, the web and its TV mode.
    private var menu: SettingsMenu {
        center.catalog.settingsMenu ?? SharedData.settingsMenu ?? SettingsMenu(conditions: [], values: [], groups: [])
    }

    private var facts: Set<String> {
        var f: Set<String> = ["app", "servers"]
        if isAdmin { f.insert("admin") }
        if isAdult { f.insert("adult") }
        if metrics.tv { f.insert("tv") }
        if twoStep?.available != false { f.insert("twoStep") }
        if hasGames { f.insert("games") }
        if PeerLibrary.available { f.insert("fromAway") }
        if model.has("sdui-experiences") { f.formUnion(["looks", "layoutEditor"]) }
        if model.has("module-settings") { f.insert("moduleSettings") }
        if model.remote.hasRemote { f.insert("remote") }
        if model.remote.hasParties { f.insert("parties") }
        return f
    }

    /// What this profile's limits turn off: rows for those aren't offered.
    private var off: Set<String> {
        model.household.allows(ProfileFeature.sharing) ? [] : ["sharing"]
    }

    /// Where a row goes here: this app's own screen, else the server's SDUI page, else the server's page (on Apple TV
    /// the card with its address and QR code).
    private func route(_ row: SettingsMenu.Row) -> Route? {
        switch row.native ?? "" {
        case "names": return .names
        case "password": return .password
        case "twoStep": return .twoStep
        case "devices": return .devices
        case "signInTv": return .signInTv
        case "profiles": if model.has("parental-controls") { return .family(.profiles) }
        case "modules": return .modules
        case "look", "theme": return .theme
        case "editLayout": return .layoutEditor
        case "nameAndLogo": return .brandEditor
        case "playingHere": return .mediaExtras
        case "servers": return .servers
        case "away": return .away
        case "licences": return .notices
        case "appLog": return .logs
        #if os(tvOS)
        case "topMenu": return .topMenu
        #endif
        default: break
        }
        guard let path = row.path, !path.isEmpty else { return nil }
        if row.sdui == true, path == "/manage/libraries" { return .sdui(SDUIPlace(page: "manage-libraries", params: [:], route: path)) }
        return .page(path)
    }

    /// A row Apple TV can't change: it stays in its place and opens the card with that setting's address.
    private func elsewhere(_ row: SettingsMenu.Row) -> Bool {
        guard metrics.tv, row.native == nil || ["editLayout", "nameAndLogo"].contains(row.native ?? "") else { return false }
        return SettingsMenu.level(of: row, in: center.catalog.tvLevels) == TvLevel.desktopOnly
    }

    private func value(_ row: SettingsMenu.Row) -> String {
        if elsewhere(row) { return summaries[SettingsMenu.summary(of: row, in: center.catalog.tvLevels)] ?? say("onAComputer") }
        switch row.value ?? "" {
        case "name": return user?.shownName ?? ""
        case "twoStep": return twoStep.map { say($0.on ? "on" : "off") } ?? ""
        case "devices": return deviceCount.map(String.init) ?? ""
        case "theme": return ThemeView.name(of: model.themeChoice, server: model.themeId, list: model.themeList)
        case "topMenu": return model.topMenu.isEmpty ? "" : "\(model.topMenu.count)"
        case "servers": return "\(model.recent.count)"
        case "away": return model.awayRowValue
        case "version": return serverVersion
        default: return ""
        }
    }

    private func label(_ row: SettingsMenu.Row) -> RowLabel {
        RowLabel(icon: row.icon.apple, tint: row.tint == "danger" ? RowTint.quiet : row.tint, title: say(row.key), value: value(row), destructive: row.tint == "danger")
    }

    @ViewBuilder private func rowView(_ row: SettingsMenu.Row, first: Bool) -> some View {
        if elsewhere(row), let path = row.path {
            NavigationLink(value: Route.page(path)) { label(row) }
                .rowStyle()
                .accessibilityIdentifier("row." + row.id)
        } else if let to = route(row) {
            if first {
                NavigationLink(value: to) { label(row) }
                    .rowStyle()
                    .accessibilityIdentifier("row." + row.id)
                    .firstFocus(in: scope)
            } else {
                NavigationLink(value: to) { label(row) }
                    .rowStyle()
                    .accessibilityIdentifier("row." + row.id)
            }
        }
    }

    private static let together = ["remoteControl", "watchParty"]

    @ViewBuilder private var groups: some View {
        let shown = menu.visible(facts: facts, off: off) { route($0) != nil || Self.together.contains($0.native ?? "") }
        // Remote control and Watch party are the app's own rows for them (TogetherRows), where the first of the two is.
        let togetherAt = shown.flatMap(\.rows).first { Self.together.contains($0.native ?? "") }?.id
        ForEach(Array(shown.enumerated()), id: \.element.id) { gi, g in
            ListGroup(title: say(g.key)) {
                ForEach(Array(g.rows.enumerated()), id: \.element.id) { ri, row in
                    if Self.together.contains(row.native ?? "") {
                        if row.id == togetherAt { TogetherRows() }
                    } else {
                        rowView(row, first: gi == 0 && ri == 0)
                    }
                }
            }
        }
    }

    /// What Apple TV says is set on the rows it can't change: the first line of each setting's summary.
    private func loadSummaries() async {
        guard metrics.tv else { return }
        let ids = Set(menu.groups.flatMap(\.rows).filter(elsewhere).map { SettingsMenu.summary(of: $0, in: center.catalog.tvLevels) }.filter { !$0.isEmpty })
        for id in ids {
            if let line = (try? await client.tvSummary(id))?.lines.first { summaries[id] = line }
        }
    }

    // MARK: Header and server

    @ViewBuilder private var header: some View {
        let size: CGFloat = metrics.tv ? 200 : (metrics.cardWidth > 124 ? 120 : 88)
        VStack(spacing: 0) {
            AvatarTile(name: user?.shownName ?? "?", size: size, picture: user?.avatar)
            Text(user?.shownName ?? "")
                .font(metrics.tv ? .title2.weight(.semibold) : .wmPage)
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .padding(.top, Tokens.Space.s3)
            if let user {
                Text("@\(user.name) · \(user.roleName)")
                    .font(.wmSecondary)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .padding(.top, Tokens.Space.s1)
            }
            Button { model.household.startSwitch(model) } label: {
                Label(say("switchProfile"), systemImage: "person.2")
            }
            .action(.secondary, pill: true)
            .padding(.top, Tokens.Space.s4)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var thisServer: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            Text(say("groupThisServer").uppercased())
                .font(.caption.weight(.medium))
                .foregroundStyle(palette.textSecondary)
                .padding(.leading, Tokens.Space.s4)
            if let server = model.current {
                HStack(spacing: Tokens.Space.s3) {
                    BrandMark(size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(server.name).font(.wmLabel.weight(.semibold)).foregroundStyle(palette.text).lineLimit(1)
                        Text(PeerInfo.isPlaceholder(server.url) ? say("awayOnly") : server.url).font(.wmSecondary).foregroundStyle(palette.textSecondary).lineLimit(1)
                        if model.way.isAway {
                            Text(model.way.words).font(.wmSecondary).foregroundStyle(palette.textSecondary).lineLimit(1)
                        }
                        if !server.fingerprint.isEmpty {
                            (Text("\(say("fingerprintLabel")) ") + Text(server.fingerprint).font(.caption2.monospaced()))
                                .font(.caption2)
                                .foregroundStyle(palette.textHint)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(Tokens.Space.s4)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).fill(palette.panel))
                .accessibilityElement(children: .combine)
            }
            Button { model.changeServer() } label: { Label(say("changeServer"), systemImage: "server.rack") }
                .action(.secondary, wide: true, tall: true)
            Button { confirmSignOut = true } label: { Label(say("signOut"), systemImage: "rectangle.portrait.and.arrow.right") }
                .action(.destructive, wide: true, tall: true)
            Text("\(say("appName")) \(WittyClient.appVersion)")
                .font(.caption)
                .foregroundStyle(palette.textHint)
                .frame(maxWidth: .infinity)
                .padding(.top, Tokens.Space.s2)
        }
    }

    var body: some View {
        Group {
            if metrics.tv {
                HStack(alignment: .top, spacing: Tokens.Space.s12) {
                    VStack { Spacer(); header; Spacer() }
                        .frame(width: 520)
                        .remoteSection()
                    ScrollView {
                        VStack(alignment: .leading, spacing: Tokens.Space.s8) {
                            groups
                            thisServer
                        }
                        .padding(.vertical, Tokens.Space.s10)
                    }
                }
                .padding(.horizontal, metrics.gutter)
            } else {
                ScrollView {
                    VStack(spacing: Tokens.Space.s6) {
                        header
                        AppNoticeLine()
                        groups
                        thisServer
                    }
                    .frame(maxWidth: 640)
                    .padding(.horizontal, metrics.gutter)
                    .padding(.top, Tokens.Space.s6)
                    .padding(.bottom, barRoom(metrics))
                    .frame(maxWidth: .infinity)
                }
                #if os(iOS)
                .refreshable { await load() }
                #endif
            }
        }
        .focusRoot(scope)
        .pageBackground(palette)
        .task { await load() }
        .task { await loadSummaries() }
        .confirmationDialog(say("signOut"), isPresented: $confirmSignOut, titleVisibility: .hidden) {
            Button(say("signOut"), role: .destructive) { model.requestSignOut() }
        }
    }
}

// MARK: - Names

struct NamesView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.client) private var client
    @State private var profileName = ""
    @State private var username = ""
    @State private var showUsername = false
    @State private var busy = false
    @State private var problem = ""
    @State private var saved = false
    @State private var loaded = false

    private var adult: Bool { model.user?.isAdult ?? false }
    private var previewName: String {
        ProfileNames.shown(name: username, displayName: profileName)
    }

    private func save() {
        guard let user = model.user, !busy else { return }
        let name = username.trimmingCharacters(in: .whitespaces)
        if adult && name.isEmpty { problem = say("errUsernameEmpty"); return }
        busy = true
        problem = ""
        Task {
            do {
                let fresh = try await client.updateProfile(
                    userId: user.id,
                    displayName: adult ? profileName.trimmingCharacters(in: .whitespaces) : nil,
                    username: adult && name != user.name ? name : nil,
                    showUsername: showUsername)
                model.user = fresh
                saved = true
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                saved = false
            } catch {
                problem = plainWords(Problem.of(error))
            }
            busy = false
        }
    }

    var body: some View {
        SettingsScreen(title: say("rowNames")) {
            AvatarTile(name: previewName, size: 64, picture: model.user?.avatar)
                .frame(maxWidth: .infinity)
                .animation(.easeOut(duration: Tokens.Motion.appear), value: AvatarLook.colour(for: previewName))
            // The picture is changed from here, as on Android (You's own row for it is gone: the settings menu is one list).
            if model.has("profile-avatars"), model.household.allows(ProfileFeature.editProfile) {
                ListGroup(title: "") {
                    NavigationLink(value: Route.family(.myPicture)) {
                        RowLabel(icon: "face.smiling", tint: "#0a6fb8", title: say("changePicture"))
                    }
                    .rowStyle()
                }
            }
            VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                OutlinedField(label: say("profileNameLabel"), text: $profileName, icon: "person.text.rectangle")
                Secondary(profileName.trimmingCharacters(in: .whitespaces).isEmpty && adult ? say("profileNameEmptyHint") : say("profileNameHint"))
                    .padding(.horizontal, Tokens.Space.s4)
            }
            .disabled(!adult)
            VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                OutlinedField(label: say("usernameLabel"), text: $username, kind: .name, icon: "at")
                Secondary(adult ? say("usernameHint") : say("usernameKidsHint"))
                    .padding(.horizontal, Tokens.Space.s4)
            }
            .disabled(!adult)
            ListGroup(title: "", footer: say("showUsernameHint")) {
                Toggle(isOn: $showUsername) {
                    Text(say("showUsernameLabel")).font(.subheadline).foregroundStyle(palette.text)
                }
                .tint(palette.accent)
                .padding(.horizontal, Tokens.Space.s4)
                .frame(minHeight: 52)
            }
            if !problem.isEmpty { ProblemLine(problem) }
            Button(action: save) { BusyText(say("save"), busy: busy) }
                .action(.primary, wide: true, tall: true)
            if saved { OutcomeLine(words: say("saved")).transition(.opacity) }
        }
        .animation(.easeOut(duration: Tokens.Motion.appear), value: saved)
        .onChange(of: profileName) { if $0.count > 60 { profileName = String($0.prefix(60)) } }
        .onChange(of: username) { if $0.count > 40 { username = String($0.prefix(40)) } }
        .onAppear {
            guard !loaded, let user = model.user else { return }
            loaded = true
            profileName = user.displayName ?? ""
            username = user.name
            showUsername = user.showUsername ?? false
        }
    }
}

// MARK: - Password

struct PasswordView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.client) private var client
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var fresh = ""
    @State private var again = ""
    @State private var code = ""
    @State private var problem = ""
    @State private var wrongCurrent = false
    @State private var busy = false
    @State private var done = false
    @State private var wantCurrent = true
    @State private var wantFresh = false
    @State private var wantAgain = false

    private var needsCode: Bool { model.user?.twoFactor == true }

    private func change() {
        guard let user = model.user, !busy else { return }
        if fresh.count < 8 { problem = say("errPasswordShort"); return }
        if fresh != again { problem = say("errPasswordsDiffer"); return }
        busy = true
        problem = ""
        Task {
            do {
                try await client.changePassword(userId: user.id, password: fresh, current: current, code: code)
                done = true
            } catch let error as APIError where error.status == 403 {
                wrongCurrent = true
                current = ""
                wantCurrent = true
                problem = say("errCurrentPassword")
            } catch {
                problem = plainWords(Problem.of(error))
            }
            busy = false
        }
    }

    var body: some View {
        SettingsScreen(title: say("rowPassword"), detail: done ? "" : say("passwordChangeHint")) {
            if done {
                OutcomeLine(words: say("passwordChanged"))
                Button(say("back")) { dismiss() }.action(.primary, wide: true, tall: true)
            } else {
                OutlinedField(label: say("currentPasswordLabel"), text: $current, kind: .password, icon: "lock",
                              request: $wantCurrent, invalid: wrongCurrent) { wantFresh = true }
                OutlinedField(label: say("newPasswordLabel"), text: $fresh, kind: .password, icon: "key",
                              request: $wantFresh) { wantAgain = true }
                OutlinedField(label: say("repeatPasswordLabel"), text: $again, kind: .password, icon: "key",
                              request: $wantAgain) { if !needsCode { change() } }
                if needsCode {
                    OutlinedField(label: say("twoStepCodeLabel"), text: $code, icon: "number") { change() }
                }
                if !problem.isEmpty { ProblemLine(problem) }
                Button(action: change) { BusyText(say("changePassword"), busy: busy) }
                    .action(.primary, wide: true, tall: true)
            }
        }
        .onChange(of: current) { if !$0.isEmpty { wrongCurrent = false } }
    }
}

// MARK: - Two-step sign-in

struct TwoStepView: View {
    private enum Stage: Equatable {
        case loading, off, password, scan(TwoFactorSetup), codes([String]), on
    }

    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @Environment(\.client) private var client
    @Environment(\.openURL) private var openURL
    @State private var stage: Stage = .loading
    @State private var state: TwoFactorState?
    @State private var password = ""
    @State private var code = ""
    @State private var problem = ""
    @State private var busy = false
    @State private var wrongCodes = 0
    @State private var turningOff = false
    @State private var copied = false
    @State private var wantPassword = false
    @Namespace private var scope

    private func load() async {
        do {
            let fresh = try await client.twoFactorState()
            state = fresh
            stage = fresh.on ? .on : .off
        } catch {
            problem = plainWords(Problem.of(error))
            stage = .off
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        problem = ""
        Task {
            do { try await work() } catch let error as APIError where error.status == 403 {
                problem = say("errCurrentPassword")
                password = ""
            } catch {
                problem = plainWords(Problem.of(error))
            }
            busy = false
        }
    }

    private func confirm(_ digits: String) {
        guard !busy else { return }
        busy = true
        problem = ""
        Task {
            do {
                let codes = try await client.twoFactorConfirm(code: digits)
                stage = .codes(codes)
            } catch {
                wrongCodes += 1
                problem = say("errWrongCode")
                code = ""
            }
            busy = false
        }
    }

    @ViewBuilder private var offStage: some View {
        if state?.available == false {
            Secondary(say("twoStepUnavailable"))
        } else {
            Button { stage = .password; wantPassword = true } label: {
                Label(say("twoStepTurnOn"), systemImage: "lock.shield")
            }
            .action(.primary, wide: true, tall: true)
            .firstFocus(in: scope)
        }
    }

    @ViewBuilder private var passwordStage: some View {
        SectionTitle(say("twoStepConfirmTitle"))
        OutlinedField(label: say("passwordLabel"), text: $password, kind: .password, icon: "lock", request: $wantPassword) {
            run { stage = .scan(try await client.twoFactorSetup(password: password)) }
        }
        if !problem.isEmpty { ProblemLine(problem) }
        Button { run { stage = .scan(try await client.twoFactorSetup(password: password)) } } label: {
            BusyText(say("continue"), busy: busy)
        }
        .action(.primary, wide: true, tall: true)
    }

    @ViewBuilder private func scanStage(_ setup: TwoFactorSetup) -> some View {
        SectionTitle(say("twoStepScanTitle"))
        Secondary(say("twoStepScanHint"))
        if let image = QRImage.make(for: setup.uri) {
            QRCard(image: image, caption: say("twoStepKeyLabel") + ": " + setup.groupedSecret)
                .frame(maxWidth: .infinity)
        }
        #if os(iOS)
        if let url = URL(string: setup.uri) {
            Button { openURL(url) } label: { Label(say("twoStepOpenApp"), systemImage: "arrow.up.forward.app") }
                .action(.secondary, wide: true)
        }
        #endif
        HStack(spacing: Tokens.Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(say("twoStepKeyLabel")).font(.caption.weight(.medium)).foregroundStyle(palette.textSecondary)
                Text(setup.groupedSecret).font(.body.monospaced()).foregroundStyle(palette.text).textSelectionIfAvailable()
            }
            Spacer(minLength: 0)
            if Clipboard.available {
                Button { Clipboard.copy(setup.secret); copied = true } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                .action(.secondary)
                .accessibilityLabel(copied ? say("copied") : say("copyAll"))
            }
        }
        .padding(Tokens.Space.s4)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).fill(palette.panel))
        DigitsEntry(code: $code, checking: busy, wrongTries: wrongCodes, label: say("twoFactorTitle"), scope: scope, onComplete: confirm)
            .padding(.top, Tokens.Space.s2)
        if !problem.isEmpty { ProblemLine(problem) }
    }

    @ViewBuilder private func codesStage(_ codes: [String]) -> some View {
        SectionTitle(say("twoStepSavedTitle"))
        Secondary(say("twoStepSavedHint"))
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Tokens.Space.s3) {
            ForEach(codes, id: \.self) { recovery in
                Text(recovery).font(.body.monospaced()).foregroundStyle(palette.text).textSelectionIfAvailable()
            }
        }
        .padding(Tokens.Space.s4)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).fill(palette.panel))
        if Clipboard.available {
            Button { Clipboard.copy(codes.joined(separator: "\n")); copied = true } label: {
                Label(copied ? say("copied") : say("copyAll"), systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .action(.secondary, wide: true)
        }
        Button {
            copied = false
            Task {
                await model.refreshUser()
                await load()
            }
        } label: { Text(say("twoStepDone")) }
        .action(.primary, wide: true, tall: true)
        .firstFocus(in: scope)
    }

    @ViewBuilder private var onStage: some View {
        let left = state?.recoveryLeft ?? 0
        HStack(spacing: Tokens.Space.s3) {
            Image(systemName: "checkmark.shield.fill").font(.title2).foregroundStyle(palette.ok)
            VStack(alignment: .leading, spacing: 2) {
                Text(say("twoStepOnTitle")).font(.wmLabel.weight(.semibold)).foregroundStyle(palette.text)
                Text(say("twoStepCodesLeft").replacingOccurrences(of: "{n}", with: "\(left)"))
                    .font(.wmSecondary)
                    .foregroundStyle(left < 3 ? palette.danger : palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Tokens.Space.s4)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).fill(palette.panel))
        .accessibilityElement(children: .combine)
        if turningOff {
            Secondary(say("twoStepTurnOffHint"))
            OutlinedField(label: say("passwordLabel"), text: $password, kind: .password, icon: "lock", request: $wantPassword)
            OutlinedField(label: say("twoStepCodeLabel"), text: $code, icon: "number")
            if !problem.isEmpty { ProblemLine(problem) }
            Button {
                run {
                    try await client.twoFactorDisable(password: password, code: code)
                    password = ""
                    code = ""
                    turningOff = false
                    await model.refreshUser()
                    await load()
                }
            } label: { BusyText(say("twoStepTurnOff"), busy: busy) }
            .action(.destructive, wide: true, tall: true)
        } else {
            Button { turningOff = true; wantPassword = true } label: { Text(say("twoStepTurnOff")) }
                .action(.destructive, wide: true, tall: true)
                .firstFocus(in: scope)
        }
    }

    var body: some View {
        SettingsScreen(title: say("rowTwoStep"), detail: stage == .off || stage == .loading ? say("twoStepIntro") : "") {
            switch stage {
            case .loading: ProgressView().frame(maxWidth: .infinity)
            case .off: offStage
            case .password: passwordStage
            case .scan(let setup): scanStage(setup)
            case .codes(let codes): codesStage(codes)
            case .on: onStage
            }
        }
        .focusRoot(scope)
        .animation(.easeOut(duration: Tokens.Motion.appear), value: stage)
        .task { await load() }
    }
}

// MARK: - Your devices

struct DevicesView: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @Environment(\.client) private var client
    @State private var devices: [SignedInDevice]?
    @State private var problem = ""
    @State private var leaving: SignedInDevice?
    @State private var leavingAll = false

    private func load() async {
        do {
            let all = try await client.signedInDevices()
            devices = all.sorted {
                ($0.isThisDevice ? 0 : 1, -($0.lastSeen ?? 0)) < ($1.isThisDevice ? 0 : 1, -($1.lastSeen ?? 0))
            }
            problem = ""
        } catch {
            problem = plainWords(Problem.of(error))
        }
    }

    private func signOut(_ device: SignedInDevice) {
        Task {
            do {
                try await client.signOutDevice(device.id)
                withAnimation { devices?.removeAll { $0.id == device.id } }
            } catch {
                problem = plainWords(Problem.of(error))
            }
        }
    }

    private func signOutOthers() {
        Task {
            do {
                try await client.signOutOtherDevices()
                await load()
            } catch {
                problem = plainWords(Problem.of(error))
            }
        }
    }

    static func icon(_ kind: DeviceKind) -> String {
        switch kind {
        case .phone: return "iphone"
        case .tablet: return "ipad"
        case .tv: return "tv"
        case .computer: return "desktopcomputer"
        case .browser: return "globe"
        }
    }

    static func whereWords(_ place: String?) -> String {
        switch place {
        case "machine": return say("whereMachine")
        case "home": return say("whereHome")
        case "vpn": return say("whereVpn")
        case "internet": return say("whereInternet")
        default: return ""
        }
    }

    static func seen(_ seconds: Int64?, now: Date = Date()) -> String {
        guard let seconds, seconds > 0 else { return "" }
        let when = Date(timeIntervalSince1970: TimeInterval(seconds))
        if now.timeIntervalSince(when) < 300 { return say("activeNow") }
        let words = RelativeDateTimeFormatter()
        words.unitsStyle = .full
        return words.localizedString(for: when, relativeTo: now)
    }

    /// This device is just shown; any other is a row that asks before signing it out. The quiet
    /// "Sign out" on the trailing side says what pressing does, without a column of red.
    @ViewBuilder private func row(_ device: SignedInDevice) -> some View {
        let detail = [Self.whereWords(device.place), device.isThisDevice ? say("activeNow") : Self.seen(device.lastSeen)]
            .filter { !$0.isEmpty }.factsLine()
        if device.isThisDevice {
            RowLabel(icon: Self.icon(device.kind), tint: RowTint.devices, title: device.name, detail: detail,
                     badge: say("thisDevice"), chevron: false)
                #if os(tvOS)
                .focusable()
                #endif
        } else {
            Button { leaving = device } label: {
                RowLabel(icon: Self.icon(device.kind), tint: RowTint.devices, title: device.name, value: say("signOut"),
                         detail: detail, chevron: false)
            }
            .rowStyle()
            .accessibilityHint(say("signOut"))
        }
    }

    var body: some View {
        SettingsScreen(title: say("rowDevices"), detail: say("devicesHint")) {
            if let devices {
                ListGroup(title: "") {
                    ForEach(devices) { row($0) }
                }
                if devices.contains(where: { !$0.isThisDevice }) {
                    Button { leavingAll = true } label: {
                        Label(say("signOutOthers"), systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .action(.destructive, wide: true, tall: true)
                }
            } else if problem.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            }
            if !problem.isEmpty { ProblemLine(problem) }
        }
        .task { await load() }
        #if os(iOS)
        .refreshable { await load() }
        #endif
        .confirmationDialog(say("signOutDeviceConfirm").replacingOccurrences(of: "{device}", with: leaving?.name ?? ""),
                            isPresented: Binding(get: { leaving != nil }, set: { if !$0 { leaving = nil } }),
                            titleVisibility: .visible) {
            Button(say("signOut"), role: .destructive) { if let leaving { signOut(leaving) } }
        }
        .confirmationDialog(say("signOutOthersConfirm"), isPresented: $leavingAll, titleVisibility: .visible) {
            Button(say("signOutOthers"), role: .destructive) { signOutOthers() }
        }
    }
}

// MARK: - Sign in a TV

// SignInTvView is in PairApprove.swift: it scans the code as well as taking it typed.

#if os(tvOS)
// MARK: - Top menu

/// Which libraries join Apple TV's top menu, after Search (docs/APP-DESIGN.md, On a TV). Only on this TV, per server
/// and per profile. Choosing a library adds it, or takes it out again.
struct TopMenuView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Namespace private var scope

    var body: some View {
        SettingsScreen(title: say("rowTopMenu"), detail: say("topMenuHint")) {
            ListGroup(title: "") {
                ForEach(Array(model.libraries.enumerated()), id: \.element.id) { index, library in
                    let added = model.topMenu.contains(library.id)
                    Button { model.toggleTopMenu(library) } label: {
                        HStack(spacing: 0) {
                            RowLabel(icon: library.barSymbol, tint: RowTint.teal, title: library.name, chevron: false)
                            Image(systemName: "checkmark")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(palette.accentText)
                                .opacity(added ? 1 : 0)
                                .padding(.trailing, Tokens.Space.s4)
                                .accessibilityHidden(true)
                        }
                    }
                    .rowStyle()
                    .firstFocus(in: scope, when: index == 0)
                    .accessibilityAddTraits(added ? [.isSelected] : [])
                }
            }
        }
        .focusRoot(scope)
    }
}
#endif
