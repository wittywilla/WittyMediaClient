// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// Finding a server and signing in: the "Signing in" section of docs/APP-DESIGN.md. One column with the
// glow behind it on a phone or tablet; words on the left and actions on the right on a TV. The Android
// app draws the same screens from the same page.

/// The legal note every connect screen ends with.
struct LegalNote: View {
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
        case joinAway
        case manage
    }

    @EnvironmentObject private var model: AppModel
    @Environment(\.metrics) private var metrics
    @Environment(\.palette) private var palette
    let initialMessage: String
    @State private var address = ""
    @State private var error = ""
    @State private var busy = false
    @State private var connectingTo = ""
    @State private var showForm = false
    /// The form is for an invite link (Join with a link or code), not an address.
    @State private var formForInvite = false
    @State private var scanning = false
    @State private var showJoin = false
    @State private var showManage = false
    /// A server that hasn't been set up: its address, for the screen that says to finish in a browser.
    @State private var notSetUp: String?
    @State private var found: [FoundServer] = []
    @State private var finder: ServerFinder?
    @State private var searchedLong = false
    @State private var refused = false
    @State private var moved = false
    @State private var offered: Spot?
    @State private var lastSpot: Spot?
    @FocusState private var spot: Spot?
    @State private var wantField = false
    @AppStorage(ServerOrder.key) private var savedFirst = true
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
            // Not there: this device isn't at home. The other way to it, if it has one.
            if reason == "unreachable", let away = await model.arriveFromAway(url) {
                problem = away
            } else if reason == "not-set-up" {
                // Setup is web-only: the app doesn't connect until it is done, and says where to finish it.
                notSetUp = (url.hasSuffix("/") ? String(url.dropLast()) : url) + "/setup"
            } else {
                problem = reasonText(reason)
            }
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

    /// An invite link from the server's Remote Access page, in place of an address.
    private func join(_ invite: PeerConnect.Invite) async {
        guard !busy else { return }
        busy = true
        error = ""
        let problem = await model.join(invite)
        busy = false
        if let problem { error = problem }
    }

    private func submit() {
        let typed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.lowercased().hasPrefix("\(DeepLink.scheme)://p2p/") {
            if let invite = PeerConnect.invite(from: typed) {
                Task { await join(invite) }
            } else {
                error = say("errInvite")
            }
            return
        }
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

    private func closeJoin() {
        showJoin = false
        DispatchQueue.main.async { spot = .joinAway }
    }

    private func closeManage() {
        showManage = false
        let any = !model.recent.isEmpty
        DispatchQueue.main.async { spot = any ? .manage : .enterAddress }
    }

    /// A remembered server was removed: focus goes to the next card, else the one before, else Enter an address.
    private func removed(_ server: SavedServer, from list: [SavedServer]) {
        let next: Spot = ServerBook.focusAfter(removing: server.url, in: list.map(\.url)).map { .recent($0) } ?? .enterAddress
        // On a TV the question that was asked first is still leaving the screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + (metrics.tv ? 0.35 : 0)) { spot = next }
    }

    /// The first server found takes focus, until the person has moved themselves. The
    /// row only exists after this update, so the focus has to wait for the next one.
    private func show(_ servers: [FoundServer]) {
        found = Discovery.keepOrder(shown: found.map(\.id), now: servers)
        // Saved servers on top keep the focus on the last one used: a server turning up below doesn't take it.
        guard !moved, !(savedFirst && !model.recent.isEmpty), let first = found.first else { return }
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

    /// Servers found on the network that haven't been added.
    private func foundOnly(_ added: [SavedServer]) -> [FoundServer] {
        found.filter { server in !added.contains { $0.url == server.url || (!$0.serverId.isEmpty && $0.serverId == server.id) } }
    }

    /// Servers found on the network that this device hasn't used: where each one is, and nothing else until it's added.
    /// Servers found on the network that this device hasn't used: where each one is, and Connect.
    @ViewBuilder private func foundSection(_ others: [SavedServer]) -> some View {
        ConnectSectionLabel(title: "On this network")
        VStack(spacing: Tokens.Space.s3) {
            if found.isEmpty {
                HStack(spacing: Tokens.Space.s2) {
                    if searching { ProgressView().tint(palette.textSecondary) }
                    DesignNote(text: refused ? say("findNotSupported") : searchedLong ? say("findNone") : say("findSearching"))
                }
                .accessibilityElement(children: .combine)
            }
            ForEach(foundOnly(others)) { server in
                ServerTile(name: ServerCard.place(server.url), line: say("foundOnNetwork"), reach: .found,
                           connecting: connectingTo == server.url) { Task { await connect(server.url) } }
                    .focused($spot, equals: .found(server.id))
                    .accessibilityIdentifier("connect.found." + server.id)
            }
        }
        .remoteSection()
    }

    /// How a saved server is reached now: peer to peer from anywhere, on this network, or neither just now.
    private func reach(_ server: SavedServer) -> ServerReach {
        if PeerInfo.isPlaceholder(server.url) { return .peer }
        let onNetwork = found.contains { $0.url == server.url || (!server.serverId.isEmpty && $0.id == server.serverId) }
        return onNetwork ? .home : .saved
    }

    /// A saved server's line: where it is and when it was last reached.
    private func line(_ server: SavedServer, _ how: ServerReach) -> String {
        if how == .peer { return "From anywhere · " + ServerWords.reached(server) }
        let place = ServerCard.place(ServerBook.address(of: server, found: found))
        return ServerBook.isStale(server, now: ServerBook.now()) ? "\(place) · \(say("staleServer"))" : "\(place) · \(ServerWords.reached(server))"
    }

    /// Servers this device has used, the last one used first when they're listed first.
    @ViewBuilder private func savedSection(_ others: [SavedServer]) -> some View {
        let first = savedFirst ? others.first?.url : nil
        RememberedServers(servers: others, removed: { removed($0, from: others) }) { server in
            // Found on the network at another address than the one remembered: that is where it is now.
            let at = ServerBook.address(of: server, found: found)
            let how = reach(server)
            ServerTile(saved: server, name: server.name.isEmpty ? "WittyMediaServer" : server.name, line: line(server, how), reach: how,
                       selected: server.url == model.lastUsedURL, connecting: connectingTo == at) { Task { await connect(at) } }
                .focused($spot, equals: .recent(server.url))
                .firstFocus(in: scope, when: server.url == first)
                .accessibilityIdentifier("connect.saved." + server.url)
        }
        .remoteSection()
    }

    private func openForm(invite: Bool) {
        formForInvite = invite
        showForm = true
        error = ""
    }

    /// What the camera read: an invite link joins from away; a server's address connects. Nothing else is sent anywhere.
    private func scanned(_ text: String) {
        scanning = false
        let read = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let invite = PeerConnect.invite(from: read) {
            Task { await join(invite) }
        } else if case .ok(let url) = Address.normalize(read), read.lowercased().hasPrefix("http") {
            Task { await connect(url) }
        } else {
            error = "That QR code isn’t an invite or a server’s address."
        }
    }

    /// The canvas's "Connect from anywhere" panel: peer to peer, made obvious, with the ways in as real buttons. On a TV:
    /// a code to type in on a phone, or an address, the first focused.
    private func remoteWays(_ none: Bool) -> some View {
        ConnectAnywherePanel {
            // Always shown, so the way in is never hidden: a copy built without peer to peer says so when it's chosen.
            #if os(tvOS)
            Button { showJoin = true; error = "" } label: { Label("Join with a link or code", systemImage: "link") }
                .action(primary: true, wide: true)
                .focused($spot, equals: .joinAway)
                .firstFocus(in: scope, when: none)
                .accessibilityIdentifier("connect.join")
            #else
            Button { openForm(invite: true) } label: { Label("Join with a link or code", systemImage: "link") }
                .action(primary: true, wide: true)
                .focused($spot, equals: .joinAway)
                .accessibilityIdentifier("connect.join")
            #if os(iOS)
            // Without a camera (a simulator, say) the sheet says so and points to pasting the link.
            Button { scanning = true } label: { Label("Scan a QR code", systemImage: "qrcode.viewfinder") }
                .action(wide: true)
                .accessibilityIdentifier("connect.scan")
            #endif
            #endif
            Button { openForm(invite: false) } label: { Label(say("enterAddress"), systemImage: "keyboard") }
                .action(wide: true)
                .focused($spot, equals: .enterAddress)
                .accessibilityIdentifier("connect.address")
        }
    }

    /// Show saved servers first, and somewhere to forget a server that needs no gesture to find.
    private func onThisDevice(_ any: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ConnectSectionLabel(title: "On this device")
            DesignRows {
                DesignRow(title: "Show saved servers first", value: savedFirst ? "On" : "Off", on: savedFirst) {
                    savedFirst.toggle()
                }
                .accessibilityIdentifier("connect.savedFirst")
                if any {
                    DesignRow(title: "Forget a server", detail: "Removes its sign-in and downloads from this device") {
                        showManage = true
                        error = ""
                    }
                    .focused($spot, equals: .manage)
                    .accessibilityIdentifier("connect.manage")
                }
            }
        }
    }

    private func findPage(_ listed: [SavedServer]) -> some View {
        // With "Show saved servers first" (the usual), the servers used before come first, the last one used at the
        // top, so nobody scrolls past the network's to reach their own; what's found on the network is below them.
        let others = savedFirst ? ServerOrder.recentFirst(listed, lastUsed: model.lastUsedURL) : listed
        let savedOnTop = savedFirst && !others.isEmpty
        return ConnectFrame {
            if !error.isEmpty { DesignNote(text: error, tone: true).padding(.top, Tokens.Space.s4) }
            if savedOnTop {
                savedSection(others)
                foundSection(others)
            } else {
                foundSection(others)
                if !others.isEmpty { savedSection(others) }
            }
            remoteWays(found.isEmpty && others.isEmpty)
            onThisDevice(!others.isEmpty)
            LegalNote().padding(.top, Tokens.Space.s6)
        }
    }

    /// Enter an address, or (`formForInvite`) paste an invite: one field, Connect, and the way back.
    private var addressPage: some View {
        DesignPage(eyebrow: formForInvite ? "Connect to a remote server" : "Welcome",
                   title: formForInvite ? "Join with a link or code" : say("addressTitle"),
                   lead: formForInvite
                       ? (PeerLibrary.available
                           ? "Paste the invite link your server’s owner sent you. It works once, for a short time, and connects peer to peer from anywhere."
                           : "This copy of WittyMediaClient was built without peer to peer, so an invite can’t be used here. Enter your server’s address instead, or install a copy built with it.")
                       : say("addressHint") + (PeerLibrary.available ? " " + say("inviteHint") : ""),
                   identifier: "connect.form") {
            DesignSection(title: "") {
                OutlinedField(label: formForInvite ? "Invite link" : say("addressLabel"), text: $address, kind: .address,
                              icon: "link", request: $wantField, onSubmit: submit)
                if !error.isEmpty { ProblemLine(error) }
            }
            if formForInvite, PeerLibrary.available {
                DesignSection(title: "") {
                    DesignChips {
                        DesignChip(title: "Show a code on this device instead", symbol: "qrcode") {
                            showForm = false
                            showJoin = true
                        }
                    }
                }
            }
            DesignSection(title: "") { LegalNote() }
        } actions: {
            // Never disabled: on a TV that would take the focus away from under the person.
            Button { if !busy { submit() } } label: { BusyText(say("connect"), busy: busy) }
                .action(primary: true)
            Button(say("back"), action: closeForm).action()
        }
    }

    var body: some View {
        // Every added server is listed as itself; one also found on the network isn't listed twice.
        let others = uniqued(model.recent)
        Group {
            if let notSetUp {
                SetupRequiredView(address: notSetUp, retry: { let a = notSetUp.hasSuffix("/setup") ? String(notSetUp.dropLast("/setup".count)) : notSetUp; self.notSetUp = nil; Task { await connect(a) } }, back: { self.notSetUp = nil })
            } else if showManage {
                ManageServersPanel(back: closeManage)
            } else if showJoin {
                JoinAwayPanel(back: closeJoin)
            } else if showForm {
                addressPage
                    .task { wantField = true }
            } else {
                findPage(others)
            }
        }
        .serverUndo()
        #if os(iOS)
        .sheet(isPresented: $scanning) {
            ScannerSheet(looking: "an invite", hint: "Point the camera at the invite’s QR code on the other screen.",
                         instead: "The camera couldn’t be started. Paste the invite link instead.") { scanned($0) }
        }
        #endif
        .focusRoot(scope)
        .onChange(of: spot) { focusChanged($0) }
        .onRemoteBack(notSetUp != nil ? { notSetUp = nil } : showManage ? { closeManage() } : showJoin ? { closeJoin() } : showForm ? { closeForm() } : nil)
        .onAppear {
            if error.isEmpty { error = initialMessage }
            #if DEBUG
            // For apple/scripts/p2p-check.sh: `-WittyCheckJoin 1` at launch goes straight to Join from away.
            if PeerLibrary.available, UserDefaults.standard.bool(forKey: "WittyCheckJoin") { showJoin = true }
            #endif
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
            #if os(tvOS)
            // Coming here from the server just removed, the question's going leaves the system with nothing to focus
            // until the first press: the first card, or Enter an address, takes it.
            try? await Task.sleep(nanoseconds: 700_000_000)
            if spot == nil, !showForm, !showJoin, !showManage {
                let saved = ServerOrder.recentFirst(model.recent, lastUsed: model.lastUsedURL).first.map { Spot.recent($0.url) }
                let near = found.first.map { Spot.found($0.id) }
                spot = (savedFirst ? saved ?? near : near ?? saved) ?? .enterAddress
            }
            try? await Task.sleep(nanoseconds: 5_300_000_000)
            #else
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            #endif
            searchedLong = true
        }
    }
}

