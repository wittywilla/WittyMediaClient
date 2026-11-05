import SwiftUI
import WittyKit

// Finding a server and signing in: the "Signing in" section of docs/APP-DESIGN.md. One column with the
// glow behind it on a phone or tablet; words on the left and actions on the right on a TV. The Android
// app draws the same screens from the same page.

/// The legal note every connect screen ends with.
private struct LegalNote: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics

    var body: some View {
        Text(say("legalConnect"))
            .font(.caption)
            .foregroundStyle(palette.textHint)
            .multilineTextAlignment(metrics.tv ? .leading : .center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Tokens.Space.s2)
    }
}

// MARK: - 1 and 2: choose your server, and its address

struct ConnectView: View {
    private enum Spot: Hashable {
        case found(String)
        case recent(String)
        case enterAddress
    }

    @EnvironmentObject private var model: AppModel
    @Environment(\.metrics) private var metrics
    let initialMessage: String
    @State private var address = ""
    @State private var error = ""
    @State private var busy = false
    @State private var connectingTo = ""
    @State private var showForm = false
    @State private var found: [FoundServer] = []
    @State private var finder: ServerFinder?
    @State private var searchedLong = false
    @State private var refused = false
    @State private var moved = false
    @State private var offered: Spot?
    @State private var lastSpot: Spot?
    @FocusState private var spot: Spot?
    @State private var wantField = false
    @Namespace private var scope

    /// A server that moves to https gets one more go, at the address it asked for.
    private func connect(_ url: String, movedOnce: Bool = false) async {
        guard !busy || movedOnce else { return }
        busy = true
        connectingTo = url
        error = ""
        var problem: String?
        switch await WittyClient.probe(url) {
        case .found(let status):
            problem = await model.arrive(url: url, status: status)
        case .failed(let reason):
            problem = reasonText(reason)
        case .moved(let safer):
            if !movedOnce {
                await connect(safer, movedOnce: true)
                return
            }
            problem = say("errNotServer")
        }
        busy = false
        connectingTo = ""
        if let problem {
            error = problem
            address = url
            showForm = true
        }
    }

    private func submit() {
        switch Address.normalize(address) {
        case .ok(let url): Task { await connect(url) }
        case .bad(let reason): error = reasonText(reason)
        }
    }

    private func closeForm() {
        showForm = false
        error = ""
        // Back puts focus where it was.
        DispatchQueue.main.async { spot = lastSpot ?? .enterAddress }
    }

    /// The first server found takes focus, until the person has moved themselves. The
    /// row only exists after this update, so the focus has to wait for the next one.
    private func show(_ servers: [FoundServer]) {
        found = servers
        guard !moved, let first = servers.first else { return }
        let target = Spot.found(first.id)
        offered = target
        DispatchQueue.main.async { spot = target }
    }

    /// The system picking the first thing to focus isn't the person moving.
    private func focusChanged(_ new: Spot?) {
        if lastSpot != nil, new != nil, new != offered { moved = true }
        if new != nil { lastSpot = new }
    }

    private var searching: Bool { found.isEmpty && !searchedLong && !refused }

    @ViewBuilder private var findWords: some View {
        BrandLockup()
        SignInHeading(title: say("findTitle"), detail: say("findSubtitle"), display: true)
        if !error.isEmpty { ProblemLine(error) }
    }

