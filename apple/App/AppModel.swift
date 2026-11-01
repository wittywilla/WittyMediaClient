import Foundation
import SwiftUI
import WittyKit

/// Themes and wording are shared data: see shared/data/, bundled into the app.
enum SharedData {
    private static func load(_ name: String) -> Data? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "data") else { return nil }
        return try? Data(contentsOf: url)
    }

    static let strings: [String: String] = load("strings.en").flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]

    struct ThemeColours: Decodable {
        let background, panel, card, border, text, textSecondary, accent, onAccent, danger: String
        let textHint, accentText, ok: String?
    }
    struct Theme: Decodable {
        let id: String
        let scheme: String
        let colours: ThemeColours
    }
    private struct ThemeFile: Decodable {
        let defaultTheme: String
        let themes: [Theme]
    }
    private static let themeFile = load("themes").flatMap { try? JSONDecoder().decode(ThemeFile.self, from: $0) }

    /// A theme uploaded to the server has no entry here, and gets the default look.
    static func theme(_ id: String?) -> Theme? {
        guard let file = themeFile else { return nil }
        return file.themes.first { $0.id == id } ?? file.themes.first { $0.id == file.defaultTheme }
    }
}

/// A word missing from the shared file shows as its key, which is ugly but never an empty button.
func say(_ key: String) -> String { SharedData.strings[key] ?? key }

/// What to show for something `WittyClient.probe` or `judge` refused.
func reasonText(_ reason: String) -> String {
    switch reason {
    case "empty": return say("errEmpty")
    case "scheme": return say("errScheme")
    case "credentials": return say("errCredentials")
    case "public-http": return say("errPublicHttp")
    case "unreachable": return say("errUnreachable")
    case "not-server": return say("errNotServer")
    case "not-set-up": return say("errNotSetUp")
    case "server-old": return say("errServerOld")
    case "app-old": return say("errAppOld")
    case "certificate": return say("errCertificate")
    default: return say("errInvalid")
    }
}

/// Plain words for a problem. The system's descriptions are for the log. Empty means show nothing.
func plainWords(_ problem: Problem) -> String {
    switch problem {
    case .cancelled, .expiredSignIn: return ""
    case .offline: return "This device isn't connected to a network."
    case .lost: return say("errLost")
    case .certificate: return say("errCertificate")
    case .server(let words): return words
    case .unreadable: return "The server sent an answer this app can't read. Updating the server or this app may help."
    }
}

enum Route: Hashable {
    case library(Library)
    case show(Int64)
    case item(Int64)
    case player(Int64, startOver: Bool)
    /// The server's own page for playing a game: iPhone and iPad only, see WebPlayerView.
    case web(String)
}

enum SignInWay: Hashable {
    case usual, password, shownCode
}

@MainActor
final class AppModel: ObservableObject {
    enum Stage: Equatable {
        case starting
        case connect(message: String)
        case code(SavedServer, fromSignIn: Bool)
        case mismatch(SavedServer)
        case signIn(SignInWay)
        case browsing
    }

    @Published var stage: Stage = .starting {
        didSet { if stage == .browsing { openWaitingLink() } }
    }
    @Published var tab: AppTab = .home
    /// Where each tab has got to, so coming back to one finds it as it was left.
    @Published var paths: [AppTab: [Route]] = [:]
    @Published var themeId: String?
    @Published var user: User?
    @Published var libraries: [Library] = []
    /// Something worth saying that isn't a failure of the screen in front of the person.
    @Published var notice = ""

    private(set) var client = WittyClient(base: "") {
        didSet { ClientLog.shared.use(client) }
    }

    /// The server the sign-in screens talk to. Its key waits here for a token to be
    /// kept with, unless it was already pinned.
    private(set) var current: SavedServer?

    private let defaults = UserDefaults.standard
    private var started = false
    private var waitingLink: DeepLink?

    var path: [Route] {
        get { paths[tab] ?? [] }
        set { paths[tab] = newValue }
    }

    func pathBinding(_ tab: AppTab) -> Binding<[Route]> {
        Binding(get: { self.paths[tab] ?? [] }, set: { self.paths[tab] = $0 })
    }

    /// The player and the game page have the whole screen.
    var hidesBars: Bool {
        switch path.last {
        case .player?, .web?: return true
        default: return false
        }
    }

    var platformName: String {
        #if os(tvOS)
        return "tvOS"
        #elseif os(macOS)
        return "macOS"
        #else
        return "iOS"
        #endif
    }

    /// The name shown in the server's list of signed-in devices.
    var deviceName: String {
        #if os(tvOS)
        let given = PlainWords.clean(UIDevice.current.name, limit: 64)
        return given.isEmpty ? "Apple TV" : given
        #elseif os(macOS)
        return "Mac"
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }

