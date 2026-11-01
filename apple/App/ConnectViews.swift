import CoreImage
import SwiftUI
import WittyKit

private struct Panel<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) { content }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(Tokens.Space.s8)
                .frame(maxWidth: .infinity)
        }
    }
}

/// The heading of a sign-in screen, which is what a screen reader jumps between.
private struct Heading: View {
    let words: String
    init(_ words: String) { self.words = words }
    var body: some View {
        Text(words).font(.wmPage).accessibilityAddTraits(.isHeader)
    }
}

/// A sentence that explains something. Not a button, so never needs to change when focused.
private struct Quiet: View {
    @Environment(\.palette) private var palette
    let words: String
    init(_ words: String) { self.words = words }
    var body: some View {
        Text(words).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
    }
}

struct ConnectView: View {
    private enum Spot: Hashable {
        case found(String)
        case recent(String)
        case enterAddress
    }

    @EnvironmentObject private var model: AppModel
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

    private func row(name: String, url: String) -> some View {
        Button {
            Task { await connect(url) }
        } label: {
            VStack(alignment: .leading) {
                Text(name)
                Text(url).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityLabel("\(name), \(url)")
    }

    var body: some View {
        let others = uniqued(model.recent).filter { saved in !found.contains { $0.url == saved.url || $0.id == saved.serverId } }
        Panel {
            if showForm {
                Heading(say("addressTitle"))
                Quiet(say("addressHint"))
                Quiet(say("legalConnect")).font(.footnote)
                TextField(say("addressLabel"), text: $address)
                    .plainEntry()
                    .onSubmit(submit)
                    .accessibilityLabel(say("addressLabel"))
                if !error.isEmpty { ProblemLine(error) }
                // Never disabled: on a TV that would take the focus away from under the person.
                Button(busy ? say("connecting") : say("connect")) { if !busy { submit() } }
                Button(say("back"), action: closeForm)
            } else {
                Heading(say("findTitle"))
                Quiet(say("legalConnect")).font(.footnote)
                if !error.isEmpty { ProblemLine(error) }
                if busy { Quiet(say("connecting")) }
                Quiet(say("foundServers")).accessibilityAddTraits(.isHeader)
                if found.isEmpty {
                    Quiet(refused ? say("findNotSupported") : searchedLong ? say("findNone") : say("findSearching"))
                }
                ForEach(found) { server in
                    row(name: server.name, url: server.url).focused($spot, equals: .found(server.id))
                }
                if !others.isEmpty {
                    Quiet(say("recentServers")).accessibilityAddTraits(.isHeader)
                    ForEach(others) { server in
                        row(name: server.name, url: server.url).focused($spot, equals: .recent(server.url))
                    }
                }
                Button(say("enterAddress")) { showForm = true; error = "" }
                    .focused($spot, equals: .enterAddress)
                    .firstFocus(in: scope, when: found.isEmpty)
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

/// A new server is opened with a six-digit code from someone already signed in. See
/// docs/CLIENT-API.md, "The code is typed on the device". Works with only a remote:
/// the zero is twice as wide, so the focus engine finds something below every digit.
struct CodeView: View {
    @EnvironmentObject private var model: AppModel
    let server: SavedServer
    let fromSignIn: Bool
    @State private var entry = CodeEntry()
    @State private var problem = ""
    /// The digits are the one fixed-size text in the app, because they have to line up.
    @ScaledMetric(relativeTo: .largeTitle) private var digitSize: CGFloat = 44
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
        Button {
            press(digit)
        } label: {
            Text(String(digit)).font(.title2.weight(.semibold)).frame(maxWidth: .infinity, minHeight: Tokens.minTarget)
        }
        .buttonStyle(.bordered)
        .digitShortcut(digit)
    }

    var body: some View {
        Panel {
            Heading(say("codeTitle"))
            Quiet(say("codeHint"))
            Text(entry.shown)
                .font(.system(size: digitSize, weight: .bold, design: .monospaced))
                .accessibilityLabel(say("codeLabel"))
                .accessibilityValue("\(entry.digits.count) \(say("codeEntered"))")
            if entry.busy {
                Quiet(say("connecting"))
            } else if !problem.isEmpty {
                ProblemLine(problem)
            }
            Grid(horizontalSpacing: Tokens.Space.s3, verticalSpacing: Tokens.Space.s3) {
                GridRow { key("1").firstFocus(in: scope); key("2"); key("3") }
                GridRow { key("4"); key("5"); key("6") }
                GridRow { key("7"); key("8"); key("9") }
                GridRow {
                    Button {
                        entry.erase()
                    } label: {
                        Text(say("codeDelete")).frame(maxWidth: .infinity, minHeight: Tokens.minTarget)
                    }
                    .buttonStyle(.bordered)
                    key("0").gridCellColumns(2)
                }
            }
            .remoteSection()
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                Button(say("usePassword")) { model.signIn(to: server, way: .password) }
                Button(say("showCodeInstead")) { model.signIn(to: server, way: .shownCode) }
                Button(say("back"), action: back)
            }
            .remoteSection()
            Quiet("\(say("fingerprintLabel")): \(server.fingerprint)").font(.caption)
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
        Panel {
            Heading(say("identityTitle"))
            Quiet(say("identityHint"))
            Quiet("\(server.url) · \(say("fingerprintLabel")): \(server.fingerprint)").font(.caption)
            if !problem.isEmpty { ProblemLine(problem) }
            Button(say("back"), action: back).focused($onSafeChoice)
            Button(busy ? say("connecting") : say("identityTrust")) {
                guard !busy else { return }
                busy = true
                Task {
                    problem = await model.trust(server) ?? ""
                    busy = false
                }
            }
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
    @ScaledMetric(relativeTo: .largeTitle) private var codeSize: CGFloat = 56
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
        VStack(alignment: .leading, spacing: Tokens.Space.s4) {
            Heading(say("pairTitle"))
            if starting && code.isEmpty && problem.isEmpty { LoadingView() }
            if !code.isEmpty {
                Quiet(say("pairHint"))
                if let qr {
                    Image(qr, scale: 1, label: Text("A code for a phone's camera, leading to the address below"))
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: qrSize, height: qrSize)
                        .padding(Tokens.Space.s4)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md))
                }
                Text(approveAt)
                Text(code).font(.system(size: codeSize, weight: .bold, design: .monospaced))
                    .accessibilityLabel(code.map(String.init).joined(separator: " "))
                Quiet(say("pairWaiting"))
            }
            if !problem.isEmpty { ProblemLine(problem) }
            if code.isEmpty && !problem.isEmpty {
                Button(say("pairNew")) { round += 1 }.firstFocus(in: scope)
            }
            if model.canTypeCode { Button(say("codeTitle")) { model.askForCode() }.firstFocus(in: scope, when: !code.isEmpty) }
            Button(say("usePassword"), action: onUsePassword)
            Button(say("changeServer")) { model.changeServer() }
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

    var body: some View {
        Panel {
            if useCode {
                PairPanel { useCode = false }
            } else if let chosen {
                Heading(chosen.name)
                SecureField("Password", text: $password)
                    .boxedField()
                    .textContentType(.password)
                    .onSubmit { login(chosen.name, password) }
                if !error.isEmpty { ProblemLine(error) }
                Button(busy ? say("connecting") : "Sign in") { login(chosen.name, password) }
                Button(say("back"), action: back)
            } else if let list = profiles?.profiles, profiles?.style == "profiles", !useForm, !list.isEmpty {
                Heading("Who's watching?")
                if !error.isEmpty { ProblemLine(error) }
                ForEach(uniqued(list)) { profile in
                    Button(profile.name) {
                        if profile.hasPassword == false { login(profile.name, "") } else { chosen = profile }
                    }
                }
                Button("Sign in with another account") { useForm = true }
                if model.canTypeCode { Button(say("codeTitle")) { model.askForCode() } }
                Button(say("useCode")) { useCode = true }
                Button(say("changeServer")) { model.changeServer() }
            } else if profiles != nil {
                Heading("Sign in")
                TextField("Name", text: $name).plainEntry().textContentType(.username)
                SecureField("Password", text: $password)
                    .boxedField()
                    .textContentType(.password)
                    .onSubmit { login(name, password) }
                if !error.isEmpty { ProblemLine(error) }
                Button(busy ? say("connecting") : "Sign in") { login(name, password) }
                if !(profiles?.profiles ?? []).isEmpty { Button(say("back")) { useForm = false; error = "" } }
                if model.canTypeCode { Button(say("codeTitle")) { model.askForCode() } }
                Button(say("useCode")) { useCode = true }
                Button(say("changeServer")) { model.changeServer() }
            } else {
                LoadingView()
            }
        }
        .onRemoteBack(back)
        .task {
            profiles = (try? await model.client.profiles()) ?? Profiles(style: "classic", profiles: nil)
        }
    }
}
