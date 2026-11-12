// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.CatchupRules
import com.wittywilla.wittymediaclient.net.ChannelSet
import com.wittywilla.wittymediaclient.net.ChannelSetDetail
import com.wittywilla.wittymediaclient.net.ChannelSets
import com.wittywilla.wittymediaclient.net.DialRules
import com.wittywilla.wittymediaclient.net.DvrRules
import com.wittywilla.wittymediaclient.net.Guide
import com.wittywilla.wittymediaclient.net.GuideChannel
import com.wittywilla.wittymediaclient.net.GuidePaging
import com.wittywilla.wittymediaclient.net.GuideProgramme
import com.wittywilla.wittymediaclient.net.LocateRules
import com.wittywilla.wittymediaclient.net.Located
import com.wittywilla.wittymediaclient.net.Recording
import com.wittywilla.wittymediaclient.net.RecordingRule
import com.wittywilla.wittymediaclient.net.SetRules
import com.wittywilla.wittymediaclient.net.json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale

// Channel sets, the guide a page at a time, finding a channel by its number, catch-up and a recording's options, as
// the server's API for them is written (tv-sets, tv-guide-paging, tv-catchup, tv-dvr-rules-2).
class GuideSetsTest {
    private val answer = """
        { "sets": [
           {"id":"all","kind":"all","name":"All channels","count":10423},
           {"id":"fav","kind":"favourites","name":"Favourites","count":12},
           {"id":"set:7","kind":"custom","name":"Kids","count":30,"shared":false,"editable":true,"mine":true},
           {"id":"set:9","kind":"custom","name":"Sports","count":8,"shared":true,"editable":false,"mine":false},
           {"id":"src:lib","kind":"source","name":"My library","count":14},
           {"id":"src:tun-3","kind":"source","name":"Provider playlist","count":10409,"driver":"iptv"},
           {"id":"grp:News","kind":"group","name":"News","count":120},
           {"id":"x:1","kind":"something new","name":"From a newer server","count":1}
         ],
          "canShare": true, "more": "ignored" }
    """.trimIndent()

    private val sets: List<ChannelSet> = json.decodeFromString<ChannelSets>(answer).sets.orEmpty()

    private fun channel(key: String, number: String, name: String) = GuideChannel(key = key, number = number, name = name)

    @Test
    fun setsAreReadAsTheServerSendsThem() {
        val all = json.decodeFromString<ChannelSets>(answer)
        assertTrue(all.canShare)
        assertEquals(8, all.sets?.size)
        val kids = all.sets!![2]
        assertEquals("set:7", kids.id)
        assertTrue(kids.isCustom && kids.editable && kids.mine && !kids.shared)
        assertEquals("iptv", all.sets!![5].driver)
        // A server that sends no list (a Go nil) and no sharing.
        val empty = json.decodeFromString<ChannelSets>("""{"sets":null}""")
        assertTrue(empty.sets.orEmpty().isEmpty())
        assertFalse(empty.canShare)
        val detail = json.decodeFromString<ChannelSetDetail>("""{"id":"set:7","name":"Kids","shared":false,"editable":true,"channels":["tun-12","lib-3"]}""")
        assertEquals(listOf("tun-12", "lib-3"), detail.channels)
    }

    @Test
    fun thePickersSectionsAreInTheServersOrder() {
        val sections = SetRules.sections(sets)
        assertEquals(listOf("All & Favourites", "My sets", "Shared", "Sources", "Groups"), sections.map { it.title })
        assertEquals(listOf("all", "fav"), sections[0].sets.map { it.id })
        assertEquals(listOf("set:7"), sections[1].sets.map { it.id })
        assertEquals(listOf("set:9"), sections[2].sets.map { it.id })
        assertEquals(listOf("src:lib", "src:tun-3"), sections[3].sets.map { it.id })
        assertEquals("a kind this app doesn't know isn't offered", listOf("grp:News"), sections[4].sets.map { it.id })
        // An empty section has no heading.
        assertEquals(listOf("All & Favourites"), SetRules.sections(sets.take(1)).map { it.title })
        // One's own shared set is still under My sets.
        val mineShared = ChannelSet(id = "set:3", kind = "custom", name = "Family", shared = true, editable = true, mine = true)
        assertEquals("My sets", SetRules.sections(listOf(mineShared)).single().title)
    }

    @Test
    fun searchingTheSetsKeepsAll() {
        assertEquals(listOf("all", "src:tun-3"), SetRules.search(sets, "PLAYLIST").map { it.id })
        assertEquals(sets, SetRules.search(sets, "  "))
        assertEquals(listOf("all"), SetRules.search(sets, "nothing like it").map { it.id })
    }

