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
    struct Theme: Decodable, Identifiable {
        let id: String
        let name: String?
        let scheme: String
        let colours: ThemeColours
    }
    private struct ThemeFile: Decodable {
        let defaultTheme: String
        let themes: [Theme]
    }
    private static let themeFile = load("themes").flatMap { try? JSONDecoder().decode(ThemeFile.self, from: $0) }

    /// Every theme the server is built with, in the order its Appearance page lists them.
    static var themes: [Theme] {
        let order = ["default", "light", "midnight", "cinema", "evergreen", "paper", "oled", "contrast"]
        return (themeFile?.themes ?? []).sorted { (order.firstIndex(of: $0.id) ?? 99, $0.id) < (order.firstIndex(of: $1.id) ?? 99, $1.id) }
    }

    /// Only that theme, with no stand-in.
    static func exactTheme(_ id: String?) -> Theme? { themeFile?.themes.first { $0.id == id } }

    /// A built-in theme, through the same translation as the server's tokens, so the first screen and a server
    /// that can't be reached look the same as once the server answers.
    static func appTheme(_ id: String?) -> AppTheme {
        guard let theme = exactTheme(id) ?? theme(id) else { return ThemeTranslator.translate(ThemeTokens(id: "default", colors: ThemeTranslator.witty)) }
        let c = theme.colours
        var colors = ["bg": c.background, "bg-2": c.panel, "bg-3": c.card, "bg-4": c.border, "fg": c.text,
                      "fg-2": c.textSecondary, "accent": c.accent, "accent-fg": c.onAccent, "danger": c.danger]
        colors["fg-3"] = c.textHint
        colors["accent-text"] = c.accentText
        colors["ok"] = c.ok
        return ThemeTranslator.translate(ThemeTokens(id: theme.id, name: theme.name, scheme: theme.scheme, colors: colors,
                                                     lengths: ["radius": 10]))
    }

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
    /// Any other page of the server's. A Mac opens these in its browser, and Apple TV has none.
    case page(String)
    /// An album or a book's chapters, on Apple TV.
    case album(library: Int64, name: String)
    /// An album, a book or a podcast, asked for by its name and whose it is: see ListeningViews.swift.
    case listeningAlbum(library: Int64, album: String, artist: String)
    /// Everything of one artist's or author's in a library.
    case artist(library: Int64, name: String)
    /// A photo and the ones around it, on Apple TV.
    case photo(library: Int64, id: Int64)
    /// Live channels, on Apple TV.
    case guide
    case channel(key: String)
    /// Recordings and series, on Apple TV.
    case recordings
    /// The licences of what this app ships, and its own log, from You.
    case notices
    case logs
    /// The person's own account and this device's choices, from You: see YouViews.swift.
    case names, password, twoStep, devices, signInTv, theme
}

/// A page a module adds to the menus, with the module it belongs to.
struct ModulePlace: Equatable {
    let module: String
    let page: ModulePage
}

/// A list of tracks being played, in order, on Apple TV.
extension AppModel {
    func play(_ tracks: [Item], from track: Item) {
        playingList = tracks.map(\.id)
        path.append(.player(track.id, startOver: true))
    }
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
    /// The tracks being played in order, on Apple TV. Only what's in this goes on by itself.
    var playingList: [Int64] = []
    /// The channels as the guide last had them, for the remote to go through while one plays.
    var channels: [GuideChannel] = []
    /// The account's WittyTV colours and whether it wants logos, once the guide has asked.
    var tvColours: TvColours?
    var tvLogos = true
    /// The server's theme, from `/status`.
    @Published var themeId: String?
    /// This device's own theme for this server: "" follows the server, "auto" follows the device's
    /// light or dark, anything else is a theme's id. Kept on the device, as the web keeps it per browser.
    @Published private(set) var themeChoice = ""
    /// The device's own light or dark, which the automatic theme follows.
    @Published var systemScheme: ColorScheme = .dark {
        didSet { if themeChoice == "auto" && oldValue != systemScheme { refreshTheme() } }
    }
    /// The theme in use, translated from the server's tokens: docs/APP-DESIGN.md, Themes.
    @Published private(set) var appTheme: AppTheme = SharedData.appTheme("default") {
        didSet { Tokens.Radius.theme = CGFloat(appTheme.radius) }
    }
    /// Every theme the server has, once asked.
    @Published private(set) var themeList: ThemeList?
    /// The look this person made with the website's theme maker.
    @Published private(set) var customTheme: ThemeMakerInput?
    private var themeFetch: Task<Void, Never>?
    /// The owner's own name and logo for the server, from `/status`, shown on the sign-in screens.
    @Published var brandName = ""
    @Published var brandLogo = ""
    @Published var user: User?
    /// Music, audiobooks and podcasts, which carry on whatever screen is showing.
    let listening = Listening()
    @Published var libraries: [Library] = []
    /// The phone's Menu: the drawer of libraries from the left.
    @Published var menuOpen = false
    /// The server's page on top is in one of its own players (a disc, the CD player): see WebPlayer.isPlayer.
    @Published var pagePlaying = false
    /// Whether this server lets this person play its game PCs, which the Menu then offers.
    @Published var gamePCs = false
    /// The website's menus: how this person (or the owner) arranged them, and the pages modules add.
    @Published var navPrefs = NavPrefs()
    @Published var modulePages: [ModulePlace] = []
    /// The server's version, for the line at the foot of every page, and its short legal notices.
    @Published var serverVersion = ""
    /// A newer version of the server, for an admin's dot on You.
    @Published var serverUpdate = ""
    @Published var legal: LegalNotices?
    /// The video playing on a phone or tablet, on its screen or in the dock above the bar once that's left, as the
    /// website's player keeps playing in its mini player.
    @Published var video: PlaybackModel?
    /// Something worth saying that isn't a failure of the screen in front of the person.
    @Published var notice = ""

