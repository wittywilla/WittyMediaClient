package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.GuideCell
import com.wittywilla.wittymediaclient.net.GuideChannel
import com.wittywilla.wittymediaclient.net.GuideRules
import com.wittywilla.wittymediaclient.net.Recording
import com.wittywilla.wittymediaclient.net.ReminderRules
import com.wittywilla.wittymediaclient.net.TvReminder
import com.wittywilla.wittymediaclient.net.json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.TimeZone

// The same checks as Apple's GuideRulesTests: the grid, its times and what the server sends, as the page has them.
class GuideRulesTest {
    private fun channel(text: String): GuideChannel = json.decodeFromString(text)

    @Test
    fun gapsAreCellsToo() {
        val c = channel("""{"key":"lib-1","kind":"library","name":"Films","programmes":[{"start":1000,"end":2000,"kind":"show","title":"A"},{"start":3000,"end":4000,"kind":"show","title":"B"}]}""")
        val cells = GuideRules.cells(c, 0, 5000, 1.0)
        assertEquals(listOf("Off air", "A", "Off air", "B", "Off air"), cells.map { it.title })
        assertEquals(listOf(0L, 1000L, 2000L, 3000L, 4000L), cells.map { it.start })
        assertEquals(5000L, cells.last().end)
        val tuner = channel("""{"key":"tun-1","kind":"tuner","name":"News","programmes":[]}""")
        assertEquals(listOf("No guide data"), GuideRules.cells(tuner, 0, 100, 1.0).map { it.title })
        assertEquals(emptyList<GuideCell>(), GuideRules.cells(null, 0, 100, 1.0))
    }

    @Test
    fun onlyWhatIsOnScreenAndAProgrammeStartedEarlierStillCounts() {
        val c = channel("""{"key":"lib-1","name":"Films","programmes":[{"start":0,"end":500,"title":"Gone"},{"start":500,"end":1500,"title":"Started"},{"start":1500,"end":9000,"title":"Long"}]}""")
        val cells = GuideRules.cells(c, 1000, 2000, 1.0)
        assertEquals(listOf("Started", "Long"), cells.map { it.title })
        assertEquals("a cell keeps its programme's own times; it's drawn from the window's edge", 500L, cells.first().start)
    }

    @Test
    fun runsOfShortProgrammesBecomeOneCell() {
        // At one point a second, each of these is under the 14 that can show anything.
        val c = channel("""{"key":"lib-1","name":"Ads","programmes":[{"start":0,"end":10,"title":"a"},{"start":10,"end":20,"title":"b"},{"start":20,"end":30,"title":"c"},{"start":30,"end":200,"title":"Film"},{"start":200,"end":205,"title":"d"}]}""")
        val cells = GuideRules.cells(c, 0, 300, 1.0)
        assertEquals(listOf("3 short programmes", "Film", "d", "No guide data"), cells.map { it.title })
        assertEquals(GuideCell.Kind.Group, cells[0].kind)
        assertEquals(listOf("a", "b", "c"), cells[0].group.map { it.title })
        assertEquals("the top of the page says which one", "b", cells[0].programmeAt(15)?.title)
        assertEquals(30L, cells[0].end)
        // A lone short one next to a long one stays itself.
        assertEquals(GuideCell.Kind.Programme, cells[2].kind)
    }

    @Test
    fun theHalfHours() {
        assertEquals(1800L, GuideRules.floorSlot(3599))
        assertEquals(3600L, GuideRules.floorSlot(3600))
        assertEquals("what fits a TV", 6, GuideRules.slots(0.0, 1920.0))
        assertEquals(3, GuideRules.slots(1.5, 1920.0))
        assertEquals(8, GuideRules.slots(4.0, 1920.0))
        assertEquals(4, GuideRules.slots(0.0, 900.0))
    }

    @Test
    fun theGuideGoesTwoHoursBackAndAFortnightOn() {
        val now = 1_000_000_800L
        val here = GuideRules.floorSlot(now)
        assertEquals(here - 1800, GuideRules.shifted(here, -1800, now))
        assertEquals(here - 7200, GuideRules.shifted(here, -86400, now))
        assertEquals(here + 14 * 86400, GuideRules.shifted(here, 30 * 86400L, now))
    }

    @Test
    fun howLongInFewWords() {
        assertEquals("1 min", GuideRules.left(20))
        assertEquals("29 min", GuideRules.left(29 * 60))
        assertEquals("1h", GuideRules.left(3600))
        assertEquals("1h 28m", GuideRules.left(88 * 60))
    }

    @Test
    fun timesPeopleJumpTo() {
        val utc = TimeZone.getTimeZone("UTC")
        val morning = 1_700_000_000L - (1_700_000_000L % 86400) + 9 * 3600
        val jumps = GuideRules.jumps(morning, utc)
        assertEquals(listOf("Tonight 8 PM", "Tomorrow morning"), jumps.map { it.label })
        assertEquals(11 * 3600L, jumps[0].at - morning)
        assertEquals("too close to tonight", "Tomorrow 8 PM", GuideRules.jumps(morning + 11 * 3600 - 600, utc)[0].label)
        assertEquals("Today", GuideRules.dayWord(morning, morning, utc))
        assertEquals("Tonight", GuideRules.dayWord(morning + 10 * 3600, morning, utc))
        assertEquals("Tomorrow", GuideRules.dayWord(morning + 86400, morning, utc))
        assertEquals("Yesterday", GuideRules.dayWord(morning - 86400, morning, utc))
        assertEquals(3, GuideRules.daysBetween(morning, morning + 3 * 86400, utc))
    }

