// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import AVFoundation
import Foundation
import Network
import SwiftUI
import WittyKit
#if canImport(UIKit)
import UIKit
#endif

// Reaching the server from away, peer to peer: no port opened on anyone's router. WittyKit's
// PeerManager chooses the way (home first, then away); this is what the app does around it:
// putting this device on the server's list while it is at home and signed in, keeping what is
// needed to find the server again, and following the app on and off the screen.
// docs/PLATFORMS.md, "From away, peer to peer", and docs/P2P.md in the server's repository.

/// The secret of the address on this device, as a cookie: the video player and a web view can't
/// be given a header, and send cookies by themselves with every request they make. For this
/// device's address only, never kept beyond this run of the app.
enum AwayCookie {
    static func cookie(_ route: PeerRoute) -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [.name: PeerConnect.secretCookie, .value: route.secret, .domain: "127.0.0.1", .path: "/",
                                                        .discard: "TRUE", .sameSitePolicy: HTTPCookieStringPolicy.sameSiteStrict]
        properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE"
        return HTTPCookie(properties: properties)
    }

    /// The one in the app's own jar, which the players read. The old secret goes when the new one comes.
    static func keep(_ route: PeerRoute?) {
        let jar = HTTPCookieStorage.shared
        for old in jar.cookies ?? [] where old.name == PeerConnect.secretCookie { jar.deleteCookie(old) }
        if let route, let cookie = cookie(route) { jar.setCookie(cookie) }
    }

    /// Something to play from one of the server's addresses. From away the address is on this
    /// device and wants its secret: the player finds it in the app's jar, and is handed it as a
    /// cookie of its own as well, so whichever it looks in, it is there.
    static func playerItem(_ url: URL) -> AVPlayerItem {
        guard PeerRoute.isLocalAddress(url),
              let secret = HTTPCookieStorage.shared.cookies?.first(where: { $0.name == PeerConnect.secretCookie && $0.domain == "127.0.0.1" }) else {
            return AVPlayerItem(url: url)
        }
        return AVPlayerItem(asset: AVURLAsset(url: url, options: [AVURLAssetHTTPCookiesKey: [secret]]))
    }
}

/// Tells the manager when the device changes network, and the library when memory is short.
final class AwayWatch {
    private final class Seen: @unchecked Sendable { var first = false } // only touched on the main actor
    private let monitor = NWPathMonitor()
    private var memory: NSObjectProtocol?

    init(changed: @escaping @MainActor () -> Void) {
        let seen = Seen()
        monitor.pathUpdateHandler = { _ in
            Task { @MainActor in
                // The first is only how things are, not a change.
                if !seen.first { seen.first = true; return }
                changed()
            }
        }
        monitor.start(queue: .global(qos: .utility))
        #if canImport(UIKit)
        memory = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { _ in
            PeerLibrary.freeMemory()
        }
        #endif
    }

    deinit {
        monitor.cancel()
        if let memory { NotificationCenter.default.removeObserver(memory) }
    }
}

extension AppModel {
    // MARK: Setting up

    func makePeers() -> PeerManager {
        let manager = PeerManager(tools: PeerManager.Tools(
            homeAnswers: { [weak self] url in await self?.homeProves(url) ?? false },
            open: { peer, key, say in try PeerLibrary.open(peer, key: key, onState: say) }))
        manager.onWay = { [weak self] way in
            guard let self, self.way != way else { return }
            let before = self.way
            self.way = way
            if before.words != way.words || before.isAway != way.isAway {
                let said = way.isAway ? "Reaching the server from away: \(way.words)" : way == .home ? "Reaching the server at home" : "No way to the server"
                // Worse than it was: through a relay, reconnecting, or no way at all after being away.
                var worse = false
                if case .away(let state) = way { worse = state.path == .relayed || state.path == .offline }
                if way == .none && before.isAway { worse = true }
                if worse {
                    ClientLog.shared.warnSeldom("p2p", said, session: self.awayLogSession)
                } else {
                    ClientLog.shared.info("p2p", said)
                }
            }
        }
        manager.onRoute = { [weak self] route in
            AwayCookie.keep(route)
            self?.routeStamp += 1
        }
        manager.onLearnt = { [weak self] info in
            guard let self, let server = self.current, self.peers.current?.home == server.url else { return }
            self.keepAway(info, for: server)
        }
        awayWatch = AwayWatch { [weak manager] in manager?.networkChanged() }
        return manager
    }

