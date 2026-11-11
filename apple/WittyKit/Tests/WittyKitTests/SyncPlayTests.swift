// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

/// Watch parties: the server's docs/SYNCPLAY.md. The clock and drift cases are the server's own
/// (internal/syncplay/clock_test.go) and the web player's (web/src/player/sync.test.mjs): all three must agree.
final class SyncPlayTests: XCTestCase {
    private func decode<T: Decodable>(_ json: String, as type: T.Type = T.self) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: The server's clock

    func testClockOffset() {
        let cases: [(name: String, t: [Double], offset: Double, rtt: Double)] = [
            // The server's clock is 5000 ms ahead; 40 ms each way; it took 10 ms to answer.
            ("even path", [1000, 6040, 6050, 1090], 5000, 80),
            // This clock is ahead of the server's.
            ("client ahead", [9000, 2030, 2030, 9060], -7000, 60),
            // Same clocks, nothing on the wire.
            ("no delay", [500, 500, 500, 500], 0, 0),
            // 100 ms out and 20 back: the sum can't know, and is out by half the difference.
            ("uneven path", [0, 100, 100, 120], 40, 120),
        ]
        for c in cases {
            let found = SyncClock.offset(t0: c.t[0], t1: c.t[1], t2: c.t[2], t3: c.t[3])
            XCTAssertEqual(found.offset, c.offset, c.name)
            XCTAssertEqual(found.rtt, c.rtt, c.name)
        }
    }

    func testBestOffsetTrustsTheQuickestPing() {
        // True offset 5000. The slow ping was held up on the way out and misleads by 200.
        let samples = [
            SyncSample(t0: 0, t1: 5450, t2: 5450, t3: 500),     // rtt 500, says 5200
            SyncSample(t0: 1000, t1: 6020, t2: 6021, t3: 1041), // rtt 40, says 5000
            SyncSample(t0: 2000, t1: 7100, t2: 7100, t3: 2150), // rtt 150, says 5025
            SyncSample(t0: 3000, t1: 8000, t2: 8000, t3: 2990), // came back before it left: ignored
            SyncSample(t0: .nan, t1: 1, t2: 1, t3: 1),
        ]
        let best = SyncClock.best(samples)
        XCTAssertEqual(best?.offset, 5000)
        XCTAssertEqual(best?.rtt, 40)
        XCTAssertNil(SyncClock.best([]), "an offset from no pings")
        XCTAssertNil(SyncClock.best(Array(samples[3...])), "an offset from pings that make no sense")
    }

    func testTheLastEightPingsAreKeptAndTheBestOfThemUsed() {
        var time = SyncTime()
        XCTAssertFalse(time.known)
        time.guess(serverTimeMs: 10_000, localMs: 4_000)
        XCTAssertEqual(time.serverNow(localMs: 4_500), 10_500, "until a ping comes back, the room's own time is the best there is")

        time.add(SyncSample(t0: 0, t1: 5450, t2: 5450, t3: 500))
        XCTAssertEqual(time.offsetMs, 5200)
        XCTAssertEqual(time.rttMs, 500)
        time.add(SyncSample(t0: 1000, t1: 6020, t2: 6021, t3: 1041))
        XCTAssertEqual(time.offsetMs, 5000)
        XCTAssertEqual(time.rttMs, 40, "the best round trip is what's sent back as rttMs")
        time.add(SyncSample(t0: 3000, t1: 8000, t2: 8000, t3: 2990))
        XCTAssertEqual(time.offsetMs, 5000, "a clock that jumped changes nothing")
        time.guess(serverTimeMs: 99, localMs: 0)
        XCTAssertEqual(time.offsetMs, 5000, "a guess never replaces a measurement")

        // Eight slower pings later the quick one has gone, and the best of what's left is used.
        for n in 0..<8 {
            let sent = 10_000 + Double(n) * 5000
            time.add(SyncSample(t0: sent, t1: sent + 5100, t2: sent + 5100, t3: sent + 180 + Double(n)))
        }
        XCTAssertEqual(time.samples.count, 8)
        XCTAssertEqual(time.rttMs, 180)
        XCTAssertEqual(time.offsetMs, 5010)
        XCTAssertEqual(time.serverNow(localMs: 1_000), 6_010)
    }

