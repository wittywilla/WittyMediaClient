package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.json
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
}