    /// Is the server at its own address, and the one remembered there? Only a proof of the key
    /// counts once a key is known: on someone else's network the same address is someone else's.
    private func homeProves(_ url: String) async -> Bool {
        guard !PeerInfo.isPlaceholder(url), let saved = current?.url == url ? current : recent.first(where: { $0.url == url }) else { return false }
        let proof = await WittyClient.identify(url, saved: [saved])
        switch proof.state {
        case .same: return true
        case .new: return saved.publicKey.isEmpty
        default: return false
        }
    }

    /// A connection to a server, by whichever way is in use.
    func connection(to base: String, token: String = "", quick: Bool = false) -> WittyClient {
        WittyClient(base: base, token: token, quick: quick, route: routeFor(base))
    }

    /// The way from away, if it is this server's.
    func routeFor(_ url: String) -> RouteBox? {
        PeerLibrary.available && peers.current?.home == url ? peers.route : nil
    }

    // MARK: What is kept

    private func awayKey(_ server: SavedServer) -> String { "peer." + (server.serverId.isEmpty ? server.url : server.serverId) }

    func awayInfo(for server: SavedServer) -> PeerInfo? {
        guard PeerLibrary.available, let data = defaults.data(forKey: awayKey(server)),
              let info = try? JSONDecoder().decode(PeerInfo.self, from: data), info.usable else { return nil }
        return info
    }

    func keepAway(_ info: PeerInfo?, for server: SavedServer) {
        if let info, let data = try? JSONEncoder().encode(info) {
            defaults.set(data, forKey: awayKey(server))
        } else {
            defaults.removeObject(forKey: awayKey(server))
        }
        objectWillChange.send()
    }

    /// "Stop connecting from away" is this device's own choice for this server, and stays until it
    /// is taken back: otherwise the app would put the device on the list again the next time it
    /// was at home.
    private func awayOffKey(_ server: SavedServer) -> String { "peer.off." + (server.serverId.isEmpty ? server.url : server.serverId) }

    func awayIsOff(for server: SavedServer) -> Bool { defaults.bool(forKey: awayOffKey(server)) }

    /// Whether the person turned it off for the server in use.
    var awayOff: Bool { current.map(awayIsOff(for:)) ?? false }

    /// This device's key, made the first time it is wanted. Nil if it can't be kept: a key that
    /// would be gone next time is no use to a server's list.
    private func deviceKey() -> String? {
        let kept = Keychain.peerKey
        if !kept.isEmpty, PeerLibrary.deviceID(of: kept) != nil { return kept }
        guard let made = PeerLibrary.newKey(), Keychain.save(peerKey: made) else { return nil }
        return made
    }

