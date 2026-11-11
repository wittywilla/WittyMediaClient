// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation

/// One running connection from away, as the manager needs it. The app's is the Go library
/// (PeerLibrary.swift there); the tests' is a fake.
public protocol PeerLink: AnyObject, Sendable {
    /// The port of the address on this device, and the secret requests to it must carry.
    var port: Int { get }
    var secret: String { get }
    var state: PeerConnect.State { get }
    /// The server's addresses as last learnt, to keep as hints for next time.
    var knownAddresses: [String] { get }
    func networkChanged()
    /// Shows the server an invite's secret, which puts this device on its list. It waits for the
    /// answer, up to a minute, so never on the thread the screen is drawn from.
    func enrol(secret: String, name: String, platform: String) throws -> PeerConnect.Enrolment
    func close()
}

/// Chooses how one server is reached, as the desktop app does: at home first, by its own
/// address; from away when that doesn't answer and this device is on the server's list. It
/// goes back home by itself, stops the connection when the app leaves the screen, and starts
/// it again when the app comes back. Everything that asks the server goes through `route`, so
/// none of it has to know which way is in use.
@MainActor
public final class PeerManager {
    /// How the server is being reached.
    public enum Way: Equatable, Sendable {
        /// Not decided yet, or neither way works.
        case none
        /// By its own address.
        case home
        /// Peer to peer, with what the library says about the connection.
        case away(PeerConnect.State)

        public var isAway: Bool { if case .away = self { return true } else { return false } }
    }

    /// The server, and what this device has for reaching it from away (nothing, for a server
    /// that doesn't take such connections).
    public struct Setup: Equatable, Sendable {
        public var home: String
        public var peer: PeerInfo?
        public var key: String

        public init(home: String, peer: PeerInfo? = nil, key: String = "") {
            self.home = home
            self.peer = peer
            self.key = key
        }

        var canGoAway: Bool { peer?.usable == true && !key.isEmpty }
    }

    /// What the manager can't do itself, so tests can stand in for the network and the clock.
    public struct Tools {
        /// Is the server at its own address, and still the one remembered there? A sign-in is
        /// sent wherever this says yes, so it has to prove the key and not just an answer.
        public var homeAnswers: @Sendable (String) async -> Bool
        /// Starts the library. The state arrives from a thread of its own.
        public var open: @MainActor (PeerInfo, String, @escaping @Sendable (PeerConnect.State) -> Void) throws -> PeerLink
        public var sleep: @Sendable (TimeInterval) async -> Void

