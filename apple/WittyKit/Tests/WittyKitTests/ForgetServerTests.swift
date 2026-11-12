// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

final class ForgetServerTests: XCTestCase {
    private let a = SavedServer(url: "http://nas:9797", name: "Home", serverId: "ida", publicKey: "KA")
    private let b = SavedServer(url: "http://nas.local:9797", name: "Flat", serverId: "idb", publicKey: "KB")
    private let c = SavedServer(url: "http://nas:9798", name: "Shed")

    /// Everything two servers and the device keep, as the app's preferences name it.
    private var keys: [String] {
        ["recent", "server", "wms.sound", "wittyplay.device", "listening.bookSpeed", "recentSince",
         "theme.http://nas:9797", "themeTokens|http://nas:9797|midnight", "themeTokens|http://nas:9797|default",
         "topMenu.http://nas:9797.willow", "topMenu.http://nas:9797.guest.one", "peer.ida",
         "theme.http://nas.local:9797", "themeTokens|http://nas.local:9797|paper", "topMenu.http://nas.local:9797.willow", "peer.idb",
         "theme.http://nas:9798", "topMenu.http://nas:9798.willow", "peer.http://nas:9798"]
    }

    private func holding(current: String = "", signedIn: Bool = false, pin: String = "", keys: [String]? = nil) -> ForgetServer.Holding {
        ForgetServer.Holding(recent: [a, b, c], current: current, signedIn: signedIn, pin: pin, keys: keys ?? self.keys)
    }

    // MARK: Whose a key is

    func testAKeyBelongsToTheLongestAddressThatFits() {
        let addresses = ["http://nas", "http://nas.local"]
        XCTAssertEqual(ServerKeys.owner(of: "topMenu.http://nas.local.willow", addresses: addresses), .address("http://nas.local"))
        XCTAssertEqual(ServerKeys.owner(of: "topMenu.http://nas.willow", addresses: addresses), .address("http://nas"))
        XCTAssertEqual(ServerKeys.owner(of: "topMenu.http://nas.a.b", addresses: addresses), .address("http://nas"), "a profile's name can have a dot")
        XCTAssertEqual(ServerKeys.owner(of: "sdui.available|http://nas:9797", addresses: addresses), .address("http://nas:9797"),
                       "whether a server has its own pages goes with it")
        XCTAssertEqual(ServerKeys.owner(of: "topMenu.http://gone:1.willow", addresses: addresses), .address("http://gone:1.willow"), "nobody's")
        XCTAssertEqual(ServerKeys.owner(of: "theme.http://nas", addresses: addresses), .address("http://nas"))
        XCTAssertEqual(ServerKeys.owner(of: "themeTokens|http://nas|light", addresses: addresses), .address("http://nas"))
        XCTAssertEqual(ServerKeys.owner(of: "peer.ida", addresses: addresses), .peer("ida"))
        for own in ["recent", "server", "wms.sound", "wms.view.item.4", "wittyplay.touch", "themes"] {
            XCTAssertNil(ServerKeys.owner(of: own, addresses: addresses), "\(own) is the device's")
        }
    }

    func testALogosFileNamesItsAddress() {
        for url in ["http://10.0.0.1:9797", "https://media.example/~?>>", "http://[fe80::1]:9797"] {
            XCTAssertEqual(ServerKeys.logoAddress(file: ServerKeys.logoName(url) + "-v12"), url)
        }
        XCTAssertNil(ServerKeys.logoAddress(file: "notes.txt"))
    }

    // MARK: The plan