    /// This device's name on servers' lists, for showing.
    var awayDeviceID: String { PeerLibrary.deviceID(of: Keychain.peerKey) ?? "" }
    /// This device's connections from away in the logs, the same id as the server's: "p2p-" and the end of its peer ID.
    var awayLogSession: String {
        let id = awayDeviceID.filter { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.:".contains($0)) }
        return id.isEmpty ? "" : "p2p-" + id.suffix(8)
    }

    /// Whether this device can reach the server in use from away.
    var awayReady: Bool { current.flatMap(awayInfo(for:)) != nil && !Keychain.peerKey.isEmpty }

    // MARK: Choosing the way

    /// The manager is told which server is in use, with what this device has for reaching it.
    func useAway(for server: SavedServer) {
        guard PeerLibrary.available else { return }
        let info = awayInfo(for: server)
        let key = info == nil ? "" : Keychain.peerKey
        peers.use(PeerManager.Setup(home: server.url, peer: key.isEmpty ? nil : info, key: key))
    }

    /// A server from the list of those used before, whose own address didn't answer: the other
    /// way to it, if this device has one. Nil if it hasn't; otherwise as `arrive` answers.
    func arriveFromAway(_ url: String) async -> String?? {
        guard let saved = recent.first(where: { $0.url == url }), PeerLibrary.available, awayInfo(for: saved) != nil else { return nil }
        let run = ConnectRun(kind: "saved server", server: awayInfo(for: saved)?.serverID ?? "")
        run.pass("read")
        run.note("the server's own address didn't answer, so it was looked for from away")
        let problem = peers.problem
        guard await reachFromAway(saved) else { return .some(checkFailed(run, peerFailure("found", problem: peers.problem.isEmpty ? problem : peers.problem), say("errAwayFailed"), retry: url)) }
        run.pass("found")
        guard let status = try? await connection(to: saved.url, quick: true).status() else {
            peers.close()
            return .some(checkFailed(run, connectSteps?.of("slow-path", step: "secure"), say("errAwayFailed"), retry: url))
        }
        return .some(await arrive(url: saved.url, status: status))
    }

    /// Whether this device has what it takes to reach a server from away.
    func canReachFromAway(_ server: SavedServer) -> Bool {
        PeerLibrary.available && awayInfo(for: server) != nil && !Keychain.peerKey.isEmpty
    }

    /// The server's own address didn't answer. True if it is reached from away instead.
    func reachFromAway(_ server: SavedServer) async -> Bool {
        guard canReachFromAway(server) else { return false }
        useAway(for: server)
        let way = await peers.settle(homeIsGone: true)
        // Given up on meanwhile (the server turned up on the network after all): nothing more to do here.
        guard !Task.isCancelled, peers.current?.home == server.url else { return false }
        if case .away(let state) = way, state.connected { return true }
        if peers.way != .home {
            ClientLog.shared.warn("p2p", "The server wasn't reached from away: \(peers.problem.isEmpty ? peers.way.words : peers.problem)", session: awayLogSession)
            peers.close()
        }
        return peers.way == .home
    }

    /// Once signed in and on screen: the way is chosen (so a lost connection at home has
    /// somewhere to turn), and the server is asked whether it takes connections from away.
    func watchWay() {
        guard PeerLibrary.available, let server = current else { return }
        useAway(for: server)
        Task {
            await peers.settle()
            await learnAway()
        }
    }

    /// Asks the server whether it takes connections from away, puts this device on its list if
    /// so, and keeps what is needed to find it again. This is how a device that was set up at
    /// home works when it leaves, with nothing done by hand.
    func learnAway() async {
        guard PeerLibrary.available, stage == .browsing, !client.token.isEmpty, let server = current, !awayIsOff(for: server) else { return }
        let asking = client
        // Not asked where the server doesn't offer peer to peer.
        guard let caps = try? await asking.capabilities(), caps.has(WittyClient.peerFeature),
              let key = deviceKey(), let id = PeerLibrary.deviceID(of: key),
              let answer = try? await asking.peerInfo(device: id), asking === client, current?.url == server.url else { return }
        guard let info = PeerInfo.learnt(answer, keeping: awayInfo(for: server)) else {
            // Turned off at the server. From away that can't be what it said, as this is how it was asked.
            if answer.enabled == false, !way.isAway, awayInfo(for: server) != nil {
                keepAway(nil, for: server)
                peers.forgetAway()
            }
            return
        }
        if answer.enrolled != true {
            do {
                try await asking.enrolPeer(device: id, name: deviceName, platform: platformName)
                ClientLog.shared.info("p2p", "This device can now reach its server from away")
            } catch {
                // An account kept at home isn't given a way in from away, and that is the server's to say.
                ClientLog.shared.info("p2p", "The server didn't add this device to its list: \((error as? APIError)?.status ?? 0)")
                return
            }
        }
        guard asking === client, current?.url == server.url else { return }
        if info != awayInfo(for: server) { keepAway(info, for: server) }
        peers.use(PeerManager.Setup(home: server.url, peer: info, key: key))
    }

    // MARK: On and off the screen

    /// The app left the screen. On Apple TV it is stopped soon after and its sockets with it, so
    /// the connection is ended properly now. On a phone, sound that carries on needs its connection.
    func leftScreen() {
        guard PeerLibrary.available else { return }
        #if os(tvOS)
        peers.suspend()
        #else
        if !(listening.isPlaying || video?.isRunning == true) { peers.suspend() }
        #endif
    }

    func cameBack() async {
        if PeerLibrary.available { await peers.resume() }
        await recheck()
        await learnAway()
    }

    // MARK: Leaving

    /// Takes this device off the server's list, and forgets how to reach the server from away.
    /// The key goes too when no other server knows this device by it.
    func forgetAway(on old: WittyClient, server: SavedServer) async {
        guard PeerLibrary.available, awayInfo(for: server) != nil else { return }
        let id = awayDeviceID
        keepAway(nil, for: server)
        if !old.token.isEmpty, !id.isEmpty {
            do {
                try await old.forgetPeer(device: id)
            } catch {
                ClientLog.shared.info("p2p", "This device couldn't be taken off the server's list: \((error as? APIError)?.status ?? 0)")
            }
        }
        if peers.current?.home == server.url {
            if way.isAway { peers.close() } else { peers.forgetAway() }
        }
        if !recent.contains(where: { awayInfo(for: $0) != nil }) { Keychain.clearPeerKey() }
    }

    /// "Stop connecting from away", from You: this server only. If that was the way in use,
    /// there is no way left, and the app says so.
    func stopAway() async {
        guard let server = current else { return }
        let wasAway = way.isAway
        defaults.set(true, forKey: awayOffKey(server))
        await forgetAway(on: client, server: server)
        if wasAway { stage = .connect(message: say("errLost")) }
    }

    /// Taking that back: the device goes on the list again now, if the server can be asked.
    func startAway() async {
        guard let server = current else { return }
        defaults.removeObject(forKey: awayOffKey(server))
        objectWillChange.send()
        await learnAway()
    }

    // MARK: The connection check

    private var connectSteps: ConnectSteps? { SharedData.connectSteps }

    /// Why the connector didn't connect, at the step it was on.
    func peerFailure(_ step: String, problem: String) -> ConnectFailure? {
        connectSteps?.classify(reason: problem.isEmpty ? "timeout" : "", text: problem, step: step)
    }

    /// Shows the steps for a run that failed (ConnectCheckView), and answers `words` for the
    /// screen underneath. `retry` is a server's address to try again, if there is one.
    func checkFailed(_ run: ConnectRun, _ failure: ConnectFailure?, _ words: String, retry: String? = nil) -> String {
        guard let failure else { return words }
        let f = run.fail(failure)
        ClientLog.shared.warn("p2p", "Connecting from away failed at \(f.step): \(f.code)", session: awayLogSession)
        connectCheck = run
        checkRetry = retry
        return words
    }

    // MARK: The connecting screen

    /// Starts a join on the connecting screen (ConnectingView). `join` answers words when it ends without opening the
    /// server or showing the connection check: the screen then shows them on the step it stopped at.
    func startJoining(_ run: ConnectRun, retry: (() -> Void)?, _ join: @escaping @MainActor (AppModel) async -> String?) {
        connectingTask?.cancel()
        connectingWords = ""
        connectingRetry = retry
        connecting = run
        connectingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let words = await join(self)
            guard !Task.isCancelled, self.connecting === run else { return }
            // The connection check shows in its place.
            if self.connectCheck === run { return }
            if let words {
                run.stop(words)
                self.connectingWords = words
            } else {
                self.connecting = nil // opened
            }
        }
    }

