// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

/// The server's docs/REMOTE-PROTOCOL.md, as far as it needs no screen: what a device announces, what a command
/// means, when a state is sent, what happens when the channel ends, and what a controller shows.
final class RemoteProtocolTests: XCTestCase {
    private func decode<T: Decodable>(_ json: String, as type: T.Type = T.self) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: What a device announces

    func testEachDeviceAnnouncesOnlyWhatItReallyDoes() {
        let tv = RemoteAbility.capabilities(.tv)
        XCTAssertEqual(tv.mediaKinds, ["video", "audio"])
        XCTAssertTrue(tv.has("navigate"), "Apple TV is steered with a remote's keys")
        XCTAssertFalse(tv.has("volume"), "an app can't set Apple TV's volume: the TV has it")
        for touch in [RemotePlatform.phone, .tablet] {
            let caps = RemoteAbility.capabilities(touch)
            XCTAssertTrue(caps.has("volume"))
            XCTAssertFalse(caps.has("navigate"), "a phone is touched, not steered")
            XCTAssertEqual(Set(caps.features), ["seek", "volume", "queue", "audio", "subtitles", "rate"])
        }
        XCTAssertFalse(tv.plays("dvd-iso"), "discs with menus open the server's own page")
    }

    func testTheAnnouncementCarriesTheVersionTheKindAndTheOldIdWhenComingBack() throws {
        let first = RemoteAbility.announcement(name: "Living room\u{202e} TV", platform: .tv, deviceId: "")
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(first)) as? [String: Any])
        XCTAssertEqual(sent["v"] as? Int, 1)
        XCTAssertEqual(sent["kind"] as? String, "tv")
        XCTAssertEqual(sent["name"] as? String, "Living room TV")
        XCTAssertNil(sent["deviceId"])
        let again = RemoteAbility.announcement(name: "iPad", platform: .tablet, deviceId: "5b0c")
        XCTAssertEqual(again.deviceId, "5b0c")
        XCTAssertEqual(again.kind, "tablet")
    }

    // MARK: Commands

    private let all = RemoteCapabilities(mediaKinds: ["video", "audio"], features: ["seek", "volume", "queue", "audio", "subtitles", "rate", "navigate"])

    func testEveryCommandOfTheGuideIsUnderstood() throws {
        let cases: [(String, RemoteAction)] = [
            (#"{"v":1,"type":"play","itemId":812,"positionSec":0}"#, .play(queue: [812], index: 0, positionSec: 0, audio: nil, subtitle: nil)),
            (#"{"v":1,"type":"play","queue":[812,813,814],"queueIndex":1,"audio":"2","subtitle":"off"}"#,
             .play(queue: [812, 813, 814], index: 1, positionSec: nil, audio: 2, subtitle: -1)),
            (#"{"v":1,"type":"pause"}"#, .pause),
            (#"{"v":1,"type":"resume"}"#, .resume),
            (#"{"v":1,"type":"stop"}"#, .stop),
            (#"{"v":1,"type":"seek","positionSec":754.5}"#, .seek(to: 754.5)),
            (#"{"v":1,"type":"seek","bySec":-10}"#, .seek(by: -10)),
            (#"{"v":1,"type":"next"}"#, .next),
            (#"{"v":1,"type":"previous"}"#, .previous),
            (#"{"v":1,"type":"volume","level":0.4}"#, .volume(0.4)),
            (#"{"v":1,"type":"mute","muted":true}"#, .mute(true)),
            (#"{"v":1,"type":"audio","audio":"2"}"#, .audio(2)),
            (#"{"v":1,"type":"subtitle","subtitle":"off"}"#, .subtitle(-1)),
            (#"{"v":1,"type":"subtitle","subtitle":"3"}"#, .subtitle(3)),
            (#"{"v":1,"type":"rate","rate":1.25}"#, .rate(1.25)),
            (#"{"v":1,"type":"navigate","key":"select"}"#, .navigate("select")),
        ]
        for (json, wanted) in cases {
            XCTAssertEqual(RemoteAction.read(try decode(json), abilities: all), wanted, json)
        }
    }

    func testACommandAsADeviceReceivesItKeepsItsIdAndWhoSentIt() throws {
        let command: RemoteCommand = try decode(#"{"v":1,"id":"c41f","type":"seek","bySec":-10,"sender":{"userName":"Sam"},"sentAt":1794000004200,"newField":{"a":1}}"#)
        XCTAssertEqual(command.id, "c41f")
        XCTAssertEqual(command.sender?.userName, "Sam")
        XCTAssertEqual(RemoteAction.read(command, abilities: all), .seek(by: -10))
    }

    func testAnUnknownCommandIsAnsweredInWordsAndNeverIgnored() throws {
        guard case .refuse(let words) = RemoteAction.read(try decode(#"{"v":1,"id":"c1","type":"teleport"}"#), abilities: all) else {
            return XCTFail("an unknown type must be refused")
        }
        XCTAssertEqual(words, "This device can't do that.")
        // A command with nothing readable in it still has a type of "", which is unknown too.
        let odd: RemoteCommand = try decode(#"{"id":"c2","type":7,"positionSec":"soon"}"#)
        XCTAssertEqual(odd.id, "c2")
        XCTAssertEqual(RemoteAction.read(odd, abilities: all), .refuse("This device can't do that."))
    }

    func testWhatWasNeverAnnouncedIsRefused() throws {
        let tv = RemoteAbility.capabilities(.tv)
        XCTAssertEqual(RemoteAction.read(RemoteCommand("volume", level: 0.5), abilities: tv), .refuse("This device can't do that."))
        XCTAssertEqual(RemoteAction.read(RemoteCommand("mute", muted: true), abilities: tv), .refuse("This device can't do that."))
        let phone = RemoteAbility.capabilities(.phone)
        XCTAssertEqual(RemoteAction.read(RemoteCommand("navigate", key: "up"), abilities: phone), .refuse("This device can't do that."))
        let noQueue = RemoteCapabilities(mediaKinds: ["video"], features: ["seek"])
        XCTAssertEqual(RemoteAction.read(RemoteCommand("play", queue: [1, 2], queueIndex: 0), abilities: noQueue), .refuse("This device can't do that."))
        XCTAssertEqual(RemoteAction.read(RemoteCommand("play", itemId: 1), abilities: noQueue), .play(queue: [1], index: 0, positionSec: nil, audio: nil, subtitle: nil))
    }

    func testCommandsThatMakeNoSenseAreRefusedWithASentence() {
        let refusals: [RemoteCommand] = [
            RemoteCommand("play"),
            RemoteCommand("play", queue: [1, 2], queueIndex: 5),
            RemoteCommand("play", itemId: 9, queue: [1, 2], queueIndex: 0),
            RemoteCommand("seek"),
            RemoteCommand("seek", positionSec: .nan),
            RemoteCommand("volume"),
            RemoteCommand("mute"),
            RemoteCommand("audio", audio: "off"),
            RemoteCommand("audio", audio: "first"),
            RemoteCommand("subtitle"),
            RemoteCommand("rate", rate: 9),
            RemoteCommand("rate", rate: 0.1),
            RemoteCommand("navigate", key: "power"),
        ]
        for command in refusals {
            guard case .refuse(let words) = RemoteAction.read(command, abilities: all) else { return XCTFail("\(command.type) should be refused") }
            XCTAssertFalse(words.isEmpty)
            XCTAssertLessThanOrEqual(words.count, 200)
        }
        XCTAssertEqual(RemoteAction.read(RemoteCommand("volume", level: 4), abilities: all), .volume(1), "a level is kept between 0 and 1")
        XCTAssertEqual(RemoteAction.read(RemoteCommand("seek", positionSec: -5), abilities: all), .seek(to: 0))
    }

    func testAQueueIsWalkedAndStopsAtItsEnds() {
        let queue: [Int64] = [812, 813, 814]
        XCTAssertEqual(RemoteQueue.step(queue, from: 0, by: 1), 1)
        XCTAssertEqual(RemoteQueue.step(queue, from: 2, by: 1), nil)
        XCTAssertEqual(RemoteQueue.step(queue, from: 0, by: -1), nil)
        XCTAssertEqual(RemoteQueue.place(of: 814, in: queue), 2)
        XCTAssertNil(RemoteQueue.place(of: 9, in: queue))
    }

    // MARK: State

    func testAnIdleStateIsJustItsStatusAndTheVersion() throws {
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(RemoteState(screen: "home"))) as? [String: Any])
        XCTAssertEqual(Set(sent.keys), ["v", "status", "screen"])
        XCTAssertEqual(sent["status"] as? String, "idle")
    }

    func testAStateIsReadEvenWithFieldsNobodyKnowsOrOfTheWrongShape() throws {
        let state: RemoteState = try decode(#"{"v":1,"status":"playing","itemId":812,"positionSec":1312.4,"durationSec":5400,"rate":1,"volume":"loud","audioTracks":[{"id":"1","label":"English · 5.1","lang":"en"}],"later":true}"#)
        XCTAssertEqual(state.itemId, 812)
        XCTAssertNil(state.volume)
        XCTAssertEqual(state.audioTracks?.first?.shownName, "English · 5.1")
    }

    func testTracksUseThePlaybackAnswersIndexAsTheirIds() throws {
        let tracks: [Track] = try decode(#"[{"index":1,"language":"eng","languageName":"English","codec":"ac3","channels":6},{"index":4,"language":"fra"}]"#)
        let listed = RemoteTrack.list(tracks)
        XCTAssertEqual(listed.map(\.id), ["1", "4"])
        XCTAssertEqual(listed[0].lang, "eng")
        XCTAssertEqual(RemoteTrack.subtitleId(-1), "off")
        XCTAssertEqual(RemoteTrack.subtitleId(3), "3")
        XCTAssertNil(RemoteTrack.subtitleId(nil))
        XCTAssertEqual(RemoteAction.trackIndex("off"), -1)
        XCTAssertEqual(RemoteAction.trackIndex("4"), 4)
    }

    func testAStateGoesAtOnceWhenSomethingChangesAndOtherwiseEveryFewSeconds() {
        var reporter = RemoteReporter()
        let playing = RemoteState(status: "playing", itemId: 1, positionSec: 100, durationSec: 600, rate: 1)
        XCTAssertTrue(reporter.due(playing, nowMs: 0), "the first always goes")
        reporter.sent(playing, nowMs: 0)

        var later = playing
        later.positionSec = 102
        XCTAssertFalse(reporter.due(later, nowMs: 2000), "time passing while it plays is not a change")
        later.positionSec = 105
        XCTAssertTrue(reporter.due(later, nowMs: 5000), "every five seconds while playing")
        reporter.sent(later, nowMs: 5000)

        var paused = later
        paused.status = "paused"
        paused.positionSec = 105.4
        XCTAssertFalse(reporter.due(paused, nowMs: 5400), "never closer together than the server allows")
        XCTAssertTrue(reporter.due(paused, nowMs: 6000), "a pause goes as soon as it may")
        reporter.sent(paused, nowMs: 6000)

        XCTAssertFalse(reporter.due(paused, nowMs: 20_000), "paused, nothing changes")
        XCTAssertTrue(reporter.due(paused, nowMs: 31_000), "but the heartbeat goes within 30 seconds")
        reporter.sent(paused, nowMs: 31_000)

        var sought = paused
        sought.positionSec = 300
        XCTAssertTrue(reporter.due(sought, nowMs: 32_500), "a seek is a change")
    }

    func testAnIdleDeviceStillSendsItsHeartbeat() {
        var reporter = RemoteReporter()
        let idle = RemoteState(screen: "home")
        reporter.sent(idle, nowMs: 0)
        XCTAssertFalse(reporter.due(idle, nowMs: 24_000))
        XCTAssertTrue(reporter.due(idle, nowMs: 25_000))
        XCTAssertLessThan(reporter.heartbeatMs, 30_000)
    }

    func testAfterA429TheLatestStateGoesAMomentLater() {
        var reporter = RemoteReporter()
        var state = RemoteState(status: "playing", itemId: 1, positionSec: 0, rate: 1)
        reporter.sent(state, nowMs: 0)
        state.status = "paused"
        XCTAssertTrue(reporter.due(state, nowMs: 1200))
        reporter.refused(nowMs: 1200, retryAfterSec: 1)
        XCTAssertFalse(reporter.due(state, nowMs: 1500))
        XCTAssertTrue(reporter.due(state, nowMs: 2300), "nothing was lost: the same state is still owed")
    }

    func testTheHeartbeatFollowsTheServersNumber() throws {
        let limits: RemoteLimits = try decode(#"{"heartbeatSec":12,"stateEveryMs":900,"idleSec":0}"#)
        let reporter = RemoteReporter(limits: limits)
        XCTAssertEqual(reporter.heartbeatMs, 7000)
        XCTAssertEqual(reporter.gapMs, 1800)
        XCTAssertEqual(limits.idleSec, 75, "a number that makes no sense keeps the usual one")
    }

    // MARK: The life of a device

    func testEachGoodbyeHasItsAnswer() {
        var backoff = Backoff()
        XCTAssertEqual(DeviceLife.after(bye: "replaced", backoff: &backoff), .stop)
        XCTAssertEqual(DeviceLife.after(bye: "removed", backoff: &backoff), .stop)
        XCTAssertEqual(DeviceLife.after(bye: "signed-out", backoff: &backoff), .stop)
        XCTAssertEqual(DeviceLife.after(bye: "idle", backoff: &backoff), .again(afterSec: 0), "the server thought it had gone: say so again at once")
        XCTAssertEqual(DeviceLife.after(bye: "server-stopping", backoff: &backoff), .again(afterSec: 3))
    }

    func testAChannelThatDropsIsOpenedAgainWithLongerAndLongerWaits() {
        var backoff = Backoff()
        XCTAssertEqual(DeviceLife.after(bye: nil, backoff: &backoff), .again(afterSec: 1))
        XCTAssertEqual(DeviceLife.after(bye: nil, backoff: &backoff), .again(afterSec: 2))
        XCTAssertEqual(DeviceLife.after(bye: "something-new", backoff: &backoff), .again(afterSec: 4), "a reason nobody knows is a drop")
        for _ in 0..<10 { _ = DeviceLife.after(bye: nil, backoff: &backoff) }
        XCTAssertEqual(DeviceLife.after(bye: nil, backoff: &backoff), .again(afterSec: 30))
    }

    func testARefusalToAnnounceStopsOrWaitsByWhatItWas() {
        var backoff = Backoff()
        XCTAssertEqual(DeviceLife.after(refusal: APIError(status: 403, message: "", code: "disabled"), backoff: &backoff), .stop)
        XCTAssertEqual(DeviceLife.after(refusal: APIError(status: 401, message: ""), backoff: &backoff), .stop)
        XCTAssertEqual(DeviceLife.after(refusal: APIError(status: 400, message: "", code: "version"), backoff: &backoff), .stop)
        XCTAssertEqual(DeviceLife.after(refusal: APIError(status: 429, message: "", code: "too-many", retryAfter: 7), backoff: &backoff), .again(afterSec: 7))
        XCTAssertEqual(DeviceLife.after(refusal: APIError(status: 503, message: ""), backoff: &backoff), .again(afterSec: 1))
    }

    func testTheChannelIsHeldInFrontAndBehindOnlyWhilePlaying() {
        XCTAssertTrue(DeviceLife.holdsChannel(inFront: true, playingBehind: false))
        XCTAssertTrue(DeviceLife.holdsChannel(inFront: false, playingBehind: true), "music carries on behind other apps, and so does the channel")
        XCTAssertFalse(DeviceLife.holdsChannel(inFront: false, playingBehind: false), "iOS stops the app: a device that can't answer isn't shown")
    }

    // MARK: A controller

    func testWhereAPlayingDeviceIsNowIsWorkedOutFromItsLastReport() {
        let state = RemoteState(status: "playing", positionSec: 1312.4, durationSec: 5400, rate: 1)
        XCTAssertEqual(RemoteLook.position(state, stateAt: 1_794_000_008_200, serverNowMs: 1_794_000_010_000), 1314.2, accuracy: 0.001)
        var fast = state
        fast.rate = 1.5
        XCTAssertEqual(RemoteLook.position(fast, stateAt: 1000, serverNowMs: 3000), 1315.4, accuracy: 0.001)
        var paused = state
        paused.status = "paused"
        XCTAssertEqual(RemoteLook.position(paused, stateAt: 1000, serverNowMs: 99_000), 1312.4)
        XCTAssertEqual(RemoteLook.position(state, stateAt: 1000, serverNowMs: 99_000_000), 5400, "never past the end")
        XCTAssertEqual(RemoteLook.position(state, stateAt: 5000, serverNowMs: 1000), 1312.4, "a clock that's behind doesn't run it backwards")
        XCTAssertEqual(RemoteLook.position(RemoteState(status: "playing", positionSec: .nan), stateAt: 0, serverNowMs: 0), 0)
    }

    func testTheServersClockIsThisOneCorrectedByWhatAnAnswerSaid() {
        var clock = RemoteClock()
        clock.learn(serverTimeMs: 1_794_000_010_000, localMs: 5_000)
        XCTAssertEqual(clock.serverNow(localMs: 6_500), 1_794_000_011_500)
        clock.learn(serverTimeMs: 0, localMs: 9_000)
        XCTAssertEqual(clock.serverNow(localMs: 6_500), 1_794_000_011_500, "an answer with no time changes nothing")
    }

    func testTheListLeavesOutThisAppAndPutsConnectedDevicesFirst() throws {
        let list: RemoteDeviceList = try decode("""
        {"serverTimeMs":1794000010000,"devices":[
          {"id":"c","name":"Zed's iPad","kind":"tablet","online":false,"mine":true,"thisSession":false,"state":{"status":"idle"}},
          {"id":"a","name":"This iPhone","kind":"phone","online":true,"mine":true,"thisSession":true,"state":{"status":"idle"}},
          {"id":"b","name":"living room TV","kind":"tv","userId":2,"userName":"Sam","v":1,
           "capabilities":{"mediaKinds":["video","audio"],"features":["seek","volume","queue"]},"online":true,"mine":true,"thisSession":false,
           "state":{"v":1,"status":"playing","itemId":812,"positionSec":1312.4,"durationSec":5400,"rate":1,"volume":0.6,"muted":false,"audio":"1","subtitle":"off"},
           "stateAt":1794000008200,"title":"Puddle Day","itemKind":"video"},
          {"id":"d","name":"Kitchen","kind":"web","online":true,"mine":false,"userName":"Ada","hidden":true,"state":{"status":"playing","volume":0.3}}]}
        """)
        let shown = RemoteLook.listed(list.devices)
        XCTAssertEqual(shown.map(\.id), ["d", "b", "c"])
        XCTAssertEqual(RemoteLook.line(shown[1], serverNowMs: list.serverTimeMs), "Puddle Day · 21:54 of 1:30:00")
        XCTAssertEqual(RemoteLook.line(shown[0], serverNowMs: list.serverTimeMs), "Playing something", "what it plays is hidden from this account")
        XCTAssertEqual(RemoteLook.line(shown[2], serverNowMs: list.serverTimeMs), "Not connected")
        XCTAssertTrue(RemoteLook.canPlay(kind: "video", on: shown[1]))
        XCTAssertFalse(RemoteLook.canPlay(kind: "book", on: shown[1]))
        XCTAssertFalse(RemoteLook.canPlay(kind: "video", on: shown[2]), "nothing starts on a device that isn't connected")
        XCTAssertFalse(shown[1].capabilities.has("navigate"), "only what it lists is offered")
    }

    func testADeviceEventTakesThePlaceOfTheOneWithItsId() {
        let old = [RemoteDevice(id: "a", name: "TV"), RemoteDevice(id: "b", name: "Tablet")]
        let fresh = RemoteDevice(id: "a", name: "TV", state: RemoteState(status: "paused"))
        let merged = RemoteLook.merged(fresh, into: old)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first { $0.id == "a" }?.state.status, "paused")
        XCTAssertEqual(RemoteLook.merged(RemoteDevice(id: "c", name: "New"), into: old).count, 3)
    }

    func testARefusalIsSaidInTheServersWordsOrByItsCode() {
        XCTAssertEqual(RemoteLook.words(APIError(status: 409, message: "Nothing is playing.", code: "refused")), "Nothing is playing.",
                       "for `refused` the sentence is the device's own reason")
        XCTAssertEqual(RemoteLook.words(APIError(status: 409, message: "", code: "offline")), "That device isn't connected.")
        XCTAssertEqual(RemoteLook.words(APIError(status: 504, message: "The server answered with an error (504).", code: "timeout")), "That device didn't answer.")
        for code in ["bad-command", "version", "disabled", "no-session", "not-allowed-there", "no-device", "no-item", "unsupported", "refused",
                     "nothing-playing", "rate", "too-many", "busy", "timeout"] {
            XCTAssertFalse(RemoteLook.words(APIError(status: 400, message: "", code: code)).isEmpty, code)
        }
        XCTAssertEqual(RemoteLook.words(APIError(status: 413, message: "")), "That was too long to send.")
        XCTAssertEqual(RemoteLook.words(URLError(.timedOut)), "The server couldn't be reached.")
    }

    func testTheServersOwnAccountOfItselfIsRead() throws {
        let info: RemoteInfo = try decode("""
        { "enabled": true, "v": 1, "minV": 1, "controlOthers": false,
          "kinds": ["web", "tv", "phone", "tablet", "desktop", "other"],
          "features": ["seek", "volume", "queue", "audio", "subtitles", "navigate", "rate"],
          "mediaKinds": ["video", "audio"], "navigateKeys": ["up", "down"],
          "limits": { "devicesPerAccount": 16, "stateEveryMs": 500, "heartbeatSec": 30, "idleSec": 75, "reconnectSec": 30, "ackTimeoutMs": 8000, "queueItems": 200 } }
        """)
        XCTAssertTrue(info.enabled)
        XCTAssertEqual(info.limits.ackTimeoutMs, 8000)
        let off: RemoteInfo = try decode(#"{"enabled":false}"#)
        XCTAssertFalse(off.enabled)
        XCTAssertEqual(off.limits, RemoteLimits())
    }

    // MARK: The routes, against a real connection

    func testACommandIsSentAsTheGuideWritesItAndARefusalKeepsItsCode() async throws {
        let server = try StandInServer { request in
            if request.path.hasSuffix("/commands") {
                return StandInServer.answer(status: "409 Conflict", body: #"{"error":"The device isn't connected.","code":"offline"}"#)
            }
            return StandInServer.answer(body: #"{"serverTimeMs":5,"devices":[]}"#)
        }
        defer { server.stop() }
        let client = WittyClient(base: server.address, token: "t")
        let list = try await client.remoteDevices()
        XCTAssertEqual(list.serverTimeMs, 5)
        do {
            _ = try await client.remoteSend(RemoteCommand("seek", bySec: -10), to: "5b/0c")
            XCTFail("the refusal should be thrown")
        } catch let refusal as APIError {
            XCTAssertEqual(refusal.code, "offline")
            XCTAssertEqual(RemoteLook.words(refusal), "The device isn't connected.")
        }
        XCTAssertEqual(server.requests.last?.path, "/api/v1/remote-control/devices/5b%2F0c/commands")
        XCTAssertTrue(server.requests.allSatisfy(\.hasToken))
    }
}