    func testAFewQuickPingsOnJoiningThenTheHeartbeat() {
        XCTAssertEqual((0..<7).map { SyncTime.wait(beforePing: $0, everySec: 5) }, [0, 0.3, 0.3, 0.3, 0.3, 5, 5])
        XCTAssertEqual(SyncTime.wait(beforePing: 9, everySec: 0), 1, "never a busy loop, whatever the server says")
    }

    // MARK: The room's position

    func testPositionAt() {
        var s = SyncState(positionSec: 60, atMs: 10_000, rate: 1)
        for (ms, want) in [9_000: 60, 10_000: 60, 10_500: 60.5, 70_000: 120] as [Double: Double] {
            XCTAssertEqual(s.position(atServerMs: ms), want, "at \(ms)")
        }
        s.rate = 1.5
        XCTAssertEqual(s.position(atServerMs: 12_000), 63)
        s.paused = true
        XCTAssertEqual(s.position(atServerMs: 99_000), 60)
        s.paused = false
        s.waiting = true
        XCTAssertEqual(s.position(atServerMs: 99_000), 60)
    }

    func testAStartIsSetInTheFutureAndHeldUntilThen() {
        let s = SyncState(positionSec: 754.5, atMs: 4_500, rate: 1)
        XCTAssertFalse(s.isPlaying(atServerMs: 4_200))
        XCTAssertEqual(s.startsIn(atServerMs: 4_200), 300)
        XCTAssertEqual(s.position(atServerMs: 4_200), 754.5)
        XCTAssertTrue(s.isPlaying(atServerMs: 4_500))
        XCTAssertNil(s.startsIn(atServerMs: 4_500))
        XCTAssertNil(SyncState(atMs: 9_000, paused: true).startsIn(atServerMs: 0), "a paused room is not about to start")
    }

    // MARK: The drift rule

    func testCorrect() {
        let cases: [(behind: Double, nudging: Bool, want: SyncStep)] = [
            (0, false, SyncStep(rate: 1)),
            (0.1, false, SyncStep(rate: 1)),
            (-0.1, false, SyncStep(rate: 1)),
            (0.2, false, SyncStep(rate: 1.03)),
            (-0.2, false, SyncStep(rate: 0.97)),
            // Once nudging it carries on past "close enough to leave alone", to "settled".
            (0.1, true, SyncStep(rate: 1.03)),
            (-0.05, true, SyncStep(rate: 0.97)),
            (0.03, true, SyncStep(rate: 1)),
            (2.9, false, SyncStep(rate: 1.03)),
            (3, false, SyncStep(rate: 1, seekBy: 3)),
            (-45, true, SyncStep(rate: 1, seekBy: -45)),
        ]
        for c in cases {
            XCTAssertEqual(SyncRules.correct(behind: c.behind, nudging: c.nudging), c.want, "behind \(c.behind) nudging \(c.nudging)")
        }
    }

