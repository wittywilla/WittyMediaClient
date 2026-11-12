// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import SwiftUI
import WittyKit

// What the signed-in profile may do, and its screen time (the server's docs/PROFILES.md). The server does
// the deciding and the stopping: it refuses to play when the time is up and ends what it is sending. This
// only hides what is turned off, says how long is left a few minutes ahead, and when the time is up stops
// every player, says why and until when, and lets a parent give more on the spot. The rules are in
// WittyKit's Household.swift. A profile with no time rules costs one request when it signs in.

/// What a route in the app is for, from here: the places a profile's own account and its household are
/// looked after. One `Route` case carries them all: see FamilyScreen in ProfileSwitch.swift.
enum FamilyRoute: Hashable {
    /// Who's watching, for a device that is already signed in.
    case switchProfile
    /// The person's own picture.
    case myPicture
    /// The profiles this account manages, one of them, and its pages.
    case profiles, addProfile, parentPin
    case profile(Int64), look(Int64), secret(Int64), report(Int64)
    case limits(Int64, LimitsPage)
}

enum LimitsPage: String, Hashable {
    case see, kinds, hideGenres, onlyGenres, collections, allowed, time
}

@MainActor
final class Household: ObservableObject {
    /// The one the players tell about a refusal: they have no model of their own to reach it through.
    private(set) static weak var current: Household?

    /// Nil until the server has answered, and for a server without parental controls: everything is offered then.
    @Published private(set) var limits: MyLimits?
    @Published private(set) var time: ScreenTime?
    /// Why playing stopped, while the screen that says so is up.
    @Published private(set) var timeUp: ScreenTime?
    /// "5 minutes of screen time left", for a few seconds.
    @Published private(set) var notice = ""
    /// The profiles to switch to, as asked for last.
    @Published var people: [HouseholdProfile] = []

    private var client = WittyClient(base: "")
    private var warner = ScreenTimeWarner()
    private var watch: Task<Void, Never>?
    private var noticeEnds: Task<Void, Never>?
    private var wasAllowed = true
    private var listsTask: Task<ParentalLists?, Never>?
    /// The profiles this account manages, for You's pages: see ProfileSettings.swift.
    let desk = ProfileDesk()
    /// Whether a screen that plays something is up, which the guard below keeps: a refusal with nothing on
    /// screen to stop (the guide's small preview) isn't worth a notice over the whole app.
    fileprivate var playerShowing = false

    init() { Household.current = self }

    /// Whether a part of the app is offered to this profile. Unknown means yes: the server refuses what is off.
    func allows(_ feature: String) -> Bool { limits?.allows(feature) ?? true }
    var isTimed: Bool { limits?.isTimed ?? false }
    var hasParentPin: Bool { limits?.parentPin == true }

    /// The tabs a bar shows, less the ones turned off for this profile.
    func shown(_ tabs: [AppTab]) -> [AppTab] {
        tabs.filter { tab in
            switch tab {
            case .games: return allows(ProfileFeature.games)
            case .guide: return allows(ProfileFeature.liveTv)
            default: return true
            }
        }
    }

    /// Someone is signed in: their limits, and the time if it is counted. `offered` is whether the server has
    /// parental controls at all.
    func use(_ client: WittyClient, offered: Bool) async {
        forget()
        self.client = client
        guard offered, !client.token.isEmpty, let found = try? await client.myLimits(), self.client.token == client.token else { return }
        limits = found
        guard found.isTimed else { return }
        if let now = found.screenTime { take(now) }
        watch = Task { [weak self] in
            while !Task.isCancelled {
                let wait = ScreenTimeRules.nextAsk(after: self?.time, now: Date().timeIntervalSince1970)
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                await self.askNow()
            }
        }
    }

    /// Nobody is signed in, or somebody else is about to be: nothing of the last profile stays.
    func forget() {
        watch?.cancel()
        watch = nil
        noticeEnds?.cancel()
        listsTask = nil
        desk.forget()
        client = WittyClient(base: "")
        limits = nil
        time = nil
        timeUp = nil
        notice = ""
        people = []
        warner = ScreenTimeWarner()
        wasAllowed = true
    }

    /// Asks the server how long is left. `refused` is when something just failed to play: the answer is then
    /// shown even if this profile already knew its time was up.
    func askNow(refused: Bool = false) async {
        let asking = client
        guard isTimed, let now = try? await asking.screenTime(), asking.token == client.token else { return }
        take(now, refused: refused)
    }

    private func take(_ next: ScreenTime, refused: Bool = false) {
        time = next
        if next.allowed {
            timeUp = nil
        } else if wasAllowed || refused {
            timeUp = next
        }
        wasAllowed = next.allowed
        if let words = warner.notice(for: next) { tell(words) }
    }

