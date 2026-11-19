// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

final class PeerConnectTests: XCTestCase {
    let server = "12D3KooWK99VoVxNE7XzyBwXEzW7xhK7Gpv85r9F3V3fyKSUKPH5"

    func testAnInviteIsReadAndNothingElseIsTakenForOne() {
        let link = "wittymedia://p2p/\(server)?s=abcdefghijklmnopqrstuv&n=Home+server&a=%2Fip4%2F203.0.113.4%2Fudp%2F4100%2Fquic-v1&a=rubbish"
        let invite = PeerConnect.invite(from: link)
        XCTAssertEqual(invite?.serverID, server)
        XCTAssertEqual(invite?.secret, "abcdefghijklmnopqrstuv")
        XCTAssertEqual(invite?.hints, ["/ip4/203.0.113.4/udp/4100/quic-v1"])
        for bad in ["", "http://192.168.1.20", "wittymedia://item/12", "wittymedia://p2p/\(server)", "wittymedia://p2p/\(server)?s=short",
                    "wittymedia://p2p/not-an-id?s=abcdefghijklmnopqrstuv", "https://p2p/\(server)?s=abcdefghijklmnopqrstuv",
                    "wittymedia://p2p/\(server)?s=abcdefghijklmnop%3Cscript%3E"] {
            XCTAssertNil(PeerConnect.invite(from: bad), bad)
        }
    }

    func testAddressesThatCouldHideSomethingAreDropped() {
        let good = ["/ip4/203.0.113.4/tcp/4100", "/ip6/2001:db8::1/udp/4100/quic-v1", "/ip4/198.51.100.2/tcp/4001/p2p/\(server)/p2p-circuit"]
        XCTAssertEqual(PeerConnect.hints(good + ["http://evil.example", "/ip4/1.2.3.4/tcp/1 --flag", "/unix/tmp/x", ""]), good)
        XCTAssertEqual(PeerConnect.hints(Array(repeating: good[0], count: 40)).count, 12)
    }

    func testTheConfigurationIsTheJSONTheLibraryTakes() throws {
        let json = PeerConnect.configuration(key: "k", serverID: server, hints: ["/ip4/203.0.113.4/tcp/4100", "nope"])
        let read = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(read["key"] as? String, "k")
        XCTAssertEqual(read["serverId"] as? String, server)
        XCTAssertEqual(read["hints"] as? [String], ["/ip4/203.0.113.4/tcp/4100"])
    }

    func testTheStateIsReadAndARelayIsAlwaysSaid() {
        let direct = PeerConnect.State(json: #"{"path":"direct","transport":"quic","since":5}"#)
        XCTAssertEqual(direct.path, .direct)
        XCTAssertTrue(direct.connected)
        XCTAssertEqual(direct.words, "Peer to peer · direct")
        XCTAssertTrue(PeerConnect.State(json: #"{"path":"relayed","community":true}"#).words.contains("relay"))
        XCTAssertFalse(PeerConnect.State(json: #"{"path":"offline","error":"x"}"#).connected)
        XCTAssertEqual(PeerConnect.State(json: "not json").path, .connecting)
        XCTAssertEqual(PeerConnect.State(json: #"{"path":"made-up"}"#).path, .connecting)
    }

    func testWhatARelayAllowsIsSaidAndNothingElseFromIt() {
        let s = PeerConnect.State(json: #"{"path":"relayed","community":true,"relayKbps":4000,"relayMaxHeight":720,"relayAllows":"Up to 4 Mbit/s,\u0007 720p."}"#)
        XCTAssertEqual(s.relayKbps, 4000)
        XCTAssertEqual(s.relayMaxHeight, 720)
        XCTAssertEqual(s.words, "Peer to peer · through a relay · 4 Mbit/s, 720p")
        XCTAssertEqual(s.relayAllows, "Up to 4 Mbit/s, 720p.")
        XCTAssertEqual(PeerConnect.State(json: #"{"path":"relayed","community":true,"relayKbps":1500}"#).words, "Peer to peer · through a relay · 1.5 Mbit/s")
        // One odd value loses only itself; a relay that only introduces, or a direct path, says no limits.
        let odd = PeerConnect.State(json: #"{"path":"relayed","community":true,"relayKbps":"4000","relayMaxHeight":99999}"#)
        XCTAssertEqual(odd.path, .relayed)
        XCTAssertNil(odd.relayKbps)
        XCTAssertNil(odd.relayMaxHeight)
        XCTAssertNil(PeerConnect.State(json: #"{"path":"relayed","community":false,"relayKbps":4000}"#).relayKbps)
        XCTAssertNil(PeerConnect.State(json: #"{"path":"direct","relayKbps":4000}"#).relayKbps)
    }

    func testIDs() {
        XCTAssertTrue(PeerConnect.isID(server))
        XCTAssertFalse(PeerConnect.isID("QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"))
        XCTAssertFalse(PeerConnect.isID(server + "x"))
        XCTAssertFalse(PeerConnect.isID(server.replacingOccurrences(of: "K", with: "0")))
    }

    func testTheAnswerToAnInviteOrACodeIsReadWithCare() {
        let yes = PeerConnect.Enrolment(json: #"{"ok":true,"code":"123456","serverName":"Home\u202e","serverId":"\#(server)","addrs":["/ip4/203.0.113.4/tcp/4100","javascript:alert(1)"]}"#)
        XCTAssertTrue(yes.ok)
        XCTAssertEqual(yes.code, "123456")
        XCTAssertEqual(yes.serverName, "Home")
        XCTAssertEqual(yes.serverID, server)
        XCTAssertEqual(yes.addresses, ["/ip4/203.0.113.4/tcp/4100"])
        // A code that isn't six digits is no code, and an ID that isn't one is no server.
        let odd = PeerConnect.Enrolment(json: #"{"ok":true,"code":"12345x","serverId":"elsewhere"}"#)
        XCTAssertEqual(odd.code, "")
        XCTAssertEqual(odd.serverID, "")
        let no = PeerConnect.Enrolment(json: #"{"ok":false,"reason":"expired","error":"That invite has expired."}"#)
        XCTAssertFalse(no.ok)
        XCTAssertEqual(no.reason, "expired")
        XCTAssertEqual(no.error, "That invite has expired.")
        XCTAssertFalse(PeerConnect.Enrolment(json: "rubbish").ok)
    }

    func testACodeADeviceShowsAndWhatTheLibraryTakesToLookWithIt() throws {
        XCTAssertTrue(PeerConnect.isJoinCode("K7QM-2XHD"))
        for bad in ["", "K7QM2XHD", "K7QM-2XH", "k7qm-2xhd", "K7QM-2XHU", "K7QM-2XHD-1", "K7QM 2XHD"] {
            XCTAssertFalse(PeerConnect.isJoinCode(bad), bad)
        }
        let json = PeerConnect.joinConfiguration(key: "k", code: "K7QM-2XHD", name: "Living room", platform: "tvOS")
        let read = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(read["key"] as? String, "k")
        XCTAssertEqual(read["code"] as? String, "K7QM-2XHD")
        XCTAssertEqual(read["name"] as? String, "Living room")
        XCTAssertEqual(read["platform"] as? String, "tvOS")
    }
}
