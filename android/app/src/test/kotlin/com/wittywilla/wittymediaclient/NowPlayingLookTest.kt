package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.FoundLyrics
import com.wittywilla.wittymediaclient.net.LyricLine
import com.wittywilla.wittymediaclient.net.LyricWord
import com.wittywilla.wittymediaclient.net.Lyrics
import com.wittywilla.wittymediaclient.net.json
import com.wittywilla.wittymediaclient.player.nearlyMono
import com.wittywilla.wittymediaclient.player.pitchFor
import com.wittywilla.wittymediaclient.ui.Karaoke
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

    @Test
    fun karaokeFillsWordsAndCountsIn() {
        val words = Karaoke.words(LyricLine(t = 10_000.0, text = "la la la"), 14_000.0)
        assertEquals(listOf("la ", "la ", "la"), words.map { it.text })
        assertEquals(10_000.0, words.first().from, 0.0)
        // Short lines are sung over at least 1.2 s.
        assertEquals(11_200.0, words.last().to, 0.01)
        assertEquals(0.0, Karaoke.fill(words[0], 9_000.0), 0.0)
        assertEquals(1.0, Karaoke.fill(words[0], 20_000.0), 0.0)
        // "la " is three of the line's eight letters: 450 ms.
        assertEquals(0.5, Karaoke.fill(words[0], 10_225.0), 0.0001)
        // A long line at 95 ms a letter, but no longer than it has.
        val long = Karaoke.words(LyricLine(t = 0.0, text = "x".repeat(30)), 2_000.0)
        assertEquals(2_000.0, long.last().to, 0.01)
        val timed = LyricLine(t = 0.0, text = "a b", words = listOf(LyricWord(0.0, "a "), LyricWord(400.0, "b")))
        assertEquals(listOf(400.0, 1_900.0), Karaoke.words(timed, 3_000.0).map { it.to })
        // The last word stops at the line's own end, when it has one.
        assertEquals(1_000.0, Karaoke.words(timed.copy(end = 1_000.0), 3_000.0).last().to, 0.0)

        val lines = listOf(LyricLine(t = 1_000.0, end = 2_000.0, text = "one"), LyricLine(t = 9_000.0, text = "two"), LyricLine(t = 10_000.0, text = "three"))
        assertEquals(3, Karaoke.countIn(lines, 6_500.0))
        assertEquals(1, Karaoke.countIn(lines, 8_100.0))
        assertEquals(0, Karaoke.countIn(lines, 9_500.0))
        assertEquals(1, Karaoke.countIn(lines, 0.0))
        assertEquals(0, Karaoke.countIn(lines, 5_000.0))
        assertEquals(0, Karaoke.countIn(lines, 11_000.0))
        assertEquals("Key +2", Karaoke.keyWords(2.0))
        assertEquals("Key -6", Karaoke.keyWords(-6.0))
        assertEquals("Key 0", Karaoke.keyWords(0.0))
        assertEquals("Words on time", Karaoke.timingWords(0.0))
        assertEquals("Words -0.3 s", Karaoke.timingWords(-300.0))
        assertEquals("Words +1.2 s", Karaoke.timingWords(1_200.0))
        assertEquals(listOf("Voice on", "Voice lower", "Voice lowest"), Karaoke.VOCALS.map { it.second })
        assertEquals(listOf(0.0, 0.6, 1.0), Karaoke.VOCALS.map { it.first })
    }

    @Test
    fun karaokeSaysWhatItsDoing() {
        assertEquals("This recording is close to mono, so there's no way to separate the voice from it.", Karaoke.note(true, 1.0, 2.0, true, false))
        assertTrue(Karaoke.note(false, 0.6, 2.0, true, false).startsWith("The voice is turned down"))
        assertEquals("A changed key can warble a little on long notes.", Karaoke.note(false, 0.0, -1.0, true, false))
        assertEquals("Lines are timed; the fill within a line is an estimate.", Karaoke.note(false, 0.0, 0.0, true, false))
        assertEquals("", Karaoke.note(false, 0.0, 0.0, true, true))
        assertEquals("", Karaoke.note(false, 0.0, 0.0, false, false))
        // The key is the player's pitch: an octave doubles it.
        assertEquals(2f, pitchFor(12.0), 0.0001f)
        assertEquals(1f, pitchFor(0.0), 0.0f)
        assertEquals(0.7937f, pitchFor(-4.0), 0.0001f)
        // Nothing off-centre is mono; silence can't tell.
        assertEquals(true, nearlyMono(0.0001, 1.0))
        assertEquals(false, nearlyMono(0.5, 1.0))
        assertEquals(null, nearlyMono(0.0, 0.0))
    }
}
