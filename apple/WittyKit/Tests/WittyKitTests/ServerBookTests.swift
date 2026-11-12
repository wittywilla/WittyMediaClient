// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

final class ServerBookTests: XCTestCase {
    private let day: Int64 = 86_400_000
    private let now: Int64 = 1_800_000_000_000

    private func server(_ url: String, _ name: String = "Home", id: String = "", key: String = "", logo: String = "", seen: Int64 = 0) -> SavedServer {
        var made = SavedServer(url: url, name: name, serverId: id, publicKey: key, fingerprint: key.isEmpty ? "" : "FP-\(key)", brandLogo: logo)
        made.lastSeen = seen
        return made
    }

    // MARK: What is stored

    func testAListFromBeforeTimesWereKeptStillReads() throws {
        let old = Data(#"[{"url":"http://10.0.0.1:9797","name":"Home","serverId":"a","publicKey":"K"}]"#.utf8)
        let read = try JSONDecoder().decode([SavedServer].self, from: old)
        XCTAssertEqual(read.first?.lastSeen, 0, "not known")
        var stamped = read[0]
        stamped.lastSeen = now
        let again = try JSONDecoder().decode(SavedServer.self, from: JSONEncoder().encode(stamped))
        XCTAssertEqual(again, stamped)
        XCTAssertEqual(again.with(name: "Den", brandLogo: "v2").lastSeen, now, "a new name keeps the time")
        XCTAssertEqual(again.moved(to: "http://10.0.0.2:9797").lastSeen, now, "and so does a new address")
    }

    // MARK: Remembering

    /// What went wrong before: a server that moved, or was typed by another of its addresses, was listed again.
    func testTheOldRuleListedAServerWithNoIDOncePerAddress() {
        let before = server("http://nas.local:9797", key: "K")
        let after = server("http://10.0.0.5:9797", key: "K")
        XCTAssertEqual(SavedServer.remember(after, in: [before]).count, 2, "the old rule keeps both")
        XCTAssertEqual(ServerBook.remember(after, in: [before], now: now).list.count, 1, "the same key is the same server")
    }

    func testAServerThatMovedIsOneEntryAndItsSettingsFollow() {
        let old = server("http://10.0.0.1:9797", "Home", id: "a", key: "K", logo: "v1", seen: now - 5 * day)
        let other = server("http://10.0.0.9:9797", "Other", id: "b", key: "L", seen: now - day)
        let done = ServerBook.remember(server("http://10.0.0.2:9797", "Home", id: "a", key: "K"), in: [other, old], now: now)
        XCTAssertEqual(done.list.map(\.url), ["http://10.0.0.2:9797", "http://10.0.0.9:9797"], "newest first, the other untouched")
        XCTAssertEqual(done.list[0].lastSeen, now)
        XCTAssertEqual(done.list[0].brandLogo, "v1", "what the new one lacks comes from the old")
        XCTAssertEqual(done.list[1], other)
        XCTAssertEqual(done.moves.map(\.from.url), ["http://10.0.0.1:9797"])
        XCTAssertEqual(done.moves.first?.to.url, "http://10.0.0.2:9797")
        XCTAssertTrue(done.replaced.isEmpty && done.dropped.isEmpty)
    }

    func testTheSameAddressIsUpdatedInPlaceWithNothingMoved() {
        let old = server("http://10.0.0.1:9797", "Home", id: "a", key: "K", seen: 5)
        let done = ServerBook.remember(server("http://10.0.0.1:9797", "Den", id: "a", key: "K"), in: [old], now: now)
        XCTAssertEqual(done.list.count, 1)
        XCTAssertEqual(done.list[0].name, "Den")
        XCTAssertEqual(done.list[0].lastSeen, now)
        XCTAssertTrue(done.moves.isEmpty)
    }

    func testAnEntryWithNoKeyGainsOneAtItsAddress() {
        let old = server("http://10.0.0.1:9797", "Home", logo: "v1")
        let done = ServerBook.remember(server("http://10.0.0.1:9797", "", id: "a", key: "K"), in: [old], now: now)
        XCTAssertEqual(done.list, [server("http://10.0.0.1:9797", "Home", id: "a", key: "K", logo: "v1", seen: now)])
        XCTAssertTrue(done.replaced.isEmpty, "the same server, as far as anyone knows")
    }

    func testAnotherServerTakingAnAddressSharesNothingWithTheOneBefore() {
        let old = server("http://10.0.0.1:9797", "Old", id: "a", key: "K", logo: "v1", seen: 5)
        let done = ServerBook.remember(server("http://10.0.0.1:9797", "New", id: "b", key: "L"), in: [old], now: now)
        XCTAssertEqual(done.list, [server("http://10.0.0.1:9797", "New", id: "b", key: "L", seen: now)])
        XCTAssertEqual(done.replaced, [old], "what was kept at that address was the old server's")
        XCTAssertTrue(done.moves.isEmpty)
    }

    func testTheOldestGivesWayPastTheLimit() {
        var list: [SavedServer] = []
        var dropped: [SavedServer] = []
        for i in 1...10 {
            let done = ServerBook.remember(server("http://10.0.0.\(i)", "\(i)", id: "\(i)"), in: list, now: now + Int64(i))
            list = done.list
            dropped += done.dropped
        }
        XCTAssertEqual(list.count, ServerBook.limit)
        XCTAssertEqual(list.first?.name, "10")
        XCTAssertEqual(dropped.map(\.name), ["1", "2"])
    }

    // MARK: Tidying a stored list

    func testDuplicatesByIDByKeyAndByAddressBecomeOne() {
        let list = [
            server("http://10.0.0.2:9797", "Home", id: "a", key: "K", seen: now),
            server("http://10.0.0.1:9797", "Home (old address)", id: "a", key: "K", logo: "v1", seen: now - 9 * day),
            server("https://media.example", "Flat", key: "F"),
            server("http://flat.local:9797", "Flat", id: "f", key: "F"),
            server("http://10.0.0.7:9797", "Shed"),
            server("http://10.0.0.7:9797", "Shed again", id: "s", key: "S"),
            server("http://10.0.0.8:9797", "Alone", id: "z", key: "Z", seen: 77),
        ]
        let tidy = ServerBook.tidy(list)
        XCTAssertEqual(tidy.list, [
            server("http://10.0.0.2:9797", "Home", id: "a", key: "K", logo: "v1", seen: now),
            server("https://media.example", "Flat", id: "f", key: "F"),
            server("http://10.0.0.7:9797", "Shed", id: "s", key: "S"),
            server("http://10.0.0.8:9797", "Alone", id: "z", key: "Z", seen: 77),
        ])
        XCTAssertEqual(tidy.moves.map { "\($0.from.url) > \($0.to.url)" },
                       ["http://10.0.0.1:9797 > http://10.0.0.2:9797", "http://flat.local:9797 > https://media.example"])
        let again = ServerBook.tidy(tidy.list)
        XCTAssertEqual(again.list, tidy.list, "tidying a tidy list changes nothing")
        XCTAssertTrue(again.moves.isEmpty)
    }

    func testTheOneReachedMostRecentlyWinsWhereverItIsInTheList() {
        let list = [server("http://old:9797", "Old name", id: "a", key: "K", seen: 10), server("http://new:9797", "New name", id: "a", key: "K", seen: 20)]
        let tidy = ServerBook.tidy(list)
        XCTAssertEqual(tidy.list, [server("http://new:9797", "New name", id: "a", key: "K", seen: 20)])
        XCTAssertEqual(tidy.moves.map(\.from.url), ["http://old:9797"])
    }

    func testMergingGoesOnUntilNothingIsLeftToMerge() {
        // The second and third are one server; once merged at the third's address, the first is at it too.
        let list = [server("http://b:9797", "Typed"), server("http://a:9797", "Home", id: "a", key: "K", seen: 1), server("http://b:9797", "Home", id: "a", key: "K", seen: 2)]
        let tidy = ServerBook.tidy(list)
        XCTAssertEqual(tidy.list.count, 1)
        XCTAssertEqual(tidy.list[0].url, "http://b:9797")
        XCTAssertEqual(tidy.list[0].publicKey, "K")
        XCTAssertEqual(ServerBook.tidy(tidy.list).list, tidy.list)
    }

    func testDifferentServersAreNeverMerged() {
        let list = [server("http://10.0.0.1:9797", "A", id: "a", key: "K"), server("http://10.0.0.2:9797", "B", id: "b", key: "L"),
                    server("http://10.0.0.3:9797", "C"), server("http://10.0.0.4:9797", "D")]
        XCTAssertEqual(ServerBook.tidy(list), ServerBook.Tidied(list: list, moves: []))
        XCTAssertEqual(ServerBook.tidy([]).list, [])
    }

    // MARK: Found on the network

    func testARememberedServerFoundElsewhereIsConnectedToThere() {
        let home = server("http://10.0.0.1:9797", id: "a", key: "K")
        let found = [FoundServer(id: "a", name: "", url: "http://10.0.0.44:9797"), FoundServer(id: "x", name: "", url: "http://10.0.0.50:9797")]
        XCTAssertEqual(ServerBook.address(of: home, found: found), "http://10.0.0.44:9797")
        XCTAssertEqual(ServerBook.address(of: home, found: []), "http://10.0.0.1:9797")
        XCTAssertEqual(ServerBook.address(of: server("http://10.0.0.1:9797"), found: [FoundServer(id: "", name: "", url: "http://10.0.0.44:9797")]), "http://10.0.0.1:9797",
                       "a server with no ID is only known by its address")
    }

    func testWhatAChangedServerClashesWith() {
        let old = server("http://10.0.0.1:9797", "Home", id: "a", key: "K")
        let moved = server("http://10.0.0.2:9797", "Flat", id: "b", key: "L")
        let shown = server("http://10.0.0.1:9797", "Home", id: "c", key: "NEW")
        XCTAssertEqual(ServerBook.clashes(with: shown, in: [moved, old]), [old], "the one at its address")
        XCTAssertEqual(ServerBook.clashes(with: server("http://10.0.0.3:9797", id: "b", key: "NEW"), in: [moved, old]), [moved], "the one with its ID")
        XCTAssertEqual(ServerBook.clashes(with: old, in: [moved, old]), [], "the same key is no clash")
    }

    // MARK: When it was last reached

    func testLastReachedWords() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // Noon on a day, in milliseconds.
        let noon: Int64 = 1_800_000_000_000 - (1_800_000_000_000 % day) + 12 * 3_600_000
        XCTAssertEqual(ServerBook.lastReached(0, now: noon, calendar: calendar), .unknown)
        XCTAssertEqual(ServerBook.lastReached(noon - 11 * 3_600_000, now: noon, calendar: calendar), .today)
        XCTAssertEqual(ServerBook.lastReached(noon - 13 * 3_600_000, now: noon, calendar: calendar), .yesterday, "by the calendar, not by 24 hours")
        XCTAssertEqual(ServerBook.lastReached(noon - 2 * day, now: noon, calendar: calendar), .days(2))
        XCTAssertEqual(ServerBook.lastReached(noon - 400 * day, now: noon, calendar: calendar), .days(400))
        XCTAssertEqual(ServerBook.lastReached(noon + 3 * day, now: noon, calendar: calendar), .today, "a clock that was put back")
    }