    private func tell(_ words: String) {
        notice = words
        announce(words)
        noticeEnds?.cancel()
        noticeEnds = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(ScreenTimeRules.noticeSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.notice = ""
        }
    }

    /// Every player calls this with whatever stopped it, before it shows a problem of its own. True when the
    /// profile's screen time is why: the time-up screen says so, and the player stops and says nothing.
    ///
    /// The server's refusal (403 `screen-time`) is recognised at once. A stream the server stopped sending
    /// looks like a network fault from inside a player, so on a profile with time rules the server is asked
    /// whether time is why; once the time is known to be up, anything that fails to play is put down to that
    /// (and the server asked again, in case a parent has just given more). `needsScreen` is for something
    /// playing in a corner of another page: its refusal only matters when a player has the screen.
    static func caught(_ error: Error?, needsScreen: Bool = false) -> Bool {
        guard let me = current else { return false }
        if let error, Problem.of(error) == .cancelled { return false }
        if ScreenTimeRules.featureOff(error) != nil {
            // Turned off since this app last asked: hide it from now on.
            Task { await me.reloadLimits() }
            return false
        }
        if let refusal = ScreenTimeRules.refusal(error) {
            if needsScreen && !me.playerShowing {
                me.time = refusal
                me.wasAllowed = false
                return false
            }
            me.take(refusal, refused: true)
            return true
        }
        guard me.isTimed, !(needsScreen && !me.playerShowing) else { return false }
        Task { await me.askNow(refused: true) }
        guard let known = me.time, !known.allowed else { return false }
        me.timeUp = known
        return true
    }

    private func reloadLimits() async {
        let asking = client
        if let found = try? await asking.myLimits(), asking.token == client.token { limits = found }
    }

    /// OK on the time-up screen. The time is still up: playing again brings the screen back.
    func dismissTimeUp() { timeUp = nil }

    /// A parent gives more time on this device. Answers the server's words when it refuses.
    func askParent(minutes: Int, pin: String, name: String, password: String) async -> String? {
        let asking = client
        do {
            let next = pin.isEmpty ? try await asking.askParent(minutes: minutes, name: name, password: password)
                                   : try await asking.askParent(minutes: minutes, pin: pin)
            guard asking.token == client.token else { return nil }
            take(next)
            if next.allowed { tell("\(ScreenTimeRules.minutesWords(next.left ?? minutes * 60)) of screen time left") }
            return nil
        } catch {
            let words = plainWords(Problem.of(error))
            return words.isEmpty ? "That didn’t work." : words
        }
    }

    /// "Switch profile": Who's watching where the server lists its profiles to this device, signing out where
    /// it doesn't (the Classic sign-in screen, away from home, or an older server), as it always was.
    func startSwitch(_ model: AppModel) {
        guard model.has("profile-switching") else {
            model.signOut()
            return
        }
        let asking = model.client
        Task {
            let list = (try? await asking.household()) ?? []
            guard asking.token == model.client.token else { return }
            if SwitchRules.offersPicker(list) {
                people = list
                if model.path.last != .family(.switchProfile) { model.path.append(.family(.switchProfile)) }
            } else {
                model.signOut()
            }
        }
    }

    /// The rating systems, pictures and switches a settings page offers. Fixed for a server, so asked for once.
    func lists() async -> ParentalLists? {
        if let listsTask { return await listsTask.value }
        let asking = client
        let task = Task { try? await asking.parentalLists() }
        listsTask = task
        let found = await task.value
        if found == nil { listsTask = nil }
        return found
    }
}

extension AppModel {
    /// A screen that is playing something: the time-up screen leaves these.
    private static func plays(_ route: Route) -> Bool {
        switch route {
        case .player, .channel, .playGame: return true
        default: return false
        }
    }

    var showsSomethingPlaying: Bool { path.last.map(AppModel.plays) ?? false }

    /// Whatever is playing stops, and its screen is left for the page it came from. Each player keeps the
    /// place as it goes: a film's is saved as its player closes, and music stays where it was paused.
    func stopPlayingForScreenTime() {
        listening.pause()
        if listening.screenShown { listening.screenShown = false }
        video?.stop()
        video = nil
        for (tab, routes) in paths where routes.contains(where: AppModel.plays) {
            paths[tab] = routes.filter { !AppModel.plays($0) }
        }
    }
}

#if DEBUG
extension AppModel {
    private static var openedForTests = false

