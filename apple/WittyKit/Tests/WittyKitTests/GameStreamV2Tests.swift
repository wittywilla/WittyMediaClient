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
        XCTAssertEqual(GameHello.reportText(hz: 50), #"{"hz":50,"type":"report"}"#)
        XCTAssertEqual(GameHello.reportText(hz: 59.94006), #"{"hz":59.94,"type":"report"}"#)
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

    // MARK: A whole controller

    func testRumbleSaysWhichMotorAndForHowLong() {
        XCTAssertEqual(GameEvent.parse(#"{"type":"rumble","port":0,"effect":0,"motor":"strong","strength":65535,"ms":300}"#),
                       .rumble(port: 0, strength: 1, motor: .strong, ms: 300))
        XCTAssertEqual(GameEvent.parse(#"{"type":"rumble","port":2,"effect":1,"motor":"weak","strength":0,"ms":0}"#),
                       .rumble(port: 2, strength: 0, motor: .weak, ms: 0), "0 stops it at once")
        XCTAssertEqual(GameEvent.parse(#"{"type":"rumble","port":0,"effect":1,"strength":32768}"#),
                       .rumble(port: 0, strength: 32768.0 / 65535, motor: .weak, ms: nil), "the first stream's effect")
        XCTAssertEqual(GameEvent.parse(#"{"type":"rumble","port":0,"strength":100}"#),
                       .rumble(port: 0, strength: 100.0 / 65535, motor: .either, ms: nil))
    }

    func testMotionIsSentOnlyWhileWanted() throws {
        guard case .motion(let want)? = GameEvent.parse(#"{"type":"motion","offered":true,"port":1,"accel":true,"gyro":false,"hz":60}"#) else {
            return XCTFail("not motion")
        }
        XCTAssertEqual(want, GameMotionWant(port: 1, accel: true, gyro: false, hz: 60))
        XCTAssertTrue(want.wanted)
        guard case .motion(let any)? = GameEvent.parse(#"{"type":"motion","offered":true}"#) else { return XCTFail("not motion") }
        XCTAssertFalse(any.wanted, "only that the game can read it")
        guard case .motion(let off)? = GameEvent.parse(#"{"type":"motion","offered":true,"port":1,"accel":false,"gyro":false,"hz":60}"#) else {
            return XCTFail("not motion")
        }
        XCTAssertFalse(off.wanted, "neither on: stop")
        guard case .motion(let fast)? = GameEvent.parse(#"{"type":"motion","port":0,"accel":true,"gyro":true,"hz":200}"#) else {
            return XCTFail("not motion")
        }
        XCTAssertEqual(fast.hz, 60, "never more than 60 a second")

        guard case .stream(let s)? = GameEvent.parse("""
        {"type":"stream","motion":true,"motionOn":[{"port":0,"accel":true,"gyro":true,"hz":60}],"leds":[{"index":0,"state":1}],"ports":4}
        """) else { return XCTFail("not a stream") }
        XCTAssertTrue(s.motion)
        XCTAssertEqual(s.motionOn, [GameMotionWant(port: 0, accel: true, gyro: true, hz: 60)])
        XCTAssertEqual(s.leds, [GameLight(index: 0, state: 1)])
        XCTAssertEqual(GameEvent.parse(#"{"type":"led","index":1,"state":200}"#), .led(index: 1, state: 200))
    }

    func testMotionsBytes() {
        // Held still and level: 1 g up; turning anticlockwise about Z at 90 degrees a second.
        let data = GameMotion.encoded(port: 1, accel: (0, 1, 0), gyro: (0, 0, Double.pi / 2))
        XCTAssertEqual(data.count, 14)
        XCTAssertEqual(Array(data.prefix(2)), [0xE1, 1])
        func i16(_ at: Int) -> Int16 { Int16(bitPattern: UInt16(data[at]) | UInt16(data[at + 1]) << 8) }
        XCTAssertEqual(i16(2), 0)
        XCTAssertEqual(i16(4), 4096, "1 g")
        XCTAssertEqual(i16(12), 1440, "90 degrees a second in sixteenths")
        let hard = GameMotion.encoded(port: 0, accel: (-20, 0, 0), gyro: (0, 0, 0))
        XCTAssertEqual(Int16(bitPattern: UInt16(hard[2]) | UInt16(hard[3]) << 8), -32767, "held at the edge of the range")
    }

    /// The NES's and the Super Nintendo's sessions both say 5 ports: a fifth player on one, an expansion port on the other.
    func testWhichPortsArePlayers() throws {
        let nes = try JSONDecoder().decode([GamePortDevices].self, from: Data("""
        [{"port":0,"current":1,"types":[{"id":1,"name":"Auto"},{"id":513,"name":"Gamepad"},{"id":258,"name":"Zapper"}]},
         {"port":1,"current":1,"types":[{"id":1,"name":"Auto"},{"id":513,"name":"Gamepad"},{"id":514,"name":"Arkanoid"},{"id":258,"name":"Zapper"},{"id":259,"name":"Power Pad A"},{"id":515,"name":"Power Pad B"}]},
         {"port":2,"current":1,"types":[{"id":1,"name":"Auto"},{"id":513,"name":"Gamepad"},{"id":259,"name":"Power Pad A"},{"id":515,"name":"Power Pad B"}]},
         {"port":3,"current":1,"types":[{"id":1,"name":"Auto"},{"id":513,"name":"Gamepad"}]},
         {"port":4,"current":1,"types":[{"id":1,"name":"Auto"},{"id":2,"name":"Arkanoid"},{"id":3,"name":"Hyper Shot"},{"id":4,"name":"Oeka Kids tablet"},{"id":5,"name":"Family Trainer"},{"id":6,"name":"4-player adapter"}]}]
        """.utf8))
        XCTAssertEqual(GamePorts.players(count: 5, devices: nes), [0, 1, 2, 3], "the Famicom's expansion port isn't a player")
        let snes = try JSONDecoder().decode([GamePortDevices].self, from: Data("""
        [{"port":0,"current":1,"types":[{"id":0,"name":"None"},{"id":257,"name":"SNES Controller"},{"id":770,"name":"SNES Mouse"}]},
         {"port":1,"current":1,"types":[{"id":0,"name":"None"},{"id":257,"name":"SNES Controller"},{"id":770,"name":"SNES Mouse"},{"id":262,"name":"Super Scope"},{"id":513,"name":"Multitap"}]},
         {"port":2,"current":1,"types":[{"id":257,"name":"SNES Controller"}]},
         {"port":3,"current":1,"types":[{"id":257,"name":"SNES Controller"}]},
         {"port":4,"current":1,"types":[{"id":257,"name":"SNES Controller"}]}]
        """.utf8))
        XCTAssertEqual(GamePorts.players(count: 5, devices: snes), [0, 1, 2, 3, 4], "five, through the multitap")
        XCTAssertEqual(GamePorts.players(count: nil, devices: nil), [0, 1, 2, 3], "the first stream: four")
        XCTAssertEqual(GamePorts.players(count: 12, devices: nil), [0, 1, 2, 3], "nothing said past the fourth")
        let ds = [GamePortDevices(port: 0, current: 1, types: [GameDeviceType(id: 1, name: "Nintendo DS")])]
        XCTAssertEqual(GamePorts.players(count: 1, devices: ds), [0], "a console's own name for its pad still plays")
        XCTAssertEqual(GamePorts.players(count: 4, devices: ds), [0, 1, 2, 3])
        XCTAssertFalse(GameDeviceType(id: 259, name: "Power Pad A").isController, "a floor mat")
        XCTAssertTrue(GameDeviceType(id: 1, name: "MD Joypad 6 Button").isController)
    }

    // MARK: WebRTC

    func testWebRTCComesFirstWhereTheAppHasIt() throws {
        let modes = [GameMode(id: "webrtc", video: ["h264"], stream: 2), GameMode(id: "ws-h264"), GameMode(id: "ws-jpeg")]
        XCTAssertEqual(GameModes.order(modes, webRTC: true), [GameModes.streamWebRTC, GameModes.streamWebSocket, "ws-h264", "ws-jpeg"])
        XCTAssertEqual(GameModes.order(modes, webRTC: false), [GameModes.streamWebSocket, "ws-h264", "ws-jpeg"])
        XCTAssertEqual(GameModes.order([GameMode(id: "ws-h264")], webRTC: true), ["ws-h264"], "no second stream, no WebRTC")
        XCTAssertEqual(GameModes.firstPictureWait(GameModes.streamWebRTC), 8)
        XCTAssertEqual(GameModes.firstPictureWait(GameModes.streamWebSocket), 12)
    }

    func testTheOfferAndItsAnswer() throws {
        let client = WittyClient(base: "https://media.example", token: "secret")
        let request = try XCTUnwrap(client.gameStreamOfferRequest("g 1"))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://media.example/api/v1/play/g%201/stream")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let hello = GameHello(app: "a", device: "d", name: "n", seats: [0], display: .init(hz: 60, width: 1, height: 1))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: GameStreamOffer.body(hello: hello, sdp: "v=0 offer")) as? [String: Any])
        XCTAssertEqual(body["sdp"] as? String, "v=0 offer")
        let sent = try XCTUnwrap(body["hello"] as? [String: Any])
        XCTAssertEqual(sent["v"] as? Int, 2)
        XCTAssertNil(sent["type"], "the hello as itself in the offer, not as a WebSocket message")

        let answer = try XCTUnwrap(GameStreamOffer.answer(Data(#"{"sdp":"v=0 answer","stream":{"v":2,"conn":"k9","transport":"webrtc","video":"h264","audio":"opus","width":512,"height":448,"ports":4}}"#.utf8)))
        XCTAssertEqual(answer.sdp, "v=0 answer")
        XCTAssertEqual(answer.stream?.conn, "k9")
        XCTAssertEqual(answer.stream?.transport, "webrtc")
        XCTAssertNil(GameStreamOffer.answer(Data(#"{"error":"no such game","code":"no-session"}"#.utf8)))
        XCTAssertEqual(GameStreamOffer.end(status: 404), .gone)
        XCTAssertEqual(GameStreamOffer.end(status: 415), .unreachable, "no codec in common: try the WebSocket")
        XCTAssertEqual(GameStreamOffer.end(status: 500), .unreachable)
    }
}
