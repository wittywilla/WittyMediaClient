// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.DiscAnalysis
import com.wittywilla.wittymediaclient.net.DiscEpisode
import com.wittywilla.wittymediaclient.net.DiscVersion
import com.wittywilla.wittymediaclient.net.DiscWords
import com.wittywilla.wittymediaclient.net.json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

// "Why this title" on a disc's page (net/DiscRanking.kt), worded as the server's web page words it.
class DiscWordsTest {
    @Test
    fun theAnalysisIsReadAndSaid() {
        val a = json.decodeFromString(
            DiscAnalysis.serializer(),
            """{"kind":"bluray","ranked":true,"main":800,"engineMain":800,"chosen":null,"canChoose":true,"protected":false,
               "rank":{"main":800,"confidence":0.91,"level":"high","why":"The longest playlist that isn't a play-all.","reasons":["no loops"],
               "versions":[{"kind":"edition","ttn":801,"durationSec":7500,"label":"Director's cut"},{"kind":"cut","ttn":800,"durationSec":7000,"main":true}],
               "candidates":[{"ttn":800,"durationSec":7000,"class":"feature"},{"ttn":5,"durationSec":120,"class":"extra"}],"newField":1}}""",
        )
        assertEquals("The longest playlist that isn't a play-all.", DiscWords.headline(a))
        assertEquals("High confidence", DiscWords.level(a.rank!!.level, a.rank!!.confidence))
        assertEquals("91% sure", DiscWords.sure(0.91))
        assertEquals("Playlist 801", DiscWords.name(a.kind, 801))
        assertEquals("2:05:00", DiscWords.clock(7500.0))
        assertEquals("/play/7?mode=title&ttn=801&angle=2", DiscWords.versionPath(7, DiscVersion(ttn = 801, angle = 2)))
        assertEquals("/play/7?mode=title&episode=3", DiscWords.episodePath(7, DiscEpisode(index = 3)))
    }

    @Test
    fun aChoiceAndAnOldModuleAreSaidSo() {
        val chosen = json.decodeFromString(DiscAnalysis.serializer(), """{"kind":"dvd","ranked":true,"main":3,"engineMain":1,"chosen":{"ttn":3},"chosenBy":"admin","rank":{"main":1}}""")
        assertEquals("Title 3 was chosen as this disc's film by admin; the engine picks Title 1.", DiscWords.headline(chosen))
        val old = json.decodeFromString(DiscAnalysis.serializer(), """{"kind":"dvd","ranked":false,"main":1}""")
        assertTrue(DiscWords.headline(old).startsWith("The disc module in use is from before ranking"))
        assertEquals("""{"ttn":4}""", DiscWords.choiceBody(4))
    }
}