    var recent: [SavedServer] {
        get {
            guard let data = defaults.data(forKey: "recent") else { return [] }
            return (try? JSONDecoder().decode([SavedServer].self, from: data)) ?? []
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "recent") }
    }

    private var server: String {
        get { defaults.string(forKey: "server") ?? "" }
        set { defaults.set(newValue, forKey: "server") }
    }

    var palette: Palette { Palette(SharedData.theme(themeId)?.colours) }
    var scheme: ColorScheme { SharedData.theme(themeId)?.scheme == "light" ? .light : .dark }

    /// Only for a server whose identity has just been checked.
    private func openServer(_ opening: SavedServer, token: String = "") {
        current = opening
        server = opening.url
        client = WittyClient(base: opening.url, token: token)
    }

    /// On to signing in, for a server that has been checked.
    func signIn(to opening: SavedServer, way: SignInWay = .usual) {
        forgetSignIn()
        openServer(opening)
        stage = .signIn(way)
    }

    private func forgetSignIn() {
        Keychain.clear()
        TopShelfWriter.clear()
        ArtCache.shared.removeAllObjects()
        user = nil
        libraries = []
        paths = [:]
        tab = .home
    }

    /// Opens a server with a token that was kept with its key. Answers words to show if it can't.
    private func openWithToken(_ opening: SavedServer) async -> String? {
        recent = SavedServer.remember(opening, in: recent)
        openServer(opening, token: Keychain.token)
        do {
            // A server can stop working with this app between one run and the next.
            if let caps = try? await client.capabilities(), let reason = WittyClient.judge(caps, appVersion: WittyClient.appVersion) {
                return reasonText(reason)
            }
            let status = try await client.status()
            themeId = status.theme
            paths = [:]
            user = status.user
            if status.user != nil {
                stage = .browsing
            } else {
                // The server doesn't know this sign-in any more, so it's no use keeping.
                Keychain.clear()
                client = WittyClient(base: opening.url)
                stage = .signIn(.usual)
            }
            return nil
        } catch let error as APIError {
            return error.message
        } catch is URLError {
            return say("errLost")
        } catch {
            return say("errNotServer")
        }
    }

    /// The key kept with the token decides. A sign-in saved with none is from a server too old
    /// to have a key, and all that's left to go on is what it said then.
    private func tokenFits(pin: String, proof: ServerProof) -> Bool {
        !Keychain.token.isEmpty && Identity.fits(pin: pin, proof: proof)
    }

    /// What the last run was using, if it still is who it was. Its token goes
    /// nowhere until then.
    func start() async {
        guard !started else { return }
        started = true
        let url = server
        guard !url.isEmpty else { stage = .connect(message: ""); return }
        var saved = recent.first { $0.url == url } ?? SavedServer(url: url, name: "WittyMediaServer")
        var proof = await WittyClient.identify(url, saved: [saved])
        if proof.state == .unreachable, !saved.serverId.isEmpty,
           let found = await ServerFinder.find(id: saved.serverId, waitSeconds: 6) {
            saved = saved.moved(to: found.url)
            proof = await WittyClient.identify(found.url, saved: [saved])
        }
        let checked = proof.saved(url: saved.url, name: saved.name)
        switch Identity.stepAtStart(proof.state, tokenFits: tokenFits(pin: Keychain.pin, proof: proof)) {
        case .warn:
            stage = .mismatch(checked)
        case .refuse:
            stage = .connect(message: say("identityBad"))
        case .lost:
            stage = .connect(message: say("errLost"))
        case .open:
            if let problem = await openWithToken(checked) { stage = .connect(message: problem) }
        case .askCode, .signIn:
            openServer(checked)
            do {
                themeId = try await client.status().theme
                stage = .signIn(.usual)
            } catch {
                stage = .connect(message: say("errLost"))
            }
        }
    }

    /// Coming back to an app left running counts as starting it. Nothing answering is
    /// left to the screens, as the network is often still waking up.
    func recheck() async {
        guard let using = current, !client.token.isEmpty else { return }
        let proof = await WittyClient.identify(using.url, saved: [using])
        guard proof.state == .different || proof.state == .bad else { return }
        current = nil
        client = WittyClient(base: "")
        paths = [:]
        stage = proof.state == .bad ? .connect(message: say("identityBad")) : .mismatch(proof.saved(url: using.url, name: using.name))
    }

    /// Someone chose this server, and it says it's a WittyMediaServer. Its identity
    /// decides what comes next. Answers words to show if that's nowhere.
    func arrive(url: String, status: ServerStatus) async -> String? {
        let proof = await WittyClient.identify(url, saved: recent)
        let pin = Keychain.pin
        let checked = proof.saved(url: url, name: status.displayName)
        let step = Identity.nextStep(proof.state, tokenFits: !pin.isEmpty && tokenFits(pin: pin, proof: proof))
        if step != .refuse && step != .lost { themeId = status.theme }
        switch step {
        case .warn:
            stage = .mismatch(checked)
        case .refuse:
            return say("identityBad")
        case .lost:
            return say("errUnreachable")
        case .askCode:
            stage = .code(checked, fromSignIn: false)
        case .signIn:
            signIn(to: checked)
        case .open:
            return await openWithToken(checked)
        }
        return nil
    }

    /// "This is my server, trust it". The key pinned is the one the warning showed, or
    /// it asks again, and the old sign-in isn't kept: docs/CLIENT-API.md says sign in again.
    func trust(_ shown: SavedServer) async -> String? {
        let proof = await WittyClient.identify(shown.url, saved: [])
        switch proof.state {
        case .unreachable:
            return say("errUnreachable")
        case .new where proof.publicKey == shown.publicKey:
            forgetSignIn()
            recent = SavedServer.remember(shown, in: recent)
            stage = .code(shown, fromSignIn: false)
            return nil
        case .new:
            stage = .mismatch(proof.saved(url: shown.url, name: shown.name))
            return nil
        default:
            return say("identityBad")
        }
    }

    /// Typing a code instead, from the sign-in screens. Only a server that has proved
    /// its identity can be sent one.
    var canTypeCode: Bool { !(current?.publicKey ?? "").isEmpty }

    func askForCode() {
        if let current { stage = .code(current, fromSignIn: true) }
    }

    /// The server has to prove itself again before a code or a password leaves, and with the very
    /// key the person was shown: it could have changed since the screen opened. If another key is
    /// answering, nothing is sent and the warning shows the new one. Nil means go ahead.
    private func refuseToSend(to shown: SavedServer) async -> String? {
        let proof = await WittyClient.identify(shown.url, saved: shown.publicKey.isEmpty ? [] : [shown])
        switch Identity.beforeSending(shownKey: shown.publicKey, proof: proof) {
        case .send:
            return nil
        case .unreachable:
            return say("errUnreachable")
        case .refuse:
            return say("identityBad")
        case .changed:
            stage = .mismatch(proof.saved(url: shown.url, name: shown.name))
            return say("identityBad")
        }
    }

    /// A code typed on this device. Answers words to show on failure.
    func redeem(_ to: SavedServer, code: String) async -> String? {
        if let refused = await refuseToSend(to: to) { return refused }
        do {
            let result = try await WittyClient(base: to.url, quick: true).pairRedeem(code: code, device: deviceName, platform: platformName)
            openServer(to)
            signedIn(token: result.token, user: result.user)
            return nil
        } catch let error as APIError {
            return error.message
        } catch is URLError {
            return say("errUnreachable")
        } catch {
            return say("errInvalid")
        }
    }

    /// A name and password, or a profile with neither. The server's own words say what was wrong.
    func passwordSignIn(name: String, password: String) async -> String? {
        if let current, let refused = await refuseToSend(to: current) { return refused }
        do {
            let result = try await client.login(name: name, password: password, device: deviceName)
            signedIn(token: result.token, user: result.user)
            return nil
        } catch let error as APIError {
            return error.message
        } catch {
            return plainWords(Problem.of(error))
        }
    }

    /// The address, the key it proved and the token are kept together.
    func signedIn(token: String, user: User? = nil) {
        let kept = current ?? SavedServer(url: client.base, name: "WittyMediaServer")
        notice = Keychain.save(token: token, pin: kept.publicKey) ? "" : "This device couldn't keep your sign-in, so you'll be asked again next time."
        server = kept.url
        recent = SavedServer.remember(kept, in: recent)
        client = WittyClient(base: kept.url, token: token)
        self.user = user
        paths = [:]
        tab = .home
        stage = .browsing
        if user == nil {
            Task { self.user = try? await client.status().user }
        }
    }

    private func endSession() {
        let old = client
        guard !old.token.isEmpty else { return }
        Task { try? await old.logout() }
    }

    func signOut() {
        endSession()
        forgetSignIn()
        client = WittyClient(base: client.base)
        stage = .signIn(.usual)
    }

    func changeServer() {
        endSession()
        forgetSignIn()
        current = nil
        server = ""
        client = WittyClient(base: "")
        themeId = nil
        stage = .connect(message: "")
    }

    /// Words for a failure, with a sign-in the server no longer accepts meaning signing in again.
    /// Empty means there's nothing to show: the screen went away, or the stage has changed.
    func handle(_ error: Error) -> String {
        let problem = Problem.of(error)
        if problem == .expiredSignIn {
            forgetSignIn()
            client = WittyClient(base: client.base)
            stage = .signIn(.usual)
        }
        return plainWords(problem)
    }

    func homeLoaded(_ home: Home) {
        let fresh = uniqued(home.libraries ?? [])
        if fresh != libraries { libraries = fresh }
        TopShelfWriter.update(home: home, client: client)
    }

    // MARK: Links from outside

    /// All a link can do is choose a screen, and only for someone signed in. If nobody is yet, it
    /// waits until they are. It can't sign anyone in or change server: it holds only a number.
    func open(link url: URL) {
        guard let link = DeepLink.parse(url) else { return }
        waitingLink = link
        if stage == .browsing { openWaitingLink() }
    }

    private func openWaitingLink() {
        guard let link = waitingLink else { return }
        waitingLink = nil
        tab = .home
        switch link {
        case .item(let id): paths[.home] = [.item(id)]
        case .show(let id): paths[.home] = [.show(id)]
        }
    }
}
