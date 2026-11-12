// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.Access
import com.wittywilla.wittymediaclient.net.ApiError
import com.wittywilla.wittymediaclient.net.Household
import com.wittywilla.wittymediaclient.net.KindLimit
import com.wittywilla.wittymediaclient.net.ManagedUser
import com.wittywilla.wittymediaclient.net.Managing
import com.wittywilla.wittymediaclient.net.MyLimits
import com.wittywilla.wittymediaclient.net.ParentalLists
import com.wittywilla.wittymediaclient.net.ProfileActivity
import com.wittywilla.wittymediaclient.net.Refusal
import com.wittywilla.wittymediaclient.net.ScreenTime
import com.wittywilla.wittymediaclient.net.ScreenTimeRules
import com.wittywilla.wittymediaclient.net.ScreenTimeTap
import com.wittywilla.wittymediaclient.net.TimeOfDay
import com.wittywilla.wittymediaclient.net.TimeRules
import com.wittywilla.wittymediaclient.net.User
import com.wittywilla.wittymediaclient.net.accessBody
import com.wittywilla.wittymediaclient.net.accessDiff
import com.wittywilla.wittymediaclient.net.json
import com.wittywilla.wittymediaclient.ui.AVATAR_COLOURS
import com.wittywilla.wittymediaclient.ui.AVATAR_SHAPES
import com.wittywilla.wittymediaclient.ui.GamesRoute
import com.wittywilla.wittymediaclient.ui.GamesScreen
import com.wittywilla.wittymediaclient.ui.Route
import com.wittywilla.wittymediaclient.ui.SwitchOutcome
import com.wittywilla.wittymediaclient.ui.TvRoute
import com.wittywilla.wittymediaclient.ui.TvScreen
import com.wittywilla.wittymediaclient.ui.YouNative
import com.wittywilla.wittymediaclient.ui.YouOpens
import com.wittywilla.wittymediaclient.ui.YouWho
import com.wittywilla.wittymediaclient.ui.isPlayingRoute
import com.wittywilla.wittymediaclient.ui.offeredAvatars
import com.wittywilla.wittymediaclient.ui.offeredColours
import com.wittywilla.wittymediaclient.ui.parseAvatar
import com.wittywilla.wittymediaclient.ui.switchOutcome
import com.wittywilla.wittymediaclient.ui.switchingSignsOut
import com.wittywilla.wittymediaclient.ui.withColour
import com.wittywilla.wittymediaclient.ui.withPicture
import com.wittywilla.wittymediaclient.ui.youGroups
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.TimeZone

// The server's docs/PROFILES.md, "For app makers": a profile's limits and what they hide, screen time and its
// notices, the two refusals, sending only the limits that changed, times of day, and who manages whom. The JSON
// here is what a 0.8.0-alpha server answers.
class ProfileRulesTest {
    private val kidsLimits = """{"allowUnrated":false,"features":{"comments":true,"downloads":true,"editProfile":false,"games":false,"liveTv":true,"recordings":true,"remote":true,"sharing":false,"writeComments":false},"kind":"kids","kinds":{},"limited":true,"maxAge":7,"parentPin":true,"screenTime":{"allowanceSec":60,"allowed":true,"extraSec":0,"message":"","reason":"","remainingSec":60,"until":1794414836,"usedSec":0},"time":{"schoolDayMinutes":1,"weekendMinutes":1,"from":"","schoolNightUntil":"","weekendUntil":""}}"""
    private val timeUp = """{"code":"screen-time","error":"That's all the screen time for today. A parent can add more.","screenTime":{"allowanceSec":60,"allowed":false,"extraSec":0,"message":"That's all the screen time for today. A parent can add more.","nextAt":1794459600,"reason":"allowance","remainingSec":0,"usedSec":60}}"""

    @Test
    fun aProfilesLimitsSayWhatToHide() {
        val limits = json.decodeFromString<MyLimits>(kidsLimits)
        assertTrue(limits.limited)
        assertFalse(limits.can("games"))
        assertFalse(limits.can("sharing"))
        assertFalse(limits.can("editProfile"))
        assertTrue(limits.can("recordings"))
        assertTrue(limits.can("liveTv"))
        // A feature a newer server names and this one doesn't is on: nothing is hidden by not knowing.
        assertTrue(limits.can("somethingNew"))
        assertTrue(limits.timed)
        assertTrue(limits.parentPin)
        assertEquals(60, limits.screenTime.remainingSec)
    }