    func testNotReachedLatelyIsOnlySaidOfAKnownTime() {
        XCTAssertTrue(ServerBook.isStale(server("http://a", seen: now - 90 * day), now: now))
        XCTAssertFalse(ServerBook.isStale(server("http://a", seen: now - 89 * day), now: now))
        XCTAssertFalse(ServerBook.isStale(server("http://a"), now: now), "not known isn't stale")
    }

    func testChoosingServersNotReachedForAWhile() {
        let recent = server("http://a", "A", seen: now - 3 * day)
        let month = server("http://b", "B", seen: now - 30 * day)
        let year = server("http://c", "C", seen: now - 400 * day)
        let unknown = server("http://d", "D")
        let list = [recent, month, year, unknown]
        XCTAssertEqual(ServerBook.notReached(for: 30, in: list, now: now).map(\.name), ["B", "C"],
                       "exactly 30 days counts, and one never reached is never chosen")
        XCTAssertEqual(ServerBook.notReached(for: 90, in: list, now: now).map(\.name), ["C"])
        XCTAssertEqual(ServerBook.notReached(for: 365, in: list, now: now).map(\.name), ["C"])
        XCTAssertEqual(ServerBook.notReached(for: 30, in: [recent], now: now), [])
        XCTAssertEqual(ServerBook.periods, [30, 90, 180, 365])
    }

    // MARK: Focus

    func testFocusAfterRemovingGoesNextThenBackThenToEnterAnAddress() {
        XCTAssertEqual(ServerBook.focusAfter(removing: "b", in: ["a", "b", "c"]), "c", "the next")
        XCTAssertEqual(ServerBook.focusAfter(removing: "c", in: ["a", "b", "c"]), "b", "else the one before")
        XCTAssertEqual(ServerBook.focusAfter(removing: "a", in: ["a", "b"]), "b")
        XCTAssertNil(ServerBook.focusAfter(removing: "a", in: ["a"]), "else Enter an address")
        XCTAssertEqual(ServerBook.focusAfter(removing: "gone", in: ["a", "b"]), "a", "never nowhere")
        XCTAssertNil(ServerBook.focusAfter(removing: "gone", in: []))
    }
}
