// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

/// The library, as far as the manager can tell.
private final class FakeLink: PeerLink, @unchecked Sendable {
    let port: Int
    let secret: String
    var state = PeerConnect.State(path: .connecting)
    var knownAddresses: [String] = []
    var networkChanges = 0
    var closed = false
    var say: (@Sendable (PeerConnect.State) -> Void)?

    init(port: Int, secret: String) {
        self.port = port
        self.secret = secret
    }

    func networkChanged() { networkChanges += 1 }
    func close() { closed = true }
    var invites: [String] = []
    func enrol(secret: String, name: String, platform: String) throws -> PeerConnect.Enrolment {
        invites.append(secret)
        return PeerConnect.Enrolment(json: secret == "the-right-invite-0001" ? #"{"ok":true,"code":"123456","serverName":"Home"}"# : #"{"ok":false,"reason":"wrong","error":"That invite isn't right."}"#)
    }

    /// The library reports from a thread of its own.
    func becomes(_ path: PeerConnect.State.Path) {
        state = PeerConnect.State(path: path)
        say?(state)
    }
}

/// The network and the library, for one test.
@MainActor
private final class World {
    var atHome = false
    var homeAsked = 0
    var links: [FakeLink] = []
    var opened: [(peer: PeerInfo, key: String)] = []
    var refuseToOpen = false
    /// What a link does when it is started: connect at once, unless a test says otherwise.
    var onOpen: (FakeLink) -> Void = { $0.state = PeerConnect.State(path: .direct) }
    var ways: [PeerManager.Way] = []
    var routes: [PeerRoute?] = []
    var learnt: [PeerInfo] = []
    var clock = Date(timeIntervalSince1970: 1_000)
    /// Sleeps the manager asked for. The short ones (waiting for a connection) pass at once. The
    /// long one between looks at home passes at once only for the test that is about it, and
    /// otherwise lasts until the manager gives it up.
    var slept: [TimeInterval] = []
    var timePasses = false

    func manager() -> PeerManager {
        let tools = PeerManager.Tools(
            homeAnswers: { [weak self] _ in
                await MainActor.run {
                    self?.homeAsked += 1
                    return self?.atHome ?? false
                }
            },
            open: { [weak self] peer, key, say in
                guard let self, !self.refuseToOpen else { throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "No library."]) }
                self.opened.append((peer, key))
                // The port asked for if there is one, as the library gives it when it is free.
                let link = FakeLink(port: peer.port != 0 ? peer.port : 40_000 + self.links.count, secret: "secret-\(self.links.count + 1)")
                link.say = say
                self.onOpen(link)
                self.links.append(link)
                return link
            },
            sleep: { [weak self] seconds in
                let passes = await MainActor.run { () -> Bool in
                    self?.slept.append(seconds)
                    return seconds < 1 || self?.timePasses == true
                }
                if passes {
                    await Task.yield()
                } else {
                    try? await Task.sleep(nanoseconds: 3_600_000_000_000)
                }
            })
        let manager = PeerManager(tools: tools, now: { [unowned self] in self.clock })
        manager.onWay = { [weak self] in self?.ways.append($0) }
        manager.onRoute = { [weak self] in self?.routes.append($0) }
        manager.onLearnt = { [weak self] in self?.learnt.append($0) }
        return manager
    }
}

/// Lets what was started on the main actor run.
@MainActor
private func settleDown() async {
    for _ in 0..<50 { await Task.yield() }
}

@MainActor
final class PeerManagerTests: XCTestCase {
    let server = "12D3KooWK99VoVxNE7XzyBwXEzW7xhK7Gpv85r9F3V3fyKSUKPH5"
    let home = "http://192.168.1.20:9797"

    private func setup(port: Int = 0) -> PeerManager.Setup {
        PeerManager.Setup(home: home, peer: PeerInfo(serverID: server, hints: ["/ip4/203.0.113.4/udp/4100/quic-v1"], port: port), key: "key")
    }