    /// Cancel, or Back once it has ended: the join stops, and the screen it came from shows again.
    func stopJoining() {
        let going = connecting != nil && connectingWords.isEmpty && connectCheck !== connecting
        connectingTask?.cancel()
        connectingTask = nil
        if going { peers.close() }
        if let run = connecting, connectCheck === run { connectCheck = nil }
        connecting = nil
        connectingWords = ""
        connectingRetry = nil
    }

    /// An invite link typed, pasted or scanned, on the connecting screen.
    func joinShown(_ invite: PeerConnect.Invite) {
        let run = ConnectRun(kind: "invite", server: invite.serverID)
        run.named(invite.name)
        startJoining(run, retry: { [weak self] in self?.joinShown(invite) }) { model in await model.join(invite, run: run) }
    }

    /// The server took the code a TV showed: the rest on the connecting screen.
    func joinedShown(_ answer: PeerConnect.Enrolment) {
        let run = ConnectRun(kind: "code", server: answer.serverID)
        run.named(answer.serverName)
        startJoining(run, retry: nil) { model in await model.joined(answer, run: run) }
    }

    // MARK: An invite

    /// An invite link, typed or pasted on the connect screen: finds the server, shows it the
    /// invite, which puts this device on its list, and signs in with the code that comes back.
    /// Answers words to show if it didn't work.
    func join(_ invite: PeerConnect.Invite, run given: ConnectRun? = nil) async -> String? {
        let run = given ?? ConnectRun(kind: "invite", server: invite.serverID)
        run.named(invite.name)
        Redact.addSecret(invite.secret)
        guard PeerLibrary.available else { return checkFailed(run, connectSteps?.of("p2p-missing", step: "read"), say("awayNotHere")) }
        guard let key = deviceKey() else { return checkFailed(run, connectSteps?.of("no-key", step: "read"), say("notKept")) }
        run.pass("read")
        run.note("looking for the server, with \(invite.hints.count) addresses from the invite")
        if let problem = await openAway(serverID: invite.serverID, hints: invite.hints, key: key, run: run) { return problem }
        let answer = await peers.enrol(secret: invite.secret, name: deviceName, platform: platformName)
        guard let answer, answer.ok else {
            peers.close()
            // A reason is the server's own answer; without one the invite never got to it.
            let reason = answer?.reason ?? ""
            if !reason.isEmpty { run.pass("found"); run.pass("secure") }
            let failure = connectSteps?.classify(reason: reason, text: answer?.error ?? peers.problem, step: reason.isEmpty ? "secure" : "signin")
            return checkFailed(run, failure, say("errInviteRefused"))
        }
        run.pass("found")
        run.pass("secure")
        run.note("the server took the invite")
        return await finishJoining(serverID: invite.serverID, hints: invite.hints, answer: answer, name: invite.name, run: run)
    }

