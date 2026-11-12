// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

final class ChannelSetsTests: XCTestCase {
    /// The server's own example of GET /tv-sets.
    private let example = #"""
    { "sets": [
       {"id":"all","kind":"all","name":"All channels","count":10423},
       {"id":"fav","kind":"favourites","name":"Favourites","count":12},
       {"id":"set:7","kind":"custom","name":"Kids","count":30,"shared":false,"editable":true,"mine":true},
       {"id":"set:9","kind":"custom","name":"Sports","count":8,"shared":true,"editable":false,"mine":false},
       {"id":"src:lib","kind":"source","name":"My library","count":14},
       {"id":"src:tun-3","kind":"source","name":"Provider playlist","count":10409,"driver":"iptv"},
       {"id":"grp:News","kind":"group","name":"News","count":120}
     ],
      "canShare": true }
    """#

    private func sets() throws -> ChannelSetList {
        try JSONDecoder().decode(ChannelSetList.self, from: Data(example.utf8))
    }

    private func channel(_ json: String) throws -> GuideChannel {
        try JSONDecoder().decode(GuideChannel.self, from: Data(json.utf8))
    }

    func testTheSetsAsTheServerSendsThem() throws {
        let list = try sets()
        XCTAssertTrue(list.canShare)
        XCTAssertEqual(list.sets.map(\.id), ["all", "fav", "set:7", "set:9", "src:lib", "src:tun-3", "grp:News"])
        XCTAssertEqual(list.sets[0].count, 10423)
        XCTAssertEqual(list.sets[5].driver, "iptv")
        XCTAssertTrue(list.sets[2].canEdit)
        XCTAssertFalse(list.sets[3].canEdit, "someone else's shared set")
        XCTAssertFalse(list.sets[0].canEdit, "only custom sets are changed")
        // An older or sparser answer still reads.
        let bare = try JSONDecoder().decode(ChannelSetList.self, from: Data(#"{"sets":null}"#.utf8))
        XCTAssertEqual(bare, ChannelSetList(sets: [], canShare: false))
    }

    func testOneSetWithItsChannelsWhicheverWayItsIdComes() throws {
        let a = try JSONDecoder().decode(ChannelSetDetail.self, from: Data(#"{"id":"set:7","name":"Kids","shared":false,"editable":true,"channels":["tun-12","lib-3"]}"#.utf8))
        XCTAssertEqual(a.id, "set:7")
        XCTAssertEqual(a.channels, ["tun-12", "lib-3"])
        let b = try JSONDecoder().decode(ChannelSetDetail.self, from: Data(#"{"id":7,"name":"Kids"}"#.utf8))
        XCTAssertEqual(b, ChannelSetDetail(id: "set:7", name: "Kids", shared: false, editable: true, channels: []))
    }

    func testThePickersSections() throws {
        let sections = ChannelSetRules.sections(try sets().sets)
        XCTAssertEqual(sections.map(\.title), ["All & Favourites", "My sets", "Shared", "Sources", "Groups"])
        XCTAssertEqual(sections.map { $0.sets.map(\.id) }, [["all", "fav"], ["set:7"], ["set:9"], ["src:lib", "src:tun-3"], ["grp:News"]])
        // A set this account shared is still its own.
        let mineShared = ChannelSet(id: "set:2", kind: "custom", name: "Films", shared: true, editable: true, mine: true)
        XCTAssertEqual(ChannelSetRules.sections([mineShared]).map(\.title), ["My sets"])
        XCTAssertEqual(ChannelSetRules.sections([]), [])
    }

    func testTheRememberedSetFallsBackToAll() throws {
        let list = try sets().sets
        XCTAssertEqual(ChannelSetRules.chosen("set:7", in: list), "set:7")
        XCTAssertEqual(ChannelSetRules.chosen("set:404", in: list), "all", "a set that has gone")
        XCTAssertEqual(ChannelSetRules.chosen(nil, in: list), "all")
        XCTAssertEqual(ChannelSetRules.chosen("", in: list), "all")
        XCTAssertEqual(ChannelSetRules.chosen("set:7", in: []), "all", "no list to check it against")
        XCTAssertEqual(ChannelSetRules.storageKey(server: "abc", account: 4), "wms.tv.set.abc.4")
        XCTAssertNotEqual(ChannelSetRules.storageKey(server: "abc", account: 4), ChannelSetRules.storageKey(server: "abc", account: 5))
        XCTAssertEqual(ChannelSetRules.name(of: "grp:News", in: list), "News")
        XCTAssertEqual(ChannelSetRules.name(of: "all", in: []), "All channels")
    }

    func testOnlyCustomSetsHaveANumberInTheirAddress() {
        XCTAssertEqual(ChannelSetRules.pathId("set:7"), "7")
        XCTAssertNil(ChannelSetRules.pathId("grp:News"))
        XCTAssertNil(ChannelSetRules.pathId("set:"))
        XCTAssertNil(ChannelSetRules.pathId("set:7/../9"))
        XCTAssertNil(ChannelSetRules.pathId("set:٣"), "only ASCII digits")
    }

    func testNamesAreShortAndUniqueAmongYourOwn() throws {
        let list = try sets().sets
        XCTAssertEqual(ChannelSetRules.nameProblem("  ", among: list), "Give the set a name.")
        XCTAssertNotNil(ChannelSetRules.nameProblem(String(repeating: "a", count: 41), among: list))
        XCTAssertNil(ChannelSetRules.nameProblem(String(repeating: "a", count: 40), among: list))
        XCTAssertEqual(ChannelSetRules.nameProblem("kids", among: list), "You already have a set called kids.")
        XCTAssertNil(ChannelSetRules.nameProblem("Kids", among: list, renaming: "set:7"), "keeping its own name")
        XCTAssertNil(ChannelSetRules.nameProblem("Sports", among: list), "someone else's set may share a name")
    }

    func testMovingAndTickingKeepTheOrder() {
        let list = ["a", "b", "c", "d"]
        XCTAssertEqual(ChannelSetRules.moved(list, at: 1, by: -1), ["b", "a", "c", "d"])
        XCTAssertEqual(ChannelSetRules.moved(list, at: 1, by: 1), ["a", "c", "b", "d"])
        XCTAssertEqual(ChannelSetRules.moved(list, at: 0, by: -1), list, "nothing above the first")
        XCTAssertEqual(ChannelSetRules.moved(list, at: 3, by: 1), list, "nothing below the last")
        XCTAssertEqual(ChannelSetRules.moved(list, at: 9, by: 1), list)
        XCTAssertEqual(ChannelSetRules.toggled(list, "e"), ["a", "b", "c", "d", "e"], "a new one goes at the end")
        XCTAssertEqual(ChannelSetRules.toggled(list, "b"), ["a", "c", "d"])
    }

    func testReorderingSetsMovesOnlyTheCustomOnes() throws {
        let list = try sets().sets
        XCTAssertEqual(ChannelSetRules.customOrder(list), ["set:7", "set:9"])
        let next = ChannelSetRules.reordered(list, ids: ["set:9", "set:7"])
        XCTAssertEqual(next.map(\.id), ["all", "fav", "set:9", "set:7", "src:lib", "src:tun-3", "grp:News"])
        // One left out keeps its place after those named.
        XCTAssertEqual(ChannelSetRules.reordered(list, ids: ["set:9"]).map(\.id), next.map(\.id))
    }

    func testFindingAChannelAsTheServerDoes() throws {
        let c = try channel(#"{"key":"tun-1","number":"105","name":"BBC News"}"#)
        XCTAssertTrue(ChannelSetRules.matches(c, "10"), "a number that starts with it")
        XCTAssertFalse(ChannelSetRules.matches(c, "05"))
        XCTAssertTrue(ChannelSetRules.matches(c, "news"))
        XCTAssertTrue(ChannelSetRules.matches(c, " "))
        XCTAssertFalse(ChannelSetRules.matches(c, "sport"))
    }

    func testPagesOfChannels() {
        XCTAssertEqual(GuidePaging.pageStart(of: 0, size: 50), 0)
        XCTAssertEqual(GuidePaging.pageStart(of: 49, size: 50), 0)
        XCTAssertEqual(GuidePaging.pageStart(of: 50, size: 50), 50)
        XCTAssertEqual(GuidePaging.pageStart(of: 77, size: 25), 75)
        XCTAssertEqual(GuidePaging.pageStart(of: 9000, size: 0), 0, "all in one list")
        XCTAssertEqual(GuidePaging.rows(start: 50, size: 50, total: 10423), 50..<100)
        XCTAssertEqual(GuidePaging.rows(start: 10400, size: 50, total: 10423), 10400..<10423)
        XCTAssertEqual(GuidePaging.rows(start: 0, size: 0, total: 10423), 0..<10423)
        XCTAssertEqual(GuidePaging.next(start: 50, size: 50, total: 10423), 100)
        XCTAssertNil(GuidePaging.next(start: 10400, size: 50, total: 10423))
        XCTAssertNil(GuidePaging.next(start: 0, size: 0, total: 10423))
        XCTAssertEqual(GuidePaging.previous(start: 100, size: 50), 50)
        XCTAssertNil(GuidePaging.previous(start: 0, size: 50))
        let english = Locale(identifier: "en_US")
        XCTAssertEqual(GuidePaging.words(start: 50, size: 50, total: 10423, locale: english), "51–100 of 10,423")
        XCTAssertEqual(GuidePaging.words(start: 10400, size: 50, total: 10423, locale: english), "10,401–10,423 of 10,423")
        XCTAssertEqual(GuidePaging.words(start: 0, size: 0, total: 10423, locale: english), "10,423 channels")
        XCTAssertEqual(GuidePaging.words(start: 0, size: 50, total: 12, locale: english), "12 channels", "one page holds them all")
        XCTAssertEqual(GuidePaging.words(start: 0, size: 50, total: 1, locale: english), "1 channel")
        XCTAssertEqual(GuidePaging.words(start: 0, size: 50, total: 0, locale: english), "No channels")
    }

    func testThePageSizeKeptOnThisDevice() {
        XCTAssertEqual(GuidePaging.size(stored: 75), 75)
        XCTAssertEqual(GuidePaging.size(stored: 0), 0)
        XCTAssertEqual(GuidePaging.size(stored: 60), 0, "not one of the choices")
        XCTAssertEqual(GuidePaging.size(stored: nil), 0)
        XCTAssertEqual(GuidePaging.sizes.map(GuidePaging.sizeName), ["25", "50", "75", "100", "All"])
        XCTAssertEqual(GuidePaging.fetchSize(pageSize: 50, paging: true), 50)
        XCTAssertEqual(GuidePaging.fetchSize(pageSize: 0, paging: true), 100)
        XCTAssertEqual(GuidePaging.fetchSize(pageSize: 0, paging: false), GuideRules.page)
    }

    func testWhatTheGuideIsAsked() {
        XCTAssertEqual(GuideRules.query(from: 3600, offset: 0), "/guide?from=3600&hours=8&offset=0&limit=30&kind=&group=", "an older server is asked what it always was")
        XCTAssertEqual(GuideRules.query(from: 3600, offset: 50, limit: 50, set: "grp:News & Weather", q: "bbc"),
                       "/guide?from=3600&hours=8&offset=50&limit=50&kind=&group=&set=grp%3ANews%20%26%20Weather&q=bbc")
        XCTAssertEqual(GuidePaging.listQuery(set: "set:7", locate: "105", limit: 1), "/guide?list=1&lite=1&offset=0&limit=1&set=set%3A7&locate=105")
        XCTAssertEqual(GuidePaging.listQuery(q: "news", limit: 20000), "/guide?list=1&lite=1&offset=0&limit=20000&q=news")
    }

    func testGoingToANumberFallsBackToAllChannels() throws {
        XCTAssertEqual(LocateRules.number(" 4.1a "), "4.1")
        XCTAssertEqual(LocateRules.number("１２"), "", "only the digits a remote sends")
        XCTAssertEqual(LocateRules.outcome(inSet: 12, inAll: nil), .here(12))
        XCTAssertEqual(LocateRules.outcome(inSet: -1, inAll: 400), .inAll(400))
        XCTAssertEqual(LocateRules.outcome(inSet: -1, inAll: -1), .nowhere)
        XCTAssertEqual(LocateRules.outcome(inSet: nil, inAll: nil), .nowhere)
        XCTAssertTrue(LocateRules.shouldTryAll(set: "set:7"))
        XCTAssertFalse(LocateRules.shouldTryAll(set: "all"))
        XCTAssertFalse(LocateRules.shouldTryAll(set: ""))
        let lineup = try JSONDecoder().decode([GuideChannel].self, from: Data(#"[{"key":"a","number":"1","name":"One"},{"key":"b","number":"4.1","name":"Four"}]"#.utf8))
        XCTAssertEqual(LocateRules.index(of: "4.1", in: lineup), 1)
        XCTAssertNil(LocateRules.index(of: "7", in: lineup))
        let page = try JSONDecoder().decode(Guide.self, from: Data(#"{"channels":[],"total":30,"offset":0,"set":"set:7","located":-1}"#.utf8))
        XCTAssertEqual(page.located, -1)
        XCTAssertEqual(page.set, "set:7")
    }

    func testWatchingFromTheStart() throws {
        let now: Int64 = 1_000_000
        let archived = try channel(#"{"key":"tun-1","kind":"tuner","name":"News","catchupDays":7}"#)
        let plain = try channel(#"{"key":"tun-2","kind":"tuner","name":"Sport"}"#)
        let started = GuideProgramme(start: now - 600, end: now + 600, kind: "broadcast", title: "On now")
        let later = GuideProgramme(start: now + 600, end: now + 1200, kind: "broadcast", title: "Later")
        let old = GuideProgramme(start: now - 8 * 86400, end: now - 8 * 86400 + 1800, kind: "broadcast", title: "Too old")
        let lastWeek = GuideProgramme(start: now - 6 * 86400, end: now - 6 * 86400 + 1800, kind: "broadcast", title: "Kept")
        XCTAssertTrue(CatchupRules.canWatchFromStart(started, on: archived, now: now))
        XCTAssertTrue(CatchupRules.canWatchFromStart(lastWeek, on: archived, now: now))
        XCTAssertFalse(CatchupRules.canWatchFromStart(later, on: archived, now: now), "it hasn't started")
        XCTAssertFalse(CatchupRules.canWatchFromStart(old, on: archived, now: now), "older than the archive")
        XCTAssertFalse(CatchupRules.canWatchFromStart(started, on: plain, now: now), "no archive")
        XCTAssertFalse(CatchupRules.canWatchFromStart(GuideProgramme(start: now - 60, end: now + 60, kind: "slate", title: "Back soon"), on: archived, now: now))
        XCTAssertFalse(CatchupRules.canWatchFromStart(nil, on: archived, now: now))
        XCTAssertEqual(CatchupRules.query(key: "tun-1", start: 10, end: 20, viewer: "v 1"), "/tv/tun-1/catchup?start=10&end=20&viewer=v%201&streamToken=1")
    }

    func testRecordingOptions() throws {
        let o = RecordingOptions(padBefore: -3, padAfter: 90, keep: -1)
        XCTAssertEqual(o.padBefore, 0)
        XCTAssertEqual(o.padAfter, 60)
        XCTAssertEqual(o.keep, 0)
        XCTAssertEqual(RecordingOptions().paddingWords, "No padding")
        XCTAssertEqual(RecordingOptions(padBefore: 1, padAfter: 5).paddingWords, "1 min before, 5 min after")
        XCTAssertEqual(RecordingOptions(newOnly: true, anyChannel: true, keep: 5).seriesWords, "Any channel · New episodes only · Keep the newest 5")
        XCTAssertEqual(RecordingOptions().seriesWords, "")
        let rule = try JSONDecoder().decode(RecordingRule.self, from: Data(#"{"id":3,"channel":"tun-12","title":"News","anyChannel":false,"newOnly":true,"keep":5,"padBefore":1,"padAfter":5}"#.utf8))
        XCTAssertEqual(rule.options, RecordingOptions(padBefore: 1, padAfter: 5, newOnly: true, keep: 5))
        let older = try JSONDecoder().decode(RecordingRule.self, from: Data(#"{"id":3,"channel":"tun-12","title":"News"}"#.utf8))
        XCTAssertEqual(older.options, RecordingOptions())
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(WittyClient.ruleBody(channel: "tun-12", title: "News", options: rule.options))) as? [String: Any]
        XCTAssertEqual(body?["newOnly"] as? Bool, true)
        XCTAssertEqual(body?["keep"] as? Int, 5)
        XCTAssertEqual(body?["channel"] as? String, "tun-12")
        let change = try JSONSerialization.jsonObject(with: JSONEncoder().encode(WittyClient.ruleBody(channel: nil, title: nil, options: rule.options))) as? [String: Any]
        XCTAssertNil(change?["channel"], "a change leaves the channel and title as they are")
    }

    func testTheSetsQuestionsGoToTheServer() async throws {
        let stand = try StandInServer { request in
            switch (request.line.split(separator: " ").first.map(String.init) ?? "", request.path) {
            case ("GET", "/api/v1/tv-sets"): return StandInServer.answer(body: #"{"sets":[{"id":"all","kind":"all","name":"All channels","count":3}],"canShare":false}"#)
            case ("GET", "/api/v1/tv-sets/7"): return StandInServer.answer(body: #"{"id":"set:7","name":"Kids","channels":["tun-1"]}"#)
            case ("POST", "/api/v1/tv-sets"): return StandInServer.answer(status: "201 Created", body: #"{"id":"set:8","name":"New","channels":[]}"#)
            case ("PUT", "/api/v1/tv-sets/7"), ("POST", "/api/v1/tv-sets/7/channels"), ("DELETE", "/api/v1/tv-sets/7"), ("PUT", "/api/v1/tv-sets/order"):
                return StandInServer.answer(body: "{}")
            case ("GET", "/api/v1/guide?list=1&lite=1&offset=0&limit=1&set=set%3A7&locate=105"):
                return StandInServer.answer(body: #"{"channels":[],"total":30,"offset":0,"set":"set:7","located":-1}"#)
            default: return StandInServer.answer(status: "404 Not Found", body: #"{"error":"no"}"#)
            }
        }
        addTeardownBlock { stand.stop() }
        let client = WittyClient(base: stand.address, token: "t")
        let list = try await client.channelSets()
        XCTAssertEqual(list.sets.first?.count, 3)
        let kids = try await client.channelSet("set:7")
        XCTAssertEqual(kids.channels, ["tun-1"])
        let made = try await client.createChannelSet(name: "New", channels: [], shared: false)
        XCTAssertEqual(made.id, "set:8")
        try await client.updateChannelSet("set:7", name: "Children")
        try await client.changeChannelSet("set:7", add: ["tun-5"])
        try await client.orderChannelSets(["set:7"])
        try await client.deleteChannelSet("set:7")
        let found = try await client.channelList(set: "set:7", locate: "105", limit: 1)
        XCTAssertEqual(found.located, -1)
        do {
            try await client.deleteChannelSet("grp:News")
            XCTFail("a group isn't a set that can be deleted")
        } catch let refused as APIError {
            XCTAssertEqual(refused.status, 0)
        }
        XCTAssertFalse(stand.requests.contains { $0.path.contains("grp") }, "never asked")
    }
}