    func testTheThresholdsAreTheServers() throws {
        let info: SyncInfo = try decode("""
        { "enabled": true, "canCreate": true,
          "drift": { "stillSec": 0.2, "settledSec": 0.05, "seekSec": 5, "rate": 0.05 },
          "limits": { "members": 16, "queue": 200, "roomsPerAccount": 2, "invites": 32, "codeLength": 6, "pingEverySec": 5,
                      "awaySec": 20, "seatGraceSec": 120, "waitTimeoutSec": 15, "emptyCloseSec": 300, "minLeadMs": 300, "maxLeadMs": 2500 },
          "rooms": [{ "id": "9f3c", "name": "Friday film", "hostName": "Sam", "members": 3, "invited": true },
                    { "id": "77aa", "name": "Mine", "hostName": "Ada", "members": 1, "memberId": "b2" }],
          "serverTimeMs": 1794000000000 }
        """)
        XCTAssertEqual(SyncRules.correct(behind: 0.15, nudging: false, drift: info.drift), SyncStep(rate: 1))
        XCTAssertEqual(SyncRules.correct(behind: 0.3, nudging: false, drift: info.drift), SyncStep(rate: 1.05))
        XCTAssertEqual(SyncRules.correct(behind: 4, nudging: false, drift: info.drift), SyncStep(rate: 1.05))
        XCTAssertEqual(SyncRules.correct(behind: -5, nudging: false, drift: info.drift), SyncStep(rate: 1, seekBy: -5))
        XCTAssertEqual(info.limits.pingEverySec, 5)
        XCTAssertEqual(info.rooms[0].line, "Started by Sam · 3 watching")
        XCTAssertFalse(info.rooms[0].seated)
        XCTAssertTrue(info.rooms[1].seated, "a seat from this sign-in: it can go back in")
        // A server that says nothing, or nonsense, leaves the guide's numbers.
        let bare: SyncInfo = try decode(#"{"enabled":true,"drift":{"stillSec":0,"rate":"fast"}}"#)
        XCTAssertEqual(bare.drift, SyncDrift())
        XCTAssertFalse(bare.canCreate)
    }

    // MARK: Following a room, tick by tick

    private let me = SyncMember(id: "b2", name: "Ada", you: true, state: "ready")
    private let loading = SyncMember(id: "b2", name: "Ada", you: true, state: "loading")

    func testInStepNothingIsDoneButPlayingAtTheRoomsSpeed() {
        var follower = SyncFollower()
        let state = SyncState(rev: 5, positionSec: 100, atMs: 0, rate: 1)
        let orders = follower.tick(state: state, me: me, serverNowMs: 10_000, localMs: 10_000, player: SyncPlayerFacts(positionSec: 110.05, paused: false))
        XCTAssertEqual(orders.rate, 1)
        XCTAssertNil(orders.seekTo)
        XCTAssertFalse(orders.pause)
        XCTAssertFalse(orders.play)
        XCTAssertNil(orders.report)
        XCTAssertEqual(orders.behind ?? 9, -0.05, accuracy: 0.0001)
        XCTAssertFalse(follower.nudging)
    }

    func testASmallGapIsClosedByPlayingSlightlyFasterUntilSettled() {
        var follower = SyncFollower()
        let state = SyncState(rev: 5, positionSec: 0, atMs: 0, rate: 1)
        // Half a second behind: 3% faster.
        var orders = follower.tick(state: state, me: me, serverNowMs: 20_000, localMs: 0, player: SyncPlayerFacts(positionSec: 19.5, paused: false))
        XCTAssertEqual(orders.rate, 1.03)
        XCTAssertTrue(follower.nudging)
        // Within "leave it alone", but not yet settled: carry on.
        orders = follower.tick(state: state, me: me, serverNowMs: 30_000, localMs: 10_000, player: SyncPlayerFacts(positionSec: 29.9, paused: false))
        XCTAssertEqual(orders.rate, 1.03)
        // Settled: back to the room's speed.
        orders = follower.tick(state: state, me: me, serverNowMs: 33_000, localMs: 13_000, player: SyncPlayerFacts(positionSec: 32.98, paused: false))
        XCTAssertEqual(orders.rate, 1)
        XCTAssertFalse(follower.nudging)
        // Ahead: slower.
        orders = follower.tick(state: state, me: me, serverNowMs: 40_000, localMs: 20_000, player: SyncPlayerFacts(positionSec: 40.4, paused: false))
        XCTAssertEqual(orders.rate, 0.97)
    }

    func testTheNudgeIsAMultipleOfTheRoomsOwnSpeed() {
        var follower = SyncFollower()
        let state = SyncState(positionSec: 0, atMs: 0, rate: 1.5)
        let orders = follower.tick(state: state, me: me, serverNowMs: 10_000, localMs: 0, player: SyncPlayerFacts(positionSec: 14.5, paused: false))
        XCTAssertEqual(orders.rate ?? 0, 1.5 * 1.03, accuracy: 0.0001)
    }

    func testThreeSecondsOffIsASeekAndAnotherWaitsForItToLand() {
        var follower = SyncFollower()
        let state = SyncState(rev: 9, positionSec: 0, atMs: 0, rate: 1)
        var orders = follower.tick(state: state, me: me, serverNowMs: 60_000, localMs: 1_000, player: SyncPlayerFacts(positionSec: 12, paused: false))
        XCTAssertEqual(orders.seekTo, 60)
        XCTAssertEqual(orders.rate, 1)
        // Half a second on it hasn't landed: no second seek on top of the first.
        orders = follower.tick(state: state, me: me, serverNowMs: 60_500, localMs: 1_500, player: SyncPlayerFacts(positionSec: 12.5, paused: false, canPlay: false, seeking: true))
        XCTAssertNil(orders.seekTo)
        // It landed, two seconds after it was asked for, and two seconds behind because of that.
        orders = follower.tick(state: state, me: me, serverNowMs: 62_000, localMs: 3_000, player: SyncPlayerFacts(positionSec: 60.2, paused: false))
        XCTAssertNil(orders.seekTo)
        XCTAssertEqual(orders.rate, 1.03)
        XCTAssertEqual(follower.lagSec, 2, accuracy: 0.001)
        // The next jump while playing aims ahead by as long as the last one took.
        orders = follower.tick(state: state, me: me, serverNowMs: 200_000, localMs: 141_000, player: SyncPlayerFacts(positionSec: 100, paused: false))
        XCTAssertEqual(orders.seekTo, 202)
    }

    func testASeekThatNeverLandsIsTriedAgainAfterFiveSeconds() {
        var follower = SyncFollower()
        let state = SyncState(positionSec: 0, atMs: 0, rate: 1)
        let far = SyncPlayerFacts(positionSec: 0, paused: false, canPlay: false)
        XCTAssertNotNil(follower.tick(state: state, me: me, serverNowMs: 50_000, localMs: 0, player: far).seekTo)
        XCTAssertNil(follower.tick(state: state, me: me, serverNowMs: 54_000, localMs: 4_000, player: far).seekTo)
        XCTAssertNotNil(follower.tick(state: state, me: me, serverNowMs: 55_500, localMs: 5_500, player: far).seekTo)
    }

    func testPausedTheRoomIsHeldAtItsPlace() {
        var follower = SyncFollower()
        let state = SyncState(rev: 3, positionSec: 754.5, atMs: 0, paused: true, rate: 1)
        // Playing on a moment past the pause: pause, and go back to the exact frame of a file.
        var orders = follower.tick(state: state, me: me, serverNowMs: 5_000, localMs: 0, player: SyncPlayerFacts(positionSec: 754.8, paused: false))
        XCTAssertTrue(orders.pause)
        XCTAssertEqual(orders.seekTo, 754.5)
        XCTAssertNil(orders.behind)
        // The same place isn't asked for twice: if it can't get there, asking again won't help.
        orders = follower.tick(state: state, me: me, serverNowMs: 11_000, localMs: 6_000, player: SyncPlayerFacts(positionSec: 754.8, paused: true))
        XCTAssertNil(orders.seekTo)
        XCTAssertFalse(orders.pause)
    }

    func testAConvertedStreamIsOnlySentBackWhenMoreThanHalfASecondOff() {
        var follower = SyncFollower()
        let state = SyncState(positionSec: 100, atMs: 0, waiting: true, rate: 1)
        var orders = follower.tick(state: state, me: me, serverNowMs: 0, localMs: 0, player: SyncPlayerFacts(positionSec: 100.4, paused: true, cheapSeek: false))
        XCTAssertNil(orders.seekTo, "a seek there starts the conversion again: not for under half a second")
        orders = follower.tick(state: state, me: me, serverNowMs: 0, localMs: 500, player: SyncPlayerFacts(positionSec: 100.6, paused: true, cheapSeek: false))
        XCTAssertEqual(orders.seekTo, 100)
    }

    func testAStartSetForAMomentFromNowIsHeldPausedAndKeptToTheMillisecond() {
        var follower = SyncFollower()
        let state = SyncState(rev: 4, positionSec: 30, atMs: 10_300, rate: 1)
        var orders = follower.tick(state: state, me: me, serverNowMs: 10_000, localMs: 0, player: SyncPlayerFacts(positionSec: 30, paused: true))
        XCTAssertFalse(orders.play, "until atMs, hold at positionSec, paused")
        XCTAssertNil(orders.seekTo)
        XCTAssertEqual(orders.againInMs, 300, "look again exactly when it starts, not at the next half second")
        orders = follower.tick(state: state, me: me, serverNowMs: 10_300, localMs: 300, player: SyncPlayerFacts(positionSec: 30, paused: true))
        XCTAssertTrue(orders.play)
        XCTAssertEqual(orders.rate, 1)
        XCTAssertNil(orders.againInMs)
    }

    func testReadyIsReportedOnceLoadedAtTheRoomsPlaceWithTheRevApplied() {
        var follower = SyncFollower()
        let state = SyncState(rev: 12, positionSec: 400, atMs: 0, waiting: true, rate: 1)
        // Still loading after the seek: nothing to say yet.
        var orders = follower.tick(state: state, me: loading, serverNowMs: 0, localMs: 0, player: SyncPlayerFacts(positionSec: 0, paused: true, canPlay: false))
        XCTAssertEqual(orders.seekTo, 400)
        XCTAssertNil(orders.report)
        orders = follower.tick(state: state, me: loading, serverNowMs: 500, localMs: 500, player: SyncPlayerFacts(positionSec: 400, paused: true, canPlay: false, seeking: true))
        XCTAssertNil(orders.report)
        // Loaded and there.
        orders = follower.tick(state: state, me: loading, serverNowMs: 1_800, localMs: 1_800, player: SyncPlayerFacts(positionSec: 400, paused: true))
        XCTAssertEqual(orders.report, "ready")
        XCTAssertEqual(orders.rev, 12)
        // The room hasn't heard yet half a second later: not said twice within a second.
        orders = follower.tick(state: state, me: loading, serverNowMs: 2_300, localMs: 2_300, player: SyncPlayerFacts(positionSec: 400, paused: true))
        XCTAssertNil(orders.report)
        orders = follower.tick(state: state, me: loading, serverNowMs: 2_900, localMs: 2_900, player: SyncPlayerFacts(positionSec: 400, paused: true))
        XCTAssertEqual(orders.report, "ready", "and said again if the room still has it wrong")
        // Once the room agrees there's nothing more to say.
        orders = follower.tick(state: state, me: me, serverNowMs: 4_000, localMs: 4_000, player: SyncPlayerFacts(positionSec: 400, paused: true))
        XCTAssertNil(orders.report)
    }

    func testAStallWhileTheRoomPlaysIsReportedAfterAMoment() {
        var follower = SyncFollower()
        let state = SyncState(rev: 7, positionSec: 0, atMs: 0, rate: 1)
        let stalled = SyncPlayerFacts(positionSec: 50, paused: false, canPlay: false)
        var orders = follower.tick(state: state, me: me, serverNowMs: 50_000, localMs: 0, player: stalled)
        XCTAssertNil(orders.report, "a hiccup isn't a stall")
        orders = follower.tick(state: state, me: me, serverNowMs: 50_500, localMs: 500, player: stalled)
        XCTAssertNil(orders.report)
        orders = follower.tick(state: state, me: me, serverNowMs: 51_000, localMs: 1_000, player: stalled)
        XCTAssertEqual(orders.report, "buffering")
        XCTAssertEqual(orders.rev, 7)
        // While the room is paused a player that isn't ready isn't "buffering".
        var held = SyncFollower()
        let paused = SyncState(positionSec: 50, atMs: 0, paused: true, rate: 1)
        for ms in stride(from: 0.0, through: 3_000, by: 500) {
            XCTAssertNil(held.tick(state: paused, me: me, serverNowMs: ms, localMs: ms, player: SyncPlayerFacts(positionSec: 50, paused: true, canPlay: false)).report)
        }
    }

    func testAPlayerWithNothingOpenIsLeftAlone() {
        var follower = SyncFollower()
        let orders = follower.tick(state: SyncState(positionSec: 9, atMs: 0), me: loading, serverNowMs: 5_000, localMs: 0,
                                   player: SyncPlayerFacts(positionSec: 0, paused: true, loaded: false, canPlay: false))
        XCTAssertEqual(orders.seekTo, nil)
        XCTAssertEqual(orders.report, nil)
        XCTAssertFalse(orders.play)
    }

    func testAtTheEndOfTheItemNothingIsChased() {
        var follower = SyncFollower()
        let orders = follower.tick(state: SyncState(positionSec: 0, atMs: 0), me: me, serverNowMs: 700_000, localMs: 0,
                                   player: SyncPlayerFacts(positionSec: 600, paused: true, ended: true))
        XCTAssertFalse(orders.play)
        XCTAssertNil(orders.seekTo)
    }

    func testTwoPlayersRestWithinAQuarterOfASecond() {
        // A player that starts 1.2 s behind, followed for a minute of half-second ticks: it closes the gap at 3%
        // and then stays inside the "leave it alone" band.
        var follower = SyncFollower()
        let state = SyncState(positionSec: 0, atMs: 0, rate: 1)
        var position = 98.8
        var rate = 1.0
        var worstAtRest = 0.0
        for tick in 0..<120 {
            let now = 100_000 + Double(tick) * 500
            let orders = follower.tick(state: state, me: me, serverNowMs: now, localMs: now, player: SyncPlayerFacts(positionSec: position, paused: false))
            XCTAssertNil(orders.seekTo)
            rate = orders.rate ?? rate
            if tick > 90 { worstAtRest = max(worstAtRest, abs(orders.behind ?? 0)) }
            position += 0.5 * rate
        }
        XCTAssertLessThan(worstAtRest, 0.12)
        XCTAssertFalse(follower.nudging)
    }

    // MARK: The room

    private let roomJSON = """
    { "id": "9f3c1a7e5b2d4c8891aa", "code": "KXM4T7", "name": "Friday film", "policy": "host", "waitForAll": true,
      "hostId": "a1", "you": "b2", "canControl": false, "blocked": false,
      "members": [
        { "id": "a1", "userId": 2, "name": "Sam", "host": true, "state": "ready", "rttMs": 18 },
        { "id": "b2", "userId": 5, "name": "Ada", "host": false, "you": true, "state": "loading", "rttMs": 64 } ],
      "queue": [812, 813], "items": [{ "id": 812, "title": "Puddle Day", "kind": "video", "runtimeSec": 5400 }, { "id": 813, "title": "Puddle Day 2", "kind": "video", "runtimeSec": 5100 }],
      "state": { "rev": 3, "seq": 1, "itemId": 812, "index": 0, "positionSec": 0, "atMs": 1794000000000, "paused": true, "waiting": false, "rate": 1 },
      "serverTimeMs": 1794000001000, "leadMs": 300, "somethingNew": [1, 2] }
    """

    func testTheRoomIsReadAsTheGuideWritesIt() throws {
        let room: SyncRoom = try decode(roomJSON)
        XCTAssertEqual(room.code, "KXM4T7")
        XCTAssertFalse(room.isHost)
        XCTAssertFalse(room.canControl)
        XCTAssertEqual(room.me?.name, "Ada")
        XCTAssertEqual(room.playing?.title, "Puddle Day")
        XCTAssertTrue(room.hasNext)
        XCTAssertFalse(room.hasPrevious)
        XCTAssertEqual(room.line, "Watching Puddle Day · paused")
        XCTAssertEqual(room.state.seq, 1)
    }

    func testAMemberWhoMayNotSeeItIsToldNothingOfIt() throws {
        let room: SyncRoom = try decode("""
        {"id":"r","code":"ABCDEF","name":"Late film","you":"b2","hostId":"a1","blocked":true,"canControl":false,
         "members":[{"id":"b2","name":"Kid","you":true,"state":"blocked"}],"queue":[0],"items":[{}],
         "state":{"rev":8,"seq":2,"itemId":0,"index":0,"positionSec":12,"atMs":5,"paused":false,"waiting":false,"rate":1}}
        """)
        XCTAssertTrue(room.blocked)
        XCTAssertEqual(room.state.itemId, 0)
        XCTAssertNil(room.playing?.title)
        XCTAssertEqual(room.line, "This one isn't available on this account")
        XCTAssertEqual(SyncWords.member(room.members[0].state), "Can't watch this one")
    }

    func testTheHighestRevWins() throws {
        let current: SyncRoom = try decode(roomJSON)
        var older = current
        older.state.rev = 2
        older.name = "Stale news"
        var newer = current
        newer.state.rev = 4
        newer.state.paused = false
        XCTAssertEqual(current.taking(older).name, "Friday film", "an older room that arrives late is forgotten")
        XCTAssertEqual(current.taking(newer).state.paused, false)
        var same = current
        same.members = []
        XCTAssertEqual(current.taking(same).members.count, 0, "the same rev is taken: members change without one")
        let other = SyncRoom(id: "another", state: SyncState(rev: 1))
        XCTAssertEqual(current.taking(other).id, "another", "another room's news takes this one's place")
    }

    func testEachMemberStateHasTheGuidesWords() {
        XCTAssertEqual(["ready", "loading", "buffering", "lagging", "away", "blocked"].map(SyncWords.member),
                       ["Ready", "Loading", "Buffering", "Catching up", "Away", "Can't watch this one"])
        XCTAssertEqual(SyncWords.member("dozing"), "Dozing", "a state from a newer server is shown as it is")
    }

    func testCodesAreForgivingOfCaseSpacesAndDashes() {
        XCTAssertEqual(SyncCode.clean("kxm4t7"), "KXM4T7")
        XCTAssertEqual(SyncCode.clean(" kxm-4t7 "), "KXM4T7")
        XCTAssertEqual(SyncCode.clean("K X M 4 T 7 9 9"), "KXM4T7", "no longer than a code is")
        XCTAssertEqual(SyncCode.clean("kx!m"), "KXM")
        XCTAssertEqual(SyncCode.spaced("KXM4T7"), "KXM 4T7")
    }

    func testAPartyFromAnEpisodeQueuesTheRestOfItsSeason() throws {
        let episodes: [Item] = try decode("""
        [{"id":31,"kind":"video","title":"Three","season":1,"episode":3},{"id":11,"kind":"video","title":"One","season":1,"episode":1},
         {"id":21,"kind":"video","title":"Two","season":1,"episode":2},{"id":41,"kind":"video","title":"Next year","season":2,"episode":1}]
        """)
        XCTAssertEqual(SyncQueue.restOfSeason(from: episodes[2], among: episodes), [21, 31])
        XCTAssertEqual(SyncQueue.restOfSeason(from: episodes[1], among: episodes, limit: 2), [11, 21])
        XCTAssertEqual(SyncQueue.restOfSeason(from: episodes[3], among: []), [41], "with nothing known it is still that episode")
    }

    // MARK: Coming back, and the end

    func testEveryClosedReasonEndsItAndReplacedSaysNothing() {
        var backoff = Backoff()
        XCTAssertEqual(SyncLife.after(closed: "closed", backoff: &backoff), .over("The watch party has ended."))
        XCTAssertEqual(SyncLife.after(closed: "removed", backoff: &backoff), .over("You were removed from the watch party."))
        XCTAssertEqual(SyncLife.after(closed: "replaced", backoff: &backoff), .over(""))
        XCTAssertEqual(SyncLife.after(closed: "signed-out", backoff: &backoff), .over("The watch party ended for this device."))
        XCTAssertEqual(SyncLife.after(closed: "server-stopping", backoff: &backoff), .over("The server is restarting, which ends the watch party."))
    }

    func testADroppedStreamTakesItsSeatAgainWithinTheGrace() {
        var backoff = Backoff()
        XCTAssertEqual(SyncLife.after(closed: nil, backoff: &backoff), .rejoin(afterSec: 1))
        XCTAssertEqual(SyncLife.after(closed: nil, backoff: &backoff), .rejoin(afterSec: 2))
        for _ in 0..<6 { _ = SyncLife.after(closed: nil, backoff: &backoff) }
        XCTAssertEqual(SyncLife.after(closed: nil, backoff: &backoff), .rejoin(afterSec: 15), "well inside the two minutes a seat is kept")
        // The room has gone, or the seat has: that's the end. Too many requests is not.
        XCTAssertEqual(SyncLife.after(closed: nil, refusal: APIError(status: 404, message: "", code: "no-room"), backoff: &backoff), .over("The watch party has ended."))
        var again = Backoff()
        XCTAssertEqual(SyncLife.after(closed: nil, refusal: APIError(status: 429, message: "", code: "rate"), backoff: &again), .rejoin(afterSec: 1))
        XCTAssertEqual(SyncLife.after(closed: nil, refusal: APIError(status: 503, message: ""), backoff: &again), .rejoin(afterSec: 2))
    }

    func testRefusalsAreSaidInTheServersWordsOrByTheirCode() {
        XCTAssertEqual(SyncWords.refusal(APIError(status: 403, message: "This watch party is playing something this account can't watch.", code: "cant-watch")),
                       "This watch party is playing something this account can't watch.")
        XCTAssertEqual(SyncWords.refusal(APIError(status: 403, message: "", code: "host-only")), "Only the host controls this watch party.")
        for code in ["disabled", "not-allowed", "cant-watch", "not-host", "no-room", "not-member", "no-item", "end-of-queue", "full", "rate", "too-many"] {
            XCTAssertFalse(SyncWords.refusal(APIError(status: 400, message: "", code: code)).isEmpty, code)
        }
    }

    // MARK: The routes, against a real connection

    func testStartingOneSendsATitleOrAQueue() throws {
        func sent(_ start: SyncStart) throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(start)) as? [String: Any])
        }
        let one = try sent(SyncStart(items: [812], name: " Friday film ", everyone: false, waitForAll: true, device: "d1"))
        XCTAssertEqual(one["itemId"] as? Int, 812)
        XCTAssertNil(one["items"])
        XCTAssertEqual(one["name"] as? String, "Friday film")
        XCTAssertEqual(one["policy"] as? String, "host")
        XCTAssertEqual(one["waitForAll"] as? Bool, true)
        XCTAssertEqual(one["device"] as? String, "d1")
        XCTAssertNil(one["positionSec"])
        let season = try sent(SyncStart(items: [21, 31], index: 0, positionSec: 42, everyone: true, waitForAll: false, device: "d1"))
        XCTAssertEqual(season["items"] as? [Int], [21, 31])
        XCTAssertEqual(season["index"] as? Int, 0)
        XCTAssertNil(season["itemId"])
        XCTAssertEqual(season["policy"] as? String, "everyone")
        XCTAssertEqual(season["positionSec"] as? Double, 42)
        XCTAssertNil(season["name"])
    }

    func testACommandBeatenToItTakesTheRoomAsItIsNow() async throws {
        let room: SyncRoom = try decode(roomJSON)
        var moved = roomJSON.replacingOccurrences(of: #""rev": 3, "seq": 1, "itemId": 812, "index": 0"#, with: #""rev": 6, "seq": 2, "itemId": 813, "index": 1"#)
        moved = moved.replacingOccurrences(of: "\n", with: " ")
        let stale = #"{"error":"Someone else got there first.","code":"stale","room":"# + moved + "}"
        let server = try StandInServer { request in
            if request.path.contains("/command") { return StandInServer.answer(status: "409 Conflict", body: stale) }
            if request.path.contains("/ping") { return StandInServer.answer(body: #"{"t0":1,"t1":1794000000140.2,"t2":1794000000140.9}"#) }
            return StandInServer.answer(status: "404 Not Found", body: #"{"error":"No such watch party.","code":"no-room"}"#)
        }
        defer { server.stop() }
        let client = WittyClient(base: server.address, token: "t")
        let now = try await client.syncCommand(room, "next", ifSeq: room.state.seq)
        XCTAssertEqual(now.state.itemId, 813, "everyone said next at the end; one of them counted, and this one is told how things stand")
        XCTAssertEqual(server.requests.last?.path, "/api/v1/syncplay/rooms/9f3c1a7e5b2d4c8891aa/command")
        let ping = try await client.syncPing(room, t0: 1, rttMs: 41)
        XCTAssertEqual(ping.t1, 1_794_000_000_140.2)
        XCTAssertEqual(ping.t2, 1_794_000_000_140.9)
        do {
            try await client.syncLeave(room)
            XCTFail("a room that has gone answers 404")
        } catch let refusal as APIError {
            XCTAssertEqual(refusal.code, "no-room")
            XCTAssertEqual(SyncWords.refusal(refusal), "No such watch party.")
        }
        XCTAssertEqual(client.syncEventsPath(room), "/syncplay/rooms/9f3c1a7e5b2d4c8891aa/events?member=b2")
    }
}
