import XCTest
@testable import WittyKit

/// The server's second stream, as WittyMediaServer docs/GAMING-STREAM.md has it.
final class GameStreamV2Tests: XCTestCase {
    private func le32(_ v: UInt32) -> [UInt8] { [UInt8(v & 0xff), UInt8(v >> 8 & 0xff), UInt8(v >> 16 & 0xff), UInt8(v >> 24)] }

    func testVideoCarriesItsNumberAndTimestamp() throws {
        let annexB: [UInt8] = [0, 0, 0, 1, 0x65, 0x88]
        let data = Data([0x11, 1] + le32(42) + le32(90_000) + annexB)
        let parsed = try XCTUnwrap(GameStreamV2.parse(data))
        XCTAssertEqual(parsed.message, .video(keyframe: true, annexB: Data(annexB)))
        XCTAssertEqual(parsed.timing, GameStreamV2.VideoTiming(frame: 42, timestamp: 90_000))
        XCTAssertEqual(try XCTUnwrap(GameStreamV2.parse(Data([0x11, 0] + le32(1) + le32(2) + annexB))).message,
                       .video(keyframe: false, annexB: Data(annexB)))
        XCTAssertNil(GameStreamV2.parse(Data([0x11, 1, 0, 0])), "too short")
    }

    func testSound() throws {
        let opus = try XCTUnwrap(GameStreamV2.parse(Data([0x12] + le32(480) + [0xFC, 0xFF])))
        XCTAssertEqual(opus.message, .opus(timestamp: 480, packet: Data([0xFC, 0xFF])))
        XCTAssertNil(opus.timing)
        let pcm = try XCTUnwrap(GameStreamV2.parse(Data([0x03] + le32(48_000) + [1, 0, 2, 0])))
        XCTAssertEqual(pcm.message, .pcm(rate: 48_000, samples: Data([1, 0, 2, 0])), "as in the first stream")
    }