    @Test
    fun filters() {
        val news = channel("""{"key":"tun-1","kind":"tuner","name":"News","group":"Test","favourite":true}""")
        val films = channel("""{"key":"lib-1","kind":"library","name":"Films","categories":["Movies"]}""")
        assertTrue(GuideRules.matches(news, "", "", false))
        assertTrue(GuideRules.matches(news, "tuner", "Test", true))
        assertFalse(GuideRules.matches(films, "tuner", "", false))
        assertTrue("a category counts as a group", GuideRules.matches(films, "", "Movies", false))
        assertFalse(GuideRules.matches(films, "", "", true))
        assertFalse(news.copy(favourite = false).favourite)
    }

    @Test
    fun theGuideIsAskedForAsThePageAsksForIt() {
        assertEquals(
            "/guide?from=3600&hours=8&offset=30&limit=30&kind=tuner&group=News%20%26%20Weather&favourites=1",
            GuideRules.query(3600, 30, kind = "tuner", group = "News & Weather", favourites = true),
        )
        assertEquals("tun%2F1%20x", GuideRules.pathPart("tun/1 x"))
    }

    @Test
    fun whatComesNext() {
        val c = channel("""{"key":"lib-1","name":"Films","programmes":[{"start":0,"end":100,"title":"Now"},{"start":100,"end":110,"kind":"slate","title":"Back soon"},{"start":110,"end":300,"kind":"show","title":"Later"}]}""")
        assertEquals("a slate isn't worth naming", "Later", GuideRules.next(c.programmes[0], null, c)?.title)
    }

    @Test
    fun theWholeChannelFromTheServer() {
        val c = channel(
            """{"key":"tun-1","kind":"tuner","id":1,"number":"201","name":"News","group":"Test","canRecord":true,"hd":true,"accent":"#ff8800","favourite":true,"brand":{"kind":"network","name":"News"},"security":{"state":"unknown","label":"Not checked yet","detail":"Checked when you tune in."},"alternative":{"key":"tun-2","number":"202","name":"News HD"},"notices":["No sound"],"programmes":[{"start":1,"end":2,"kind":"broadcast","title":"Bulletin","genre":"News","itemId":5,"showId":6,"season":1,"episode":2}]}""",
        )
        assertEquals(true, c.canRecord)
        assertEquals("Not checked yet", c.security?.label)
        assertEquals("202", c.alternative?.number)
        assertEquals("News", c.brand?.name)
        assertEquals("News", c.programmes.first().genre)
        val cell = GuideRules.cells(c, 1, 2, 100.0)[0]
        assertTrue(cell.isBroadcast)
        assertFalse(cell.isDim)
    }

    @Test
    fun onlyTheServerSaysWhatCanBeRecorded() {
        val unsaid = channel("""{"key":"tun-1","kind":"tuner","name":"News","programmes":[{"start":1,"end":2,"kind":"broadcast","title":"Bulletin"}]}""")
        assertNotEquals("a tuner channel without the flag isn't recordable", true, unsaid.canRecord)
        val library = channel("""{"key":"lib-1","kind":"library","name":"Films","canRecord":false}""")
        assertNotEquals(true, library.canRecord)
        val tuner = channel("""{"key":"tun-2","kind":"tuner","name":"Sport","canRecord":true}""")
        assertEquals(true, tuner.canRecord)
    }

    @Test
    fun recordingsSayWhereTheyAre() {
        val list: List<Recording> = json.decodeFromString(
            """[{"id":1,"channelId":1,"channel":"News","number":"201","title":"Bulletin","start":10,"stop":20,"status":"done","sizeBytes":1500000000,"path":"/r/a.ts"},{"id":2,"channel":"News","title":"Later","start":30,"stop":40,"status":"scheduled","sizeBytes":340000000}]""",
        )
        assertEquals("Done", list[0].statusWords)
        assertTrue(list[0].isFinished)
        assertEquals("1.5 GB", list[0].sizeWords)
        assertEquals("Scheduled", list[1].statusWords)
        assertFalse(list[1].isFinished)
        assertEquals("340 MB", list[1].sizeWords)
    }

    @Test
    fun aRemindersMoment() {
        val r = TvReminder(id = 1, channel = "lib-1", title = "Film", start = 1000, end = 2000)
        assertNull("not yet", ReminderRules.due(listOf(r), emptySet(), 900))
        assertEquals("a minute before", 1L, ReminderRules.due(listOf(r), emptySet(), 940)?.id)
        assertEquals("and for a while after it starts", 1L, ReminderRules.due(listOf(r), emptySet(), 1100)?.id)
        assertNull(ReminderRules.due(listOf(r), emptySet(), 1200))
        assertNull("once only", ReminderRules.due(listOf(r), setOf(1L), 1000))
        assertEquals(940L, ReminderRules.nextCheck(listOf(r), emptySet(), 0))
        assertNull(ReminderRules.nextCheck(listOf(r), setOf(1L), 0))
    }

    @Test
    fun theRemoteGoesRoundTheChannelsThatCanBeWatched() {
        val list = listOf(GuideChannel(key = "a"), GuideChannel(key = "b", encrypted = "Encrypted"), GuideChannel(key = "c"))
        assertEquals("c", GuideRules.channel("a", 1, list)?.key)
        assertEquals("a", GuideRules.channel("c", 1, list)?.key)
        assertEquals("c", GuideRules.channel("a", -1, list)?.key)
    }
}