    @Test
    fun theRememberedSetFallsBackToAll() {
        assertEquals("set:7", SetRules.remembered("set:7", sets))
        assertEquals("a set that has gone", "all", SetRules.remembered("set:99", sets))
        assertEquals("nothing remembered", "all", SetRules.remembered(null, sets))
        assertEquals("all", SetRules.remembered("", sets))
        assertEquals("the sets not read yet: what was remembered stands", "set:99", SetRules.remembered("set:99", null))
        assertEquals("a server that has no sets at all", "all", SetRules.remembered("grp:News", emptyList()))
    }

    @Test
    fun theChoiceIsKeptForEachServerAndAccount() {
        assertEquals("wms.tv.set.abc-123.4", SetRules.prefKey("ABC-123", 4))
        assertFalse(SetRules.prefKey("abc", 4) == SetRules.prefKey("abc", 5))
        assertFalse(SetRules.prefKey("abc", 4) == SetRules.prefKey("def", 4))
    }

    @Test
    fun cyclingGoesRoundInThePickersOrder() {
        val known = sets.dropLast(1)
        assertEquals("fav", SetRules.cycle("all", known, 1))
        assertEquals("grp:News", SetRules.cycle("all", known, -1))
        assertEquals("all", SetRules.cycle("grp:News", known, 1))
        assertEquals("one that isn't there starts at the first", "all", SetRules.cycle("set:99", known, 1))
        assertNull(SetRules.cycle("all", emptyList(), 1))
    }

    @Test
    fun aSetsNumberIsItsAddress() {
        assertEquals("7", SetRules.number("set:7"))
        assertNull(SetRules.number("all"))
        assertNull(SetRules.number("set:"))
        assertNull(SetRules.number("set:7/../x"))
    }

    @Test
    fun namesAreCheckedAsTheServerChecksThem() {
        assertEquals("Give the set a name.", SetRules.nameProblem("   ", sets))
        assertTrue(SetRules.nameProblem("x".repeat(41), sets)!!.contains("40"))
        assertNull(SetRules.nameProblem("x".repeat(40), sets))
        assertTrue("unique per account, whatever the case", SetRules.nameProblem(" kids ", sets)!!.contains("already"))
        assertNull("renaming a set to its own name", SetRules.nameProblem("Kids", sets, except = "set:7"))
        assertNull("someone else's shared set may share a name", SetRules.nameProblem("Sports", sets))
        val many = (1..50).map { ChannelSet(id = "set:$it", kind = "custom", name = "S$it", mine = true) }
        assertFalse(SetRules.canMakeAnother(many))
        assertTrue(SetRules.canMakeAnother(sets))
    }

    @Test
    fun movingAndOrdering() {
        assertEquals(listOf("b", "a", "c"), SetRules.move(listOf("a", "b", "c"), 1, -1))
        assertEquals(listOf("a", "c", "b"), SetRules.move(listOf("a", "b", "c"), 1, 1))
        assertEquals("the first can't go up", listOf("a", "b", "c"), SetRules.move(listOf("a", "b", "c"), 0, -1))
        assertEquals("the last can't go down", listOf("a", "b", "c"), SetRules.move(listOf("a", "b", "c"), 2, 1))
        assertEquals(listOf("a"), SetRules.move(listOf("a"), 5, 1))
        // The order sent is every custom set seen, own and shared.
        assertEquals(listOf("set:9", "set:7"), SetRules.orderAfterMove(sets, "set:9", -1))
        assertEquals(listOf("set:7", "set:9"), SetRules.orderAfterMove(sets, "set:7", -1))
    }

    @Test
    fun tickingChannelsKeepsTheOrderChosen() {
        var chosen = listOf<String>()
        chosen = SetRules.toggle(chosen, "tun-2")
        chosen = SetRules.toggle(chosen, "lib-1")
        chosen = SetRules.toggle(chosen, "tun-9")
        assertEquals(listOf("tun-2", "lib-1", "tun-9"), chosen)
        chosen = SetRules.toggle(chosen, "lib-1")
        assertEquals(listOf("tun-2", "tun-9"), chosen)
        val full = (1..SetRules.MAX_CHANNELS).map { "k$it" }
        assertEquals("no more than a set can hold", full, SetRules.toggle(full, "one more"))
        val (added, removed) = SetRules.changes(listOf("a", "b", "c"), listOf("c", "d", "a"))
        assertEquals(listOf("d"), added)
        assertEquals(listOf("b"), removed)
    }

