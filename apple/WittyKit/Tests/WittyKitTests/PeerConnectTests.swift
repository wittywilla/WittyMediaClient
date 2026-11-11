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

    func testIDs() {
        XCTAssertTrue(PeerConnect.isID(server))
        XCTAssertFalse(PeerConnect.isID("QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN"))
        XCTAssertFalse(PeerConnect.isID(server + "x"))
        XCTAssertFalse(PeerConnect.isID(server.replacingOccurrences(of: "K", with: "0")))
    }
}
