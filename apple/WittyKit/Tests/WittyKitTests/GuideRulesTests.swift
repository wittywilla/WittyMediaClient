import XCTest
@testable import WittyKit

final class GuideRulesTests: XCTestCase {
    private func channel(_ json: String) throws -> GuideChannel {
        try JSONDecoder().decode(GuideChannel.self, from: Data(json.utf8))
    }

    func testGapsAreCellsToo() throws {
        let c = try channel(#"{"key":"lib-1","kind":"library","name":"Films","programmes":[{"start":1000,"end":2000,"kind":"show","title":"A"},{"start":3000,"end":4000,"kind":"show","title":"B"}]}"#)
        let cells = GuideRules.cells(c, from: 0, to: 5000, pointsPerSecond: 1)
        XCTAssertEqual(cells.map(\.title), ["Off air", "A", "Off air", "B", "Off air"])
        XCTAssertEqual(cells.map(\.start), [0, 1000, 2000, 3000, 4000])
        XCTAssertEqual(cells.last?.end, 5000)
        let tuner = try channel(#"{"key":"tun-1","kind":"tuner","name":"News","programmes":[]}"#)
        XCTAssertEqual(GuideRules.cells(tuner, from: 0, to: 100, pointsPerSecond: 1).map(\.title), ["No guide data"])
        XCTAssertEqual(GuideRules.cells(nil, from: 0, to: 100, pointsPerSecond: 1), [])
    }

    func testOnlyWhatIsOnScreenAndAProgrammeStartedEarlierStillCounts() throws {
        let c = try channel(#"{"key":"lib-1","name":"Films","programmes":[{"start":0,"end":500,"title":"Gone"},{"start":500,"end":1500,"title":"Started"},{"start":1500,"end":9000,"title":"Long"}]}"#)
        let cells = GuideRules.cells(c, from: 1000, to: 2000, pointsPerSecond: 1)
        XCTAssertEqual(cells.map(\.title), ["Started", "Long"])
        XCTAssertEqual(cells.first?.start, 500, "a cell keeps its programme's own times; it's drawn from the window's edge")
    }

    func testRunsOfShortProgrammesBecomeOneCell() throws {
        // At one point a second, each of these is under the 14 that can show anything.
        let json = #"{"key":"lib-1","name":"Ads","programmes":[{"start":0,"end":10,"title":"a"},{"start":10,"end":20,"title":"b"},{"start":20,"end":30,"title":"c"},{"start":30,"end":200,"title":"Film"},{"start":200,"end":205,"title":"d"}]}"#
        let cells = GuideRules.cells(try channel(json), from: 0, to: 300, pointsPerSecond: 1)
        XCTAssertEqual(cells.map(\.title), ["3 short programmes", "Film", "d", "No guide data"])
        XCTAssertEqual(cells[0].kind, .group)
        XCTAssertEqual(cells[0].group.map(\.title), ["a", "b", "c"])
        XCTAssertEqual(cells[0].programme(at: 15)?.title, "b", "the top of the page says which one")
        XCTAssertEqual(cells[0].end, 30)
        // A lone short one next to a long one stays itself.
        XCTAssertEqual(cells[2].kind, .programme)
    }

    func testTheHalfHours() {
        XCTAssertEqual(GuideRules.floorSlot(3599), 1800)
        XCTAssertEqual(GuideRules.floorSlot(3600), 3600)
        XCTAssertEqual(GuideRules.slots(hours: 0, width: 1920), 6, "what fits a TV")
        XCTAssertEqual(GuideRules.slots(hours: 1.5, width: 1920), 3)
        XCTAssertEqual(GuideRules.slots(hours: 4, width: 1920), 8)
        XCTAssertEqual(GuideRules.slots(hours: 0, width: 900), 4)
    }

    func testTheGuideGoesTwoHoursBackAndAFortnightOn() {
        let now: Int64 = 1_000_000_800
        let here = GuideRules.floorSlot(now)
        XCTAssertEqual(GuideRules.shifted(here, by: -1800, now: now), here - 1800)
        XCTAssertEqual(GuideRules.shifted(here, by: -86400, now: now), here - 7200)
        XCTAssertEqual(GuideRules.shifted(here, by: 30 * 86400, now: now), here + 14 * 86400)
    }

    func testHowLongInFewWords() {
        XCTAssertEqual(GuideRules.left(20), "1 min")
        XCTAssertEqual(GuideRules.left(29 * 60), "29 min")
        XCTAssertEqual(GuideRules.left(3600), "1h")
        XCTAssertEqual(GuideRules.left(88 * 60), "1h 28m")
    }

    func testTimesPeopleJumpTo() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let morning: Int64 = 1_700_000_000 - (1_700_000_000 % 86400) + 9 * 3600
        let jumps = GuideRules.jumps(now: morning, calendar: calendar)
        XCTAssertEqual(jumps.map(\.label), ["Tonight 8 PM", "Tomorrow morning"])
        XCTAssertEqual(jumps[0].at - morning, 11 * 3600)
        XCTAssertEqual(GuideRules.jumps(now: morning + 11 * 3600 - 600, calendar: calendar)[0].label, "Tomorrow 8 PM", "too close to tonight")
        XCTAssertEqual(GuideRules.dayWord(morning, now: morning, calendar: calendar), "Today")
        XCTAssertEqual(GuideRules.dayWord(morning + 10 * 3600, now: morning, calendar: calendar), "Tonight")
        XCTAssertEqual(GuideRules.dayWord(morning + 86400, now: morning, calendar: calendar), "Tomorrow")
        XCTAssertEqual(GuideRules.dayWord(morning - 86400, now: morning, calendar: calendar), "Yesterday")
    }

    func testFilters() throws {
        let news = try channel(#"{"key":"tun-1","kind":"tuner","name":"News","group":"Test","favourite":true}"#)
        let films = try channel(#"{"key":"lib-1","kind":"library","name":"Films","categories":["Movies"]}"#)
        XCTAssertTrue(GuideRules.matches(news, kind: "", group: "", favourites: false))
        XCTAssertTrue(GuideRules.matches(news, kind: "tuner", group: "Test", favourites: true))
        XCTAssertFalse(GuideRules.matches(films, kind: "tuner", group: "", favourites: false))
        XCTAssertTrue(GuideRules.matches(films, kind: "", group: "Movies", favourites: false), "a category counts as a group")
        XCTAssertFalse(GuideRules.matches(films, kind: "", group: "", favourites: true))
        XCTAssertTrue(news.with(favourite: false).favourite == false)
    }

    func testTheGuideIsAskedForAsThePageAsksForIt() {
        XCTAssertEqual(GuideRules.query(from: 3600, offset: 30, kind: "tuner", group: "News & Weather", favourites: true),
                       "/guide?from=3600&hours=8&offset=30&limit=30&kind=tuner&group=News%20%26%20Weather&favourites=1")
    }

    func testWhatComesNext() throws {
        let c = try channel(#"{"key":"lib-1","name":"Films","programmes":[{"start":0,"end":100,"title":"Now"},{"start":100,"end":110,"kind":"slate","title":"Back soon"},{"start":110,"end":300,"kind":"show","title":"Later"}]}"#)
        let now = c.programmes![0]
        XCTAssertEqual(GuideRules.next(after: now, cell: nil, on: c)?.title, "Later", "a slate isn't worth naming")
    }

    func testTheWholeChannelFromTheServer() throws {
        let json = ##"{"key":"tun-1","kind":"tuner","id":1,"number":"201","name":"News","group":"Test","canRecord":true,"hd":true,"accent":"#ff8800","favourite":true,"brand":{"kind":"network","name":"News"},"security":{"state":"unknown","label":"Not checked yet","detail":"Checked when you tune in."},"alternative":{"key":"tun-2","number":"202","name":"News HD"},"notices":["No sound"],"programmes":[{"start":1,"end":2,"kind":"broadcast","title":"Bulletin","genre":"News","itemId":5,"showId":6,"season":1,"episode":2}]}"##
        let c = try channel(json)
        XCTAssertTrue(c.isTuner)
        XCTAssertEqual(c.canRecord, true)
        XCTAssertEqual(c.security?.label, "Not checked yet")
        XCTAssertEqual(c.alternative?.number, "202")
        XCTAssertEqual(c.brand?.name, "News")
        XCTAssertEqual(c.programmes?.first?.genre, "News")
        let cell = GuideRules.cells(c, from: 1, to: 2, pointsPerSecond: 100)[0]
        XCTAssertTrue(cell.isBroadcast)
        XCTAssertFalse(cell.isDim)
    }

    func testRecordingsSayWhereTheyAre() throws {
        let json = #"[{"id":1,"channelId":1,"channel":"News","number":"201","title":"Bulletin","start":10,"stop":20,"status":"done","sizeBytes":1500000000,"path":"/r/a.ts"},{"id":2,"channel":"News","title":"Later","start":30,"stop":40,"status":"scheduled","sizeBytes":340000000}]"#
        let list = try JSONDecoder().decode([Recording].self, from: Data(json.utf8))
        XCTAssertEqual(list[0].statusWords, "Done")
        XCTAssertTrue(list[0].isFinished)
        XCTAssertEqual(list[0].sizeWords, "1.5 GB")
        XCTAssertEqual(list[1].statusWords, "Scheduled")
        XCTAssertFalse(list[1].isFinished)
        XCTAssertEqual(list[1].sizeWords, "340 MB")
    }

    func testARemindersMoment() {
        let r = TvReminder(id: 1, channel: "lib-1", title: "Film", sub: nil, start: 1000, end: 2000)
        XCTAssertNil(ReminderRules.due([r], shown: [], now: 900), "not yet")
        XCTAssertEqual(ReminderRules.due([r], shown: [], now: 940)?.id, 1, "a minute before")
        XCTAssertEqual(ReminderRules.due([r], shown: [], now: 1100)?.id, 1, "and for a while after it starts")
        XCTAssertNil(ReminderRules.due([r], shown: [], now: 1200))
        XCTAssertNil(ReminderRules.due([r], shown: [1], now: 1000), "once only")
        XCTAssertEqual(ReminderRules.nextCheck([r], shown: [], now: 0), 940)
        XCTAssertNil(ReminderRules.nextCheck([r], shown: [1], now: 0))
    }
}

extension TvReminder {
    init(id: Int64, channel: String, title: String, sub: String?, start: Int64, end: Int64) {
        let json = try! JSONSerialization.data(withJSONObject: ["id": id, "channel": channel, "title": title, "start": start, "end": end].merging(sub.map { ["sub": $0] } ?? [:]) { a, _ in a })
        self = try! JSONDecoder().decode(TvReminder.self, from: json)
    }
}