    @Test
    fun anAccountWithoutLimitsHidesNothing() {
        val limits = json.decodeFromString<MyLimits>("""{"allowUnrated":true,"features":{"games":true,"liveTv":true},"kind":"adult","kinds":{},"limited":false,"maxAge":-1,"parentPin":false,"screenTime":{"allowanceSec":-1,"allowed":true,"extraSec":0,"message":"","reason":"","remainingSec":-1,"usedSec":0},"time":null}""")
        assertFalse(limits.limited)
        assertFalse(limits.timed)
        assertTrue(limits.can("games"))
        assertNull(ScreenTimeRules.minutesLeftNotice(limits.screenTime))
    }

    @Test
    fun whatIsOffIsNotOfferedOnYou() {
        val adult = YouWho(admin = false, adult = true, hasGames = true, twoStepAvailable = false, onTv = false)
        fun rows(who: YouWho) = youGroups(who).flatMap { it.rows }.map { it.key }
        assertTrue("rowShareLinks" in rows(adult))
        assertTrue("rowGameSettings" in rows(adult))
        val limited = adult.copy(off = setOf("sharing", "games"))
        assertFalse("rowShareLinks" in rows(limited))
        assertFalse("rowGameSettings" in rows(limited))
        assertFalse("rowControllers" in rows(limited))
        // Profiles is the app's own screen where the server has parental controls, and its page where it doesn't.
        val row = { who: YouWho -> youGroups(who).flatMap { it.rows }.single { it.key == "rowProfiles" }.opens }
        assertEquals(YouOpens.Page("/settings/users"), row(adult))
        assertEquals(YouOpens.Native(YouNative.Profiles), row(adult.copy(nativeProfiles = true)))
        assertFalse("rowProfiles" in rows(adult.copy(adult = false, nativeProfiles = true)))
    }

    @Test
    fun theTwoRefusalsAreRead() {
        val time = Refusal.read(timeUp)
        assertTrue(time.isScreenTime)
        assertEquals("allowance", time.screenTime?.reason)
        assertEquals(1794459600L, time.screenTime?.nextAt)
        assertFalse(time.screenTime!!.allowed)
        val off = Refusal.read("""{"error":"Games are turned off for this profile.","code":"feature-off","feature":"games"}""")
        assertTrue(off.isFeatureOff)
        assertEquals("games", off.feature)
        assertEquals("Games are turned off for this profile.", off.message)
        assertFalse(Refusal.read("""{"error":"not allowed"}""").isScreenTime)
        assertEquals(Refusal(), Refusal.read("not json"))
        // Only a 403 with a code is one of these.
        assertTrue(Refusal.of(ApiError(403, "x", code = "screen-time", body = timeUp))!!.isScreenTime)
        assertNull(Refusal.of(ApiError(403, "not allowed")))
        assertNull(Refusal.of(ApiError(404, "x", code = "screen-time", body = timeUp)))
        assertNull(Refusal.of(java.io.IOException("x")))
    }

    @Test
    fun theLineComesAFewMinutesBefore() {
        fun left(sec: Int) = ScreenTime(allowed = true, allowanceSec = 3600, remainingSec = sec)
        assertNull(ScreenTimeRules.minutesLeftNotice(left(601)))
        assertEquals(10, ScreenTimeRules.minutesLeftNotice(left(600)))
        assertEquals(5, ScreenTimeRules.minutesLeftNotice(left(290)))
        assertEquals(1, ScreenTimeRules.minutesLeftNotice(left(20)))
        assertEquals(1, ScreenTimeRules.minutesLeftNotice(left(0)))
        // No allowance at all, or time already up: no line.
        assertNull(ScreenTimeRules.minutesLeftNotice(left(-1)))
        assertNull(ScreenTimeRules.minutesLeftNotice(ScreenTime(allowed = false, remainingSec = 0)))
        assertNull(ScreenTimeRules.minutesLeftNotice(null))
    }

    @Test
    fun theLineIsShownAgainAtEachMark() {
        fun step(sec: Int) = ScreenTimeRules.noticeStep(ScreenTime(allowed = true, allowanceSec = 3600, remainingSec = sec))
        assertEquals(Int.MAX_VALUE, step(1200))
        assertEquals(10, step(600))
        assertEquals(10, step(400))
        assertEquals(5, step(300))
        assertEquals(3, step(170))
        assertEquals(2, step(110))
        assertEquals(1, step(50))
        // Each mark is lower than the one before, which is how the app knows the line is due again.
        assertTrue(step(300) < step(400))
        assertEquals(Int.MAX_VALUE, ScreenTimeRules.noticeStep(ScreenTime(allowed = false)))
    }