    @ViewBuilder private func findActions(_ others: [SavedServer]) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
            SearchingCaption(words: say("foundServers"), searching: searching)
            if found.isEmpty {
                NoteCard(words: refused ? say("findNotSupported") : searchedLong ? say("findNone") : say("findSearching"),
                         busy: searching, icon: refused ? "wifi.slash" : "magnifyingglass")
            }
            ForEach(found) { server in
                ServerCard(name: server.name, url: server.url, lastUsed: server.url == model.lastUsedURL,
                           connecting: connectingTo == server.url) { Task { await connect(server.url) } }
                    .focused($spot, equals: .found(server.id))
            }
            if !others.isEmpty {
                SearchingCaption(words: say("recentServers")).padding(.top, Tokens.Space.s2)
                ForEach(others) { server in
                    ServerCard(name: server.name, url: server.url, lastUsed: server.url == model.lastUsedURL,
                               connecting: connectingTo == server.url) { Task { await connect(server.url) } }
                        .focused($spot, equals: .recent(server.url))
                }
            }
        }
        Button {
            showForm = true
            error = ""
        } label: {
            Label(say("enterAddress"), systemImage: "link")
        }
        .action(found.isEmpty && others.isEmpty ? .primary : .secondary, wide: true, tall: true)
        .focused($spot, equals: .enterAddress)
        .firstFocus(in: scope, when: found.isEmpty)
        .padding(.top, Tokens.Space.s2)
        LegalNote()
    }

    @ViewBuilder private var addressWords: some View {
        SignInHeading(title: say("addressTitle"), detail: say("addressHint"))
    }

    @ViewBuilder private var addressActions: some View {
        OutlinedField(label: say("addressLabel"), text: $address, kind: .address, icon: "link", request: $wantField, onSubmit: submit)
        if !error.isEmpty { ProblemLine(error) }
        // Never disabled: on a TV that would take the focus away from under the person.
        Button { if !busy { submit() } } label: { BusyText(say("connect"), busy: busy) }
            .action(.primary, wide: true, tall: true)
        LegalNote()
    }

    var body: some View {
        let others = uniqued(model.recent).filter { saved in !found.contains { $0.url == saved.url || $0.id == saved.serverId } }
        Group {
            if showForm {
                SignInLayout(back: closeForm) { addressWords } actions: { addressActions }
                    .task { wantField = true }
            } else {
                SignInLayout { findWords } actions: { findActions(others) }
            }
        }
        .focusRoot(scope)
        .onChange(of: spot) { focusChanged($0) }
        .onRemoteBack(showForm ? { closeForm() } : nil)
        .onAppear {
            if error.isEmpty { error = initialMessage }
            // Only looks while this screen is open.
            let looking = ServerFinder(onChange: { show($0) }, onRefused: { refused = true })
            looking.start()
            finder = looking
        }
        .onDisappear {
            finder?.stop()
            finder = nil
        }
        .task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            searchedLong = true
        }
    }
}

/// Which server a code or a sign-in goes to: its mark and name in a quiet pill.
private struct ServerPill: View {
    @Environment(\.palette) private var palette
    let name: String

    var body: some View {
        HStack(spacing: Tokens.Space.s2) {
            BrandMark(size: 24)
            Text(name).font(.wmLabel).foregroundStyle(palette.text).lineLimit(1)
        }
        .padding(.leading, Tokens.Space.s1)
        .padding(.trailing, Tokens.Space.s3)
        .padding(.vertical, Tokens.Space.s1)
        .background(Capsule().fill(palette.panel))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 7: enter the security code

/// A new server is opened with a six-digit code from someone already signed in. See
/// docs/CLIENT-API.md, "The code is typed on the device".
struct CodeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let server: SavedServer
    let fromSignIn: Bool
    @State private var entry = CodeEntry()
    @State private var problem = ""
    @State private var wrongTries = 0
    @Namespace private var scope

    private func press(_ digit: Character) {
        let before = entry
        entry.type(digit)
        guard entry != before else { return }
        problem = ""
        announce("\(entry.digits.count) \(say("codeEntered"))")
        guard entry.isComplete else { return }
        entry.busy = true
        let code = entry.digits
        Task {
            if let failed = await model.redeem(server, code: code) {
                entry = CodeEntry()
                problem = failed
                wrongTries += 1
            }
        }
    }

    private func back() {
        model.stage = fromSignIn ? .signIn(.usual) : .connect(message: "")
    }

    @ViewBuilder private var codeLinks: some View {
        Button(say("usePassword")) { model.signIn(to: server, way: .password) }.action(.quiet).fixedSize()
        Button(say("showCodeInstead")) { model.signIn(to: server, way: .shownCode) }.action(.quiet).fixedSize()
    }

    var body: some View {
        SignInLayout(back: back) {
            SignInHeading(title: say("codeTitle"), detail: say("codeHint"))
            ServerPill(name: server.name)
            CodeBoxes(digits: entry.digits, checking: entry.busy, wrongTries: wrongTries)
            // Room is kept for the message, or the keys would move under a finger as it comes and goes.
            Group {
                if entry.busy {
                    HStack(spacing: Tokens.Space.s2) { ProgressView(); Secondary(say("connecting")) }
                } else if !problem.isEmpty {
                    ProblemLine(problem)
                }
            }
            .frame(minHeight: 24)
        } actions: {
            NumberPad(onDigit: press, onDelete: { entry.erase() }, scope: scope)
            // Side by side where they fit on one line each, one above the other where they don't:
            // a link is never broken over two lines.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Tokens.Space.s6) { codeLinks }
                VStack(alignment: metrics.tv ? .leading : .center, spacing: 0) { codeLinks }
            }
            .frame(maxWidth: .infinity, alignment: metrics.tv ? .leading : .center)
            .remoteSection()
            (Text("\(say("fingerprintLabel")): ") + Text(server.fingerprint).font(.caption.monospaced()))
                .font(.caption)
                .foregroundStyle(palette.textHint)
        }
        .focusRoot(scope)
        .onRemoteBack(back)
    }
}