        public init(homeAnswers: @escaping @Sendable (String) async -> Bool,
                    open: @escaping @MainActor (PeerInfo, String, @escaping @Sendable (PeerConnect.State) -> Void) throws -> PeerLink,
                    sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }) {
            self.homeAnswers = homeAnswers
            self.open = open
            self.sleep = sleep
        }
    }

    /// How long choosing waits for the connection from away before carrying on without it: the
    /// library keeps trying after that, and requests say in words why they can't get through.
    public var awayWait: TimeInterval = 25
    /// While away, how often the server's own address is asked whether this device is home again.
    public var homeCheckEvery: TimeInterval = 45
    /// Requests failing in a burst are one piece of news.
    public var troubleEvery: TimeInterval = 5

    public let route = RouteBox()
    public private(set) var way: Way = .none
    /// Why the connection from away couldn't be started, in words, if it couldn't.
    public private(set) var problem = ""
    public private(set) var suspended = false

    /// The way changed, or what is known about it did.
    public var onWay: ((Way) -> Void)?
    /// The address on this device changed: a new port, a new secret, or none.
    public var onRoute: ((PeerRoute?) -> Void)?
    /// Something worth keeping for next time: the server's addresses, the local port.
    public var onLearnt: ((PeerInfo) -> Void)?

    private let tools: Tools
    private var setup: Setup?
    private var link: PeerLink?
    /// Counts servers and stops, so that an answer to an old question changes nothing.
    private var generation = 0
    private var settling: Task<Way, Never>?
    private var homeChecks: Task<Void, Never>?
    private var lastTrouble = Date.distantPast
    private var now: () -> Date

    public init(tools: Tools, now: @escaping () -> Date = Date.init) {
        self.tools = tools
        self.now = now
        route.onTrouble { [weak self] _ in
            Task { @MainActor [weak self] in self?.requestFailed() }
        }
    }

    public var current: Setup? { setup }

    // MARK: Which server

    /// The server in use from now on, or none. The same one again only brings what is known
    /// about it up to date; another one ends whatever was open.
    public func use(_ new: Setup?) {
        guard new != setup else { return }
        let sameServer = new != nil && new?.home == setup?.home && new?.peer?.serverID == setup?.peer?.serverID && new?.key == setup?.key
        setup = new
        if sameServer { return }
        generation += 1
        settling?.cancel()
        settling = nil
        closeLink()
        setRoute(nil)
        problem = ""
        setWay(.none)
    }

    /// This device is off the server's list, or the server takes no such connections any more.
    public func forgetAway() {
        guard var kept = setup else { return }
        kept.peer = nil
        setup = kept
        if way.isAway {
            generation += 1
            closeLink()
            setRoute(nil)
            setWay(.none)
        }
    }

    // MARK: Choosing

    /// Chooses the way now: home if it answers, away otherwise. Several askers at once get the
    /// same answer. `homeIsGone` is for whoever has just asked the server's own address
    /// themselves and got no answer: it isn't asked again.
    @discardableResult
    public func settle(homeIsGone: Bool = false) async -> Way {
        if let settling { return await settling.value }
        guard setup != nil else { return .none }
        let run = generation
        let task = Task { [weak self] () -> Way in
            guard let self else { return .none }
            return await self.choose(run, homeIsGone: homeIsGone)
        }
        settling = task
        let chosen = await task.value
        if settling == task { settling = nil }
        return chosen
    }

    private func choose(_ run: Int, homeIsGone: Bool) async -> Way {
        guard let setup else { return .none }
        let atHome = homeIsGone ? false : await tools.homeAnswers(setup.home)
        guard run == generation, let setup = self.setup else { return way }
        if atHome {
            goHome()
            return way
        }
        guard setup.canGoAway, let peer = setup.peer else {
            // Nothing else to try. What was open, if anything, is for a list this device has left.
            closeLink()
            setRoute(nil)
            setWay(.none)
            return way
        }
        // Not while the app is off the screen: the system would only take the sockets away again.
        guard !suspended else { return way }
        if link == nil {
            do {
                try open(peer, key: setup.key)
            } catch {
                problem = (error as NSError).localizedDescription
                setRoute(nil)
                setWay(.none)
                return way
            }
        }
        await waitUntilConnected(run)
        return way
    }

    private func open(_ peer: PeerInfo, key: String) throws {
        let run = generation
        let opened = try tools.open(peer, key) { [weak self] state in
            Task { @MainActor [weak self] in self?.heard(state, run: run) }
        }
        link = opened
        problem = ""
        setRoute(PeerRoute(port: opened.port, secret: opened.secret))
        setWay(.away(opened.state))
        if opened.port != peer.port {
            var kept = peer
            kept.port = opened.port
            keep(kept)
        }
        watchForHome(run)
    }

    private func waitUntilConnected(_ run: Int) async {
        let step = 0.25
        var waited = 0.0
        while run == generation, let link, !link.state.connected, waited < awayWait {
            await tools.sleep(step)
            waited += step
        }
        guard run == generation, let link else { return }
        setWay(.away(link.state))
    }

    /// The library said something about the connection.
    private func heard(_ state: PeerConnect.State, run: Int) {
        guard run == generation, let link else { return }
        setWay(.away(state))
        guard state.connected, var kept = setup?.peer else { return }
        let found = PeerConnect.hints(link.knownAddresses)
        if !found.isEmpty, found != kept.hints {
            kept.hints = found
            keep(kept)
        }
        // On the server's own network after all: its own address is the better way.
        if state.path == .local { Task { await self.checkHome(run) } }
    }

    private func keep(_ peer: PeerInfo) {
        setup?.peer = peer
        onLearnt?(peer)
    }

    private func goHome() {
        closeLink()
        setRoute(nil)
        problem = ""
        setWay(.home)
    }

    /// While away, the server's own address is asked now and then: the device may have come home.
    private func watchForHome(_ run: Int) {
        homeChecks?.cancel()
        homeChecks = Task { [weak self] in
            while !Task.isCancelled {
                guard let every = self?.homeCheckEvery else { return }
                await self?.tools.sleep(every)
                guard !Task.isCancelled, let self, run == self.generation, self.link != nil else { return }
                await self.checkHome(run)
            }
        }
    }

    private func checkHome(_ run: Int) async {
        guard run == generation, way.isAway, let home = setup?.home, settling == nil else { return }
        let atHome = await tools.homeAnswers(home)
        guard run == generation, atHome, way.isAway else { return }
        goHome()
    }

    // MARK: What happens to the app

    /// The app left the screen. The system takes its sockets soon after, so the connection is
    /// ended properly here instead. The address on this device stays as it was, answering
    /// nothing, so a request made meanwhile fails at once and never goes anywhere else.
    public func suspend() {
        guard !suspended else { return }
        suspended = true
        guard link != nil else { return }
        generation += 1
        settling?.cancel()
        settling = nil
        closeLink()
        setWay(.away(PeerConnect.State(path: .offline)))
    }

    /// The app is back. Home first, as ever; from away the connection starts again on the
    /// port it had, so what was playing finds the server where it left it.
    @discardableResult
    public func resume() async -> Way {
        suspended = false
        // A connection kept through the time away (sound was playing) may have lost its sockets.
        link?.networkChanged()
        return await settle()
    }

    /// The device moved between networks, or got one back.
    public func networkChanged() {
        guard setup != nil, !suspended else { return }
        link?.networkChanged()
        Task { await settle() }
    }

    /// A request couldn't get through. At home that may mean the device has left; away, that
    /// the connection needs looking at.
    public func requestFailed() {
        guard setup != nil, !suspended, settling == nil, now().timeIntervalSince(lastTrouble) >= troubleEvery else { return }
        lastTrouble = now()
        if way.isAway { link?.networkChanged() }
        Task { await settle() }
    }

    /// Shows the server an invite over the connection that is open. Nil with none open.
    public func enrol(secret: String, name: String, platform: String) async -> PeerConnect.Enrolment? {
        guard let link else { return nil }
        return await Task.detached(priority: .userInitiated) {
            (try? link.enrol(secret: secret, name: name, platform: platform)) ?? PeerConnect.Enrolment(json: "")
        }.value
    }

    /// Everything stops: the app is going away, or the server is being left.
    public func close() {
        use(nil)
    }

    // MARK: Inside

    private func closeLink() {
        homeChecks?.cancel()
        homeChecks = nil
        guard let closing = link else { return }
        link = nil
        closing.close()
    }

    private func setRoute(_ new: PeerRoute?) {
        guard route.current != new else { return }
        route.set(new)
        onRoute?(new)
    }

    private func setWay(_ new: Way) {
        guard new != way else { return }
        way = new
        onWay?(new)
    }
}

public extension PeerManager.Way {
    /// In words, for wherever the app says which server it is on. Nothing to say at home.
    var words: String {
        if case .away(let state) = self { return state.words }
        return ""
    }
}

public extension PeerConnect.State {
    init(path: Path) {
        self.init(json: "")
        self.path = path
    }
}