    @Test
    fun timeUpIsKnownAndAskedAboutAtTheRightMoment() {
        assertTrue(ScreenTimeRules.timeUp(Refusal.read(timeUp).screenTime))
        assertFalse(ScreenTimeRules.timeUp(ScreenTime()))
        assertFalse(ScreenTimeRules.timeUp(null))
        val now = 1_000_000_000L
        // Once a minute, or just after `until` when that is sooner.
        assertEquals(60_000, ScreenTimeRules.nextAskMs(ScreenTime(allowed = true, until = 0), now))
        assertEquals(21_500, ScreenTimeRules.nextAskMs(ScreenTime(allowed = true, until = now / 1000 + 20), now))
        assertEquals(60_000, ScreenTimeRules.nextAskMs(ScreenTime(allowed = true, until = now / 1000 + 600), now))
        assertEquals(60_000, ScreenTimeRules.nextAskMs(ScreenTime(allowed = true, until = now / 1000 - 30), now))
        assertEquals(60_000, ScreenTimeRules.nextAskMs(ScreenTime(allowed = false, until = now / 1000 + 20), now))
        assertEquals(60_000, ScreenTimeRules.nextAskMs(null, now))
    }

    @Test
    fun theHeaderKeepsTheTimeLeftFresh() {
        val st = ScreenTime(allowed = true, allowanceSec = 3600, remainingSec = 900, until = 5000)
        val fresher = ScreenTimeRules.withHeader(st, 300, 4000)!!
        assertEquals(300, fresher.remainingSec)
        assertEquals(4300, fresher.until)
        // Zero is only a hint: why and until when comes from the refusal or from asking.
        assertEquals(st, ScreenTimeRules.withHeader(st, 0, 4000))
        assertNull(ScreenTimeRules.withHeader(null, 300, 4000))
        val up = ScreenTime(allowed = false)
        assertEquals(up, ScreenTimeRules.withHeader(up, 300, 4000))
        assertTrue(ScreenTimeRules.allowedAgain(up, st))
        assertFalse(ScreenTimeRules.allowedAgain(st, st))
    }

    @Test
    fun everyAnswerIsHeardOnce() {
        val heard = mutableListOf<String>()
        val listener = object : ScreenTimeTap.Listener {
            override fun timeLeft(seconds: Int) { heard += "left $seconds" }
            override fun refused(refusal: Refusal) { heard += "refused ${refusal.code} ${refusal.feature}" }
        }
        ScreenTimeTap.note(200, "540", "application/json", listener) { error("the body of a good answer isn't read") }
        ScreenTimeTap.note(403, "0", "application/json; charset=utf-8", listener) { timeUp }
        ScreenTimeTap.note(403, null, "application/json", listener) { """{"error":"x","code":"feature-off","feature":"games"}""" }
        // Another 403, a picture, a header that isn't a number: nothing to say.
        ScreenTimeTap.note(403, null, "application/json", listener) { """{"error":"not allowed"}""" }
        ScreenTimeTap.note(403, null, "image/png", listener) { error("a picture isn't read") }
        ScreenTimeTap.note(200, "soon", null, listener) { "" }
        assertEquals(listOf("left 540", "left 0", "refused screen-time ", "refused feature-off games"), heard)
    }

    @Test
    fun whenPlayingCanStartAgainIsTodayOrTomorrow() {
        val zone = TimeZone.getTimeZone("UTC")
        val noon = 1_794_398_400_000L // 2026-11-11 12:00 UTC
        assertTrue(ScreenTimeRules.nextIsToday(noon / 1000 + 3600, noon, zone))
        assertFalse(ScreenTimeRules.nextIsToday(noon / 1000 + 18 * 3600, noon, zone))
        assertEquals("1234", ScreenTimeRules.typedPin("12 34"))
        assertTrue(ScreenTimeRules.pinReady("1234"))
        assertFalse(ScreenTimeRules.pinReady("123"))
        assertEquals(12, ScreenTimeRules.typedPin("1234567890123456").length)
    }