/// Which server a code or a sign-in goes to: its mark and name in a quiet pill.
private struct ServerPill: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let name: String

    var body: some View {
        HStack(spacing: Tokens.Space.s2) {
            // Big enough to read from across the room on a TV.
            BrandMark(size: metrics.tv ? 40 : 24, logo: model.client.brandLogoURL(version: model.brandLogo))
            Text(name).font(metrics.tv ? .wmSection : .wmLabel).foregroundStyle(palette.text).lineLimit(1)
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

    // A TV reads the TV words; a phone or iPad is told it can be signed in the same way (client #80).
    private var codeHintKey: String {
        #if os(tvOS)
        "codeHint"
        #else
        "codeHintPhone"
        #endif
    }

    var body: some View {
        SignInLayout(back: back) {
            SignInHeading(title: say("codeTitle"), detail: say(codeHintKey))
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
    let server: SavedServer
    @State private var problem = ""
    @State private var busy = false

    private func back() {
        model.stage = .connect(message: "")
    }

    /// The remembered servers this one answered in place of.
    private var clashes: [SavedServer] { ServerBook.clashes(with: server, in: model.recent) }

    /// The canvas's "Careful" page: the key remembered and the one shown now, side by side.
    private var spec: DesignPageSpec {
        var identity: [DesignPageSpec.Row] = []
        if let old = clashes.first {
            identity.append(.init(id: "saved", title: "Saved", value: old.fingerprint, detail: old.url, pressable: false))
        }
        identity.append(.init(id: "now", title: "Now", value: server.fingerprint, on: true, detail: server.url, pressable: false))
        var sections: [DesignPageSpec.Section] = [
            .secR("Identity", identity),
            .secN("", "Only continue if you reinstalled or restored this server yourself.", true),
        ]
        if !problem.isEmpty { sections.append(.secN("", problem, true)) }
        var actions: [DesignPageSpec.Action] = [.init(id: "back", title: "Go back")]
        // A reinstalled server: the old one is forgotten, and this one can then be added as new.
        if !clashes.isEmpty { actions.append(.init(id: "remove-old", title: say("removeOldOne"))) }
        actions.append(.init(id: "trust", title: "Trust this server", primary: true))
        var page = DesignPageSpec.mk(
            "Careful", "This isn’t the server you used before",
            "The address is the same, but the server’s identity changed. This can happen after a reinstall, or if someone is pretending to be your server.",
            sections, actions)
        // Back, and focus, start on the safe choice.
        page.layer = true
        page.start = "back"
        return page
    }

    private func pressed(_ id: String) {
        switch id {
        case "back": back()
        case "remove-old":
            model.forgetServers(clashes)
            model.stage = .connect(message: say("removedOldOne"))
        case "trust":
            guard !busy else { return }
            busy = true
            Task {
                problem = await model.trust(server) ?? ""
                busy = false
            }
        default: break
        }
    }

    var body: some View {
        DesignSpecPage(spec: spec, onPress: pressed, onBack: back)
            .accessibilityIdentifier("identity-mismatch")
            .onAppear { announce("This isn’t the server you used before") }
    }
}

// MARK: - 8: sign in with a code

// The TV shows a code, and with a newer server a PIN beside it; someone already signed in on a phone or
// computer approves it. That screen is PairPanel, in PairDevice.swift.

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
    /// The first face takes the remote's focus once the profiles have arrived, whatever screen came before.
    @FocusState private var firstTile: Bool?
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
            case .needsParentPin(let words):
                // A kids' profile is kept on this device: leaving it takes the parents' PIN, asked on Who's watching.
                error = words.isEmpty ? say("parentPinLead") : words
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

    private var serverName: String {
        if !model.brandName.isEmpty { return model.brandName }
        let saved = model.current?.name ?? ""
        return saved.isEmpty ? "WittyMediaServer" : saved
    }

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
            // This server as itself: its logo and name, larger on a TV so it reads from the sofa.
            BrandMark(size: metrics.tv ? 32 : 20, logo: model.client.brandLogoURL(version: model.brandLogo))
                .padding(.trailing, Tokens.Space.s1)
            Text(serverName).font(metrics.tv ? .wmLabel : .wmSecondary).foregroundStyle(palette.textSecondary).lineLimit(1)
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
                        .focused($firstTile, equals: index == 0 ? true : nil)
                        .disabled(busy)
                }
            }
            .remoteSection()
            otherWays(centred: true)
        }
        if metrics.tv {
            ZStack {
                SignInBackground()
                page.padding(.horizontal, metrics.gutter).frame(maxWidth: .infinity)
            }
        } else {
            SignInPage { page.frame(maxWidth: .infinity) }
        }
    }

    /// 5: one person's password, or the authenticator's code after it.
    @ViewBuilder private func passwordStep(_ profile: Profile) -> some View {
        // One centred column on every device: the face, its names centred under it, then the way in.
        SignInLayout(back: back, centred: true) {
            VStack(spacing: Tokens.Space.s2) {
                AvatarTile(name: profile.shownName, size: metrics.tv ? 200 : 120, picture: profile.avatar)
                    .padding(.bottom, metrics.tv ? Tokens.Space.s2 : 0)
                Text(profile.shownName).font(.wmHero).foregroundStyle(palette.text).lineLimit(1)
                if profile.showsUsername {
                    Text("@\(profile.name)").font(.wmSecondary).foregroundStyle(palette.textSecondary)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityElement(children: .combine)
            SignInHeading(title: needsCode ? twoFactorTitle : "", detail: needsCode ? twoFactorHint : say("passwordHint"), centred: true)
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
                    .frame(maxWidth: .infinity, alignment: .center)
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

    /// The password screen is one centred column, TVs included; the sign-in form keeps a TV's two halves.
    private var twoFactorCentred: Bool {
        if case .password = step { return true }
        return !metrics.tv
    }

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
                .frame(maxWidth: .infinity, alignment: twoFactorCentred ? .center : .leading)
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
        .frame(maxWidth: .infinity, alignment: twoFactorCentred ? .center : .leading)
    }

    var body: some View {
        Group {
            if useCode {
                PairPanel(onUsePassword: { useCode = false }, onBack: showsPeople ? { useCode = false } : nil)
            } else if profiles == nil {
                ZStack {
                    SignInBackground()
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
            #if os(tvOS)
            if showsPeople { DispatchQueue.main.async { firstTile = true } }
            #endif
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

/// "This server isn't set up yet": first-run setup happens in a web browser only, and a server that hasn't finished it answers
/// `setupRequired`. The app doesn't connect; it says where to finish, with a code a phone's camera can read.
struct SetupRequiredView: View {
    @Environment(\.palette) private var palette
    let address: String
    let retry: () -> Void
    let back: () -> Void
    var backTitle: String = say("back")

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            SignInGlow()
            VStack(spacing: Tokens.Space.s6) {
                SignInHeading(title: say("setupNeededTitle"), detail: say("setupNeededDetail"))
                if let image = QRImage.make(for: address) { QRCard(image: image, caption: say("pairScan")) }
                Text(address).font(.wmLabel).foregroundStyle(palette.accentText).multilineTextAlignment(.center)
                    .accessibilityLabel("Finish setup in a web browser at \(address)")
                HStack(spacing: Tokens.Space.s4) {
                    Button(say("setupNeededRetry"), action: retry).action(.primary, tall: true)
                    Button(backTitle, action: back).action(.secondary, tall: true)
                }
            }
            .padding(Tokens.gutter)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("connect.notSetUp")
        }
    }
}
