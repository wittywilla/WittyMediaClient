// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.JobAnswer
import com.wittywilla.wittymediaclient.net.ServerTask
import com.wittywilla.wittymediaclient.net.SseEvent
import com.wittywilla.wittymediaclient.net.TaskList
import com.wittywilla.wittymediaclient.net.TaskLook
import com.wittywilla.wittymediaclient.net.WatchGroup
import com.wittywilla.wittymediaclient.net.WatchLook
import com.wittywilla.wittymediaclient.net.WatchOffer
import com.wittywilla.wittymediaclient.net.WhereToWatch
import com.wittywilla.wittymediaclient.net.json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// Where a title can be watched, and following a job on the server, read from what a 0.8.0 server really answers.
class MediaExtrasTest {
    private val noKey = """{"inLibrary":true,"itemId":1,"local":{"itemId":1,"title":"Metropolis Test","quality":"SD","versions":[{"itemId":1,"kind":"video","quality":"SD","width":640,"height":360,"container":"mov","videoCodec":"h264","sizeBytes":22955124}]},"region":"US","groups":[],"providers":[],"reason":"no-api-key","fetchedAt":0,"cached":false}"""

    private val listed = WhereToWatch(
        inLibrary = true,
        local = json.decodeFromString<WhereToWatch>(noKey).local!!.let { it.copy(quality = "4K", versions = it.versions + it.versions[0].copy(itemId = 9, label = "Director's cut", quality = "4K", videoCodec = "hevc", sizeBytes = 12_400_000_000)) },
        region = "NL",
        link = "https://www.themoviedb.org/movie/603-the-matrix/watch?locale=NL",
        groups = listOf(
            WatchGroup("buy", listOf(WatchOffer(2, "apple-tv", "Apple TV", "buy", 4))),
            WatchGroup("stream", listOf(WatchOffer(1899, "hbo-max", "HBO Max", "stream", 27), WatchOffer(8, "netflix", "Netflix", "stream", 0), WatchOffer(8, "netflix", "netflix ", "stream", 1))),
            WatchGroup("cinema", listOf(WatchOffer(1, "x", "A newer server's kind", "cinema", 0))),
            WatchGroup("rent", listOf(WatchOffer(2, "apple-tv", "Apple TV", "rent", 4), WatchOffer(3, "", " ", "rent", 5))),
        ),
        attribution = "Data from JustWatch.",
    )

    @Test
    fun aServerWithoutAKeyStillSaysWhatIsHere() {
        val answer = json.decodeFromString<WhereToWatch>(noKey)
        assertEquals("In your library · SD", WatchLook.hereWords(answer))
        assertEquals(emptyList<WatchLook.Section>(), WatchLook.sections(answer))
        // The only copy is the one whose page this is.
        assertEquals(emptyList<Any>(), WatchLook.otherVersions(answer, 1))
        // Why nothing is listed is the administrator's to fix, so only they are told.
        assertTrue(WatchLook.reasonWords(answer, admin = true).contains("TMDB key"))
        assertEquals("", WatchLook.reasonWords(answer, admin = false))
        assertTrue(WatchLook.hasAnything(answer, 1, admin = true))
        assertFalse(WatchLook.hasAnything(answer, 1, admin = false))
        assertNull(WatchLook.offersLink(answer))
    }

    @Test
    fun servicesAreGroupedInTheOrderPeopleLookForThem() {
        val sections = WatchLook.sections(listed)
        assertEquals(listOf("Stream", "Rent", "Buy"), sections.map { it.title })
        // By the source's own order, each service once, and one without a name not at all.
        assertEquals(listOf("Netflix", "HBO Max"), sections[0].providers.map { it.name })
        assertEquals(listOf("Apple TV"), sections[1].providers.map { it.name })
        assertEquals("", WatchLook.reasonWords(listed, admin = true))
    }

    @Test
    fun otherCopiesAreNamedByWhatSetsThemApart() {
        val others = WatchLook.otherVersions(listed, 1)
        assertEquals(listOf(9L), others.map { it.itemId })
        assertEquals("Director's cut · 4K · HEVC · 12.40 GB", WatchLook.versionWords(others[0]))
        assertEquals("In your library · 4K", WatchLook.hereWords(listed))
        // From the other copy's page, this one is the other.
        assertEquals(listOf(1L), WatchLook.otherVersions(listed, 9).map { it.itemId })
        assertEquals("Another copy · SD · H.264 · 0.02 GB", WatchLook.versionWords(WatchLook.otherVersions(listed, 9)[0]))
    }

    @Test
    fun onlyTheSourcesOwnPageIsEverOpened() {
        assertEquals("https://www.themoviedb.org/movie/603-the-matrix/watch?locale=NL", WatchLook.offersLink(listed))
        assertNull(WatchLook.offersLink(listed.copy(link = "https://evil.example/phish?locale=US")))
        assertNull(WatchLook.offersLink(listed.copy(link = "http://www.themoviedb.org/movie/603/watch")))
        assertNull(WatchLook.offersLink(listed.copy(link = "https://www.themoviedb.org.evil.example/")))
        assertNull(WatchLook.offersLink(listed.copy(link = "https://user:pw@www.themoviedb.org/")))
        assertNull(WatchLook.offersLink(listed.copy(link = "javascript:alert(1)")))
        assertNull(WatchLook.offersLink(listed.copy(link = "")))
    }