    @Test
    fun timesOfDayAreReadAsTheServerReadsThem() {
        assertEquals(20 * 60 + 30, TimeOfDay.minutes("20:30"))
        assertEquals(0, TimeOfDay.minutes("00:00"))
        assertNull(TimeOfDay.minutes("7:00"))
        assertNull(TimeOfDay.minutes("24:00"))
        assertNull(TimeOfDay.minutes("12:60"))
        assertNull(TimeOfDay.minutes("12.30"))
        assertNull(TimeOfDay.minutes(""))
        assertEquals("07:05", TimeOfDay.text(7 * 60 + 5))
        // What people type, made into the server's form where that's plain.
        assertEquals("07:00", TimeOfDay.tidy("7:00"))
        assertEquals("20:30", TimeOfDay.tidy(" 2030 "))
        assertEquals("07:30", TimeOfDay.tidy("730"))
        assertEquals("", TimeOfDay.tidy("  "))
        assertEquals("7pm", TimeOfDay.tidy("7pm"))
    }

    @Test
    fun timeRulesAreCheckedBeforeTheyAreSent() {
        assertNull(TimeOfDay.problem(TimeRules()))
        assertNull(TimeOfDay.problem(TimeRules(60, 120, "07:00", "20:30", "21:30")))
        assertEquals("timeErrNotTime", TimeOfDay.problem(TimeRules(from = "7pm")))
        assertEquals("timeErrNotTime", TimeOfDay.problem(TimeRules(weekendUntil = "9:30")))
        assertEquals("timeErrMinutes", TimeOfDay.problem(TimeRules(schoolDayMinutes = 2000)))
        assertEquals("timeErrBedtime", TimeOfDay.problem(TimeRules(from = "09:00", schoolNightUntil = "08:00")))
        // With no earliest time the day starts at 6:00, so a bedtime before that is refused.
        assertEquals("timeErrBedtime", TimeOfDay.problem(TimeRules(schoolNightUntil = "05:30")))
        assertTrue(TimeRules().empty)
        assertFalse(TimeRules(weekendUntil = "21:00").empty)
    }

    private val kiddo = """{"id":3,"name":"kiddo","displayName":"Kiddo","showUsername":false,"isAdmin":false,"createdAt":1794414553,"kind":"kids","hasPassword":true,"twoFactor":false,"avatar":"rocket:teal","access":{"maxAge":7,"allowUnrated":false,"libraries":null,"blockGenres":null,"allowItems":null,"blockItems":null,"allowShows":null,"blockShows":null,"liveTv":true,"libraryChannels":true,"tunerChannels":false,"off":["editProfile"],"futureLimit":{"x":1}}}"""

    @Test
    fun onlyWhatChangedIsSent() {
        val user = json.decodeFromString<ManagedUser>(kiddo)
        val before = user.access!!
        assertEquals(7, before.maxAge)
        assertTrue(before.libraries.isEmpty())
        assertTrue(accessDiff(before, before).isEmpty())
        assertEquals("{}", accessBody(accessDiff(before, before)))

        val after = before.copy(maxAge = 10, time = TimeRules(schoolDayMinutes = 60))
        val change = accessDiff(before, after)
        assertEquals(setOf("maxAge", "time"), change.keys)
        // A limit this app has never heard of isn't in what's sent, so the server keeps it.
        assertFalse("futureLimit" in accessBody(change))
        assertEquals("""{"access":{"maxAge":10,"time":{"schoolDayMinutes":60,"weekendMinutes":0,"from":"","schoolNightUntil":"","weekendUntil":""}}}""", accessBody(change))

        // A kind's age and time rules are each sent whole, as the server replaces them whole.
        val kinds = accessDiff(before.copy(kinds = mapOf("game" to KindLimit(12, false))), before.copy(kinds = mapOf("game" to KindLimit(12, false), "film" to KindLimit(13, true))))
        assertEquals("""{"kinds":{"game":{"maxAge":12,"allowUnrated":false},"film":{"maxAge":13,"allowUnrated":true}}}""", kinds.toString())
        // Turning a switch on takes it out of what's off, and clearing a list sends the empty list.
        assertEquals("""{"off":[]}""", accessDiff(before, before.with("editProfile", true)).toString())
        assertEquals("""{"off":["editProfile","games"]}""", accessDiff(before, before.with("games", false)).toString())
        assertEquals("""{"libraries":[]}""", accessDiff(before.copy(libraries = listOf(2)), before).toString())
        assertEquals("""{"clearPassword":true}""", accessBody(accessDiff(before, before), clearPassword = true))
    }