    func testAtHomeNothingIsStarted() async {
        let world = World()
        world.atHome = true
        let manager = world.manager()
        manager.use(setup())
        let way = await manager.settle()
        XCTAssertEqual(way, .home)
        XCTAssertTrue(world.links.isEmpty)
        XCTAssertNil(manager.route.current)
        XCTAssertEqual(way.words, "")
    }

    func testAwayTheLibraryIsStartedAndRequestsGoToItsAddress() async {
        let world = World()
        let manager = world.manager()
        manager.use(setup())
        let way = await manager.settle()
        XCTAssertEqual(way, .away(PeerConnect.State(path: .direct)))
        XCTAssertEqual(world.opened.count, 1)
        XCTAssertEqual(world.opened.first?.peer.serverID, server)
        XCTAssertEqual(world.opened.first?.key, "key")
        XCTAssertEqual(manager.route.current, PeerRoute(port: 40_000, secret: "secret-1"))
        XCTAssertEqual(manager.route.current?.origin, "http://127.0.0.1:40000")
        XCTAssertEqual(way.words, "Peer to peer · direct")
        // The port is kept, to be asked for again.
        XCTAssertEqual(world.learnt.last?.port, 40_000)
    }

    func testWhoeverKnowsHomeIsGoneIsntMadeToWaitForItAgain() async {
        let world = World()
        world.atHome = true // it would answer, if it were asked
        let manager = world.manager()
        manager.use(setup())
        let way = await manager.settle(homeIsGone: true)
        XCTAssertTrue(way.isAway)
        XCTAssertEqual(world.homeAsked, 0)
    }

    func testWithNothingToGoAwayWithThereIsNoWay() async {
        let world = World()
        let manager = world.manager()
        manager.use(PeerManager.Setup(home: home))
        let none = await manager.settle()
        XCTAssertEqual(none, .none)
        // A key and no server ID, or the other way round, is nothing either.
        manager.use(PeerManager.Setup(home: home, peer: PeerInfo(serverID: server), key: ""))
        let noKey = await manager.settle()
        XCTAssertEqual(noKey, .none)
        manager.use(PeerManager.Setup(home: home, peer: PeerInfo(serverID: "not-an-id"), key: "key"))
        let noID = await manager.settle()
        XCTAssertEqual(noID, .none)
        XCTAssertTrue(world.links.isEmpty)
        XCTAssertNil(manager.route.current)
    }

    func testALibraryThatWontStartIsSaidInWords() async {
        let world = World()
        world.refuseToOpen = true
        let manager = world.manager()
        manager.use(setup())
        let way = await manager.settle()
        XCTAssertEqual(way, .none)
        XCTAssertEqual(manager.problem, "No library.")
        XCTAssertNil(manager.route.current)
    }

    func testAConnectionThatIsSlowIsWaitedForAndThenLeftTrying() async {
        let world = World()
        world.onOpen = { _ in } // stays "connecting"
        let manager = world.manager()
        manager.awayWait = 2
        manager.use(setup())
        let way = await manager.settle()
        // Still away: the library keeps trying, and requests to its address wait or say why not.
        XCTAssertEqual(way, .away(PeerConnect.State(path: .connecting)))
        XCTAssertNotNil(manager.route.current)
        XCTAssertEqual(world.slept.filter { $0 == 0.25 }.count, 8)
        XCTAssertFalse(world.links[0].closed)
        // When it does connect, the app hears, and the addresses it found are kept.
        world.links[0].knownAddresses = ["/ip4/198.51.100.7/udp/4100/quic-v1", "not an address"]
        world.links[0].becomes(.relayed)
        await settleDown()
        XCTAssertEqual(manager.way, .away(PeerConnect.State(path: .relayed)))
        XCTAssertEqual(world.learnt.last?.hints, ["/ip4/198.51.100.7/udp/4100/quic-v1"])
    }

    func testComingHomeEndsTheConnection() async {
        let world = World()
        let manager = world.manager()
        manager.use(setup())
        await manager.settle()
        XCTAssertTrue(manager.way.isAway)
        world.atHome = true
        let way = await manager.settle()
        XCTAssertEqual(way, .home)
        XCTAssertTrue(world.links[0].closed)
        XCTAssertNil(manager.route.current)
        XCTAssertEqual(world.routes.count, 2)
    }

