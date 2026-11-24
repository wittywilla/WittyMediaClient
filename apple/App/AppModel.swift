// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
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
    /// How this device reaches the server from away: see AwayViews.swift.
    case away
    /// The servers this device remembers, to remove: see ManageServersViews.swift.
    case servers
    /// Skipping by itself and canvases, on this device: see MediaPages.swift.
    case mediaExtras
    /// The server's layout options for this device, and modules' settings: see LayoutModulesSettings.swift.
    case modules
    /// This profile's own colours over the theme: see PersonalColoursView.swift.
    case personalColours
    /// The layout editor (LayoutEditor.swift) and the server's name and mark editor, for administrators (BrandEditor.swift).
    case layoutEditor, brandEditor
    case moduleSettings(String)
    /// Apple TV's choice of libraries for the top menu: see YouViews.swift.
    case topMenu
    /// WittyPlay on Apple TV: a games library or one console's games in it, a game's page, and a
    /// game being played. See GamesViews.swift and GamePlayer.swift.
    case gameLibrary(Library, console: String?)
    case game(Int64)
    case playGame(Int64, GameStart)
    /// A server-driven page: see SDUI/SDUICenter.swift.
    case sdui(SDUIPlace)
    /// Switching profile, and the profiles this account looks after: see Household.swift and ProfileSwitch.swift.
    case family(FamilyRoute)
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
        didSet { applyShape() }
    }
    /// Every theme the server has, once asked.
    @Published private(set) var themeList: ThemeList?
    /// Which look and theme an administrator requires of this profile, and for whom: Settings > Appearance shows them locked.
    @Published private(set) var requiredLook: LookState?
    /// The look this person made with the website's theme maker.
    @Published private(set) var customTheme: ThemeMakerInput?
    private var themeFetch: Task<Void, Never>?
    /// The owner's own name and logo for the server, from `/status`, shown on the sign-in screens.
    @Published var brandName = ""
    @Published var brandLogo = ""
    @Published var user: User? {
        didSet { if oldValue?.id != user?.id || oldValue?.name != user?.name { loadTopMenu() } }
    }
    /// The libraries this person added to Apple TV's top menu, by id: docs/APP-DESIGN.md, On a TV. Kept on the
    /// device, per server and per profile.
    @Published private(set) var topMenu: [Int64] = []
    /// Music, audiobooks and podcasts, which carry on whatever screen is showing.
    let listening = Listening()
    /// What this profile may do and its screen time: see Household.swift.
    let household = Household()
    /// Playing on other devices, being played on from them, and watch parties: see RemoteHub.swift.
    let remote = RemoteHub()
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
    static let keychainNoticeClosed = "keychainNoticeClosed"

    /// The notice closed by its ×. The one about the keychain stays closed on this device: on a copy that isn't signed
    /// it would otherwise come back at every sign-in.
    func closeNotice() {
        if notice.hasPrefix("This copy of the app isn't signed") { UserDefaults.standard.set(true, forKey: Self.keychainNoticeClosed) }
        notice = ""
    }
    /// What this server can do, by the names in its `/capabilities`. Everything newer than the app's first
    /// version is offered only when its name is here, so an older server just doesn't show it.
    @Published private(set) var features: Set<String> = []
    /// Whether this server has been asked what it can do yet, and has answered or failed to.
    @Published private(set) var featuresKnown = false

    func has(_ feature: String) -> Bool { features.contains(feature) }

    /// The server whose features were last asked for, so opening it and learning its status ask once.
    private var featuresAsked = ""

    /// Asked for whenever a server is opened, signed in or not: signing in has newer ways too. `again` asks a
    /// server that was asked already (its status was read again, and it may have been updated since).
    private func learnFeatures(again: Bool = true) {
        let asking = client
        // A status can arrive before the server is opened (a server just chosen, still to be signed in to):
        // there is nothing to ask then, and opening it asks.
        guard !asking.base.isEmpty, again || featuresAsked != asking.base else { return }
        featuresAsked = asking.base
        Task {
            let caps = try? await asking.capabilities()
            guard client.base == asking.base else { return }
            if let caps {
                let found = Set(caps.features ?? [])
                if found != features {
                    let newTheme = found.contains("theme-derived") && !features.contains("theme-derived")
                    features = found
                    // The theme's layers can be asked for now.
                    if newTheme { refreshTheme() }
                }
            }
            featuresKnown = true
        }
    }

    // Published, so the screens that get it from the environment never see the one before it.
    @Published private(set) var client = WittyClient(base: "") {
        didSet { ClientLog.shared.use(client) }
    }

    /// How the server is being reached: at home, or from away, peer to peer. AwayModel.swift has
    /// everything about it; the manager chooses, and every connection made here follows it.
    @Published var way: PeerManager.Way = .none
    private(set) lazy var peers: PeerManager = makePeers()
    var awayWatch: AwayWatch?
    /// Counts changes of the address on this device, for the one thing that can't follow them
    /// by itself: a web view, which is made again.
    @Published var routeStamp = 0

    /// The server the sign-in screens talk to. Its key waits here for a token to be
    /// kept with, unless it was already pinned.
    private(set) var current: SavedServer?

    let defaults = UserDefaults.standard
    private var started = false
    private var waitingLink: DeepLink?

    var path: [Route] {
        get { paths[tab] ?? [] }
        set { paths[tab] = playing(newValue, was: paths[tab] ?? []) }
    }

    func pathBinding(_ tab: AppTab) -> Binding<[Route]> {
        Binding(get: { self.paths[tab] ?? [] }, set: { self.paths[tab] = self.playing($0, was: self.paths[tab] ?? []) })
    }

    // MARK: WittyPlay

    /// WittyPlay is on this server (its entry is in the server's menu). Set by the shell from the navigation.
    @Published var wittyPlayInstalled = false
    /// WittyPlay is open over the whole app, at this address of its own: see WittyPlayFrame.swift.
    @Published var wittyPlay: String?

    /// A games place WittyPlay takes over on a phone and a tablet, as on the website: a games library, a game's page,
    /// WittyPlay's own pages. Its address in WittyPlay, or nil to open it in the app as before.
    func wittyPlayAddress(_ route: Route) -> String? {
        #if os(iOS) || os(visionOS) || os(tvOS)
        guard wittyPlayInstalled else { return nil }
        switch route {
        case .library(let library) where library.hasGameScreens: return WittyPlayPlace.library(library.id)
        case .gameLibrary(let library, _): return WittyPlayPlace.library(library.id)
        case .page(let path) where WittyPlayPlace.isPlayPath(path): return path
        #if os(tvOS)
        // Apple TV draws WittyPlay's pages itself (in its frame, SDUIPageView.swift): they are already where they go.
        case .sdui(let place) where WittyPlayPlace.isPlayPage(place.page): return nil
        #else
        case .sdui(let place) where WittyPlayPlace.isPlayPage(place.page):
            return place.route.flatMap { WittyPlayPlace.isPlayPath($0) ? $0 : nil } ?? "/page/" + place.page
        #endif
        case .sdui(let place) where place.page == "library":
            // The server's page for a library: a games library's is WittyPlay's view of it.
            guard let id = place.params["library"].flatMap({ Int64($0) }),
                  let library = libraries.first(where: { $0.id == id }), library.hasGameScreens else { return nil }
            return WittyPlayPlace.library(id, query: place.params)
        default: return nil
        }
        #else
        return nil
        #endif
    }

    /// Going to a place WittyPlay takes over opens WittyPlay instead: over everything on a phone and a tablet, and in its
    /// place on the stack on Apple TV.
    private func playing(_ new: [Route], was old: [Route]) -> [Route] {
        guard new.count > old.count, let last = new.last, let address = wittyPlayAddress(last) else { return new }
        #if os(tvOS)
        return Array(new.dropLast()) + [Self.wittyPlayRoute(address)]
        #else
        wittyPlay = address
        return Array(new.dropLast())
        #endif
    }

    /// WittyPlay's page for an address, as Apple TV draws it.
    static func wittyPlayRoute(_ address: String) -> Route {
        let found = WittyPlayPlace.page(for: address)
        let query = found.params.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        return .sdui(SDUIPlace(page: found.page, params: found.params, route: "/page/" + found.page + (query.isEmpty ? "" : "?" + query)))
    }

    /// Opens WittyPlay at an address of its own: a phone's and a tablet's cover, or Apple TV's page from Home.
    func openWittyPlay(_ address: String) {
        #if os(tvOS)
        tab = .home
        paths[.home] = [Self.wittyPlayRoute(address)]
        #else
        wittyPlay = address
        #endif
    }

    /// The player and the game page have the whole screen.
    var hidesBars: Bool {
        switch path.last {
        case .player?, .web?, .playGame?: return true
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
        // A theme an administrator requires of this profile is the theme, whatever this device chose.
        if let required = requiredLook?.requiredTheme?.value, !required.isEmpty { return required }
        switch themeChoice {
        case "": return themeId
        case "auto": return systemScheme == .light ? "light" : "default"
        case "custom": return customTheme == nil ? themeId : "custom"
        default: return themeChoice
        }
    }

    var palette: Palette { Palette(appTheme) }

    private var topMenuKey: String { "topMenu." + client.base + "." + (user?.name ?? "") }

    private func loadTopMenu() {
        let kept = (defaults.array(forKey: topMenuKey) as? [NSNumber])?.map(\.int64Value) ?? []
        if kept != topMenu { topMenu = kept }
    }

    /// Adds a library to the top menu, or takes it out. A tab taken out while it's showing gives way to Home.
    func toggleTopMenu(_ library: Library) {
        if topMenu.contains(library.id) {
            topMenu.removeAll { $0 == library.id }
            if tab == .library(library.id) { tab = .home }
        } else {
            topMenu.append(library.id)
        }
        defaults.set(topMenu.map { NSNumber(value: $0) }, forKey: topMenuKey)
    }

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
        let following = themeChoice.isEmpty
        let resolving = has("theme-derived") || has("theme-shape-type")
        let systemDark = systemScheme != .light
        themeFetch = Task { [weak self] in
            // A server with the theme engine's layers says the colours this account sees: the theme with the
            // administrator's overrides and the profile's own colours over it. Followed when this device follows
            // the server's theme; its corners, typefaces and name are used either way.
            if resolving, let resolved = try? await asking.resolvedTheme(), !Task.isCancelled, let self, self.client.base == asking.base {
                // The theme's own look decides; only the automatic theme follows the device's light or dark setting.
                let dark = resolved.scheme == "auto" ? systemDark : resolved.scheme != "light"
                self.themeStyle = ThemeStyle(shape: resolved.shape(dark: dark), type: resolved.typefaces(dark: dark), brand: resolved.brand, colors: resolved.colors(dark: dark))
                self.look = resolved.experienceLook ?? .plain
                if following, self.themeChoice.isEmpty {
                    let colors = resolved.colors(dark: dark)
                    if !colors.isEmpty {
                        let tokens = ThemeTokens(id: resolved.look(dark: dark)?.id ?? id, scheme: dark ? "dark" : "light", colors: colors)
                        if let data = try? JSONEncoder().encode(tokens) { self.defaults.set(data, forKey: self.tokensKey(id)) }
                        self.appTheme = ThemeTranslator.translate(tokens, preview: self.preview(id)).with(tv: resolved.tvColours(dark: dark))
                        return
                    }
                }
            }
            guard let tokens = try? await asking.themeTokens(id), !Task.isCancelled, let self,
                  self.client.base == asking.base, (self.effectiveThemeId ?? "default") == id else { return }
            if let data = try? JSONEncoder().encode(tokens) { self.defaults.set(data, forKey: self.tokensKey(id)) }
            self.appTheme = ThemeTranslator.translate(tokens, preview: self.preview(id))
        }
    }

    /// The experience's effects, corners and type set with the theme's finish and scene (`look` in `GET /theme`): what every
    /// surface is finished with (App/LookKit.swift). Plain until the server says.
    @Published private(set) var look: ExperienceLook = .plain {
        didSet { applyShape() }
    }

    /// The corners and the type set of the look in use: the theme's radius times the experience's multiple.
    private func applyShape() {
        Tokens.Radius.theme = CGFloat(appTheme.radius * look.radiusMultiple)
        TypeSet.current = look.type
    }

    /// The resolved theme's corners, typefaces and the server's name, on a server that has them: what server-driven
    /// pages draw with (SDUI/SDUIKit.swift). Nil keeps what the app draws by itself.
    @Published private(set) var themeStyle: ThemeStyle?

    /// What themes the server has, and the person's own, once signed in.
    func loadThemes() async {
        let asking = client
        async let list = try? asking.themeList()
        async let made = try? asking.customTheme()
        async let modules = has("sdui-modules") ? try? asking.themeModules() : nil
        async let look = try? asking.lookState()
        let (l, m, scopes, required) = await (list, made, modules, look)
        guard client.base == asking.base else { return }
        if required != requiredLook { requiredLook = required }
        if let l { themeList = l }
        customTheme = m ?? nil
        let palettes = scopes?.tokens ?? [:]
        if palettes != modulePalettes { modulePalettes = palettes }
        refreshTheme()
    }

    /// Each module's colours, for its screens drawn by this app itself: see ThemeModules in WittyKit.
    @Published private(set) var modulePalettes: [String: [String: String]] = [:]

    /// The account as the server has it now, after a change from You.
    func refreshUser() async {
        if let fresh = try? await client.status().user { user = fresh }
    }
    /// What the owner set, in the guide, and what this account chose, for Apple TV's guide and channels.
    func learnTvLook(from guide: Guide, client: WittyClient) async {
        let saved = try? await client.tvSaved()
        tvColours = TvLook.colours(saved: saved, ownerTheme: guide.theme, app: tvAppColours)
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
        useAway(for: opening)
        client = connection(to: opening.url, token: token)
        // What it can do decides whether Home and Search are the server's pages; until it's known they wait.
        // The status that brought it here may have been read before there was a connection to ask with.
        learnFeatures(again: false)
        let theme = defaults.string(forKey: "theme." + client.base) ?? ""
        if theme != themeChoice {
            themeChoice = theme
            refreshTheme()
        }
    }

    /// On to signing in, for a server that has been checked.
    func signIn(to opening: SavedServer, way: SignInWay = .usual) {
        forgetSignIn()
        openServer(opening)
        stage = .signIn(way)
    }

    private func forgetSignIn() {
        listening.forget()
        household.forget()
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
    func openWithToken(_ opening: SavedServer) async -> String? {
        remember(opening)
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
                watchWay()
            } else {
                // The server doesn't know this sign-in any more, so it's no use keeping.
                Keychain.clear()
                client = connection(to: opening.url)
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

    /// The key kept with the token decides: only the server that proved that key gets it.
    func tokenFits(pin: String, proof: ServerProof) -> Bool {
        !Keychain.token.isEmpty && Identity.fits(pin: pin, proof: proof)
    }

    /// What the last run was using, if it still is who it was. Its token goes
    /// nowhere until then.
    func start() async {
        guard !started else { return }
        started = true
        #if DEBUG
        if await startForTests() { return }
        #endif
        let url = server
        guard !url.isEmpty else {
            stage = .connect(message: "")
            #if DEBUG
            await connectForCheck()
            #endif
            return
        }
        var saved = recent.first { $0.url == url } ?? SavedServer(url: url, name: "WittyMediaServer")
        var proof = await WittyClient.identify(url, saved: [saved])
        if proof.state == .unreachable {
            // Not where it was. It may have moved on the home network, or this device isn't at home:
            // the network is searched for it, and meanwhile the other way to it is started, if this
            // device was put on the server's list while it was at home.
            let home = saved
            let away = canReachFromAway(home) ? Task { await reachFromAway(home) } : nil
            if !saved.serverId.isEmpty, let found = await ServerFinder.find(id: saved.serverId, waitSeconds: 6) {
                let moved = saved.moved(to: found.url)
                let there = await WittyClient.identify(found.url, saved: [moved])
                if there.state != .unreachable {
                    away?.cancel()
                    peers.close()
                    saved = moved
                    proof = there
                }
            }
            if proof.state == .unreachable, let away, await away.value {
                proof = await WittyClient.identify(saved.url, saved: [saved], route: routeFor(saved.url))
            }
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

    #if DEBUG
    /// For the UI tests and for checking a screen on a simulator, in debug builds only:
    /// `-WMCServer http://localhost:9000 -WMCUser name -WMCPassword word` opens that server and signs in,
    /// with nothing kept from the run before. The address must be this machine's own.
    private func startForTests() async -> Bool {
        let given = UserDefaults.standard
        guard let url = given.string(forKey: "WMCServer"), let host = URL(string: url)?.host,
              ["localhost", "127.0.0.1", "::1"].contains(host) else { return false }
        Keychain.clear()
        let opening = SavedServer(url: url, name: "WittyMediaServer")
        openServer(opening)
        guard let status = try? await client.status() else {
            stage = .connect(message: say("errLost"))
            return true
        }
        learn(status)
        guard let name = given.string(forKey: "WMCUser") else {
            stage = .signIn(.usual)
            return true
        }
        do {
            let result = try await client.login(name: name, password: given.string(forKey: "WMCPassword") ?? "", device: deviceName)
            signedIn(token: result.token, user: result.user)
            openForMediaTests()
        } catch {
            stage = .signIn(.usual)
        }
        return true
    }
    #endif

    /// Coming back to an app left running counts as starting it. Nothing answering is
    /// left to the screens, as the network is often still waking up.
    func recheck() async {
        guard let using = current, !client.token.isEmpty else { return }
        let proof = await WittyClient.identify(using.url, saved: [using], route: routeFor(using.url))
        guard proof.state == .different || proof.state == .bad else { return }
        current = nil
        listening.forget()
        peers.close()
        client = WittyClient(base: "")
        paths = [:]
        stage = proof.state == .bad ? .connect(message: say("identityBad")) : .mismatch(proof.saved(url: using.url, name: using.name, brandLogo: using.brandLogo))
    }

    /// Someone chose this server, and it says it's a WittyMediaServer. Its identity
    /// decides what comes next. Answers words to show if that's nowhere.
    func arrive(url: String, status: ServerStatus) async -> String? {
        let proof = await WittyClient.identify(url, saved: recent, route: routeFor(url))
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
            remember(shown)
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
        let proof = await WittyClient.identify(shown.url, saved: shown.publicKey.isEmpty ? [] : [shown], route: routeFor(shown.url))
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
            let result = try await connection(to: to.url, quick: true).pairRedeem(code: code, device: deviceName, platform: platformName)
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
        /// Leaving this kids' profile takes the parents' PIN. The words say why when the one typed was wrong.
        case needsParentPin(String)
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

    /// Another profile on this device, without signing out first: the server signs it in and ends the sign-in it
    /// came from in one step, so the new token is kept exactly as a sign-in's is, with the key the server proved.
    /// Everything of the profile being left goes, as signing out does it. What was playing stops first, so its
    /// place is saved while its sign-in still counts.
    func switchProfile(name: String, password: String, code: String = "", parentPin: String = "") async -> SignInOutcome {
        if let current, let refused = await refuseToSend(to: current) { return .failed(refused) }
        video?.stop()
        video = nil
        await listening.forget()?.value
        do {
            let result = try await client.switchProfile(name: name, password: password, code: code, device: deviceName, parentPin: parentPin)
            forgetSignIn()
            signedIn(token: result.token, user: result.user)
            return .signedIn
        } catch let error as APIError {
            if error.needsParentPin { return .needsParentPin("") }
            if error.wrongParentPin || (error.status == 429 && !parentPin.isEmpty) { return .needsParentPin(error.message) }
            switch SwitchRules.refusal(error, sentCode: !code.isEmpty) {
            case .needsCode(let wrong): return .needsCode(wrong ? error.message : "")
            // A wrong password is a 403 here, and the device stays signed in as it was. The server's words say
            // what was wrong, or how long to wait.
            case .wait, .refused: return .failed(error.status == 401 ? handle(error) : error.message)
            }
        } catch {
            return .failed(plainWords(Problem.of(error)))
        }
    }

    /// The address, the key it proved and the token are kept together.
    func signedIn(token: String, user: User? = nil) {
        let kept = current ?? SavedServer(url: client.base, name: "WittyMediaServer")
        let keptSignIn = Keychain.save(token: token, pin: kept.publicKey)
        // A notice the person closed for good (an unsigned test copy's) isn't said again at every sign-in.
        notice = keptSignIn || UserDefaults.standard.bool(forKey: Self.keychainNoticeClosed) ? "" : KeychainWords.notice(status: Keychain.lastFailure)
        server = kept.url
        remember(kept)
        client = connection(to: kept.url, token: token)
        self.user = user
        paths = [:]
        tab = .home
        stage = .browsing
        watchWay()
        Task { await loadThemes() }
        if user == nil {
            Task { self.user = try? await client.status().user }
        }
    }

    /// The last place listened to is sent before the sign-in ends.
    /// `first` is whatever else has to be said to the server while the sign-in still stands.
    private func endSession(first: (@MainActor (WittyClient) async -> Void)? = nil) {
        let old = client
        let placeSent = listening.forget()
        guard !old.token.isEmpty else { return }
        Task {
            await placeSent?.value
            await first?(old)
            await remote.goodbye()
            try? await old.logout()
        }
    }

    func signOut() {
        endSession()
        forgetSignIn()
        client = connection(to: client.base)
        stage = .signIn(.usual)
    }

    /// Signing out from a button: a kids' profile kept on this device asks for the parents' PIN first, on the
    /// Who's watching page (ProfileSwitch.swift). Every other profile signs out as before.
    func requestSignOut() {
        guard household.limits?.pinToLeave == true else { signOut(); return }
        household.leavingWithPin = true
        if path.last != .family(.switchProfile) { path.append(.family(.switchProfile)) }
    }

    /// Signs out with the parents' PIN. Nil when it worked; otherwise the words to show.
    func signOut(parentPin: String) async -> String? {
        do {
            try await client.logout(pin: parentPin)
        } catch let error as APIError {
            if error.needsParentPin || error.wrongParentPin || error.status == 429 { return error.message }
        } catch {
            // Not reached: signed out here all the same, as signing out always is.
        }
        household.leavingWithPin = false
        signOut()
        return nil
    }

    func changeServer() {
        // Leaving a server takes this device off its list for connections from away, as on the desktop.
        if let leaving = current, !client.token.isEmpty {
            endSession { [weak self] old in
                await self?.forgetAway(on: old, server: leaving)
                if self?.peers.current?.home == leaving.url { self?.peers.close() }
            }
        } else if let leaving = current {
            // Nobody is signed in, so the server can't be told; this device forgets its side all the same.
            let old = client
            endSession()
            Task {
                await forgetAway(on: old, server: leaving)
                if peers.current?.home == leaving.url { peers.close() }
            }
        } else {
            endSession()
            peers.close()
        }
        forgetSignIn()
        current = nil
        server = ""
        client = WittyClient(base: "")
        themeId = nil
        themeStyle = nil
        features = []
        featuresKnown = false
        featuresAsked = ""
        themeChoice = ""
        themeList = nil
        customTheme = nil
        appTheme = SharedData.appTheme("default")
        look = .plain
        brandName = ""
        brandLogo = ""
        stage = .connect(message: "")
    }

    /// After the name, its colours, the mark or the logo changed: asks the server how it looks now.
    func refreshBrand() async {
        guard let status = try? await client.status() else { return }
        learn(status)
    }

    /// What a server says about how it looks: its theme, and the owner's name and logo for it.
    private func learn(_ status: ServerStatus) {
        // A server updated since it was asked may do more now.
        let updated = serverVersion != (status.version ?? "")
        serverVersion = status.version ?? ""
        serverUpdate = status.update ?? ""
        themeId = status.theme
        learnFeatures(again: updated)
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
            client = connection(to: client.base)
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
        if let address = wittyPlayAddress(route) { openWittyPlay(address); return }
        var transaction = Transaction()
        transaction.disablesAnimations = tab == .home && (paths[.home]?.count ?? 0) == 1
        withTransaction(transaction) {
            tab = .home
            paths[.home] = [route]
        }
    }

    func openLibrary(_ library: Library) {
        let route = libraryRoute(library)
        if let address = wittyPlayAddress(route) { openWittyPlay(address); return }
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
            remote.adopt(following, id: then)
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

    #if DEBUG
    /// `-WMCOpen` is followed once a run.
    private var openedForTests = false
    #endif

    private func openWaitingLink() {
        #if DEBUG
        // For checking a game on the simulator: `-WittyPlayOpenGame <id>` at launch opens its page
        // on Apple TV; `-WittyPlayPlayGame <id>` plays it, on any device.
        let play = UserDefaults.standard.integer(forKey: "WittyPlayPlayGame")
        if play > 0, paths[.home]?.isEmpty ?? true {
            paths[.home] = [.playGame(Int64(play), .resume)]
            return
        }
        #endif
        #if DEBUG
        // For apple/scripts/p2p-check.sh: `-WittyCheckPlay <id>` plays that item, from its start.
        let film = UserDefaults.standard.integer(forKey: "WittyCheckPlay")
        if film > 0, paths[.home]?.isEmpty ?? true {
            paths[.home] = [.player(Int64(film), startOver: true)]
            return
        }
        #endif
        #if DEBUG && os(tvOS)
        let game = UserDefaults.standard.integer(forKey: "WittyPlayOpenGame")
        if game > 0, paths[.home]?.isEmpty ?? true {
            paths[.home] = [.game(Int64(game))]
            return
        }
        #endif
        #if DEBUG
        // For the UI tests and for checking a page on a simulator: `-WMCOpen /library/3` at launch opens that
        // route as a link from outside would, once someone is signed in.
        if !openedForTests, waitingLink == nil, let route = UserDefaults.standard.string(forKey: "WMCOpen"), DeepLink.isOpenable(route) {
            openedForTests = true
            waitingLink = .route(route)
        }
        #endif
        guard let link = waitingLink else { return }
        waitingLink = nil
        tab = .home
        switch link {
        case .item(let id): paths[.home] = [.item(id)]
        case .show(let id): paths[.home] = [.show(id)]
        case .route(let route): openFromOutside(route: route)
        }
    }
}