    @Test
    fun whyNothingIsListedIsSaidPlainly() {
        val none = WhereToWatch(inLibrary = true, region = "GB", attribution = "Data from JustWatch.")
        assertEquals("No streaming service lists this for GB.", WatchLook.reasonWords(none, admin = false))
        assertTrue(WatchLook.reasonWords(none.copy(reason = "unavailable"), admin = false).contains("couldn't be reached"))
        assertEquals("", WatchLook.reasonWords(none.copy(reason = "not-matched"), admin = true))
    }

    // What the server sent while intros were being looked for, and when it had finished.
    private val running = """{"id":"t6uu4cf-8","type":"intros","title":"Finding intros and credits","state":"running","phase":"Season 1","item":"Rain Show","done":1,"total":3,"unit":"episodes","percent":33.3,"startedAt":1794414708,"updatedAt":1794414708,"byId":1,"by":"admin","canPause":false,"canResume":false,"canCancel":true,"canRetry":false}"""
    private val done = """{"id":"t6uu4cf-8","type":"intros","title":"Finding intros and credits","state":"done","done":3,"total":3,"unit":"episodes","percent":100,"startedAt":1794414708,"updatedAt":1794414709,"finishedAt":1794414709,"byId":1,"by":"admin","result":"Found an intro in 3 of 3 episodes, and credits in 0.","canPause":false,"canResume":false,"canCancel":false,"canRetry":false}"""
    private val queued = """{"id":"t6uu4cf-9","type":"other","title":"Making a canvas","state":"queued","done":0,"total":0,"percent":-1,"startedAt":1794414708,"updatedAt":1794414708,"byId":1,"by":"admin","canPause":false,"canResume":false,"canCancel":true,"canRetry":false}"""

    @Test
    fun startingAJobSaysWhichTaskToFollow() {
        val started = json.decodeFromString<JobAnswer>("""{"episodes":3,"ok":true,"seasons":1,"task":"t6uu4cf-8"}""")
        assertEquals("t6uu4cf-8", started.task)
        assertEquals(3, started.episodes)
        // An instrumental that's already there has nothing to follow.
        val exists = json.decodeFromString<JobAnswer>("""{"ok":true,"exists":true,"approximate":true,"source":"approximate"}""")
        assertTrue(exists.exists)
        assertEquals("", exists.task)
    }

    @Test
    fun aTaskIsFollowedThroughTheListAndTheStream() {
        val id = "t6uu4cf-8"
        val snapshot = SseEvent("snapshot", """{"access":{"enabled":true,"visible":true,"readOnly":false},"tasks":[$running,$queued],"recent":[],"summary":{"active":1,"queued":1,"paused":0,"percent":33}}""")
        val first = TaskLook.apply(snapshot, id)!!
        assertEquals("running", first.state)
        assertTrue(first.canCancel)
        assertFalse(TaskLook.isOver(first))
        assertEquals("Season 1 · 1 of 3 episodes", TaskLook.line(first))
        assertEquals(0.333f, TaskLook.fraction(first)!!, 1e-3f)
        // A change to another task says nothing about this one.
        assertNull(TaskLook.apply(SseEvent("update", """{"tasks":[$queued],"summary":{"active":1,"queued":1,"paused":0,"percent":-1}}"""), id))
        val last = TaskLook.apply(SseEvent("update", """{"tasks":[$done],"gone":["x"],"summary":{"active":0,"queued":1,"paused":0,"percent":-1}}"""), id)!!
        assertTrue(TaskLook.isOver(last))
        assertFalse(TaskLook.failed(last))
        assertEquals("Found an intro in 3 of 3 episodes, and credits in 0.", TaskLook.line(last))
        assertEquals(1f, TaskLook.fraction(last))
        // Something that isn't the list is ignored, not a crash.
        assertNull(TaskLook.apply(SseEvent("update", "not json"), id))
        assertNull(TaskLook.apply(SseEvent("hello", "{}"), id))
    }

    @Test
    fun aFinishedTaskIsFoundAmongTheRecentOnes() {
        val list = json.decodeFromString<TaskList>("""{"access":{"enabled":true,"visible":true,"readOnly":false},"tasks":[],"recent":[$done],"summary":{"active":0,"queued":0,"paused":0,"percent":-1}}""")
        assertEquals("done", TaskLook.find(list, "t6uu4cf-8")?.state)
        assertNull(TaskLook.find(list, "gone"))
        // An account that may not see the activity gets an empty list that says so.
        val hidden = json.decodeFromString<TaskList>("""{"access":{"enabled":true,"visible":false,"readOnly":true},"tasks":[],"recent":[],"summary":{"active":0,"queued":0,"paused":0,"percent":-1}}""")
        assertFalse(hidden.access.visible)
    }

    @Test
    fun whereATaskStandsIsSaidInALine() {
        val waiting = json.decodeFromString<ServerTask>(queued)
        assertEquals("Waiting its turn", TaskLook.line(waiting))
        // No telling how far along: a bar that turns, not one that fills.
        assertNull(TaskLook.fraction(waiting))
        assertEquals("Working…", TaskLook.line(waiting.copy(state = "running")))
        assertEquals("Stopped.", TaskLook.line(waiting.copy(state = "cancelled")))
        assertTrue(TaskLook.failed(waiting.copy(state = "cancelled")))
        val failed = waiting.copy(state = "failed", error = "this song is mono, so there are no two channels to take from each other")
        assertTrue(TaskLook.failed(failed))
        assertEquals("this song is mono, so there are no two channels to take from each other", TaskLook.line(failed))
        assertEquals("It didn't work. Try again.", TaskLook.line(waiting.copy(state = "failed", fix = "Try again.")))
        assertEquals("Done.", TaskLook.line(waiting.copy(state = "done")))
    }
}
