// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
import XCTest
@testable import WittyKit

final class HouseholdTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func refusal(_ status: Int, _ json: String) -> APIError {
        struct Said: Decodable { let error: String?; let code: String?; let twoFactor: Bool? }
        let said = try? JSONDecoder().decode(Said.self, from: Data(json.utf8))
        return APIError(status: status, message: said?.error ?? "", twoFactor: said?.twoFactor == true, code: said?.code ?? "", body: Data(json.utf8))
    }

    private func object(_ data: Data?) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(data)) as? [String: Any])
    }

    // MARK: Switching

    func testTheHouseholdIsReadAndSaysWhoCanBeSwitchedToWithATap() throws {
        let json = #"{"profiles":[{"id":1,"name":"willa","displayName":"Willa","kind":"adult","hasPassword":true,"avatar":"star:blue","current":true},{"id":2,"name":"mia","displayName":"","kind":"kids","hasPassword":false,"avatar":"","current":false}]}"#
        let list = try decode(HouseholdList.self, json).profiles ?? []
        XCTAssertTrue(SwitchRules.offersPicker(list))
        XCTAssertTrue(list[0].isCurrent)
        XCTAssertEqual(list[0].note, "Watching now")
        XCTAssertFalse(list[0].opensWithTap)
        XCTAssertEqual(list[1].shownName, "mia")
        XCTAssertEqual(list[1].note, "Kids")
        XCTAssertTrue(list[1].opensWithTap)
        XCTAssertEqual(list[0].asProfile.avatar, "star:blue")
        XCTAssertEqual(SwitchRules.secretLabel(list[0]), "Password")
        XCTAssertEqual(SwitchRules.secretLabel(list[1]), "Password or PIN")
        // Nobody to switch to: the Classic sign-in screen, or an older server. Switching is then signing out.
        XCTAssertFalse(SwitchRules.offersPicker([]))
        XCTAssertFalse(SwitchRules.offersPicker([list[0]]))
        XCTAssertEqual(try decode(HouseholdList.self, "{}").profiles, nil)
    }

    func testARefusedSwitchSaysWhatToAskForNext() {
        XCTAssertEqual(SwitchRules.refusal(refusal(401, #"{"error":"a code is needed","twoFactor":true}"#), sentCode: false), .needsCode(wrong: false))
        XCTAssertEqual(SwitchRules.refusal(refusal(401, #"{"error":"that code isn't right","twoFactor":true}"#), sentCode: true), .needsCode(wrong: true))
        XCTAssertEqual(SwitchRules.refusal(refusal(403, #"{"error":"wrong name or password"}"#), sentCode: false), .refused)
        XCTAssertEqual(SwitchRules.refusal(refusal(429, #"{"error":"Too many wrong tries. Try again in 30 seconds."}"#), sentCode: false), .wait)
    }

    // MARK: Limits and screen time

    func testLimitsSayWhatToHideAndWhetherTimeIsCounted() throws {
        let json = #"{"limited":true,"kind":"kids","features":{"games":false,"recordings":true,"downloads":true,"sharing":false,"comments":true,"writeComments":false,"remote":true,"editProfile":false,"liveTv":false},"maxAge":7,"allowUnrated":false,"kinds":{},"time":{"schoolDayMinutes":60,"weekendMinutes":120,"from":"","schoolNightUntil":"20:00","weekendUntil":""},"screenTime":{"allowed":true,"reason":"","allowanceSec":3600,"usedSec":600,"extraSec":0,"remainingSec":3000,"message":"","until":1700003000},"parentPin":true}"#
        let limits = try decode(MyLimits.self, json)
        XCTAssertFalse(limits.allows(ProfileFeature.games))
        XCTAssertFalse(limits.allows(ProfileFeature.liveTv))
        XCTAssertTrue(limits.allows(ProfileFeature.recordings))
        // Something the server didn't mention is offered: the server refuses what is really off.
        XCTAssertTrue(limits.allows("somethingNew"))
        XCTAssertTrue(limits.isTimed)
        XCTAssertEqual(limits.screenTime?.left, 3000)
        XCTAssertEqual(limits.parentPin, true)

        let free = try decode(MyLimits.self, #"{"limited":false,"kind":"adult","features":{"games":true},"time":null,"screenTime":{"allowed":true,"allowanceSec":-1,"usedSec":0,"extraSec":0,"remainingSec":-1,"message":""},"parentPin":false}"#)
        XCTAssertFalse(free.isTimed)
        XCTAssertNil(free.screenTime?.left)
        XCTAssertTrue(MyLimits().allows(ProfileFeature.games))
        XCTAssertFalse(MyLimits(time: TimeRules()).isTimed)
    }

    func testTheTimeIsAskedAfterEachMinuteAndRightAfterItRunsOut() {
        XCTAssertEqual(ScreenTimeRules.nextAsk(after: nil, now: 1000), 60)
        XCTAssertEqual(ScreenTimeRules.nextAsk(after: ScreenTime(allowed: true, remainingSec: 3000, until: 4000), now: 1000), 60)
        XCTAssertEqual(ScreenTimeRules.nextAsk(after: ScreenTime(allowed: true, remainingSec: 20, until: 1020), now: 1000), 21.5)
        // Already past: the next minute's question finds out.
        XCTAssertEqual(ScreenTimeRules.nextAsk(after: ScreenTime(allowed: true, remainingSec: 0, until: 990), now: 1000), 60)
        XCTAssertEqual(ScreenTimeRules.nextAsk(after: ScreenTime(allowed: false, until: 1020), now: 1000), 60)
        XCTAssertEqual(ScreenTimeRules.nextAsk(after: ScreenTime(allowed: true, remainingSec: -1), now: 1000), 60)
    }

    func testTheTimeLeftIsSaidOnceAtEachMarkOnTheWayDown() {
        var warner = ScreenTimeWarner()
        XCTAssertNil(warner.notice(for: ScreenTime(allowed: true, remainingSec: 3000)))
        XCTAssertNil(warner.notice(for: ScreenTime(allowed: true, remainingSec: -1)))
        XCTAssertEqual(warner.notice(for: ScreenTime(allowed: true, remainingSec: 590)), "10 minutes of screen time left")
        XCTAssertNil(warner.notice(for: ScreenTime(allowed: true, remainingSec: 530)))
        XCTAssertEqual(warner.notice(for: ScreenTime(allowed: true, remainingSec: 290)), "5 minutes of screen time left")
        XCTAssertNil(warner.notice(for: ScreenTime(allowed: true, remainingSec: 230)))
        XCTAssertEqual(warner.notice(for: ScreenTime(allowed: true, remainingSec: 110)), "2 minutes of screen time left")
        XCTAssertEqual(warner.notice(for: ScreenTime(allowed: true, remainingSec: 50)), "1 minute of screen time left")
        XCTAssertNil(warner.notice(for: ScreenTime(allowed: true, remainingSec: 5)))
        // Time up says nothing here: the time-up screen does. A parent then gives 15 minutes, and it starts again.
        XCTAssertNil(warner.notice(for: ScreenTime(allowed: false, remainingSec: 0)))
        XCTAssertNil(warner.notice(for: ScreenTime(allowed: true, remainingSec: 900)))
        XCTAssertEqual(warner.notice(for: ScreenTime(allowed: true, remainingSec: 600)), "10 minutes of screen time left")
        // A profile that signs in with a minute left is told at once.
        var late = ScreenTimeWarner()
        XCTAssertEqual(late.notice(for: ScreenTime(allowed: true, remainingSec: 60)), "1 minute of screen time left")
        XCTAssertEqual(ScreenTimeRules.minutesWords(0), "1 minute")
        XCTAssertEqual(ScreenTimeRules.minutesWords(400), "7 minutes")
    }

    func testTheServersRefusalToPlayIsRecognisedWhateverElseA403Means() {
        let said = #"{"error":"That's all the screen time for today. A parent can add more.","code":"screen-time","screenTime":{"allowed":false,"reason":"allowance","allowanceSec":60,"usedSec":61,"extraSec":0,"remainingSec":0,"message":"That's all the screen time for today. A parent can add more.","nextAt":1700090000}}"#
        let time = ScreenTimeRules.refusal(refusal(403, said))
        XCTAssertEqual(time?.allowed, false)
        XCTAssertEqual(time?.reason, "allowance")
        XCTAssertEqual(time?.nextAt, 1_700_090_000)
        // The words alone are enough when the rest is missing.
        let bare = ScreenTimeRules.refusal(refusal(403, #"{"error":"Time is up.","code":"screen-time"}"#))
        XCTAssertEqual(bare?.allowed, false)
        XCTAssertEqual(bare?.message, "Time is up.")
        XCTAssertNil(ScreenTimeRules.refusal(refusal(403, #"{"error":"not allowed"}"#)))
        XCTAssertNil(ScreenTimeRules.refusal(refusal(500, #"{"error":"x","code":"screen-time"}"#)))
        XCTAssertNil(ScreenTimeRules.refusal(URLError(.timedOut)))
        XCTAssertNil(ScreenTimeRules.refusal(nil))
        XCTAssertEqual(ScreenTimeRules.featureOff(refusal(403, #"{"error":"Games are turned off for this profile.","code":"feature-off","feature":"games"}"#)), "games")
        XCTAssertNil(ScreenTimeRules.featureOff(refusal(403, said)))
        XCTAssertEqual(ScreenTimeRules.left(header: "42"), 42)
        XCTAssertEqual(ScreenTimeRules.left(header: " 0 "), 0)
        XCTAssertNil(ScreenTimeRules.left(header: "-1"))
        XCTAssertNil(ScreenTimeRules.left(header: nil))
    }

    func testTheTimeUpScreenSaysWhyAndUntilWhen() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let now = Date(timeIntervalSince1970: 1_700_000_000) // 22:13 UTC on a Tuesday
        let clock: (Date) -> String = { date in
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return "\(parts.hour ?? 0):" + ((parts.minute ?? 0) < 10 ? "0" : "") + "\(parts.minute ?? 0)"
        }
        XCTAssertEqual(ScreenTimeRules.title(ScreenTime(allowed: false, reason: "allowance")), "Screen time is up")
        XCTAssertEqual(ScreenTimeRules.title(ScreenTime(allowed: false, reason: "bedtime")), "That’s all for tonight")
        XCTAssertEqual(ScreenTimeRules.title(ScreenTime(allowed: false, reason: "early")), "It’s a bit early")
        XCTAssertEqual(ScreenTimeRules.message(ScreenTime(allowed: false, message: "It's too early.")), "It's too early.")
        XCTAssertEqual(ScreenTimeRules.message(ScreenTime(allowed: false)), "This profile can’t watch any more right now.")
        let laterToday = ScreenTime(allowed: false, nextAt: 1_700_000_000 + 3600)
        XCTAssertEqual(ScreenTimeRules.nextWords(laterToday, now: now, calendar: calendar, clock: clock), "You can watch again at 23:13.")
        let tomorrow = ScreenTime(allowed: false, nextAt: 1_700_000_000 + 8 * 3600)
        XCTAssertEqual(ScreenTimeRules.nextWords(tomorrow, now: now, calendar: calendar, clock: clock), "You can watch again tomorrow at 6:13.")
        XCTAssertEqual(ScreenTimeRules.nextWords(ScreenTime(allowed: false), now: now, calendar: calendar, clock: clock), "")
        XCTAssertEqual(ScreenTimeRules.nextWords(ScreenTime(allowed: false, nextAt: 1_600_000_000), now: now, calendar: calendar, clock: clock), "")
        XCTAssertEqual(ScreenTimeRules.extras.map(ScreenTimeRules.extraLabel), ["15 minutes", "30 minutes", "1 hour"])
        XCTAssertTrue(ScreenTimeRules.pinIsValid("1234"))
        XCTAssertFalse(ScreenTimeRules.pinIsValid("123"))
        XCTAssertFalse(ScreenTimeRules.pinIsValid("1234567890123"))
        XCTAssertFalse(ScreenTimeRules.pinIsValid("12a4"))
        XCTAssertEqual(ScreenTimeRules.cleanPin("12-34 56789012345"), "123456789012")
    }

    // MARK: Limits a parent sets

    func testLimitsAreReadWhateverAnOlderServerLeavesOut() throws {
        let old = try decode(Access.self, #"{"maxAge":7,"allowUnrated":false,"libraries":[1,2],"blockGenres":["Horror"],"allowItems":[],"blockItems":[],"allowShows":null,"blockShows":null,"liveTv":true,"libraryChannels":true,"tunerChannels":false}"#)
        XCTAssertEqual(old.maxAge, 7)
        XCTAssertEqual(old.libraries, [1, 2])
        XCTAssertEqual(old.kinds, [:])
        XCTAssertEqual(old.off, [])
        XCTAssertNil(old.time)
        XCTAssertFalse(old.tunerChannels)
        let full = try decode(Access.self, #"{"maxAge":13,"allowUnrated":true,"libraries":null,"blockGenres":null,"liveTv":false,"kinds":{"game":{"maxAge":12,"allowUnrated":false}},"onlyGenres":["Family"],"blockTags":["scary"],"allowCollections":[4],"blockCollections":[9],"off":["games","sharing"],"on":["editProfile"],"time":{"schoolDayMinutes":60,"weekendMinutes":120,"from":"07:00","schoolNightUntil":"20:00","weekendUntil":""}}"#)
        XCTAssertEqual(full.kinds["game"], KindLimit(maxAge: 12, allowUnrated: false))
        XCTAssertFalse(full.allows("games"))
        XCTAssertTrue(full.allows("comments"))
        XCTAssertEqual(full.time?.schoolNightUntil, "20:00")
        XCTAssertEqual(full.rule(forCollection: 4), "allow")
        XCTAssertEqual(full.rule(forCollection: 9), "block")
        XCTAssertEqual(full.rule(forCollection: 1), "")
        // Rules that limit nothing are no rules.
        XCTAssertNil(try decode(Access.self, #"{"time":{"schoolDayMinutes":0,"weekendMinutes":0,"from":"","schoolNightUntil":"","weekendUntil":""}}"#).time)
        XCTAssertEqual(try decode(Access.self, "{}"), Access())
    }

    func testOnlyWhatChangedIsSent() throws {
        let had = Access(maxAge: 7, allowUnrated: false, libraries: [1], off: ["games"], time: TimeRules(schoolDayMinutes: 60, weekendMinutes: 120))
        XCTAssertNil(had.changes(from: had))

        var now = had
        now.maxAge = 10
        XCTAssertEqual(try object(now.changes(from: had)) as NSDictionary, ["maxAge": 10] as NSDictionary)

        now = had
        now.set("games", on: true)
        now.set("comments", on: false)
        now.kinds["game"] = KindLimit(maxAge: 12, allowUnrated: false)
        let sent = try object(now.changes(from: had))
        XCTAssertEqual(Set(sent.keys), ["off", "kinds"])
        XCTAssertEqual(sent["off"] as? [String], ["comments"])
        XCTAssertEqual((sent["kinds"] as? [String: [String: Any]])?["game"]?["maxAge"] as? Int, 12)

        // Taking the time rules away says so: left out, the server would keep them.
        now = had
        now.time = nil
        let cleared = try object(now.changes(from: had))
        XCTAssertEqual(Array(cleared.keys), ["time"])
        XCTAssertTrue(cleared["time"] is NSNull)

        now = had
        now.time?.schoolNightUntil = "20:30"
        let timed = try object(now.changes(from: had))
        XCTAssertEqual((timed["time"] as? [String: Any])?["schoolNightUntil"] as? String, "20:30")
        XCTAssertEqual((timed["time"] as? [String: Any])?["schoolDayMinutes"] as? Int, 60)

        now = had
        now.setRule("block", forCollection: 5)
        now.setRule("allow", forCollection: 6)
        now.setRule("allow", forCollection: 5)
        XCTAssertEqual(now.allowCollections, [6, 5])
        XCTAssertEqual(now.blockCollections, [])
        now.setRule("", forCollection: 6)
        XCTAssertEqual(try object(now.changes(from: had))["allowCollections"] as? [Int], [5])
    }

    func testTimeRulesAreCheckedAsTheServerChecksThem() {
        XCTAssertEqual(TimeRules.minutes("07:30"), 450)
        XCTAssertEqual(TimeRules.minutes("23:59"), 1439)
        XCTAssertNil(TimeRules.minutes("7:30"))
        XCTAssertNil(TimeRules.minutes("24:00"))
        XCTAssertNil(TimeRules.minutes("ab:cd"))
        XCTAssertEqual(TimeRules.clock(450), "07:30")
        XCTAssertEqual(TimeRules.clock(1230), "20:30")
        XCTAssertNil(TimeRules(schoolDayMinutes: 60, from: "07:00", schoolNightUntil: "20:00").problem)
        XCTAssertNotNil(TimeRules(from: "21:00", schoolNightUntil: "20:00").problem)
        // With a bedtime and no earliest time, the day starts at 6:00.
        XCTAssertNotNil(TimeRules(schoolNightUntil: "05:00").problem)
        XCTAssertNotNil(TimeRules(weekendUntil: "8pm").problem)
        XCTAssertTrue(TimeRules().isEmpty)
        XCTAssertFalse(TimeRules(weekendUntil: "22:00").isEmpty)
        XCTAssertEqual(TimeRules.allowanceLabel(0), "No limit")
        XCTAssertEqual(TimeRules.allowanceLabel(45), "45 minutes")
        XCTAssertEqual(TimeRules.allowanceLabel(60), "1 hour")
        XCTAssertEqual(TimeRules.allowanceLabel(180), "3 hours")
        XCTAssertEqual(TimeRules.allowanceLabel(75), "1 h 15 min")
        XCTAssertEqual(TimeRules.allowanceChoices(including: 60), TimeRules.allowances)
        XCTAssertEqual(TimeRules.allowanceChoices(including: 1), [0, 1, 30, 45, 60, 90, 120, 180, 240, 360])
    }

    func testAgesAreOfferedFromTheServersRatingSystems() {
        let systems = [
            RatingSystem(id: "mpa", kinds: ["film"], ratings: [.init(label: "G", age: 0), .init(label: "PG", age: 10), .init(label: "PG-13", age: 13), .init(label: "R", age: 17)]),
            RatingSystem(id: "bbfc", kinds: ["film", "tv"], ratings: [.init(label: "U", age: 0), .init(label: "12A", age: 12), .init(label: "12", age: 12), .init(label: "15", age: 15)]),
            RatingSystem(id: "pegi", kinds: ["game"], ratings: [.init(label: "PEGI 3", age: 3), .init(label: "PEGI 7", age: 7)]),
        ]
        XCTAssertEqual(LimitWords.ages(for: "film", in: systems), [0, 10, 12, 13, 15, 17])
        XCTAssertEqual(LimitWords.ages(for: "game", in: systems, including: 5), [3, 5, 7])
        XCTAssertEqual(LimitWords.ages(for: "book", in: systems), [])
        XCTAssertEqual(LimitWords.allowed(at: 13, kind: "film", in: systems), "PG-13, 12")
        XCTAssertEqual(LimitWords.ageChoice(0, kind: "film", in: systems), "For everyone (G, U)")
        XCTAssertEqual(LimitWords.ageChoice(13, kind: "film", in: systems), "Up to age 13 (PG-13, 12)")
        XCTAssertEqual(LimitWords.ageChoice(2, kind: "game", in: systems), "Up to age 2")
        XCTAssertEqual(LimitWords.ageChoice(-1, kind: "game", in: systems), "No age limit")
        XCTAssertEqual(LimitWords.ageLabel(7), "Kids 7+")
        XCTAssertEqual(LimitWords.ageLabel(-1), "Everything")
        XCTAssertEqual(LimitWords.ageLabel(9), "Up to age 9")
        XCTAssertEqual(LimitWords.kindLabel("music"), "Music and audio")
    }

    func testTheSwitchesAreWordedForTheKindOfProfile() {
        let kids = LimitWords.featureSwitches(profileKind: "kids", offered: ["games", "recordings", "downloads", "sharing", "comments", "remote", "editProfile"])
        XCTAssertEqual(kids.map(\.feature.id), ["games", "recordings", "downloads", "sharing", "comments", "remote", "editProfile"])
        XCTAssertEqual(kids.first { $0.feature.id == "sharing" }?.fixedOff, true)
        XCTAssertEqual(kids.first { $0.feature.id == "sharing" }?.feature.hint, "Only for adult accounts.")
        let adult = LimitWords.featureSwitches(profileKind: "adult", offered: nil)
        XCTAssertEqual(adult.first { $0.feature.id == "sharing" }?.fixedOff, false)
        // A server that offers fewer switches gets fewer.
        XCTAssertEqual(LimitWords.featureSwitches(profileKind: "kids", offered: ["games"]).map(\.feature.id), ["games"])
        XCTAssertEqual(LimitWords.summary(nil), "No limits")
        XCTAssertEqual(LimitWords.summary(Access()), "No limits")
        XCTAssertEqual(LimitWords.summary(Access(maxAge: 7, liveTv: false, off: ["games"], time: TimeRules(schoolDayMinutes: 60))),
                       "Kids 7+ · 1 hour on school days · no Live TV · 1 thing turned off")
        XCTAssertEqual(Access.tags(from: " scary, , loud ,scary"), ["scary", "loud"])
        XCTAssertEqual(Access.starting(kind: "kids", maxAge: 7).liveTv, true)
        XCTAssertEqual(Access.starting(kind: "guest", maxAge: 7).liveTv, false)
        XCTAssertEqual(Access.starting(kind: "kids", maxAge: 7).allowUnrated, false)
    }

    func testManagedProfilesAndTheirReportAreRead() throws {
        let users = try decode([ManagedUser].self, #"[{"id":1,"name":"willa","displayName":"Willa","showUsername":false,"isAdmin":true,"createdAt":1,"kind":"adult","hasPassword":true,"twoFactor":false,"avatar":"","access":null},{"id":2,"name":"mia","displayName":"","isAdmin":false,"kind":"kids","hasPassword":false,"avatar":"paw:pink","access":{"maxAge":7,"allowUnrated":false,"libraries":null,"liveTv":true,"libraryChannels":true,"tunerChannels":false,"on":["editProfile"]}}]"#)
        XCTAssertFalse(users[0].canBeLimited(by: 1))
        XCTAssertTrue(users[1].canBeLimited(by: 1))
        XCTAssertFalse(users[1].canBeLimited(by: 2))
        XCTAssertEqual(users[0].role, "Administrator")
        XCTAssertEqual(users[1].role, "Kids")
        XCTAssertEqual(users[1].access?.maxAge, 7)

        let report = try decode(ProfileActivity.self, #"{"days":[{"day":20261111,"screenSec":3900,"extraSec":900},{"day":20261110,"screenSec":600,"extraSec":0}],"watched":[{"day":20261111,"itemId":5,"title":"Pilot","showTitle":"Bluey","kind":"video","seconds":1320.5,"lastAt":1},{"day":20261109,"itemId":6,"title":"","kind":"video","seconds":60,"lastAt":1}],"events":[{"at":1,"kind":"blocked","itemId":9,"title":"Alien","detail":"R"},{"at":2,"kind":"extra","title":"PIN","detail":"15"},{"at":3,"kind":"extra","title":"willa","detail":"30"},{"at":4,"kind":"time","title":"","detail":"bedtime"},{"at":5,"kind":"feature","title":"","detail":"games"}],"screenTime":{"allowed":false,"reason":"allowance","allowanceSec":3600,"usedSec":3900,"extraSec":0,"remainingSec":0,"message":"That's all the screen time for today. A parent can add more."}}"#)
        XCTAssertEqual(ReportWords.days(report), [20261111, 20261110, 20261109])
        XCTAssertEqual(ReportWords.dayTotal(report.days?.first), "1 h 5 min of screen time, with 15 min extra given")
        XCTAssertEqual(ReportWords.dayTotal(report.days?.last), "10 min of screen time")
        XCTAssertEqual(ReportWords.dayTotal(nil), "")
        XCTAssertEqual(ReportWords.watched(try XCTUnwrap(report.watched?.first)), "Bluey: Pilot")
        XCTAssertEqual(ReportWords.watched(try XCTUnwrap(report.watched?.last)), "A title that has gone")
        let events = (report.events ?? []).map(ReportWords.event)
        XCTAssertEqual(events, ["Asked for a hidden title: Alien (R)", "Was given more time: 15 minutes, by the parents’ PIN",
                                "Was given more time: 30 minutes, by willa", "Tried to play when time was up: it was past bedtime",
                                "Tried something that is turned off: games"])
        XCTAssertEqual(ReportWords.today(report.screenTime), "1 h 5 min of 1 h used. That's all the screen time for today. A parent can add more.")
        XCTAssertEqual(ReportWords.today(ScreenTime(allowed: true, allowanceSec: -1, usedSec: 1200)), "20 min of screen time.")
        XCTAssertEqual(ReportWords.duration(7200), "2 h")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(ReportWords.date(day: 20261111, calendar: calendar), calendar.date(from: DateComponents(year: 2026, month: 11, day: 11)))
        XCTAssertNil(ReportWords.date(day: 7, calendar: calendar))
        XCTAssertEqual(try decode(ProfileActivity.self, "{}").days, nil)
    }
}