    func testHomeIsNoticedByItselfWhileAway() async {
        let world = World()
        world.timePasses = true
        let manager = world.manager()
        manager.homeCheckEvery = 45
        manager.use(setup())
        await manager.settle()
        let asked = world.homeAsked
        await settleDown()
        XCTAssertGreaterThan(world.homeAsked, asked, "the server's own address is asked again while away")
        XCTAssertTrue(world.slept.contains(45))
        world.atHome = true
        await settleDown()
        XCTAssertEqual(manager.way, .home)
        XCTAssertTrue(world.links[0].closed)
    }

    func testTheLibrarySayingSameNetworkAsksHomeAtOnce() async {
        let world = World()
        let manager = world.manager()
        manager.homeCheckEvery = 3600
        manager.use(setup())
        await manager.settle()
        world.atHome = true
        world.links[0].becomes(.local)
        await settleDown()
        XCTAssertEqual(manager.way, .home)
    }

    func testLeavingTheScreenEndsItAndComingBackStartsItOnTheSamePort() async {
        let world = World()
        let manager = world.manager()
        manager.use(setup())
        await manager.settle()
        let before = manager.route.current
        manager.suspend()
        XCTAssertTrue(world.links[0].closed)
        XCTAssertEqual(manager.way, .away(PeerConnect.State(path: .offline)))
        // The address stays, answering nothing: a request made meanwhile never goes anywhere else.
        XCTAssertEqual(manager.route.current, before)
        // Nothing is started while off the screen, whoever asks.
        let asleep = await manager.settle()
        XCTAssertEqual(asleep, .away(PeerConnect.State(path: .offline)))
        XCTAssertEqual(world.links.count, 1)
        // What the old connection still has to say changes nothing.
        world.links[0].becomes(.direct)
        await settleDown()
        XCTAssertEqual(manager.way, .away(PeerConnect.State(path: .offline)))

        let way = await manager.resume()
        XCTAssertEqual(way, .away(PeerConnect.State(path: .direct)))
        XCTAssertEqual(world.links.count, 2)
        XCTAssertEqual(world.opened[1].peer.port, 40_000, "the port it had is asked for again")
        XCTAssertEqual(manager.route.current, PeerRoute(port: 40_000, secret: "secret-2"))
        XCTAssertNotEqual(manager.route.current?.secret, before?.secret, "and the secret is a new one")
    }

    func testLeavingTheScreenAtHomeChangesNothing() async {
        let world = World()
        world.atHome = true
        let manager = world.manager()
        manager.use(setup())
        await manager.settle()
        manager.suspend()
        XCTAssertEqual(manager.way, .home)
        world.atHome = false
        // Back on the screen somewhere else: away, without being asked twice.
        let way = await manager.resume()
        XCTAssertTrue(way.isAway)
    }

    func testARequestFailingAtHomeFindsTheOtherWayAndABurstCountsOnce() async {
        let world = World()
        world.atHome = true
        let manager = world.manager()
        manager.use(setup())
        await manager.settle()
        world.atHome = false
        let asked = world.homeAsked
        // What a connection does when a request is lost: every screen's at once.
        for _ in 0..<6 { manager.route.trouble(.lost) }
        await settleDown()
        XCTAssertTrue(manager.way.isAway)
        XCTAssertEqual(world.links.count, 1)
        XCTAssertEqual(world.homeAsked, asked + 1)
        // Soon after, more of the same is not news; later it is, and the connection is looked at.
        manager.route.trouble(.lost)
        await settleDown()
        XCTAssertEqual(world.links[0].networkChanges, 0)
        world.clock += 10
        manager.route.trouble(.lost)
        await settleDown()
        XCTAssertEqual(world.links[0].networkChanges, 1)
        XCTAssertEqual(world.links.count, 1, "the connection that is open is kept")
    }

