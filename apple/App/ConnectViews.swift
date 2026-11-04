import CoreImage
import SwiftUI
import WittyKit

// Finding a server and signing in, laid out as the Android app's ConnectScreens.kt: one column of
// words and full-width buttons, with the main one in the accent colour. On a TV the words and the
// buttons sit side by side.

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

    @ViewBuilder private var words: some View {
        Heading(say("findTitle"))
        Secondary(say("legalConnect"))
        if !error.isEmpty { ProblemLine(error) }
        if busy { Secondary(say("connecting")) }
    }

    @ViewBuilder private func servers(_ others: [SavedServer]) -> some View {
        Secondary(say("foundServers")).accessibilityAddTraits(.isHeader)
        if found.isEmpty {
            Secondary(refused ? say("findNotSupported") : searchedLong ? say("findNone") : say("findSearching"))
        }
        ForEach(found) { server in
            ServerRow(name: server.name, url: server.url) { Task { await connect(server.url) } }
                .focused($spot, equals: .found(server.id))
        }
        if !others.isEmpty {
            Secondary(say("recentServers")).accessibilityAddTraits(.isHeader)
            ForEach(others) { server in
                ServerRow(name: server.name, url: server.url) { Task { await connect(server.url) } }
                    .focused($spot, equals: .recent(server.url))
            }
        }
        Button(say("enterAddress")) {
            showForm = true
            error = ""
        }
        .action(wide: true)
        .focused($spot, equals: .enterAddress)
        .firstFocus(in: scope, when: found.isEmpty)
    }

    var body: some View {
        let others = uniqued(model.recent).filter { saved in !found.contains { $0.url == saved.url || $0.id == saved.serverId } }
        Group {
            if showForm {
                Centred {
                    Heading(say("addressTitle"))
                    Secondary(say("addressHint"))
                    OutlinedField(label: say("addressLabel"), text: $address, kind: .address, request: $wantField, onSubmit: submit)
                    if !error.isEmpty { ProblemLine(error) }
                    // Never disabled: on a TV that would take the focus away from under the person.
                    Button(busy ? say("connecting") : say("connect")) { if !busy { submit() } }
                        .action(primary: true, wide: true)
                    Button(say("back"), action: closeForm).action(wide: true)
                    Secondary(say("legalConnect"))
                }
                .task { wantField = true }
            } else {
                SideBySide {
                    words
                } actions: {
                    servers(others)
                }
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

/// A key of the number pad: the card colour, a large digit, and room for a thumb.
private struct PadKey: View {
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    let label: String
    var small = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(small ? .wmLabel : .title3.weight(.semibold))
                .foregroundStyle(palette.text)
                .frame(maxWidth: .infinity, minHeight: metrics.minTarget + Tokens.Space.s2)
        }
        .buttonStyle(SurfaceStyle(fill: palette.card))
    }
}

/// A new server is opened with a six-digit code from someone already signed in. See
/// docs/CLIENT-API.md, "The code is typed on the device". Works with only a remote:
/// the zero is twice as wide, so the focus engine finds something below every digit.
struct CodeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    let server: SavedServer
    let fromSignIn: Bool
    @State private var entry = CodeEntry()
    @State private var problem = ""
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
            }
        }
    }

    private func back() {
        model.stage = fromSignIn ? .signIn(.usual) : .connect(message: "")
    }

    private func key(_ digit: Character) -> some View {
        PadKey(label: String(digit)) { press(digit) }.digitShortcut(digit)
    }

    var body: some View {
        SideBySide {
            Heading(say("codeTitle"))
            // Several servers can look alike in the list: this says which one the code goes to.
            Secondary("\(server.name) · \(server.url)")
            Secondary(say("codeHint"))
            Text(entry.shown)
                .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                .foregroundStyle(palette.text)
                .accessibilityLabel(say("codeLabel"))
                .accessibilityValue("\(entry.digits.count) \(say("codeEntered"))")
            // Room is kept for the message, or the keys would move under a finger as it comes and goes.
            Group {
                if entry.busy {
                    Secondary(say("connecting"))
                } else if !problem.isEmpty {
                    ProblemLine(problem)
                }
            }
            .frame(minHeight: 40, alignment: .topLeading)
            Secondary("\(say("fingerprintLabel")): \(server.fingerprint)")
        } actions: {
            Grid(horizontalSpacing: Tokens.Space.s2, verticalSpacing: Tokens.Space.s2) {
                GridRow { key("1").firstFocus(in: scope); key("2"); key("3") }
                GridRow { key("4"); key("5"); key("6") }
                GridRow { key("7"); key("8"); key("9") }
                GridRow {
                    PadKey(label: say("codeDelete"), small: true) { entry.erase() }
                    key("0").gridCellColumns(2)
                }
            }
            .remoteSection()
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                Button(say("usePassword")) { model.signIn(to: server, way: .password) }.action(wide: true)
                Button(say("showCodeInstead")) { model.signIn(to: server, way: .shownCode) }.action(wide: true)
                Button(say("back"), action: back).action(wide: true)
            }
            .remoteSection()
        }
        .focusRoot(scope)
        .onRemoteBack(back)
    }
}

