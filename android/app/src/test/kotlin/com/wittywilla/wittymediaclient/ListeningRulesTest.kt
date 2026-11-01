package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.Item
import com.wittywilla.wittymediaclient.net.Progress
import com.wittywilla.wittymediaclient.player.Report
import com.wittywilla.wittymediaclient.player.Start
import com.wittywilla.wittymediaclient.player.convertedPosition
import com.wittywilla.wittymediaclient.player.convertedStartSec
import com.wittywilla.wittymediaclient.player.hasPlaceToResume
import com.wittywilla.wittymediaclient.player.nextSpeed
import com.wittywilla.wittymediaclient.player.placeOn
import com.wittywilla.wittymediaclient.player.playOrder
import com.wittywilla.wittymediaclient.player.reportOn
import com.wittywilla.wittymediaclient.player.speedWords
import com.wittywilla.wittymediaclient.player.whereToStart
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ListeningRulesTest {
    private fun track(id: Long, at: Double = 0.0, done: Boolean = false, started: Boolean = at > 0 || done) =
        Item(id = id, kind = "audio", runtimeSec = 100.0, progress = if (started) Progress(positionSec = at, durationSec = 100.0, watched = done) else null)

    @Test
    fun songsAlwaysStartAtTheBeginning() {
        val album = listOf(track(1, done = true), track(2, at = 40.0), track(3))
        assertEquals(Start(0), whereToStart(album, keepsPlace = false))
        assertEquals(0.0, placeOn(album[1], keepsPlace = false), 0.0)
        assertFalse(hasPlaceToResume(album, keepsPlace = false))
    }

    @Test
    fun aBookGoesOnFromTheChapterInTheMiddle() {
        val book = listOf(track(1, done = true), track(2, at = 40.0), track(3))
        assertEquals(Start(1, 40.0), whereToStart(book, keepsPlace = true))
        assertTrue(hasPlaceToResume(book, keepsPlace = true))
    }

    @Test
    fun aBookGoesOnFromTheFirstNotFinished() {
        val book = listOf(track(1, done = true), track(2, done = true), track(3))
        assertEquals(Start(2), whereToStart(book, keepsPlace = true))
        assertTrue(hasPlaceToResume(book, keepsPlace = true))
    }

    @Test
    fun aFinishedOrUnstartedBookStartsAtTheBeginning() {
        val finished = listOf(track(1, done = true), track(2, done = true))
        assertEquals(Start(0), whereToStart(finished, keepsPlace = true))
        assertFalse(hasPlaceToResume(finished, keepsPlace = true))
        val fresh = listOf(track(1), track(2))
        assertEquals(Start(0), whereToStart(fresh, keepsPlace = true))
        assertFalse(hasPlaceToResume(fresh, keepsPlace = true))
    }

    @Test
    fun anEmptyAlbumDoesNotFail() {
        assertEquals(Start(0), whereToStart(emptyList(), keepsPlace = true))
        assertFalse(hasPlaceToResume(emptyList(), keepsPlace = true))
    }

    @Test
    fun aBookKeepsItsPlaceAndNotInTheFirstSeconds() {
        assertEquals(Report.Place(42.0, 100.0), reportOn(true, 42.0, 100.0, 42.0, reachedEnd = false))
        assertNull(reportOn(true, 3.0, 100.0, 3.0, reachedEnd = false))
    }

    @Test
    fun reachingTheEndMarksItAsFinished() {
        assertEquals(Report.Place(100.0, 100.0), reportOn(true, 99.2, 100.0, 99.0, reachedEnd = true))
    }

    @Test
    fun aTrackWithNoLengthKeepsNoPlace() {
        assertNull(reportOn(true, 42.0, 0.0, 42.0, reachedEnd = false))
    }

    @Test
    fun aSongOnlyCountsOnceHeard() {
        assertEquals(Report.Listened(12.0), reportOn(false, 90.0, 100.0, 12.0, reachedEnd = false))
        assertNull(reportOn(false, 90.0, 100.0, 2.0, reachedEnd = false))
    }

    @Test
    fun speedsGoRoundAndComeBack() {
        val seen = generateSequence(1f) { nextSpeed(it) }.take(7).toList()
        assertEquals(listOf(1f, 1.25f, 1.5f, 1.75f, 2f, 0.75f, 1f), seen)
        assertEquals(1.25f, nextSpeed(1.1f), 0f)
    }

    @Test
    fun speedsAreSaidWithoutExtraNoughts() {
        assertEquals("1×", speedWords(1f))
        assertEquals("1.5×", speedWords(1.5f))
        assertEquals("1.25×", speedWords(1.25f))
    }

    @Test
    fun aQueueListsWhatTheShuffleWillPlay() {
        val next = mapOf(2 to 0, 0 to 3, 3 to 1, 1 to -1)
        assertEquals(listOf(2, 0, 3, 1), playOrder(2, 4) { next.getValue(it) })
    }

    @Test
    fun aQueueListStopsEvenIfTheAnswersGoRound() {
        assertEquals(listOf(0, 1, 0), playOrder(0, 3) { if (it == 0) 1 else 0 })
        assertEquals(emptyList<Int>(), playOrder(-1, 0) { 0 })
    }

    @Test
    fun aPlaceInAConversionComesBackAsTheSameTime() {
        for (sec in listOf(0L, 1L, 90L, 3_600L, 36_000L)) {
            assertEquals(sec.toDouble(), convertedStartSec(convertedPosition(sec * 1_000_000)), 0.001)
        }
    }
}