    /// A device with no keyboard, away from home, can't take an invite in. It shows a code
    /// instead (`PeerLibrary.newJoinCode`), which someone signed in types into the server; this
    /// waits for that, and then carries on as after an invite. Nil if it couldn't start.
    func waitToJoin(code: String) -> PeerJoining? {
        guard PeerLibrary.available, let key = deviceKey() else { return nil }
        return PeerLibrary.join(key: key, code: code, name: deviceName, platform: platformName)
    }

    /// The server took the code this device showed, and has put it on its list.
    func joined(_ answer: PeerConnect.Enrolment, run given: ConnectRun? = nil) async -> String? {
        let run = given ?? ConnectRun(kind: "code", server: answer.serverID)
        run.named(answer.serverName)
        run.pass("read")
        guard answer.ok, !answer.serverID.isEmpty else {
            return checkFailed(run, connectSteps?.classify(reason: answer.reason, text: answer.error, step: "signin"), say("joinAwayRefused"))
        }
        guard let key = deviceKey() else { return checkFailed(run, connectSteps?.of("no-key", step: "read"), say("notKept")) }
        run.pass("found") // the server took the code
        if let problem = await openAway(serverID: answer.serverID, hints: answer.addresses, key: key, run: run, step: "secure") { return problem }
        run.pass("secure")
        return await finishJoining(serverID: answer.serverID, hints: answer.addresses, answer: answer, name: "", run: run)
    }

    private func knownAway(_ serverID: String) -> SavedServer? {
        recent.first { awayInfo(for: $0)?.serverID == serverID }
    }