    func testTheHello() throws {
        let hello = GameHello(app: "WittyMedia tvOS 0.3.1", device: "appletv-abc", name: "Living room", seats: [0, 1],
                              display: .init(hz: 59.94, width: 3840, height: 2160))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(hello.text().utf8)) as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "hello", "the WebSocket's first message says what it is")
        XCTAssertEqual(object["v"] as? Int, 2)
        XCTAssertEqual(object["device"] as? String, "appletv-abc")
        XCTAssertEqual(object["watch"] as? Bool, true)
        XCTAssertEqual(object["video"] as? [String], ["h264"])
        XCTAssertEqual(object["audio"] as? [String], ["pcm"], "no Opus until it's decoded here")
        XCTAssertEqual(object["seats"] as? [Int], [0, 1])
        XCTAssertEqual((object["display"] as? [String: Any])?["hz"] as? Double, 59.94)
        XCTAssertEqual(object["latency"] as? String, "auto")
        XCTAssertEqual(object["maxKbps"] as? Int, 0)
        XCTAssertEqual(GameHello(app: String(repeating: "a", count: 99), device: "d", name: String(repeating: "n", count: 99), seats: [],
                                 display: .init(hz: 60, width: 1, height: 1)).name.count, 40, "names are kept short")
        XCTAssertEqual(GameHello.seatsText([1, 0]), #"{"ports":[0,1],"take":false,"type":"seats"}"#)
    }

    func testTheStreamsEvents() throws {
        guard case .stream(let s)? = GameEvent.parse("""
        {"type":"stream","v":2,"conn":"k3","transport":"websocket","video":"h264","audio":"pcm","width":512,"height":448,"aspect":1.3333,"fps":60.0988,"rate":32040,"turns":0,"ports":4,"motion":false,"pace":60,"seats":[{"port":0,"conn":"k3","name":"Living room","you":true}],"kbps":5800,"away":false}
        """) else { return XCTFail("not a stream") }
        XCTAssertEqual(s.conn, "k3")
        XCTAssertEqual(s.transport, "websocket")
        XCTAssertEqual(s.width, 512)
        XCTAssertEqual(s.aspect ?? 0, 1.3333, accuracy: 0.0001)
        XCTAssertEqual(s.rate, 32040)
        XCTAssertEqual(s.ports, 4)
        XCTAssertEqual(s.pace, 60)
        XCTAssertEqual(GameEvent.parse(#"{"type":"seats","seats":[{"port":1,"conn":"q","name":"Phone","you":false}]}"#),
                       .seats([GameSeat(port: 1, conn: "q", name: "Phone", you: false)]))
        XCTAssertEqual(GameEvent.parse(#"{"type":"error","code":"seat-taken","port":1,"text":"Player 2 is on another device"}"#),
                       .refused(code: "seat-taken", text: "Player 2 is on another device", port: 1))
        XCTAssertEqual(GameEvent.parse(#"{"type":"ended","code":"stopped","text":"Saved and stopped"}"#), .ended("Saved and stopped"))
        XCTAssertEqual(GameEvent.parse(#"{"type":"ended","code":"idle"}"#), .ended(GameStreamDescription.endedWords("idle")),
                       "words of our own when the server gives none")
    }

    func testTheSecondStreamComesFirstWhereTheServerHasIt() throws {
        let modes = try JSONDecoder().decode([GameMode].self, from: Data("""
        [{"id":"webrtc","video":["h264"],"stream":2},{"id":"ws-h264","video":["h264"]},{"id":"ws-jpeg"}]
        """.utf8))
        XCTAssertEqual(GameModes.order(modes), [GameModes.streamWebSocket, "ws-h264", "ws-jpeg"])
        XCTAssertEqual(GameModes.order([GameMode(id: "ws-h264"), GameMode(id: "ws-jpeg")]), ["ws-h264", "ws-jpeg"], "a server without it")
        XCTAssertEqual(GameModes.order(nil), ["ws-h264", "ws-jpeg"])

        let client = WittyClient(base: "http://127.0.0.1:9797", token: "secret")
        let request = try XCTUnwrap(client.gameStreamRequest("g1"))
        XCTAssertEqual(request.url?.absoluteString, "ws://127.0.0.1:9797/api/v1/play/g1/stream")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        let hello = GameHello(app: "a", device: "d", name: "n", seats: [0], display: .init(hz: 60, width: 1, height: 1))
        let v2 = try XCTUnwrap(GameTransports.make(mode: GameModes.streamWebSocket, session: "g1", client: client, hello: hello) as? GameWebSocketTransport)
        XCTAssertTrue(v2.isSecondStream)
        XCTAssertNil(GameTransports.make(mode: GameModes.streamWebSocket, session: "g1", client: client), "it needs the hello")
        XCTAssertFalse(try XCTUnwrap(GameTransports.make(mode: "ws-h264", session: "g1", client: client) as? GameWebSocketTransport).isSecondStream)
    }

    func testHowLateFramesArrive() {
        var delay = ArrivalDelay()
        XCTAssertNil(delay.report(), "nothing to say before a frame")
        // Frames every 16.7 ms, arriving on time.
        for n in 0..<30 {
            let at = 1000 + Double(n) * 16.7
            delay.arrived(timestamp: UInt32(Double(n) * 16.7 * 90), now: at)
        }
        XCTAssertEqual(delay.report(), 0)
        XCTAssertNil(delay.report(), "each report covers the time since the last")
        // Then they back up: the worst of the half second is reported.
        delay.arrived(timestamp: UInt32(30 * 16.7 * 90), now: 1000 + 30 * 16.7 + 40)
        delay.arrived(timestamp: UInt32(31 * 16.7 * 90), now: 1000 + 31 * 16.7 + 120)
        delay.arrived(timestamp: UInt32(32 * 16.7 * 90), now: 1000 + 32 * 16.7 + 80)
        XCTAssertEqual(delay.report(), 120)
        // The quickest is looked for over the last ten seconds: lateness that stays becomes the new normal.
        let later = 1000 + 32 * 16.7 + 11_000
        for n in 0..<10 {
            delay.arrived(timestamp: UInt32((32 * 16.7 + 11_000 + Double(n) * 16.7) * 90), now: later + Double(n) * 16.7 + 80)
        }
        XCTAssertEqual(delay.report(), 0)
        XCTAssertEqual(ArrivalDelay.reportText(12), #"{"delayMs":12,"type":"report"}"#)
    }
}
