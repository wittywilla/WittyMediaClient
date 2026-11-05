package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.FoundLyrics
import com.wittywilla.wittymediaclient.net.Lyrics
import com.wittywilla.wittymediaclient.net.json
import com.wittywilla.wittymediaclient.ui.LyricFile
import com.wittywilla.wittymediaclient.ui.LyricWords
import com.wittywilla.wittymediaclient.ui.VisualizerPrefs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// The rest of the website's Now Playing (NowPlaying.tsx, LyricsPanel.tsx, lyrics.ts, Karaoke.tsx, backdrop.ts), ported
// from the iPhone's SoundLookTests so both apps say and do the same. Where the website's code says otherwise, it wins.
class NowPlayingLookTest {
    @Test
    fun theVisualizersChoicesAreReadAsTheWebsiteReadsThem() {
        val saved = VisualizerPrefs.read(json.parseToJsonElement("""{"viz":false,"style":"plasma","shuffleEvery":7,"shufflePool":"all"}"""))
        assertFalse(saved.viz)
        assertEquals("plasma", saved.style)
        assertEquals("bars", saved.nativeStyle)
        assertEquals(0, saved.shuffleEvery)
        assertEquals("all", saved.shufflePool)
        assertTrue(VisualizerPrefs.read(json.parseToJsonElement("{}")).viz)
        assertTrue(VisualizerPrefs.read(null).viz)
        // Only false turns it off; a long style is someone else's, and a known interval stays.
        val odd = VisualizerPrefs.read(json.parseToJsonElement("""{"viz":"no","style":"${"x".repeat(49)}","slow":"true","shuffleEvery":30}"""))
        assertTrue(odd.viz)
        assertEquals("bars", odd.style)
        assertFalse(odd.slow)
        assertEquals(30, odd.shuffleEvery)
        assertEquals("waves", VisualizerPrefs(style = "waves").nativeStyle)
        // What's saved reads back the same.
        val mine = VisualizerPrefs(viz = true, style = "drift", slow = true, shuffleEvery = 120, shufflePool = "mine")
        assertEquals(mine, VisualizerPrefs.read(json.parseToJsonElement(mine.toJson().toString())))
    }

    @Test
    fun theStylesChipSaysHowOften() {
        assertEquals(
            listOf("Off: stay on this one", "Every 15 seconds", "Every 30 seconds", "Every minute", "Every 2 minutes", "Every 5 minutes", "Every 10 minutes"),
            VisualizerPrefs.SHUFFLE_CHOICES.map(VisualizerPrefs::everyWords),
        )
        assertEquals("Styles", VisualizerPrefs.chipWords(0))
        assertEquals("15 seconds", VisualizerPrefs.chipWords(15))
        assertEquals("minute", VisualizerPrefs.chipWords(60))
        assertEquals("2 minutes", VisualizerPrefs.chipWords(120))
        assertEquals(listOf("Bars", "Waves", "Drift"), VisualizerPrefs.STYLES.map { it.second })
    }

    @Test
    fun theWordsFollowTheMusicWithTheListenersOwnTiming() {
        val lyrics = json.decodeFromString<Lyrics>("""{"synced":true,"lines":[{"t":1000,"text":"one"},{"t":5000,"text":""},{"t":9000,"text":"three"}],"plain":"one\nthree","offsetMs":500}""")
        assertEquals(-1, lyrics.lineAt(0.9))
        // Half a second later than the file says.
        assertEquals(-1, lyrics.lineAt(1.2))
        assertEquals(0, lyrics.lineAt(1.5))
        assertEquals(1, lyrics.lineAt(5.6))
        assertEquals(2, lyrics.lineAt(100.0))
        // A timing being tried out, before it's saved.
        assertEquals(0, lyrics.lineAt(1.2, 0.0))
        // Words that aren't timed don't follow anything.
        assertTrue(json.decodeFromString<Lyrics>("""{"synced":false,"lines":[{"t":0,"text":"a"}]}""").timed.isEmpty())
        assertEquals("On time", LyricWords.offset(0.0))
        assertEquals("+0.25 s", LyricWords.offset(250.0))
        assertEquals("-1.50 s", LyricWords.offset(-1500.0))
        assertEquals(-250.0, LyricWords.nudge(0.0, -250.0), 0.0)
        assertEquals(120_000.0, LyricWords.nudge(119_900.0, 250.0), 0.0)
        assertEquals(-120_000.0, LyricWords.nudge(-119_900.0, -250.0), 0.0)
    }

    @Test
    fun aSongWithNoWordsSaysWhy() {
        fun none(fields: String) = LyricWords.none(json.decodeFromString<Lyrics>("{$fields}"))
        assertEquals(listOf("The lyrics source couldn't be reached just now. It'll be tried again next time this song is opened."), none(""""failed":"timeout","tried":true"""))
        assertEquals(listOf("No words found for this song online. Fix lets you search under another name, or add them yourself."), none(""""tried":true,"canEdit":true"""))
        assertEquals(listOf("No words found for this song online."), none(""""tried":true"""))
        assertEquals(listOf("No words found for this song."), none(""""online":true"""))
        val owner = none(""""canEdit":true""")
        assertEquals(2, owner.size)
        assertTrue(owner[1].contains("turn on online lyrics"))
        assertEquals("Whoever runs this server can also turn on finding them online.", none("")[1])
    }

    @Test
    fun fixingTheWords() {
        assertEquals("01:02.50", LyricFile.stamp(62_500.0))
        assertEquals("00:00.00", LyricFile.stamp(-5.0))
        assertEquals(listOf("one", "two"), LyricFile.lines(" one \n\n two"))
        assertEquals("[00:01.00]a\n[00:02.34]b\n", LyricFile.lrc(listOf(1_000.0, 2_340.0), listOf("a", "b")))
        val found = json.decodeFromString<FoundLyrics>("""{"provider":"lrclib","id":"9","title":"T","artist":"A","durationSec":200,"hasSynced":true}""")
        assertEquals("Timed · same length", found.facts(201.0))
        assertEquals("Timed · 12 s different", found.facts(212.0))
        assertEquals("Timed", found.facts(null))
        assertEquals("No words", found.copy(instrumental = true).facts(0.0))
        assertEquals("Words only", found.copy(hasSynced = false, durationSec = null).facts(200.0))
        val lyrics = json.decodeFromString<Lyrics>("""{"synced":true,"lines":[{"t":1000,"text":"hi"}],"plain":"hi"}""")
        assertEquals("[00:01.00]hi", LyricFile.draft(lyrics))
        assertEquals("hi", LyricFile.tapText(lyrics))
        assertEquals("plain words", LyricFile.draft(Lyrics(plain = "plain words")))
        assertTrue("lrclib" in LyricFile.STARTS_OVER)
        assertFalse("file" in LyricFile.STARTS_OVER)
    }
}