/// Another machine is answering for a server we know. Only the person can decide, so
/// the safe choice comes first and has focus, and nothing has been sent to it.
struct MismatchView: View {
    @EnvironmentObject private var model: AppModel
    let server: SavedServer
    @State private var problem = ""
    @State private var busy = false
    @FocusState private var onSafeChoice: Bool

    private func back() {
        model.stage = .connect(message: "")
    }

    var body: some View {
        Centred {
            Heading(say("identityTitle"))
            Secondary(say("identityHint"))
            Secondary("\(server.url) · \(say("fingerprintLabel")): \(server.fingerprint)")
            if !problem.isEmpty { ProblemLine(problem) }
            Button(say("back"), action: back).action(primary: true, wide: true).focused($onSafeChoice)
            Button(busy ? say("connecting") : say("identityTrust")) {
                guard !busy else { return }
                busy = true
                Task {
                    problem = await model.trust(server) ?? ""
                    busy = false
                }
            }
            .action(wide: true)
        }
        .onRemoteBack(back)
        .task { onSafeChoice = true }
        .onAppear { announce(say("identityTitle")) }
    }
}

/// The picture of an address that a phone's camera can read. Black on white with its own margin,
/// whatever the theme, since that's what a camera needs. No network is involved in making it.
private enum QRCode {
    static func image(for text: String) -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        return CIContext(options: nil).createCGImage(output, from: output.extent)
    }
}

/// The TV shows a code; someone already signed in on a phone or computer approves
/// it, so nobody has to type a password with a remote. See docs/CLIENT-API.md.
private struct PairPanel: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    let onUsePassword: () -> Void
    @State private var round = 0
    @State private var code = ""
    @State private var approveAt = ""
    @State private var qr: CGImage?
    @State private var problem = ""
    @State private var starting = true
    @Namespace private var scope

    #if os(tvOS)
    private let qrSize: CGFloat = 320
    #else
    private let qrSize: CGFloat = 200
    #endif

    private func run() async {
        code = ""
        problem = ""
        qr = nil
        starting = true
        defer { starting = false }
        let start: PairStart
        do {
            start = try await model.client.pairStart(device: model.deviceName, platform: model.platformName)
        } catch {
            problem = plainWords(Problem.of(error))
            return
        }
        code = start.code
        approveAt = start.approveAddress(base: model.client.base) ?? model.client.base
        qr = QRCode.image(for: approveAt)
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
        SideBySide {
            Heading(say("pairTitle"))
            if starting && code.isEmpty && problem.isEmpty { LoadingView() }
            if !code.isEmpty {
                Secondary(say("pairHint"))
                Text(approveAt).foregroundStyle(palette.text)
                Text(code)
                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.text)
                    .accessibilityLabel(code.map(String.init).joined(separator: " "))
                Secondary(say("pairWaiting"))
            }
            if !problem.isEmpty { ProblemLine(problem) }
        } actions: {
            if !code.isEmpty, let qr {
                Secondary(say("pairScan"))
                Image(qr, scale: 1, label: Text("A code for a phone's camera, leading to the address on screen"))
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: qrSize, height: qrSize)
                    .padding(Tokens.Space.s4)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md))
            }
            if code.isEmpty && !problem.isEmpty {
                Button(say("pairNew")) { round += 1 }.action(primary: true, wide: true).firstFocus(in: scope)
            }
            if model.canTypeCode {
                Button(say("codeTitle")) { model.askForCode() }.action(wide: true)
            }
            Button(say("usePassword"), action: onUsePassword).action(wide: true).firstFocus(in: scope, when: !code.isEmpty)
            Button(say("changeServer")) { model.changeServer() }.action(wide: true)
        }
        .focusRoot(scope)
        .task(id: round) { await run() }
    }
}