// MARK: - 3: this isn't the server you used before

/// Another machine is answering for a server we know. Only the person can decide, so
/// the safe choice comes first and has focus, and nothing has been sent to it.
struct MismatchView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    let server: SavedServer
    @State private var problem = ""
    @State private var busy = false
    @FocusState private var onSafeChoice: Bool

    private func back() {
        model.stage = .connect(message: "")
    }

    var body: some View {
        SignInLayout {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(palette.danger)
                .frame(width: 64, height: 64)
                .background(Circle().fill(palette.danger.opacity(0.16)))
                .accessibilityHidden(true)
            SignInHeading(title: say("identityTitle"), detail: say("identityHint"))
            VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                Text(server.url).font(.wmLabel).foregroundStyle(palette.text)
                Text("\(say("fingerprintLabel")): \(server.fingerprint)").font(.wmSecondary.monospaced()).foregroundStyle(palette.textSecondary)
            }
            .padding(Tokens.Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).fill(palette.panel))
        } actions: {
            if !problem.isEmpty { ProblemLine(problem) }
            Button(say("back"), action: back).action(.primary, wide: true, tall: true).focused($onSafeChoice)
            Button {
                guard !busy else { return }
                busy = true
                Task {
                    problem = await model.trust(server) ?? ""
                    busy = false
                }
            } label: {
                BusyText(say("identityTrust"), busy: busy)
            }
            .action(.destructive, wide: true, tall: true)
        }
        .onRemoteBack(back)
        .task { onSafeChoice = true }
        .onAppear { announce(say("identityTitle")) }
    }
}

// MARK: - 8: sign in with a code