    /// Starts the connection to a server known only by its ID. Words if it can't be reached.
    private func openAway(serverID: String, hints: [String], key: String, run: ConnectRun? = nil, step: String = "found") async -> String? {
        let known = knownAway(serverID)
        let home = known?.url ?? PeerInfo.placeholderAddress(serverID: serverID)
        let info = PeerInfo(serverID: serverID, hints: hints, port: known.flatMap(awayInfo(for:))?.port ?? 0)
        peers.use(nil)
        peers.use(PeerManager.Setup(home: home, peer: info, key: key))
        peers.awayWait = 45
        defer { peers.awayWait = 25 }
        if case .away(let state) = await peers.settle(), state.connected { return nil }
        let atHome = peers.way == .home
        let problem = peers.problem
        peers.close()
        if atHome { return say("awayAtHome") }
        guard let run else { return say("errAwayFailed") }
        return checkFailed(run, peerFailure(step, problem: problem), say("errAwayFailed"))
    }

    /// On the server's list and connected: who it is is proved and remembered, and the sign-in
    /// code that came back is redeemed over the connection.
    private func finishJoining(serverID: String, hints: [String], answer: PeerConnect.Enrolment, name: String, run: ConnectRun = ConnectRun(kind: "invite")) async -> String? {
        let known = knownAway(serverID)
        let home = known?.url ?? PeerInfo.placeholderAddress(serverID: serverID)
        // Who it is, proved: the key it shows now is the one remembered from here on.
        let proof = await WittyClient.identify(home, saved: known.map { [$0] } ?? [], route: peers.route)
        guard proof.state == .new || proof.state == .same else {
            run.note("the server didn't prove itself over the connection: \(proof.state)")
            peers.close()
            // Not answered at all is a connection that couldn't carry a request yet; answered wrongly is another server.
            let unreachable = proof.state == .unreachable
            return checkFailed(run, unreachable ? connectSteps?.of("slow-path", step: "secure") : connectSteps?.of("identity-bad", step: "signin"),
                               unreachable ? say("errAwayFailed") : say("identityBad"))
        }
        let shown = PlainWords.clean(answer.serverName.isEmpty ? name : answer.serverName, limit: 80)
        run.named(shown.isEmpty ? (known?.name ?? "") : shown)
        // Cancelled meanwhile: nothing is kept or opened.
        if Task.isCancelled {
            peers.close()
            return nil
        }
        let server = proof.saved(url: home, name: shown.isEmpty ? (known?.name ?? "WittyMediaServer") : shown, brandLogo: known?.brandLogo ?? "")
        defaults.removeObject(forKey: awayOffKey(server))
        keepAway(PeerInfo(serverID: serverID, hints: hints, port: peers.route.current?.port ?? 0), for: server)
        remember(server)
        signIn(to: server)
        guard !answer.code.isEmpty else { return nil }
        do {
            let result = try await connection(to: home, quick: true).pairRedeem(code: answer.code, device: deviceName, platform: platformName)
            signedIn(token: result.token, user: result.user)
        } catch {
            // They sign in by hand, on the screen that is now showing.
            ClientLog.shared.warn("p2p", "The sign-in code that came with joining was refused")
        }
        return nil
    }

    // MARK: For the check

    #if DEBUG
    /// For `apple/scripts/p2p-check.sh`, which runs the app in a simulator against a real server
    /// with nobody there to work a remote: `-WittyCheckServer <address>` at launch, with no server
    /// chosen yet, chooses that one and asks for a code shown on this screen, which the check
    /// approves as a phone would. `-WittyCheckPlay <item>` plays that item once someone is signed
    /// in (see `openWaitingLink`), `-WittyCheckJoin 1` opens Join from away (see `ConnectView`), and
    /// `-WittyCheckInvite <link>` takes an invite link. None of them is in a release build.
    func connectForCheck() async {
        // `-WittyCheckInvite <link>`: an invite link, as if it had been pasted where the address goes.
        if let link = UserDefaults.standard.string(forKey: "WittyCheckInvite"), let invite = PeerConnect.invite(from: link) {
            if let problem = await join(invite) { ClientLog.shared.warn("p2p", "The invite didn't work: \(problem)") }
            return
        }
        guard let address = UserDefaults.standard.string(forKey: "WittyCheckServer"), case .ok(let url) = Address.normalize(address),
              case .found(let status) = await WittyClient.probe(url) else { return }
        _ = await arrive(url: url, status: status)
        if case .code(let server, _) = stage { signIn(to: server, way: .shownCode) }
    }
    #endif
}