    func testANetworkChangeIsPassedOnAndTheWayChosenAgain() async {
        let world = World()
        let manager = world.manager()
        manager.use(setup())
        await manager.settle()
        world.atHome = true
        manager.networkChanged()
        await settleDown()
        XCTAssertEqual(world.links[0].networkChanges, 1)
        XCTAssertEqual(manager.way, .home)
    }

    func testAnotherServerEndsThisOnesConnection() async {
        let world = World()
        let manager = world.manager()
        manager.use(setup())
        await manager.settle()
        manager.use(PeerManager.Setup(home: "http://192.168.1.99:9797"))
        XCTAssertTrue(world.links[0].closed)
        XCTAssertNil(manager.route.current)
        XCTAssertEqual(manager.way, .none)
        // News about the same server (its addresses, kept) ends nothing.
        manager.use(setup())
        await manager.settle()
        var same = setup()
        same.peer?.hints = ["/ip4/198.51.100.9/tcp/4100"]
        manager.use(same)
        XCTAssertFalse(world.links[1].closed)
        XCTAssertTrue(manager.way.isAway)
    }

    func testForgettingTheServerFromAwayEndsItForGood() async {
        let world = World()
        let manager = world.manager()
        manager.use(setup())
        await manager.settle()
        manager.forgetAway()
        XCTAssertTrue(world.links[0].closed)
        XCTAssertNil(manager.route.current)
        let way = await manager.settle()
        XCTAssertEqual(way, .none)
        XCTAssertEqual(world.links.count, 1)
    }

    func testAnInviteIsShownOverTheConnectionThatIsOpen() async {
        let world = World()
        let manager = world.manager()
        manager.use(setup())
        let early = await manager.enrol(secret: "the-right-invite-0001", name: "TV", platform: "tvOS")
        XCTAssertNil(early, "with no connection there is nobody to show it to")
        await manager.settle()
        let wrong = await manager.enrol(secret: "a-wrong-invite-000000", name: "TV", platform: "tvOS")
        XCTAssertEqual(wrong?.ok, false)
        XCTAssertEqual(wrong?.reason, "wrong")
        let right = await manager.enrol(secret: "the-right-invite-0001", name: "TV", platform: "tvOS")
        XCTAssertEqual(right?.ok, true)
        XCTAssertEqual(right?.code, "123456")
        XCTAssertEqual(world.links[0].invites.count, 2)
    }

    func testSeveralAskersAtOnceGetOneAnswer() async {
        let world = World()
        let manager = world.manager()
        manager.use(setup())
        async let a = manager.settle()
        async let b = manager.settle()
        async let c = manager.settle()
        let ways = await [a, b, c]
        XCTAssertTrue(ways.allSatisfy(\.isAway))
        XCTAssertEqual(world.links.count, 1)
    }