    @Test
    fun whoMayBeManagedIsWhatTheServerLists() {
        val admin = ManagedUser(id = 1, name = "admin", isAdmin = true)
        val child = json.decodeFromString<ManagedUser>(kiddo)
        // Nobody sets their own limits, and an administrator has none.
        assertTrue(Managing.mayLimit(1, child))
        assertFalse(Managing.mayLimit(3, child))
        assertFalse(Managing.mayLimit(2, admin))
        assertTrue(Managing.mayRename(2, admin))
        assertFalse(Managing.mayRename(1, admin))
        assertTrue(Managing.mayManageAnyone(false, "adult"))
        assertFalse(Managing.mayManageAnyone(false, "kids"))
        // Their own name and picture: adults unless their limits say no, a Kids profile only when given it.
        val limits = json.decodeFromString<MyLimits>(kidsLimits)
        assertFalse(Managing.ownLook(false, limits))
        assertTrue(Managing.ownLook(true, limits))
        assertTrue(Managing.ownLook(false, limits.copy(features = mapOf("editProfile" to true))))
        assertFalse(Managing.ownUsername(false, "kids", limits.copy(features = mapOf("editProfile" to true))))
        assertTrue(Managing.ownUsername(false, "adult", null))
        assertEquals("rocket:teal", child.avatar)
    }

    @Test
    fun eachCountrysRatingsAreShownForAnAge() {
        val lists = json.decodeFromString<ParentalLists>(
            """{"avatarColours":["red","blue"],"avatars":["star","unknown-shape","rocket"],"features":["games"],"kinds":["film","tv","game"],"maxExtraMinutes":240,"systems":[{"id":"mpa","name":"MPA","country":"US","kinds":["film"],"ratings":[{"label":"G","age":0},{"label":"PG","age":10},{"label":"PG-13","age":13},{"label":"R","age":17}]},{"id":"bbfc","name":"BBFC","country":"GB","kinds":["film","tv"],"ratings":[{"label":"U","age":0},{"label":"PG","age":10},{"label":"12A","age":12},{"label":"15","age":15}]},{"id":"pegi","name":"PEGI","country":"","kinds":["game"],"ratings":[{"label":"PEGI 3","age":3},{"label":"PEGI 7","age":7},{"label":"PEGI 12","age":12}]}]}""",
        )
        assertEquals("PG-13, 12A", Managing.allowedAt(lists.systems, "film", 13))
        assertEquals("G, U", Managing.allowedAt(lists.systems, "film", 7))
        assertEquals("PEGI 7", Managing.allowedAt(lists.systems, "game", 10))
        // Nothing of a system is allowed yet: it isn't named.
        assertEquals("", Managing.allowedAt(lists.systems, "game", 0))
        assertEquals(listOf(3, 7, 12), Managing.agesFor(lists.systems, "game"))
        assertEquals(listOf(3, 7, 9, 12), Managing.agesFor(lists.systems, "game", 9))
        assertEquals(listOf(0, 10, 12, 13, 15, 17), Managing.agesFor(lists.systems, "film"))
        // The age over everything shows one rating a system, of those that rate films or TV.
        assertEquals("PG", Managing.allowedOverall(lists.systems, 10))
        assertEquals("PG-13, 12A", Managing.allowedOverall(lists.systems, 13))
        assertEquals(listOf(0, 30, 45, 60, 75, 90, 120, 180, 240, 360), Managing.allowances(75))
        assertEquals(Managing.ALLOWANCES, Managing.allowances(60))
        // The pictures offered are the server's that this app can draw.
        assertEquals(listOf("star", "rocket"), offeredAvatars(lists.avatars))
        assertEquals(listOf("red", "blue"), offeredColours(lists.avatarColours))
        assertEquals(AVATAR_SHAPES.keys.toList(), offeredAvatars(emptyList()))
    }

