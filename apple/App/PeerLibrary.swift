// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import Foundation
import WittyKit
#if canImport(Wittyconnect)
import Wittyconnect
#endif

/// The library that does the connecting from away: Wittyconnect, built from the server's own
/// source in Go (`apple/scripts/build-wittyconnect.sh`; AGPL, see NOTICE). It is in the app on
/// Apple TV, iPhone and iPad. Apple Vision Pro has no build of it, so there the app is as it
/// was: at home, or through whatever else leads there.
///
/// WittyKit's PeerManager decides when it runs; this is only the door to it.
enum PeerLibrary {
    #if canImport(Wittyconnect)
    static let available = true

    /// A new key for this device. The server knows the device by it.
    static func newKey() -> String? {
        var error: NSError?
        let key = WittyMobileNewKey(&error)
        return error == nil && !key.isEmpty ? key : nil
    }

    /// The public name of a key: what the server lists the device under.
    static func deviceID(of key: String) -> String? {
        var error: NSError?
        let id = WittyMobileDeviceID(key, &error)
        return error == nil && PeerConnect.isID(id) ? id : nil
    }

    static func open(_ peer: PeerInfo, key: String, onState: @escaping @Sendable (PeerConnect.State) -> Void) throws -> PeerLink {
        tune()
        return try PeerConnector(key: key, peer: peer, onState: onState)
    }

    /// The code a device with no keyboard shows, for someone signed in to type into the server.
    static func newJoinCode() -> String? {
        var error: NSError?
        let code = WittyMobileNewJoinCode(&error)
        return error == nil && PeerConnect.isJoinCode(code) ? code : nil
    }

    /// Starts looking for the server that is told this device's code. Nil if it couldn't start.
    static func join(key: String, code: String, name: String, platform: String) -> PeerJoining? {
        tune()
        var error: NSError?
        guard let joining = WittyMobileStartJoin(PeerConnect.joinConfiguration(key: key, code: code, name: name, platform: platform), &error) else { return nil }
        return PeerJoining(joining)
    }

    /// The system says memory is short: the Go part gives back what it isn't using.
    static func freeMemory() { WittyMobileFreeMemory() }

    /// An Apple TV ends an app that takes too much, early and without asking, and an Apple TV HD
    /// has 2 GB for everything. The Go part is told to stay small there; a phone has more room.
    private static func tune() {
        #if os(tvOS)
        WittyMobileSetMemoryLimit(48)
        #else
        WittyMobileSetMemoryLimit(64)
        #endif
    }
    #else
    static let available = false
    static func newKey() -> String? { nil }
    static func deviceID(of key: String) -> String? { nil }
    static func open(_ peer: PeerInfo, key: String, onState: @escaping @Sendable (PeerConnect.State) -> Void) throws -> PeerLink {
        throw NSError(domain: "PeerLibrary", code: 1, userInfo: [NSLocalizedDescriptionKey: "This device can't connect from away."])
    }
    static func newJoinCode() -> String? { nil }
    static func join(key: String, code: String, name: String, platform: String) -> PeerJoining? { nil }
    static func freeMemory() {}
    #endif
}

/// A device showing a code, waiting for the server that is told it.
final class PeerJoining: @unchecked Sendable {
    #if canImport(Wittyconnect)
    private let joining: WittyMobileJoining
    init(_ joining: WittyMobileJoining) { self.joining = joining }

    /// The server's answer, once someone has typed the code in. Nil if nobody did before the code
    /// ran out (fifteen minutes), or `cancel` was called.
    func answer() async -> PeerConnect.Enrolment? {
        let joining = joining
        return await Task.detached(priority: .utility) { () -> PeerConnect.Enrolment? in
            var error: NSError?
            let answer = joining.wait(&error)
            return error == nil ? PeerConnect.Enrolment(json: answer) : nil
        }.value
    }

    func cancel() { joining.cancel() }
    deinit { joining.cancel() }
    #else
    func answer() async -> PeerConnect.Enrolment? { nil }
    func cancel() {}
    #endif
}

#if canImport(Wittyconnect)
/// One connection to one server, for as long as it is kept.
final class PeerConnector: NSObject, PeerLink, @unchecked Sendable {
    private let session: WittyMobileSession
    private let lock = NSLock()
    private var closed = false
    let port: Int
    let secret: String

    init(key: String, peer: PeerInfo, onState: @escaping @Sendable (PeerConnect.State) -> Void) throws {
        let ears = Ears(onState)
        var error: NSError?
        let config = PeerConnect.configuration(key: key, serverID: peer.serverID, hints: peer.hints, port: peer.port)
        guard let session = WittyMobileStart(config, ears, &error) else {
            throw error ?? NSError(domain: "PeerLibrary", code: 2, userInfo: [NSLocalizedDescriptionKey: "The connection from away couldn't be started."])
        }
        self.session = session
        port = session.port()
        secret = session.secret()
        super.init()
    }

    /// The library holds what listens to it; this only passes the news on.
    private final class Ears: NSObject, WittyMobileListenerProtocol {
        let hear: @Sendable (PeerConnect.State) -> Void
        init(_ hear: @escaping @Sendable (PeerConnect.State) -> Void) { self.hear = hear }
        func onState(_ state: String?) { hear(PeerConnect.State(json: state ?? "")) }
    }

    private var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }

    var state: PeerConnect.State { isClosed ? PeerConnect.State(path: .offline) : PeerConnect.State(json: session.state()) }

    var knownAddresses: [String] {
        guard !isClosed else { return [] }
        return (try? JSONDecoder().decode([String].self, from: Data(session.knownAddrs().utf8))) ?? []
    }

    func networkChanged() { if !isClosed { session.networkChanged() } }

    func enrol(secret: String, name: String, platform: String) throws -> PeerConnect.Enrolment {
        var error: NSError?
        let answer = session.enrol(secret, name: name, platform: platform, error: &error)
        if let error { throw error }
        return PeerConnect.Enrolment(json: answer)
    }

    /// Ending it waits for the node to stop, which can take a second or two, so not on the
    /// thread the screen is drawn from. The address stops answering at once either way.
    func close() {
        lock.lock()
        let already = closed
        closed = true
        lock.unlock()
        guard !already else { return }
        let session = session
        DispatchQueue.global(qos: .utility).async { session.close() }
    }

    deinit { close() }
}
#endif