    func testForgettingOneLeavesExactlyTheOthers() {
        let plan = ForgetServer.plan(removing: [a], holding: holding())
        XCTAssertEqual(plan.removed, [a])
        XCTAssertEqual(plan.remaining, [b, c])
        XCTAssertEqual(Set(plan.keys), ["theme.http://nas:9797", "themeTokens|http://nas:9797|midnight", "themeTokens|http://nas:9797|default",
                                        "topMenu.http://nas:9797.willow", "topMenu.http://nas:9797.guest.one", "peer.ida"])
        XCTAssertEqual(plan.keys.count, Set(plan.keys).count)
        let left = Set(keys).subtracting(plan.keys)
        XCTAssertEqual(left, ["recent", "server", "wms.sound", "wittyplay.device", "listening.bookSpeed", "recentSince",
                              "theme.http://nas.local:9797", "themeTokens|http://nas.local:9797|paper", "topMenu.http://nas.local:9797.willow", "peer.idb",
                              "theme.http://nas:9798", "topMenu.http://nas:9798.willow", "peer.http://nas:9798"],
                       "the other servers' and the device's own are all still there")
        XCTAssertEqual(plan.logos, ["http://nas:9797"])
        XCTAssertEqual(plan.hosts, [], "another server is at the same host, and cookies don't know ports")
        XCTAssertEqual(plan.peers, [a])
        XCTAssertFalse(plan.clearsDeviceKey, "two servers still know this device by its key")
        XCTAssertFalse(plan.clearsCurrent)
        XCTAssertNil(plan.signIn)
    }

    func testAnAddressThatIsTheStartOfAnotherTakesNothingOfTheOthers() {
        let short = SavedServer(url: "http://nas", name: "Short")
        let long = SavedServer(url: "http://nas.local", name: "Long")
        let all = ["theme.http://nas", "theme.http://nas.local", "topMenu.http://nas.willow", "topMenu.http://nas.local.willow",
                   "themeTokens|http://nas|light", "themeTokens|http://nas.local|light"]
        let plan = ForgetServer.plan(removing: [short], holding: ForgetServer.Holding(recent: [short, long], keys: all))
        XCTAssertEqual(plan.keys, ["theme.http://nas", "topMenu.http://nas.willow", "themeTokens|http://nas|light"])
        XCTAssertEqual(plan.hosts, ["nas"])
        let other = ForgetServer.plan(removing: [long], holding: ForgetServer.Holding(recent: [short, long], keys: all))
        XCTAssertEqual(other.keys, ["theme.http://nas.local", "topMenu.http://nas.local.willow", "themeTokens|http://nas.local|light"])
    }

    func testTheSignInGoesOnlyWithTheServerItBelongsTo() {
        // Signed in to b, which is the one in use.
        let inUse = holding(current: b.url, signedIn: true, pin: "KB")
        XCTAssertNil(ForgetServer.plan(removing: [a], holding: inUse).signIn, "another server's sign-in stays")
        XCTAssertNil(ForgetServer.plan(removing: [a, c], holding: inUse).signIn)
        XCTAssertFalse(ForgetServer.plan(removing: [a, c], holding: inUse).clearsCurrent)
        let gone = ForgetServer.plan(removing: [b], holding: inUse)
        XCTAssertEqual(gone.signIn, b)
        XCTAssertTrue(gone.clearsCurrent)
        // Kept with b's key, though the address in use is by now something else.
        XCTAssertEqual(ForgetServer.plan(removing: [b], holding: holding(current: "http://elsewhere", signedIn: true, pin: "KB")).signIn, b, "by the key it was kept with")
        // A server too old to have a key: only the address in use says whose the sign-in is.
        XCTAssertEqual(ForgetServer.plan(removing: [c], holding: holding(current: c.url, signedIn: true)).signIn, c)
        XCTAssertNil(ForgetServer.plan(removing: [a], holding: holding(current: c.url, signedIn: true)).signIn)
        // Nobody is signed in: there is nothing to tell the server.
        let nobody = ForgetServer.plan(removing: [b], holding: holding(current: b.url))
        XCTAssertNil(nobody.signIn)
        XCTAssertTrue(nobody.clearsCurrent, "the address in use is forgotten all the same")
    }

