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
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @Environment(\.client) private var client
    @State private var twoStep: TwoFactorState?
    @State private var deviceCount: Int?
    @State private var hasGames = false
    @State private var serverVersion = ""
    @State private var confirmSignOut = false
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

    private func row(_ route: Route, _ icon: String, _ tint: String, _ title: String, value: String = "") -> some View {
        NavigationLink(value: route) {
            RowLabel(icon: icon, tint: tint, title: say(title), value: value)
        }
        .rowStyle()
    }

    /// One of the server's own pages, by the path the web gives it.
    private func page(_ path: String, _ icon: String, _ tint: String = RowTint.quiet, title: String, value: String = "") -> some View {
        row(.page(path), icon, tint, title, value: value)
    }

    @ViewBuilder private var groups: some View {
        ListGroup(title: say("groupAccount")) {
            row(.names, "person.text.rectangle", RowTint.account, "rowNames", value: user?.shownName ?? "")
                .firstFocus(in: scope)
            if isAdult {
                row(.password, "key", RowTint.password, "rowPassword")
                if twoStep?.available != false {
                    row(.twoStep, "lock.shield", RowTint.twoStep, "rowTwoStep",
                        value: twoStep.map { say($0.on ? "on" : "off") } ?? "")
                }
            }
            row(.devices, "ipad.and.iphone", RowTint.devices, "rowDevices", value: deviceCount.map(String.init) ?? "")
        }
        if isAdult {
            ListGroup(title: say("groupHousehold")) {
                #if !os(tvOS)
                row(.signInTv, "tv", RowTint.tv, "rowSignInTv")
                #endif
                page("/settings/users", "figure.2.and.child.holdinghands", RowTint.family, title: "rowProfiles")
            }
        }
        ListGroup(title: say("groupYours")) {
            page("/review", "sparkles", RowTint.year, title: "rowYourYear")
            page("/collections", "square.stack", RowTint.teal, title: "rowCollections")
            page("/settings/sharing", "link", RowTint.account, title: "rowShareLinks")
            page("/settings/activity", "waveform.path.ecg", RowTint.gold, title: "rowActivity")
            if hasGames {
                page("/settings/games", "gamecontroller", RowTint.devices, title: "rowGameSettings")
                page("/controllers", "dpad", RowTint.password, title: "rowControllers")
            }
        }
        ListGroup(title: say("groupDevice")) {
            row(.theme, "paintpalette", RowTint.teal, "rowTheme", value: ThemeView.name(of: model.themeChoice, server: model.themeId, list: model.themeList))
        }
        if isAdmin {
            ListGroup(title: say("groupServer")) {
                page("/settings/libraries", "books.vertical", title: "rowLibraries")
                page("/settings/metadata", "photo.on.rectangle", title: "rowMetadata")
                page("/fix-matches", "wand.and.stars", title: "rowFixMatches")
                page("/settings/playback", "play.rectangle", title: "rowPlayback")
                page("/settings/channels", "antenna.radiowaves.left.and.right", title: "rowLiveTv")
                page("/settings/gaming", "gamecontroller", title: "rowGaming")
                page("/settings/couch", "desktopcomputer", title: "rowGamePcs")
                page("/settings/transcoding", "bolt", title: "rowTranscoding")
                page("/settings/library-transcoding", "arrow.triangle.2.circlepath", title: "rowLibraryTranscoding")
                page("/settings/remote", "globe", title: "rowRemote")
                page("/settings/appearance", "paintbrush", title: "rowAppearance")
                page("/settings/wittyrigs", "server.rack", title: "rowWittyRigs")
            }
            ListGroup(title: say("groupMaintenance")) {
                page("/settings/logs", "doc.text.magnifyingglass", title: "rowLogs")
                page("/settings/diagnoser", "stethoscope", title: "rowDiagnoser")
                page("/settings/modules", "puzzlepiece.extension", title: "rowModules")
                page("/settings/backup", "externaldrive", title: "rowBackup")
                page("/settings/repair", "wrench.and.screwdriver", title: "rowRepair")
                NavigationLink(value: Route.page("/settings/reset")) {
                    RowLabel(icon: "arrow.counterclockwise", tint: RowTint.quiet, title: say("rowReset"), destructive: true)
                }
                .rowStyle()
            }
        }
        ListGroup(title: say("groupHelp")) {
            page("/help", "questionmark.circle", RowTint.gold, title: "rowHelp")
            page("/settings/about", "info.circle", title: "rowAboutServer", value: serverVersion)
            page("/legal", "doc.plaintext", title: "rowLegal")
            row(.notices, "text.book.closed", RowTint.quiet, "rowLicences")
            row(.logs, "list.bullet.rectangle", RowTint.quiet, "rowAppLog")
        }
    }

    // MARK: Header and server

    @ViewBuilder private var header: some View {
        let size: CGFloat = metrics.tv ? 200 : (metrics.cardWidth > 124 ? 120 : 88)
        VStack(spacing: 0) {
            AvatarTile(name: user?.shownName ?? "?", size: size)
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
            Button { model.signOut() } label: {
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
                        Text(server.url).font(.wmSecondary).foregroundStyle(palette.textSecondary).lineLimit(1)
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
                        if !model.notice.isEmpty { ProblemLine(model.notice) }
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
        .confirmationDialog(say("signOut"), isPresented: $confirmSignOut, titleVisibility: .hidden) {
            Button(say("signOut"), role: .destructive) { model.signOut() }
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
            AvatarTile(name: previewName, size: 64)
                .frame(maxWidth: .infinity)
                .animation(.easeOut(duration: Tokens.Motion.appear), value: AvatarLook.colour(for: previewName))
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
            .filter { !$0.isEmpty }.joined(separator: " · ")
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

struct SignInTvView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.client) private var client
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var info: PairInfo?
    @State private var chosen: Int64?
    @State private var names: [Int64: String] = [:]
    @State private var busy = false
    @State private var wrongTries = 0
    @State private var problem = ""
    @State private var outcome: String?
    @State private var invite: PairInvite?

    private func look(_ digits: String) {
        guard !busy else { return }
        busy = true
        problem = ""
        Task {
            do {
                let found = try await client.pairInfo(code: digits)
                info = found
                chosen = found.profiles?.first?.id ?? model.user?.id
            } catch {
                wrongTries += 1
                problem = plainWords(Problem.of(error))
                code = ""
            }
            busy = false
        }
    }

    private func answer(approve: Bool) {
        guard !busy, let info else { return }
        busy = true
        problem = ""
        Task {
            do {
                // The code as the TV shows it; the server ignores case, spaces and the dash.
                let digits = info.code ?? code
                if approve, let chosen {
                    try await client.pairApprove(code: digits, userId: chosen)
                    outcome = say("signInTvDone")
                } else {
                    try await client.pairDeny(code: digits)
                    outcome = say("signInTvDenied")
                }
            } catch {
                problem = plainWords(Problem.of(error))
            }
            busy = false
        }
    }

    private func makeInvite() {
        guard !busy, let me = model.user else { return }
        busy = true
        problem = ""
        Task {
            do { invite = try await client.pairInvite(userId: me.id) } catch { problem = plainWords(Problem.of(error)) }
            busy = false
        }
    }

    private func reset() {
        code = ""
        info = nil
        outcome = nil
        invite = nil
        problem = ""
    }

    private func shownName(_ choice: PairChoice) -> String {
        if choice.id == model.user?.id { return model.user?.shownName ?? choice.name }
        return names[choice.id] ?? choice.name
    }

    @ViewBuilder private func card(_ info: PairInfo) -> some View {
        HStack(spacing: Tokens.Space.s3) {
            IconTile(symbol: "tv", hex: RowTint.tv)
            VStack(alignment: .leading, spacing: 2) {
                Text(info.deviceName).font(.wmLabel.weight(.semibold)).foregroundStyle(palette.text)
                let facts = [PlainWords.clean(info.platform ?? "", limit: 40), PlainWords.clean(info.ip ?? "", limit: 64)]
                    .filter { !$0.isEmpty }.joined(separator: " · ")
                if !facts.isEmpty { Text(facts).font(.wmSecondary).foregroundStyle(palette.textSecondary) }
            }
            Spacer(minLength: 0)
        }
        .padding(Tokens.Space.s4)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).fill(palette.panel))
        .accessibilityElement(children: .combine)
        SectionTitle(say("signInTvAs"))
        FlowLayout(spacing: Tokens.Space.s4, rowSpacing: Tokens.Space.s3) {
            ForEach(info.profiles ?? []) { choice in
                let picked = chosen == choice.id
                Button { chosen = choice.id } label: {
                    VStack(spacing: Tokens.Space.s2) {
                        AvatarTile(name: shownName(choice), size: 72)
                            .overlay {
                                if picked {
                                    RoundedRectangle(cornerRadius: 72 * 0.22 + 6, style: .continuous)
                                        .inset(by: -6)
                                        .strokeBorder(palette.accent, lineWidth: 3)
                                }
                            }
                        Text(shownName(choice)).font(.wmLabel).foregroundStyle(picked ? palette.text : palette.textSecondary).lineLimit(1)
                    }
                    .frame(width: 96)
                    .padding(.vertical, Tokens.Space.s2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(shownName(choice))
                .accessibilityAddTraits(picked ? [.isSelected] : [])
            }
        }
        if !problem.isEmpty { ProblemLine(problem) }
        Button { answer(approve: true) } label: { BusyText(say("signInTvApprove"), busy: busy) }
            .action(.primary, wide: true, tall: true)
            .disabled(chosen == nil)
        Button(say("signInTvDeny")) { answer(approve: false) }
            .action(.quiet)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func inviteCard(_ invite: PairInvite) -> some View {
        let minutes = max(1, (invite.expiresInSec ?? 600) / 60)
        Text(invite.code)
            .font(.system(size: 44, weight: .bold, design: .monospaced))
            .kerning(8)
            .foregroundStyle(palette.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Tokens.Space.s6)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).fill(palette.panel))
            .accessibilityLabel(invite.code.map(String.init).joined(separator: " "))
        Secondary(say("signInTvInviteHint").replacingOccurrences(of: "{minutes}", with: "\(minutes)"))
        Button(say("back")) { reset() }.action(.secondary, wide: true, tall: true)
    }

    var body: some View {
        SettingsScreen(title: say("rowSignInTv"), detail: info == nil && invite == nil && outcome == nil ? say("signInTvHint") : "") {
            if model.user?.isAdult == false {
                Secondary(say("signInTvAdultOnly"))
            } else if let outcome {
                OutcomeLine(words: outcome, good: outcome == say("signInTvDone"))
                Button(say("signInTvAnother")) { reset() }.action(.secondary, wide: true, tall: true)
                Button(say("back")) { dismiss() }.action(.primary, wide: true, tall: true)
            } else if let invite {
                inviteCard(invite)
            } else if let info {
                card(info)
            } else {
                LetterCodeEntry(code: $code, checking: busy, wrongTries: wrongTries, onComplete: look)
                if !problem.isEmpty { ProblemLine(problem) }
                Button(say("signInTvInvite")) { makeInvite() }
                    .action(.quiet)
                    .frame(maxWidth: .infinity)
            }
        }
        .animation(.easeOut(duration: Tokens.Motion.appear), value: info)
        .task {
            // The pairing answer has usernames only; the profile list has the names people chose.
            if let listed = try? await client.profiles().profiles {
                names = Dictionary(listed.map { ($0.id, $0.shownName) }, uniquingKeysWith: { first, _ in first })
            }
        }
    }
}

// MARK: - Theme

struct ThemeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette

    /// One theme on offer: the server's list when there is one, the built-ins otherwise.
    struct Choice: Identifiable {
        let id: String
        let name: String
        let bg, surface, accent: String
        let webOnly: Bool
    }

    static func choices(_ list: ThemeList?) -> [Choice] {
        if let themes = list?.themes, !themes.isEmpty {
            return themes.map { t in
                Choice(id: t.id, name: t.shownName, bg: t.preview?.bg ?? "#0f1115", surface: t.preview?.surface ?? "#1f232c",
                       accent: t.preview?.accent ?? "#7955ff", webOnly: t.webOnly == true)
            }
        }
        return SharedData.themes.map { t in
            Choice(id: t.id, name: t.name ?? t.id, bg: t.colours.background, surface: t.colours.card, accent: t.colours.accent, webOnly: false)
        }
    }

    static func name(of choice: String, server: String?, list: ThemeList? = nil) -> String {
        func named(_ id: String?) -> String? { choices(list).first { $0.id == id }?.name ?? SharedData.exactTheme(id)?.name }
        switch choice {
        case "": return named(server) ?? say("themeServer")
        case "auto": return say("themeAutomatic")
        case "custom": return say("themeMadeByYou")
        default: return named(choice) ?? choice
        }
    }

    private func pick(_ id: String) {
        withAnimation(.easeInOut(duration: 0.2)) { model.chooseTheme(id) }
    }

    @ViewBuilder private func swatch(bg: String, surface: String, accent: String) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color(hex: bg))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color(hex: surface)).frame(height: 10)
            }
            .overlay(alignment: .topTrailing) {
                Circle().fill(Color(hex: accent)).frame(width: 9, height: 9).padding(5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
    }

    private func check(_ id: String) -> some View {
        Image(systemName: "checkmark")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(palette.accentText)
            .opacity(model.themeChoice == id ? 1 : 0)
            .accessibilityHidden(true)
    }

    private func row(_ id: String, icon: String, tint: String, title: String, detail: String) -> some View {
        Button { pick(id) } label: {
            HStack(spacing: 0) {
                RowLabel(icon: icon, tint: tint, title: title, detail: detail, chevron: false)
                check(id).padding(.trailing, Tokens.Space.s4)
            }
        }
        .rowStyle()
        .accessibilityAddTraits(model.themeChoice == id ? [.isSelected] : [])
    }

    var body: some View {
        SettingsScreen(title: say("rowTheme"), detail: say("themeHint")) {
            ListGroup(title: "") {
                row("auto", icon: "circle.lefthalf.filled", tint: RowTint.teal, title: say("themeAutomatic"), detail: say("themeAutomaticHint"))
                row("", icon: "server.rack", tint: RowTint.quiet, title: say("themeServer"),
                    detail: Self.name(of: model.themeId ?? "default", server: nil, list: model.themeList))
                if model.customTheme != nil {
                    row("custom", icon: "paintbrush.pointed", tint: RowTint.tv, title: say("themeMadeByYou"),
                        detail: model.customTheme?.name ?? "")
                }
            }
            ListGroup(title: "", footer: Self.choices(model.themeList).contains(where: \.webOnly) ? say("themeWebOnly") : "") {
                ForEach(Self.choices(model.themeList)) { theme in
                    Button { pick(theme.id) } label: {
                        HStack(spacing: Tokens.Space.s3) {
                            swatch(bg: theme.bg, surface: theme.surface, accent: theme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(theme.name).font(.subheadline).foregroundStyle(palette.text)
                                if theme.webOnly {
                                    Text(say("themeLooksPlainer")).font(.wmSecondary).foregroundStyle(palette.textSecondary)
                                }
                            }
                            Spacer(minLength: 0)
                            check(theme.id)
                        }
                        .padding(.horizontal, Tokens.Space.s4)
                        .frame(minHeight: 52)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(palette.border).frame(height: 0.5).padding(.leading, 56)
                        }
                        .contentShape(Rectangle())
                    }
                    .rowStyle()
                    .accessibilityLabel(theme.name)
                    .accessibilityAddTraits(model.themeChoice == theme.id ? [.isSelected] : [])
                }
            }
        }
        .task { await model.loadThemes() }
    }
}