    func testWhatIsKeptAboutAServer() throws {
        let answer = try JSONDecoder().decode(PeerAnswer.self, from: Data("""
        {"enabled":true,"serverId":"\(server)","addrs":["/ip4/127.0.0.1/tcp/4100","/ip6/::1/tcp/4100","/ip4/203.0.113.4/tcp/4100","junk"],"enrolled":false}
        """.utf8))
        let kept = try XCTUnwrap(PeerInfo.learnt(answer, keeping: PeerInfo(serverID: server, port: 41_000)))
        XCTAssertEqual(kept.hints, ["/ip4/203.0.113.4/tcp/4100"], "addresses on the server's own machine are no use from away")
        XCTAssertEqual(kept.port, 41_000)
        XCTAssertEqual(PeerInfo.learnt(answer, keeping: PeerInfo(serverID: String(server.reversed()), port: 41_000))?.port, 0)
        let off = try JSONDecoder().decode(PeerAnswer.self, from: Data(#"{"enabled":false}"#.utf8))
        XCTAssertNil(PeerInfo.learnt(off, keeping: nil))
        // Kept and read back; a port that could never be one is dropped.
        let read = try JSONDecoder().decode(PeerInfo.self, from: try JSONEncoder().encode(kept))
        XCTAssertEqual(read, kept)
        XCTAssertEqual(try JSONDecoder().decode(PeerInfo.self, from: Data(#"{"serverID":"x","port":80}"#.utf8)).port, 0)
        XCTAssertFalse(PeerInfo(serverID: "x").usable)
        // A server only ever reached from away has an address that leads nowhere at home.
        let placeholder = PeerInfo.placeholderAddress(serverID: server)
        XCTAssertEqual(placeholder, "http://p2p-" + server.suffix(16).lowercased() + ".localhost")
        XCTAssertTrue(PeerInfo.isPlaceholder(placeholder))
        XCTAssertFalse(PeerInfo.isPlaceholder(home))
    }

    // MARK: A connection that follows the way

    func testRequestsGoTheWayInUseWithItsSecretAndComeBackHome() async throws {
        let seen = Seen()
        let tunnel = try StandInServer { request in
            seen.add(request.head)
            return StandInServer.answer(body: #"{"name":"WittyMediaServer","version":"0.8.0"}"#)
        }
        defer { tunnel.stop() }
        let box = RouteBox()
        // Home is an address where nothing answers.
        let client = WittyClient(base: "http://127.0.0.1:9", token: "token", quick: true, route: box)
        XCTAssertEqual(client.root, "http://127.0.0.1:9")
        XCTAssertNil(client.authHeaders[PeerConnect.secretHeader])
        let poster = try XCTUnwrap(client.posterURL(id: 7))

        box.set(PeerRoute(port: tunnel.port, secret: "s3cret"))
        XCTAssertEqual(client.root, tunnel.address)
        let status = try await client.status()
        XCTAssertEqual(status.name, "WittyMediaServer")
        let head = seen.all.first?.lowercased() ?? ""
        XCTAssertTrue(head.contains("x-witty-connect: s3cret"))
        XCTAssertTrue(head.contains("authorization: bearer token"))
        // The name everything is kept under hasn't moved.
        XCTAssertEqual(client.base, "http://127.0.0.1:9")
        // An address made before the way changed is asked for the new way; a stranger's never is.
        XCTAssertEqual(client.current(poster)?.absoluteString, "\(tunnel.address)/api/v1/items/7/poster")
        XCTAssertEqual(client.posterURL(id: 7)?.absoluteString, "\(tunnel.address)/api/v1/items/7/poster")
        XCTAssertNil(client.current(try XCTUnwrap(URL(string: "http://203.0.113.9/api/v1/items/7/poster"))))
        XCTAssertNil(client.current(try XCTUnwrap(URL(string: "https://127.0.0.1:\(tunnel.port)/x"))))

        // Home again: the same connection, the old address of this device brought back with it.
        let away = try XCTUnwrap(client.posterURL(id: 7))
        box.set(nil)
        XCTAssertEqual(client.current(away)?.absoluteString, "http://127.0.0.1:9/api/v1/items/7/poster")
        XCTAssertNil(client.authHeaders[PeerConnect.secretHeader])
    }

    func testALostRequestIsToldToWhoeverChoosesTheWay() async throws {
        let box = RouteBox()
        let heard = Seen()
        box.onTrouble { _ in heard.add("trouble") }
        let client = WittyClient(base: "http://127.0.0.1:9", token: "token", quick: true, route: box)
        _ = try? await client.status()
        XCTAssertEqual(heard.all.count, 1)
        // The address on this device answering that it can't get through is the same news.
        let tunnel = try StandInServer { _ in
            StandInServer.answer(status: "502 Bad Gateway", headers: ["X-Witty-Connect-Error: 1"], body: #"{"error":"Not found"}"#)
        }
        defer { tunnel.stop() }
        box.set(PeerRoute(port: tunnel.port, secret: "s"))
        do {
            _ = try await client.status()
            XCTFail("a 502 is a failure")
        } catch let error as APIError {
            XCTAssertEqual(error.message, "Not found")
        }
        XCTAssertEqual(heard.all.count, 2)
    }
}

private final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [String] = []
    func add(_ text: String) {
        lock.lock()
        list.append(text)
        lock.unlock()
    }
    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return list
    }
}