struct SignInView: View {
    @EnvironmentObject private var model: AppModel
    @State private var useCode: Bool
    @State private var profiles: Profiles?
    @State private var chosen: Profile?
    @State private var useForm = false
    @State private var name = ""
    @State private var password = ""
    @State private var error = ""
    @State private var busy = false
    @State private var wantPassword = false
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

    private func login(_ who: String, _ secret: String) {
        guard !busy else { return }
        busy = true
        error = ""
        Task {
            if let failed = await model.passwordSignIn(name: who, password: secret) { error = failed }
            busy = false
        }
    }

    /// One step back at a time, and never out of the app from the middle of signing in.
    private func back() {
        if chosen != nil {
            chosen = nil
            password = ""
            error = ""
        } else if useForm {
            useForm = false
            error = ""
        } else if useCode, profiles != nil, !(profiles?.profiles ?? []).isEmpty {
            useCode = false
        } else {
            model.changeServer()
        }
    }

    /// The other ways in, under whatever the screen is mainly for.
    @ViewBuilder private var otherWays: some View {
        if model.canTypeCode { Button(say("codeTitle")) { model.askForCode() }.action(wide: true) }
        Button(say("useCode")) { useCode = true }.action(wide: true)
        Button(say("changeServer")) { model.changeServer() }.action(wide: true)
    }

    var body: some View {
        Group {
            if useCode {
                PairPanel { useCode = false }
            } else {
                Centred {
                    if let chosen {
                        Heading(chosen.name)
                        OutlinedField(label: "Password", text: $password, kind: .password, request: $wantPassword) { login(chosen.name, password) }
                        if !error.isEmpty { ProblemLine(error) }
                        Button(busy ? say("connecting") : "Sign in") { login(chosen.name, password) }.action(primary: true, wide: true)
                        Button(say("back"), action: back).action(wide: true)
                    } else if let list = profiles?.profiles, profiles?.style == "profiles", !useForm, !list.isEmpty {
                        Heading("Who's watching?")
                        if !error.isEmpty { ProblemLine(error) }
                        FlowLayout {
                            ForEach(Array(uniqued(list).enumerated()), id: \.element.id) { index, profile in
                                Button(profile.name) {
                                    if profile.hasPassword == false { login(profile.name, "") } else { chosen = profile }
                                }
                                .action()
                                .firstFocus(in: scope, when: index == 0)
                            }
                        }
                        .remoteSection()
                        Button("Sign in with another account") { useForm = true }.action(wide: true)
                        otherWays
                    } else if profiles != nil {
                        Heading("Sign in")
                        OutlinedField(label: "Name", text: $name, kind: .name) { wantPassword = true }
                        OutlinedField(label: "Password", text: $password, kind: .password, request: $wantPassword) { login(name, password) }
                        if !error.isEmpty { ProblemLine(error) }
                        Button(busy ? say("connecting") : "Sign in") { login(name, password) }.action(primary: true, wide: true)
                        if !(profiles?.profiles ?? []).isEmpty {
                            Button(say("back")) { useForm = false; error = "" }.action(wide: true)
                        }
                        otherWays
                    } else {
                        LoadingView()
                    }
                }
                .focusRoot(scope)
            }
        }
        .onChange(of: chosen?.id) { picked in
            // The password box is the next thing to use, as on Android.
            if picked != nil { wantPassword = true }
        }
        .onRemoteBack(back)
        .task {
            profiles = (try? await model.client.profiles()) ?? Profiles(style: "classic", profiles: nil)
        }
    }
}