/// The TV shows a code; someone already signed in on a phone or computer approves
/// it, so nobody has to type a password with a remote. See docs/CLIENT-API.md.
private struct PairPanel: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let onUsePassword: () -> Void
    var onBack: (() -> Void)?
    @State private var round = 0
    @State private var code = ""
    @State private var approveAt = ""
    @State private var qr: CGImage?
    @State private var problem = ""
    @State private var starting = true
    /// The server has handed this device all the codes it will for now: a password is the way in.
    @State private var limited = false
    @Namespace private var scope
    /// The screen's main action, which takes the focus when an answer from the server changes it.
    @FocusState private var mainAction: Bool

    private func run() async {
        code = ""
        problem = ""
        limited = false
        qr = nil
        starting = true
        defer { starting = false }
        let start: PairStart
        do {
            start = try await model.client.pairStart(device: model.deviceName, platform: model.platformName)
        } catch let error as APIError where error.status == 429 {
            limited = true
            problem = say("pairBusy")
            return
        } catch {
            problem = plainWords(Problem.of(error))
            return
        }
        code = start.code
        approveAt = start.approveAddress(base: model.client.base) ?? model.client.base
        qr = QRImage.make(for: approveAt)
        starting = false
        var wait = max(start.intervalSec ?? 3, 1)
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: UInt64(wait) * 1_000_000_000)
                let poll = try await model.client.pairPoll(deviceSecret: start.deviceSecret)
                problem = ""
                switch poll.status {
                case "approved":
                    if let token = poll.token {
                        model.signedIn(token: token)
                    } else {
                        problem = say("pairExpired")
                        code = ""
                    }
                    return
                case "denied":
                    problem = say("pairDenied"); code = ""; return
                case "expired":
                    problem = say("pairExpired"); code = ""; return
                case "slow-down":
                    wait = max(poll.intervalSec ?? wait, wait) + 1
                default:
                    break
                }
            } catch {
                let trouble = Problem.of(error)
                if trouble == .cancelled { return }
                // The code stays good through a lost connection, so this keeps trying until it expires.
                problem = plainWords(trouble)
            }
        }
    }

    var body: some View {
        SignInLayout(back: onBack) {
            BrandLockup()
            SignInHeading(title: say("pairTitle"), detail: code.isEmpty ? "" : say("pairHint"))
            if !code.isEmpty {
                Text(approveAt)
                    .font(.wmLabel)
                    .foregroundStyle(palette.accentText)
                    .multilineTextAlignment(metrics.tv ? .leading : .center)
                    .textSelectionIfAvailable()
                Text(code)
                    .font(.system(size: metrics.tv ? 72 : 40, weight: .bold, design: .monospaced))
                    .kerning(metrics.tv ? 16 : 8)
                    .foregroundStyle(palette.text)
                    .padding(.horizontal, Tokens.Space.s6)
                    .padding(.vertical, Tokens.Space.s3)
                    .background(RoundedRectangle(cornerRadius: Tokens.Radius.lg, style: .continuous).fill(palette.panel))
                    .accessibilityLabel(code.map(String.init).joined(separator: " "))
                HStack(spacing: Tokens.Space.s2) {
                    ProgressView()
                    Secondary(say("pairWaiting"))
                }
            } else if starting && problem.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 80)
            }
            if !problem.isEmpty { ProblemLine(problem) }
        } actions: {
            if !code.isEmpty, let qr {
                QRCard(image: qr, caption: say("pairScan"))
                    .frame(maxWidth: .infinity, alignment: metrics.tv ? .leading : .center)
            }
            if code.isEmpty && !problem.isEmpty {
                if limited {
                    Button(say("usePassword"), action: onUsePassword).action(.primary, wide: true, tall: true).focused($mainAction)
                } else {
                    Button(say("pairNew")) { round += 1 }.action(.primary, wide: true, tall: true).focused($mainAction)
                }
            }
            FlowLayout(spacing: Tokens.Space.s2, centred: !metrics.tv) {
                if model.canTypeCode { Button(say("codeTitle")) { model.askForCode() }.action(.quiet) }
                if !limited {
                    Button(say("usePassword"), action: onUsePassword).action(.quiet).firstFocus(in: scope, when: !code.isEmpty)
                }
                Button(say("changeServer")) { model.changeServer() }.action(.quiet)
            }
            .remoteSection()
        }
        .focusRoot(scope)
        .task(id: round) { await run() }
        // When the server says no, the remote's focus goes to what to do about it, once it's on screen.
        .onChange(of: problem.isEmpty) { empty in
            guard !empty, code.isEmpty else { return }
            DispatchQueue.main.async { mainAction = true }
        }
    }
}

extension View {
    /// Words that can be copied, where there's a way to copy them.
    @ViewBuilder func textSelectionIfAvailable() -> some View {
        #if os(tvOS)
        self
        #else
        self.textSelection(.enabled)
        #endif
    }
}

// MARK: - 4, 5 and 6: who's watching, the password, and the sign-in form