    @Test
    fun aProfilesPictureIsItsShapeOnItsColour() {
        val rocket = parseAvatar("rocket:teal")!!
        assertEquals("rocket", rocket.name)
        assertEquals(AVATAR_COLOURS[4], rocket.background)
        assertEquals(AVATAR_SHAPES["rocket"], rocket.shape)
        // The web's table: purple and pink skip one of the shared colours.
        assertEquals(AVATAR_COLOURS[7], parseAvatar("star:purple")!!.background)
        assertEquals(AVATAR_COLOURS[8], parseAvatar("star:pink")!!.background)
        // None, or one this app doesn't know: the initial is drawn.
        assertNull(parseAvatar(""))
        assertNull(parseAvatar(null))
        assertNull(parseAvatar("dragon:red"))
        assertNull(parseAvatar("star:mauve"))
        assertNull(parseAvatar("star"))
        assertEquals(15, AVATAR_SHAPES.size)
        assertEquals("heart:blue", withPicture("", "heart"))
        assertEquals("heart:teal", withPicture("rocket:teal", "heart"))
        assertEquals("rocket:pink", withColour("rocket:teal", "pink"))
        assertEquals("", withColour("", "pink"))
    }

    @Test
    fun switchingAsksForWhatSigningInAsksFor() {
        assertEquals(SwitchOutcome.AskCode, switchOutcome(401, twoFactor = true, codeSent = false))
        assertEquals(SwitchOutcome.WrongCode, switchOutcome(401, twoFactor = true, codeSent = true))
        // 403, not 401: the device is still signed in to the profile it had.
        assertEquals(SwitchOutcome.WrongPassword, switchOutcome(403, twoFactor = false, codeSent = false))
        assertEquals(SwitchOutcome.Wait, switchOutcome(429, twoFactor = false, codeSent = false))
        assertEquals(SwitchOutcome.Failed, switchOutcome(500, twoFactor = false, codeSent = false))
        val list = json.decodeFromString<Household>(
            """{"profiles":[{"id":1,"name":"admin","displayName":"","kind":"adult","hasPassword":true,"avatar":"","current":true},{"id":3,"name":"kiddo","displayName":"Kiddo","kind":"kids","hasPassword":false,"avatar":"paw:green","current":false}]}""",
        ).profiles
        assertFalse(switchingSignsOut(list))
        assertTrue(list[0].current)
        assertFalse(list[1].hasPassword)
        // Where the server doesn't list its profiles, switching is signing out.
        assertTrue(switchingSignsOut(emptyList()))
        assertTrue(switchingSignsOut(list.take(1)))
        assertEquals("paw:green", json.decodeFromString<User>("""{"id":3,"name":"kiddo","avatar":"paw:green"}""").avatar)
    }

    @Test
    fun whatIsPlayingIsLeftWhenTimeIsUp() {
        assertTrue(isPlayingRoute(Route.Player(4, false)))
        assertTrue(isPlayingRoute(Route.NowPlaying))
        assertTrue(isPlayingRoute(TvRoute(TvScreen.Channel("c1"))))
        assertTrue(isPlayingRoute(Route.Page("/watch/12")))
        assertTrue(isPlayingRoute(Route.Web("/play/7")))
        // Browsing goes on.
        assertFalse(isPlayingRoute(Route.Home))
        assertFalse(isPlayingRoute(Route.Item(4)))
        assertFalse(isPlayingRoute(TvRoute(TvScreen.Guide)))
        assertFalse(isPlayingRoute(GamesRoute(GamesScreen.Game(9))))
        assertFalse(isPlayingRoute(Route.Page("/settings/users")))
        assertFalse(isPlayingRoute(Route.Page("/watchlist")))
    }

    @Test
    fun theReportIsRead() {
        val report = json.decodeFromString<ProfileActivity>(
            """{"days":[{"day":20261111,"screenSec":60,"extraSec":900}],"watched":[{"day":20261111,"itemId":4,"title":"Puddle Day","kind":"video","seconds":5,"lastAt":1794414865},{"day":20261109,"itemId":5,"title":"Pilot","showTitle":"Tiny Show","kind":"video","seconds":600,"lastAt":1794214865}],"events":[{"at":1794414865,"kind":"extra","title":"sam","detail":"15"},{"at":1794414855,"kind":"time","title":"","detail":"allowance"}],"screenTime":{"allowanceSec":960,"allowed":true,"extraSec":900,"message":"","reason":"","remainingSec":900,"until":1794415765,"usedSec":60}}""",
        )
        assertEquals(listOf(20261111, 20261109), Managing.reportDays(report))
        assertEquals(Triple(2026, 11, 11), Managing.dayParts(20261111))
        assertEquals("Tiny Show", report.watched[1].showTitle)
        assertEquals("extra", report.events[0].kind)
        assertEquals(900, report.screenTime.extraSec)
    }
}