    func testTheDevicesKeyGoesOnlyWhenNoServerLeftUsesIt() {
        XCTAssertFalse(ForgetServer.plan(removing: [a, b], holding: holding()).clearsDeviceKey, "c still reaches this device by it")
        let all = ForgetServer.plan(removing: [a, b, c], holding: holding())
        XCTAssertTrue(all.clearsDeviceKey)
        XCTAssertEqual(all.peers, [a, b, c], "each is asked to take this device off its list")
        XCTAssertEqual(Set(all.keys), Set(keys.filter { ServerKeys.owner(of: $0, addresses: []) != nil }))
        XCTAssertEqual(all.hosts, ["nas", "nas.local"])
        XCTAssertTrue(all.remaining.isEmpty)
        // Only a has a way from away: removing b has nothing to say about the key.
        let onlyA = keys.filter { !["peer.idb", "peer.http://nas:9798"].contains($0) }
        let plan = ForgetServer.plan(removing: [b], holding: holding(keys: onlyA))
        XCTAssertEqual(plan.peers, [])
        XCTAssertFalse(plan.clearsDeviceKey)
        XCTAssertTrue(ForgetServer.plan(removing: [a], holding: holding(keys: onlyA)).clearsDeviceKey, "the last server that used it")
    }

    func testAServerTheDeviceDoesNotRememberRemovesNothing() {
        let plan = ForgetServer.plan(removing: [SavedServer(url: "http://stranger", name: "?")], holding: holding(current: b.url, signedIn: true, pin: "KB"))
        XCTAssertEqual(plan.removed, [])
        XCTAssertEqual(plan.remaining, [a, b, c])
        XCTAssertTrue(plan.keys.isEmpty && plan.logos.isEmpty && plan.hosts.isEmpty && plan.peers.isEmpty)
        XCTAssertNil(plan.signIn)
        XCTAssertFalse(plan.clearsCurrent || plan.clearsDeviceKey)
    }

    // MARK: A server that moved, and what nobody owns

    func testSettingsFollowAServerToItsNewAddress() {
        let moved = SavedServer(url: "https://media.example", name: "Home", serverId: "ida", publicKey: "KA")
        let renames = ServerKeys.renames(ServerMove(from: a, to: moved), in: keys, addresses: [a.url, b.url, c.url])
        XCTAssertEqual(renames.map { "\($0.from) > \($0.to)" }, [
            "theme.http://nas:9797 > theme.https://media.example",
            "themeTokens|http://nas:9797|midnight > themeTokens|https://media.example|midnight",
            "themeTokens|http://nas:9797|default > themeTokens|https://media.example|default",
            "topMenu.http://nas:9797.willow > topMenu.https://media.example.willow",
            "topMenu.http://nas:9797.guest.one > topMenu.https://media.example.guest.one",
        ], "the way from away is kept by ID, and stays where it is")
        // With no ID, the way from away is by address and moves too.
        let noId = SavedServer(url: "http://10.0.0.3:9798", name: "Shed")
        XCTAssertEqual(ServerKeys.renames(ServerMove(from: c, to: noId), in: keys, addresses: [a.url, b.url, c.url]).last?.to, "peer.http://10.0.0.3:9798")
    }

    func testKeysNobodyOwnsAreFound() {
        let stray = ["theme.http://old:9797", "themeTokens|http://old:9797|light", "topMenu.http://old:9797.willow", "peer.gone"]
        let found = ServerKeys.orphans(in: keys + stray, servers: [a, b, c], current: "")
        XCTAssertEqual(found, ["theme.http://old:9797", "themeTokens|http://old:9797|light", "topMenu.http://old:9797.willow"],
                       "a way from away is never guessed at")
        XCTAssertEqual(ServerKeys.orphans(in: keys + stray, servers: [a, b, c], current: "http://old:9797"), [], "the server in use counts, listed or not")
        XCTAssertEqual(ServerKeys.orphans(in: keys, servers: [a, b, c], current: ""), [])
    }
}