struct SignInView: View {
    private enum Step: Equatable {
        case people
        case password(Profile)
        case form
    }

    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @State private var useCode: Bool
    @State private var profiles: Profiles?
    @State private var step: Step = .people
    @State private var name = ""
    @State private var password = ""
    @State private var error = ""
    @State private var busy = false
    @State private var wantPassword = false
    @State private var wantName = false
    /// The account asked for the authenticator's code: the same name and password go again with it.
    @State private var needsCode = false
    @State private var twoFactorCode = ""
    @State private var wrongCodes = 0
    /// The phone with the authenticator is lost, so one of the saved recovery codes goes instead.
    @State private var useRecovery = false
    @State private var recoveryCode = ""
    @State private var wantRecovery = false
    /// The last password was refused, and nothing new has been typed since.
    @State private var refused = false
    @State private var wrongPasswords = 0
    @State private var help: URL?
    @Namespace private var scope

    init(way: SignInWay) {
        switch way {
        case .shownCode:
            _useCode = State(initialValue: true)
        case .password:
            _useCode = State(initialValue: false)
        case .usual:
            #if os(tvOS)
            _useCode = State(initialValue: true) // on a TV the code comes first
            #else
            _useCode = State(initialValue: false) // everywhere else a keyboard is at hand
            #endif
        }
    }

    private var people: [Profile] { uniqued(profiles?.profiles ?? []) }
    private var showsPeople: Bool { profiles?.style == "profiles" && !people.isEmpty }

    private func login(_ who: String, _ secret: String, code: String = "") {
        guard !busy else { return }
        busy = true
        error = ""
        Task {
            switch await model.passwordSignIn(name: who, password: secret, code: code) {
            case .signedIn:
                break
            case .needsCode(let words):
                let wrongCode = needsCode && !words.isEmpty
                if wrongCode { wrongCodes += 1 }
                needsCode = true
                twoFactorCode = ""
                if wrongCode && useRecovery { recoveryCode = ""; wantRecovery = true }
                error = !wrongCode ? "" : say(useRecovery ? "errWrongRecovery" : "errWrongCode")
            case .wrong:
                // Cleared and asked for again, as every phone does: no one fixes a password they can't see.
                error = say(step == .form ? "errWrongNameOrPassword" : "errWrongPassword")
                password = ""
                refused = true
                wrongPasswords += 1
                wantPassword = true
            case .failed(let words):
                error = words
            }
            busy = false
        }
    }

    private func choose(_ profile: Profile) {
        error = ""
        refused = false
        if profile.hasPassword == false {
            login(profile.name, "")
        } else {
            password = ""
            step = .password(profile)
            wantPassword = true
        }
    }

    /// One step back at a time, and never out of the app from the middle of signing in.
    private func back() {
        error = ""
        if needsCode {
            needsCode = false
            twoFactorCode = ""
            useRecovery = false
            recoveryCode = ""
        } else if case .password = step {
            step = showsPeople ? .people : .form
            password = ""
            refused = false
        } else if step == .form, showsPeople {
            step = .people
        } else if useCode, showsPeople {
            useCode = false
        } else {
            model.changeServer()
        }
    }

    private var forgotURL: URL? { model.client.mediaURL("/help/accounts#if-you-forget-your-password") }

    private var serverName: String { model.current?.name ?? "WittyMediaServer" }

    /// The other ways in, and which server this is, under whatever the screen is mainly for. On a TV's
    /// Who's watching, which is centred, they're one centred row, as on Android TV.
    @ViewBuilder private func otherWays(centred: Bool = false) -> some View {
        let middle = centred || !metrics.tv
        let ways = Group {
            if step == .people {
                Button(say("otherAccount")) { step = .form; wantName = true }.action(.quiet)
            }
            Button(say("useCode")) { useCode = true }.action(.quiet)
            if model.canTypeCode { Button(say("codeTitle")) { model.askForCode() }.action(.quiet) }
        }
        Group {
            if metrics.tv && centred {
                HStack(spacing: Tokens.Space.s6) { ways }
            } else {
                VStack(alignment: middle ? .center : .leading, spacing: 0) { ways }
            }
        }
        .frame(maxWidth: .infinity, alignment: middle ? .center : .leading)
        .remoteSection()
        HStack(spacing: Tokens.Space.s1) {
            Image(systemName: "server.rack").font(.caption).foregroundStyle(palette.textHint)
            Text(serverName).font(.wmSecondary).foregroundStyle(palette.textSecondary).lineLimit(1)
            Button(say("changeServer")) { model.changeServer() }.action(.quiet)
        }
        .frame(maxWidth: .infinity, alignment: middle ? .center : .leading)
    }