    /// For the UI tests and for checking a screen on a simulator, in debug builds only: `-WMCOpen profiles`
    /// opens that page of You once the app is signed in. Also `switch`, `signInTv`, `addProfile`, `parentPin`,
    /// `myPicture`, `profile:<id>`, `look:<id>`, `secret:<id>`, `report:<id>`, `limits:<id>:<page>` and
    /// `player:<item id>`.
    func openForTests() {
        // A route (`/library/3`) is the other test hook's, in AppModel.openWaitingLink: this one takes names.
        guard stage == .browsing, !AppModel.openedForTests, let wanted = UserDefaults.standard.string(forKey: "WMCOpen"),
              !wanted.hasPrefix("/") else { return }
        AppModel.openedForTests = true
        let parts = wanted.split(separator: ":").map(String.init)
        let id = parts.count > 1 ? Int64(parts[1]) ?? 0 : 0
        if parts.first == "player" {
            tab = .home
            paths[.home] = [.player(id, startOver: true)]
            return
        }
        let route: Route?
        switch parts.first {
        case "profiles": route = .family(.profiles)
        case "addProfile": route = .family(.addProfile)
        case "parentPin": route = .family(.parentPin)
        case "myPicture": route = .family(.myPicture)
        case "signInTv": route = .signInTv
        case "profile": route = .family(.profile(id))
        case "look": route = .family(.look(id))
        case "secret": route = .family(.secret(id))
        case "report": route = .family(.report(id))
        case "limits": route = .family(.limits(id, parts.count > 2 ? LimitsPage(rawValue: parts[2]) ?? .see : .see))
        default: route = nil
        }
        guard route != nil || parts.first == "switch" else { return }
        tab = .profile
        if let route { paths[.profile] = [route] }
        if parts.first == "switch" { household.startSwitch(self) }
    }
}
#endif

extension View {
    /// `onChange` as each system wants it written: the one-value form is the only one before iOS 17 and is
    /// deprecated on tvOS 17, which this app starts at.
    @ViewBuilder func whenChanged<V: Equatable>(_ value: V, _ act: @escaping (V) -> Void) -> some View {
        #if os(tvOS) || os(visionOS)
        self.onChange(of: value) { _, new in act(new) }
        #else
        self.onChange(of: value, perform: act)
        #endif
    }
}

// MARK: - Over the whole app

/// Around everything a signed-in person sees: it learns the profile's limits, shows the line about time left,
/// and puts the time-up screen over whatever was on.
struct ScreenTimeGuard: ViewModifier {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var household: Household

    private var signedIn: String {
        "\(model.client.base)|\(model.client.token)|\(model.stage == .browsing)|\(model.has("parental-controls"))"
    }

    func body(content: Content) -> some View {
        let up = household.timeUp
        content
            // Under the time-up screen nothing else answers a remote or a finger.
            .disabled(up != nil)
            .overlay(alignment: .top) {
                if up == nil, !household.notice.isEmpty { TimeLeftPill(words: household.notice) }
            }
            .overlay {
                if let up { TimeUpScreen(household: household, time: up).transition(.opacity) }
            }
            .animation(.easeOut(duration: Tokens.Motion.appear), value: up != nil)
            .animation(.easeOut(duration: Tokens.Motion.appear), value: household.notice)
            .task(id: signedIn) {
                if model.stage == .browsing { await household.use(model.client, offered: model.has("parental-controls")) }
                #if DEBUG
                model.openForTests()
                #endif
            }
            // The bars and You read the limits through the model, so they redraw when the limits arrive.
            .onReceive(household.objectWillChange) { _ in model.objectWillChange.send() }
            .whenChanged(up != nil) { stopped in
                if stopped { model.stopPlayingForScreenTime() }
            }
            // Opening a player with the time already up: ask at once, rather than wait for the stream to fail.
            .whenChanged(model.showsSomethingPlaying) { playing in
                household.playerShowing = playing
                if playing, household.time?.allowed == false { Task { await household.askNow(refused: true) } }
            }
            // A tab that has just been turned off for this profile gives way to Home.
            .whenChanged(household.limits) { _ in
                if household.shown([model.tab]).isEmpty { model.tab = .home }
            }
    }
}

/// How long is left, at the top of the screen for a few seconds, over a film as much as over a list.
private struct TimeLeftPill: View {
    @Environment(\.metrics) private var metrics
    let words: String

    var body: some View {
        Label(words, systemImage: "hourglass")
            .font(metrics.tv ? .body.weight(.semibold) : .subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, Tokens.Space.s4)
            .padding(.vertical, Tokens.Space.s2)
            .background(Capsule().fill(Color.black.opacity(0.82)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .padding(.top, metrics.tv ? Tokens.Space.s8 : Tokens.Space.s2)
            .transition(.move(edge: .top).combined(with: .opacity))
            .allowsHitTesting(false)
            .accessibilityIdentifier("screen-time-left")
    }
}

/// Time is up: why, until when, and what can be done about it. A parent can give more time here, with the
/// parents' PIN or their own name and password.
private struct TimeUpScreen: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.metrics) private var metrics
    @ObservedObject var household: Household
    let time: ScreenTime
    @State private var asking = false
    @State private var minutes = 30
    @State private var pin = ""
    @State private var name = ""
    @State private var password = ""
    @State private var byPassword = false
    @State private var problem = ""
    @State private var busy = false
    @State private var wantPin = false
    @State private var wantName = false
    @State private var wrongTries = 0
    @FocusState private var onMain: Bool
    @Namespace private var scope