    @Test
    fun pageMaths() {
        assertEquals(listOf(25, 50, 75, 100, 0), GuidePaging.SIZES)
        assertEquals("a size no longer offered is All", 0, GuidePaging.size(30))
        assertEquals(50, GuidePaging.size(50))
        assertEquals(50, GuidePaging.pageStart(73, 50))
        assertEquals(0, GuidePaging.pageStart(49, 50))
        assertEquals(0, GuidePaging.pageStart(-3, 50))
        assertEquals(0, GuidePaging.pageStart(9000, 0))
        assertEquals(50, GuidePaging.rowsOn(50, 50, 10423))
        assertEquals("the last page is shorter", 23, GuidePaging.rowsOn(10400, 25, 10423))
        assertEquals(10423, GuidePaging.rowsOn(0, 0, 10423))
        assertTrue(GuidePaging.hasNext(10350, 50, 10423))
        assertFalse(GuidePaging.hasNext(10400, 50, 10423))
        assertFalse(GuidePaging.hasNext(0, 0, 10423))
        assertFalse(GuidePaging.hasPrevious(0, 50))
        assertTrue(GuidePaging.hasPrevious(50, 50))
        assertEquals(100, GuidePaging.next(50, 50, 10423))
        assertEquals("no page after the last", 10400, GuidePaging.next(10400, 50, 10423))
        assertEquals(0, GuidePaging.previous(50, 50))
        assertEquals(0, GuidePaging.previous(0, 50))
        assertEquals("a set that got shorter", 50, GuidePaging.clamp(400, 50, 60))
        assertEquals(0, GuidePaging.clamp(400, 50, 0))
    }

    @Test
    fun whereThePageIsInWords() {
        val uk = Locale.UK
        assertEquals("51–100 of 10,423", GuidePaging.rangeWords(50, 50, 10423, uk))
        assertEquals("10,401–10,423 of 10,423", GuidePaging.rangeWords(10400, 25, 10423, uk))
        assertEquals("10,423 channels", GuidePaging.rangeWords(0, 0, 10423, uk))
        assertEquals("1 channel", GuidePaging.rangeWords(0, 0, 1, uk))
        assertEquals("No channels", GuidePaging.rangeWords(0, 25, 0, uk))
        assertEquals("30 channels", SetRules.countWords(30, uk))
        assertEquals("1 channel", SetRules.countWords(1, uk))
        assertEquals("All", GuidePaging.label(0))
        assertEquals("75", GuidePaging.label(75))
    }

    @Test
    fun allAsksForPiecesAndLetsGoOfTheFarOnes() {
        assertEquals(100, GuidePaging.chunk(0, paging = true))
        assertEquals("an older server: as before", 30, GuidePaging.chunk(0, paging = false))
        assertEquals(75, GuidePaging.chunk(75, paging = true))
        assertEquals(2..9, GuidePaging.keep(listOf(500, 520, 640), 100, 3))
        assertEquals(0..3, GuidePaging.keep(listOf(0, 12), 100, 3))
        assertTrue(GuidePaging.keep(emptyList(), 100).isEmpty())
    }

    @Test
    fun theQueriesAsTheServerReadsThem() {
        assertEquals(
            "/guide?from=1000&hours=8&offset=50&limit=50&set=set%3A7&q=bbc%20one&locate=101",
            GuidePaging.query(1000, 50, 50, "set:7", " bbc one ", "101"),
        )
        assertEquals("/guide?from=0&hours=8&offset=0&limit=200", GuidePaging.query(0, -5, 500, null))
        assertEquals("/guide?list=1&lite=1&limit=20000&set=grp%3ANews", GuidePaging.liteQuery("grp:News"))
        assertEquals("/guide?list=1&lite=1&limit=1&set=all&locate=tun-12", GuidePaging.liteQuery("all", limit = 1, locate = "tun-12"))
        // A page of the guide on such a server says where it found a channel.
        val g = json.decodeFromString<Guide>("""{"channels":[],"total":10423,"offset":100,"set":"all","located":137}""")
        assertEquals(137, g.located)
        assertEquals("all", g.set)
        assertNull(json.decodeFromString<Guide>("""{"channels":[]}""").located)
    }

    @Test
    fun narrowingMatchesAsTheServerDoes() {
        val bbc = channel("tun-1", "101", "BBC One HD")
        assertTrue(GuidePaging.matches(bbc, "10"))
        assertTrue(GuidePaging.matches(bbc, "one"))
        assertFalse("a number only matches from its start", GuidePaging.matches(bbc, "01"))
        assertTrue(GuidePaging.matches(bbc, ""))
    }