    // Published, so the screens that get it from the environment never see the one before it.
    @Published private(set) var client = WittyClient(base: "") {
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
        case .page?: return pagePlaying
        default: return false
        }
    }

    var platformName: String {
        #if os(tvOS)
        return "tvOS"
        #elseif os(macOS)
        return "macOS"
        #elseif os(visionOS)
        return "visionOS"
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
        #elseif os(visionOS)
        return "Apple Vision Pro"
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

    /// The theme in use: this device's choice, or the server's.
    var effectiveThemeId: String? {
        switch themeChoice {
        case "": return themeId
        case "auto": return systemScheme == .light ? "light" : "default"
        case "custom": return customTheme == nil ? themeId : "custom"
        default: return themeChoice
        }
    }

    var palette: Palette { Palette(appTheme) }

    func chooseTheme(_ id: String) {
        themeChoice = id
        defaults.set(id, forKey: "theme." + client.base)
        refreshTheme()
    }

    private func preview(_ id: String) -> ThemeList.ThemeSummary.Preview? {
        themeList?.themes.first { $0.id == id }?.preview
    }

    private func tokensKey(_ id: String) -> String { "themeTokens|\(client.base)|\(id)" }

    /// The theme in use, at once from what this device kept (or the built-in copy), then from the server.
    func refreshTheme() {
        let id = effectiveThemeId ?? "default"
        if id == "custom", let made = customTheme {
            appTheme = ThemeTranslator.translate(made: made)
            return
        }
        if let data = defaults.data(forKey: tokensKey(id)), let kept = try? JSONDecoder().decode(ThemeTokens.self, from: data) {
            appTheme = ThemeTranslator.translate(kept, preview: preview(id))
        } else if SharedData.exactTheme(id) != nil {
            appTheme = SharedData.appTheme(id)
        }
        let asking = client
        guard !asking.base.isEmpty else { return }
        themeFetch?.cancel()
        themeFetch = Task { [weak self] in
            guard let tokens = try? await asking.themeTokens(id), !Task.isCancelled, let self,
                  self.client.base == asking.base, (self.effectiveThemeId ?? "default") == id else { return }
            if let data = try? JSONEncoder().encode(tokens) { self.defaults.set(data, forKey: self.tokensKey(id)) }
            self.appTheme = ThemeTranslator.translate(tokens, preview: self.preview(id))
        }
    }

    /// What themes the server has, and the person's own, once signed in.
    func loadThemes() async {
        let asking = client
        async let list = try? asking.themeList()
        async let made = try? asking.customTheme()
        let (l, m) = await (list, made)
        guard client.base == asking.base else { return }
        if let l { themeList = l }
        customTheme = m ?? nil
        refreshTheme()
    }

    /// The account as the server has it now, after a change from You.
    func refreshUser() async {
        if let fresh = try? await client.status().user { user = fresh }
    }
    /// What the owner set, in the guide, and what this account chose, for Apple TV's guide and channels.
    func learnTvLook(from guide: Guide, client: WittyClient) async {
        let saved = try? await client.tvSaved()
        tvColours = TvLook.colours(saved: saved, ownerTheme: guide.theme, ownerLayout: guide.layout, ownerSkin: guide.skin, app: tvAppColours)
        tvLogos = saved?.logos ?? true
    }

    /// The app's theme, for the WittyTV themes that follow it.
    var tvAppColours: TvAppColours {
        let t = appTheme
        func hex(_ c: ThemeColour) -> String { String(c.over(t.background).hex.prefix(7)) }
        return TvAppColours(bg: hex(t.background), bg2: hex(t.panel), bg3: hex(t.card), bg4: hex(t.raised), fg: hex(t.text),
                            fg2: hex(t.textSecondary), accent: hex(t.accent), accentText: hex(t.accentText),
                            accentFg: hex(t.onAccent), border: hex(t.raised))
    }
    /// Nothing for the automatic theme, so the device's own light or dark comes through to be followed.
    var scheme: ColorScheme? {
        if themeChoice == "auto" { return nil }
        return appTheme.isLight ? .light : .dark
    }

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
        listening.forget()
        Keychain.clear()
        TopShelfWriter.clear()
        ArtCache.shared.removeAllObjects()
        user = nil
        libraries = []
        navPrefs = NavPrefs()
        modulePages = []
        legal = nil
        menuOpen = false
        gamePCs = false
        video?.stop()
        video = nil
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
            learn(status)
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
        let checked = proof.saved(url: saved.url, name: saved.name, brandLogo: saved.brandLogo)
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
                learn(try await client.status())
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
        listening.forget()
        client = WittyClient(base: "")
        paths = [:]
        stage = proof.state == .bad ? .connect(message: say("identityBad")) : .mismatch(proof.saved(url: using.url, name: using.name, brandLogo: using.brandLogo))
    }

    /// Someone chose this server, and it says it's a WittyMediaServer. Its identity
    /// decides what comes next. Answers words to show if that's nowhere.
    func arrive(url: String, status: ServerStatus) async -> String? {
        let proof = await WittyClient.identify(url, saved: recent)
        let pin = Keychain.pin
        let checked = proof.saved(url: url, name: status.displayName, brandLogo: PlainWords.clean(status.brandLogo ?? "", limit: 64))
        let step = Identity.nextStep(proof.state, tokenFits: !pin.isEmpty && tokenFits(pin: pin, proof: proof))
        if step != .refuse && step != .lost { learn(status) }
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
            stage = .mismatch(proof.saved(url: shown.url, name: shown.name, brandLogo: shown.brandLogo))
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
            stage = .mismatch(proof.saved(url: shown.url, name: shown.name, brandLogo: shown.brandLogo))
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
    enum SignInOutcome: Equatable {
        case signedIn
        /// The account asks for the code from an authenticator app. The words say why when a code was wrong.
        case needsCode(String)
        /// The name and password didn't match. The screen words it, since it knows which was asked for.
        case wrong
        case failed(String)
    }

    /// A name and password, and the authenticator's code when the account has asked for one.
    func passwordSignIn(name: String, password: String, code: String = "") async -> SignInOutcome {
        if let current, let refused = await refuseToSend(to: current) { return .failed(refused) }
        do {
            let result = try await client.login(name: name, password: password, device: deviceName, code: code)
            signedIn(token: result.token, user: result.user)
            return .signedIn
        } catch let error as APIError {
            if error.twoFactor { return .needsCode(code.isEmpty ? "" : error.message) }
            // The server's own 429 words already say how long to wait.
            if error.status == 401 { return .wrong }
            return .failed(error.message)
        } catch {
            return .failed(plainWords(Problem.of(error)))
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
        Task { await loadThemes() }
        if user == nil {
            Task { self.user = try? await client.status().user }
        }
    }

    /// The last place listened to is sent before the sign-in ends.
    private func endSession() {
        let old = client
        let placeSent = listening.forget()
        guard !old.token.isEmpty else { return }
        Task {
            await placeSent?.value
            try? await old.logout()
        }
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
        themeChoice = ""
        themeList = nil
        customTheme = nil
        appTheme = SharedData.appTheme("default")
        brandName = ""
        brandLogo = ""
        stage = .connect(message: "")
    }

    /// What a server says about how it looks: its theme, and the owner's name and logo for it.
    private func learn(_ status: ServerStatus) {
        serverVersion = status.version ?? ""
        serverUpdate = status.update ?? ""
        themeId = status.theme
        themeChoice = defaults.string(forKey: "theme." + client.base) ?? ""
        refreshTheme()
        brandName = PlainWords.clean(status.brandName ?? "", limit: 60)
        brandLogo = PlainWords.clean(status.brandLogo ?? "", limit: 64)
        rememberLook(of: status)
    }

    /// An added server's name and logo go with it into the list of servers, the logo's picture kept on the device.
    private func rememberLook(of status: ServerStatus) {
        guard let saved = current else { return }
        let updated = saved.with(name: status.displayName, brandLogo: brandLogo)
        if updated != saved {
            current = updated
            recent = recent.map { $0.url == updated.url ? updated : $0 }
        }
        let version = brandLogo
        guard !version.isEmpty, LogoCache.image(server: updated.url, version: version) == nil,
              let url = client.brandLogoURL(version: version) else { return }
        let asking = client
        Task {
            guard let data = try? await asking.imageData(url) else { return }
            LogoCache.keep(data, server: updated.url, version: version)
            objectWillChange.send()
        }
    }

    /// The address of the server used last, which the connect screen marks.
    var lastUsedURL: String { server }

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

    /// A library from the strip along the top or the Menu: its page on Home's stack. From another library's
    /// page it takes that one's place, as the website's strip does, rather than piling up.
    /// Every place in the menu, in this person's order: Home, TV guide, libraries, Collections, Game PCs, modules' pages.
    var navPlaces: [NavPlace] {
        NavPlaces.arrange(NavPlaces.all(libraries: libraries, gamePCs: gamePCs, modulePages: modulePages.map { ($0.module, $0.page) }), navPrefs)
    }

    /// The strip's places: the menu's but Home and TV guide, which are on the bar.
    var stripPlaces: [NavPlace] { NavPlaces.strip(navPlaces) }

    /// A server page that's a top of its own (Collections, Game PCs, a module's page): it gets the strip, not Back.
    func isTopPage(_ path: String) -> Bool { stripPlaces.contains { $0.path == path } }

    /// A film or TV library's page with something chosen (`/library/3?genre=Drama`), which this app shows itself.
    /// Nil for anything else, and for a library the app hands to the server's page.
    func libraryPage(_ path: String) -> (library: Library, state: LibraryState)? {
        guard let (id, state) = LibraryState.page(path), state != LibraryState(),
              let library = libraries.first(where: { $0.id == id }),
              library.opensHere, !library.isRigGames else { return nil }
        return (library, state)
    }

    /// The menus' arrangement, modules' pages and the legal notices, asked for once a person is in.
    func loadNavigation() async {
        async let bundles = try? client.moduleBundles()
        async let prefs = try? client.prefs()
        async let mine = try? client.interfaceChoice("nav", as: NavPrefs.self)
        async let notices = try? client.legalNotices()
        async let couch = try? client.couchStatus()
        let (found, owner, own, words, pcs) = await (bundles, prefs, mine, notices, couch)
        modulePages = (found ?? []).flatMap { bundle in (bundle.pages ?? []).map { ModulePlace(module: bundle.id, page: $0) } }
        navPrefs = own ?? NavPrefs.owner(owner?.navDefault) ?? NavPrefs()
        if let words { legal = words }
        if let pcs { gamePCs = pcs.allowed == true }
    }

    /// A place in the strip or the menu, as the website goes there: a library's page, or the server's page.
    func open(_ place: NavPlace) {
        if let id = place.libraryId, let library = libraries.first(where: { $0.id == id }) {
            openLibrary(library)
            return
        }
        let route: Route = place.id == "couch" ? .web(WebPlayer.gamePCsPath) : .page(place.path)
        var transaction = Transaction()
        transaction.disablesAnimations = tab == .home && (paths[.home]?.count ?? 0) == 1
        withTransaction(transaction) {
            tab = .home
            paths[.home] = [route]
        }
    }

    func openLibrary(_ library: Library) {
        let route = libraryRoute(library)
        var transaction = Transaction()
        // From a section to a section: no slide, as the website's strip changes the page in place.
        transaction.disablesAnimations = tab == .home && (paths[.home]?.count ?? 0) == 1
        withTransaction(transaction) {
            tab = .home
            paths[.home] = [route]
        }
    }

    /// The player's screen, if it's the one showing.
    var showsPlayer: Bool { if case .player? = path.last { return true } else { return false } }

    /// Back to the full player from the dock.
    func expandVideo() {
        guard let video, !showsPlayer else { return }
        path.append(.player(video.id, startOver: false))
    }

    /// Back to the app, playing on in the dock.
    func minimizeVideo() {
        if showsPlayer { path.removeLast() }
    }

    /// Stops it, wherever it is.
    func closeVideo() {
        video?.stop()
        video = nil
        if showsPlayer { path.removeLast() }
    }

    /// The end of one: the next episode or the next in a list, on the screen it was on, or in the dock.
    func videoFinished(next: Int64?, from id: Int64) {
        let showing: Bool = { if case .player(let shown, _)? = path.last { return shown == id } else { return false } }()
        guard let then = next ?? ServerPages.next(after: id, in: playingList) else {
            closeVideo()
            return
        }
        if showing {
            path.removeLast()
            path.append(.player(then, startOver: false))
        } else {
            video?.stop()
            let following = PlaybackModel()
            following.onFinished = { [weak self] after in self?.videoFinished(next: after, from: then) }
            video = following
            Task { await following.start(id: then, client: client, startOver: false) }
        }
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