    private var usesPassword: Bool { byPassword || !household.hasParentPin }
    private var ready: Bool { usesPassword ? !name.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty : pin.count >= 4 }

    private func give() {
        guard ready, !busy else { return }
        busy = true
        problem = ""
        Task {
            let refused = usesPassword
                ? await household.askParent(minutes: minutes, pin: "", name: name.trimmingCharacters(in: .whitespaces), password: password)
                : await household.askParent(minutes: minutes, pin: pin, name: "", password: "")
            if let refused {
                // The server's own words: a wrong PIN, or how long to wait after too many.
                problem = refused
                pin = ""
                password = ""
                wrongTries += 1
            }
            busy = false
        }
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    /// The profile's name, the page's eyebrow.
    private var who: String {
        guard let user = model.user else { return "" }
        let shown = PlainWords.clean(user.displayName ?? "", limit: 40)
        return shown.isEmpty ? user.name : shown
    }

    /// Why, and when it starts again; then Ask a parent, Switch profile and OK.
    private var why: some View {
        let next = ScreenTimeRules.nextWords(time, now: Date()) { TimeUpScreen.clock.string(from: $0) }
        let lead = [ScreenTimeRules.message(time), next].filter { !$0.isEmpty }.joined(separator: " ")
        return DesignPage(eyebrow: who, title: ScreenTimeRules.title(time), lead: lead, identifier: "time-up") {
            DesignSection(title: "") {
                DesignChips {
                    DesignChip(title: "Ask a parent", on: true) {
                        asking = true
                        if usesPassword { wantName = true } else { wantPin = true }
                    }
                    .focused($onMain)
                    .firstFocus(in: scope)
                    .accessibilityIdentifier("time-up-ask")
                    DesignChip(title: "Switch profile") {
                        household.dismissTimeUp()
                        household.startSwitch(model)
                    }
                }
            }
        } actions: {
            Button("OK") { household.dismissTimeUp() }.action()
        }
    }

    /// A parent gives more time: how much, then their PIN (or their name and password).
    private var ask: some View {
        DesignPage(eyebrow: "Ask a parent", title: "Add more time",
                   lead: "A parent or administrator can give \(who.isEmpty ? "this profile" : who) more time today.",
                   identifier: "time-up-asking") {
            DesignSection(title: "How long") {
                DesignChips {
                    ForEach(ScreenTimeRules.extras, id: \.self) { choice in
                        DesignChip(title: ScreenTimeRules.extraLabel(choice), on: minutes == choice) { minutes = choice }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("How long")
            }
            DesignSection(title: "Parent") {
                if usesPassword {
                    OutlinedField(label: "A parent’s username", text: $name, kind: .name, icon: "person", request: $wantName)
                    OutlinedField(label: "Their password", text: $password, kind: .password, icon: "lock", invalid: !problem.isEmpty) { give() }
                        .shake(wrongTries)
                } else {
                    OutlinedField(label: "The parents’ PIN", text: Binding(get: { pin }, set: { pin = ScreenTimeRules.cleanPin($0) }),
                                  kind: .password, icon: "lock", request: $wantPin, invalid: !problem.isEmpty) { give() }
                        .shake(wrongTries)
                }
                if !problem.isEmpty { ProblemLine(problem) }
            }
        } actions: {
            Button { give() } label: { BusyText("Give time", busy: busy) }
                .action(primary: true)
                .disabled(!ready || busy)
            if household.hasParentPin {
                Button(byPassword ? "Use the parents’ PIN instead" : "Use a parent’s password instead") {
                    byPassword.toggle()
                    problem = ""
                }
                .action()
            }
            Button(say("back")) {
                asking = false
                problem = ""
            }
            .action()
        }
    }

    var body: some View {
        Group {
            if asking { ask } else { why }
        }
        .scrollDismissesKeyboardIfAvailable()
        .focusRoot(scope)
        // Back on a remote is OK: the time is still up, and the screen comes back with the next thing played.
        .onRemoteBack {
            if asking { asking = false } else { household.dismissTimeUp() }
        }
        .onAppear {
            announce(ScreenTimeRules.title(time))
            DispatchQueue.main.async { onMain = true }
        }
        .accessibilityAddTraits(.isModal)
    }
}