    @Test
    fun typingANumber() {
        assertEquals("1", DialRules.append("", '1'))
        assertEquals("12", DialRules.append("1", '2'))
        assertEquals("12", DialRules.append("12", 'x'))
        assertEquals("as long as any number can be: starts again", "7", DialRules.append("123456", '7'))
        val list = listOf(channel("tun-1", "2", "Two"), channel("tun-2", "007", "Bond"), channel("tun-3", "101", "BBC"), channel("lib-1", "5.1", "Sub"))
        assertEquals(2, DialRules.locate(list, "101"))
        assertEquals("leading zeros don't matter", 1, DialRules.locate(list, "7"))
        assertEquals(3, DialRules.locate(list, "5.1"))
        assertEquals("by key", 0, DialRules.locate(list, "tun-1"))
        assertEquals(-1, DialRules.locate(list, "999"))
        assertEquals(-1, DialRules.locate(list, " "))
    }

    @Test
    fun findingFallsBackToAll() {
        assertEquals(Located.Here(12), LocateRules.decide(12, null, showingAll = false))
        assertEquals("only in All: offered", Located.InAll(400), LocateRules.decide(-1, 400, showingAll = false))
        assertEquals(Located.Nowhere, LocateRules.decide(-1, -1, showingAll = false))
        assertEquals("showing All already, a miss is a miss", Located.Nowhere, LocateRules.decide(-1, 400, showingAll = true))
        assertEquals(Located.Nowhere, LocateRules.decide(-1, null, showingAll = false))
    }

    @Test
    fun watchingFromTheStart() {
        val now = 1_000_000L
        val archive = json.decodeFromString<GuideChannel>("""{"key":"tun-5","kind":"tuner","number":"5","name":"Five","catchupDays":7}""")
        val plain = archive.copy(catchupDays = null)
        val started = GuideProgramme(start = now - 600, end = now + 1200, title = "News", kind = "broadcast")
        val yesterday = GuideProgramme(start = now - 86400, end = now - 84600, title = "Film", kind = "broadcast")
        val tooOld = GuideProgramme(start = now - 8 * 86400, end = now - 8 * 86400 + 1800, title = "Old", kind = "broadcast")
        val later = GuideProgramme(start = now + 600, end = now + 1800, title = "Later", kind = "broadcast")
        assertTrue(CatchupRules.canWatchFromStart(archive, started, now))
        assertTrue(CatchupRules.canWatchFromStart(archive, yesterday, now))
        assertFalse("outside what's kept", CatchupRules.canWatchFromStart(archive, tooOld, now))
        assertFalse("not started yet", CatchupRules.canWatchFromStart(archive, later, now))
        assertFalse("no archive", CatchupRules.canWatchFromStart(plain, started, now))
        assertFalse("a slate", CatchupRules.canWatchFromStart(archive, started.copy(kind = "slate"), now))
        assertFalse("can't be tuned", CatchupRules.canWatchFromStart(archive.copy(encrypted = "protected"), started, now))
        assertFalse(CatchupRules.canWatchFromStart(archive, null, now))
        assertEquals("/tv/tun-5/catchup?start=913600&end=915400&viewer=v-1", CatchupRules.path("tun-5", yesterday, "v-1"))
    }

    @Test
    fun aRecordingsOptions() {
        assertEquals(0, DvrRules.pad(-4))
        assertEquals(60, DvrRules.pad(90))
        assertEquals(0, DvrRules.keep(-1))
        assertEquals("None", DvrRules.padWords(0))
        assertEquals("Keep all", DvrRules.keepWords(0))
        assertEquals("Keep the newest 5", DvrRules.keepWords(5))
        val rule = json.decodeFromString<RecordingRule>(
            """{"id":3,"channel":"tun-12","title":"Quiz","anyChannel":true,"newOnly":true,"keep":5,"padBefore":1,"padAfter":5}""",
        )
        assertEquals("Every airing on any channel · new episodes only · keep the newest 5 · starts 1 min early, ends 5 min late", DvrRules.ruleWords(rule))
        val old = json.decodeFromString<RecordingRule>("""{"id":3,"channel":"BBC One","title":"Quiz"}""")
        assertEquals("an older server's rule", "Every airing on BBC One", DvrRules.ruleWords(old))
        val r = json.decodeFromString<Recording>("""{"id":1,"title":"Quiz","status":"scheduled","conflict":true,"ruleTitle":"Quiz"}""")
        assertTrue(r.conflict)
        assertEquals("Quiz", r.ruleTitle)
        assertFalse(json.decodeFromString<Recording>("""{"id":1}""").conflict)
    }
}