    /// 4: everyone on this server, as faces.
    @ViewBuilder private var whoIsWatching: some View {
        let size: CGFloat = metrics.tv ? 200 : (metrics.cardWidth > 124 ? 140 : 104)
        let page = VStack(spacing: metrics.tv ? Tokens.Space.s10 : Tokens.Space.s6) {
            BrandLockup()
            SignInHeading(title: say("whoTitle"), display: true, centred: true)
            if !error.isEmpty { ProblemLine(error) }
            FlowLayout(spacing: metrics.tv ? 48 : 24, rowSpacing: 28, centred: true) {
                ForEach(Array(people.enumerated()), id: \.element.id) { index, profile in
                    ProfileTile(profile: profile, avatarSize: size) { choose(profile) }
                        .firstFocus(in: scope, when: index == 0)
                        .disabled(busy)
                }
            }
            .remoteSection()
            otherWays(centred: true)
        }
        if metrics.tv {
            ZStack {
                palette.background.ignoresSafeArea()
                SignInGlow()
                page.padding(.horizontal, metrics.gutter).frame(maxWidth: .infinity)
            }
        } else {
            SignInPage { page.frame(maxWidth: .infinity) }
        }
    }

    /// 5: one person's password, or the authenticator's code after it.
    @ViewBuilder private func passwordStep(_ profile: Profile) -> some View {
        SignInLayout(back: back) {
            VStack(spacing: Tokens.Space.s2) {
                AvatarTile(name: profile.shownName, size: metrics.tv ? 200 : 120)
                Text(profile.shownName).font(.wmHero).foregroundStyle(palette.text).lineLimit(1)
                if profile.showsUsername {
                    Text("@\(profile.name)").font(.wmSecondary).foregroundStyle(palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: metrics.tv ? .leading : .center)
            .accessibilityElement(children: .combine)
            SignInHeading(title: needsCode ? twoFactorTitle : "", detail: needsCode ? twoFactorHint : say("passwordHint"))
        } actions: {
            if needsCode {
                twoFactorEntry { login(profile.name, password, code: $0) }
            } else {
                OutlinedField(label: say("passwordLabel"), text: $password, kind: .password, icon: "lock",
                              request: $wantPassword, invalid: refused) {
                    login(profile.name, password)
                }
                .shake(wrongPasswords)
                if !error.isEmpty { ProblemLine(error) }
                Button { login(profile.name, password) } label: { BusyText(say("signIn"), busy: busy) }
                    .action(.primary, wide: true, tall: true)
                Button(say("forgotPassword")) { help = forgotURL }.action(.quiet)
                    .frame(maxWidth: .infinity, alignment: metrics.tv ? .leading : .center)
            }
        }
    }

    /// 6: any account, by name and password.
    @ViewBuilder private var form: some View {
        SignInLayout(back: showsPeople ? back : { model.changeServer() }) {
            BrandLockup()
            SignInHeading(title: needsCode ? twoFactorTitle : say("signInTitle"), detail: needsCode ? twoFactorHint : "")
        } actions: {
            if needsCode {
                twoFactorEntry { login(name, password, code: $0) }
            } else {
                OutlinedField(label: say("usernameLabel"), text: $name, kind: .name, icon: "person",
                              request: $wantName, invalid: refused) { wantPassword = true }
                OutlinedField(label: say("passwordLabel"), text: $password, kind: .password, icon: "lock",
                              request: $wantPassword, invalid: refused) {
                    login(name, password)
                }
                .shake(wrongPasswords)
                if !error.isEmpty { ProblemLine(error) }
                Button { login(name, password) } label: { BusyText(say("signIn"), busy: busy) }
                    .action(.primary, wide: true, tall: true)
                otherWays()
            }
        }
    }

    /// The authenticator's six digits: the system's number keyboard on a phone, which can fill in a
    /// code it was sent; the number pad on a TV.
    private var twoFactorTitle: String { say(useRecovery ? "recoveryTitle" : "twoFactorTitle") }
    private var twoFactorHint: String { say(useRecovery ? "recoveryHint" : "twoFactorHint") }

    @ViewBuilder private func twoFactorEntry(_ send: @escaping (String) -> Void) -> some View {
        if useRecovery {
            let typed = recoveryCode.trimmingCharacters(in: .whitespaces)
            OutlinedField(label: say("recoveryLabel"), text: $recoveryCode, icon: "key", request: $wantRecovery,
                          invalid: !error.isEmpty) {
                if !typed.isEmpty { send(typed) }
            }
            .shake(wrongCodes)
            if !error.isEmpty { ProblemLine(error) }
            Button { send(typed) } label: { BusyText(say("signIn"), busy: busy) }
                .action(.primary, wide: true, tall: true)
                .disabled(typed.isEmpty || busy)
        } else {
            CodeBoxes(digits: twoFactorCode, checking: busy, wrongTries: wrongCodes)
                .frame(maxWidth: .infinity, alignment: metrics.tv ? .leading : .center)
            #if os(tvOS)
            NumberPad(onDigit: { digit in
                guard twoFactorCode.count < 6 else { return }
                twoFactorCode.append(digit)
                if twoFactorCode.count == 6 { send(twoFactorCode) }
            }, onDelete: { if !twoFactorCode.isEmpty { twoFactorCode.removeLast() } }, scope: scope)
            #else
            TwoFactorKeyboard(code: $twoFactorCode) { send($0) }
            #endif
            if !error.isEmpty { ProblemLine(error) }
        }
        Button(say(useRecovery ? "useAuthenticatorCode" : "useRecoveryCode")) {
            error = ""
            twoFactorCode = ""
            useRecovery.toggle()
            if useRecovery { wantRecovery = true }
        }
        .action(.quiet)
        .frame(maxWidth: .infinity, alignment: metrics.tv ? .leading : .center)
    }

    var body: some View {
        Group {
            if useCode {
                PairPanel(onUsePassword: { useCode = false }, onBack: showsPeople ? { useCode = false } : nil)
            } else if profiles == nil {
                ZStack {
                    palette.background.ignoresSafeArea()
                    SignInGlow()
                    ProgressView()
                }
            } else if case .password(let profile) = step {
                passwordStep(profile)
            } else if step == .form || !showsPeople {
                form
            } else {
                whoIsWatching
            }
        }
        .focusRoot(scope)
        .onRemoteBack(back)
        .onChange(of: password) { typed in
            // Typing again takes back the red: the refusal was about the last try.
            if refused && !typed.isEmpty { refused = false; error = "" }
        }
        .sheet(item: $help) { HelpSheet(url: $0) }
        .task {
            profiles = (try? await model.client.profiles()) ?? Profiles(style: "classic", profiles: nil)
            if !showsPeople { wantName = true }
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

#if !os(tvOS)
/// The six digits typed on the system's number keyboard, shown in the boxes above. The box itself
/// is out of sight; it's what the keyboard, and a code the system offers to fill in, type into.
private struct TwoFactorKeyboard: View {
    @Binding var code: String
    let onComplete: (String) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $code)
            #if os(iOS) || os(visionOS)
            .keyboardType(.numberPad)
            #endif
            .textContentType(.oneTimeCode)
            .focused($focused)
            .frame(width: 1, height: 1)
            .opacity(0.02)
            .accessibilityLabel(say("twoFactorTitle"))
            .onChange(of: code) { typed in
                let digits = String(typed.filter(\.isNumber).prefix(6))
                if digits != typed { code = digits }
                if digits.count == 6 { onComplete(digits) }
            }
            .task { focused = true }
    }
}
#endif
