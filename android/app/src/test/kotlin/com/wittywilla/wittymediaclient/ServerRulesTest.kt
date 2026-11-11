// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.data.DAY_MS
import com.wittywilla.wittymediaclient.data.DataStep
import com.wittywilla.wittymediaclient.data.Reached
import com.wittywilla.wittymediaclient.data.STALE_CHOICES
import com.wittywilla.wittymediaclient.data.SavedServer
import com.wittywilla.wittymediaclient.data.ServerKeys
import com.wittywilla.wittymediaclient.data.addressNow
import com.wittywilla.wittymediaclient.data.dataSteps
import com.wittywilla.wittymediaclient.data.fill
import com.wittywilla.wittymediaclient.data.focusAfterRemoval
import com.wittywilla.wittymediaclient.data.isStale
import com.wittywilla.wittymediaclient.data.manageOrder
import com.wittywilla.wittymediaclient.data.mergeServers
import com.wittywilla.wittymediaclient.data.namesOf
import com.wittywilla.wittymediaclient.data.notReachedFor
import com.wittywilla.wittymediaclient.data.oldEntryFor
import com.wittywilla.wittymediaclient.data.planForget
import com.wittywilla.wittymediaclient.data.putBack
import com.wittywilla.wittymediaclient.data.reached
import com.wittywilla.wittymediaclient.data.reachedServer
import com.wittywilla.wittymediaclient.data.reachedWords
import com.wittywilla.wittymediaclient.data.rememberServer
import com.wittywilla.wittymediaclient.net.FoundServer
import com.wittywilla.wittymediaclient.net.json
import com.wittywilla.wittymediaclient.ui.YouNative
import com.wittywilla.wittymediaclient.ui.YouOpens
import com.wittywilla.wittymediaclient.ui.YouWho
import com.wittywilla.wittymediaclient.ui.youGroups
import kotlinx.serialization.encodeToString
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.TimeZone

// The list of servers a device remembers: one entry per server, tidying a list from an older version, what
// removing a server takes with it and what it leaves, and the words for when one was last reached.
class ServerRulesTest {
    private val a = "http://192.168.1.10:9797"
    private val b = "http://192.168.1.20:9797"
    private val c = "http://192.168.1.30:9797"
    private val home = SavedServer(a, "Home", "id-home", "key-home", "AAAA-AAAA-AAAA", "3", lastSeen = 5000)
    private val cabin = SavedServer(b, "Cabin", "id-cabin", "key-cabin", "BBBB-BBBB-BBBB", "", lastSeen = 4000)

    private val words: Map<String, String> = json.decodeFromString(
        generateSequence(File("").absoluteFile) { it.parentFile }.first { File(it, "shared/data").isDirectory }
            .resolve("shared/data/strings.en.json").readText(),
    )

    // What the owner ran into: before this, a server that had been reached at two addresses, or that was first
    // added before servers proved a key, stayed in the list twice, and nothing took the old entry out.
    @Test
    fun aServerRememberedTwiceBecomesOneEntryById() {
        val moved = home.copy(url = c, name = "", brandLogo = "", lastSeen = 9000)
        val merged = mergeServers(listOf(moved, cabin, home))
        assertEquals(listOf(moved.copy(name = "Home", brandLogo = "3"), cabin), merged.servers)
        // What was kept under the old address follows it to the one it's at now.
        assertEquals(listOf(a to c), merged.moved)
    }

    @Test
    fun theSameKeyIsTheSameServerEvenWithoutAnId() {
        val byKey = SavedServer(c, "Home again", "", "key-home", lastSeen = 0)
        val merged = mergeServers(listOf(byKey, home))
        // The one reached more recently wins, and what it lacks comes from the other. The list keeps its order.
        assertEquals(listOf(home), merged.servers)
        assertEquals(listOf(c to a), merged.moved)
    }

    @Test
    fun entriesWithNoIdentityAreTheSameOnlyByAddress() {
        val old = SavedServer(a, "Old name")
        val other = SavedServer(b, "Old name")
        assertEquals(listOf(old, other), mergeServers(listOf(old, other)).servers)
        // The same address twice, one from before servers proved a key: one entry, with the key.
        val merged = mergeServers(listOf(old, home))
        assertEquals(listOf(home), merged.servers)
        assertTrue(merged.moved.isEmpty())
        // Unreadable entries with no address at all are dropped.
        assertEquals(listOf(home), mergeServers(listOf(SavedServer("", "?"), home)).servers)
    }

    @Test
    fun twoMachinesAtOneAddressLeaveTheMoreRecentAndNothingIsMixed() {
        val reinstalled = SavedServer(a, "", "id-new", "key-new", lastSeen = 9000)
        val merged = mergeServers(listOf(home, reinstalled))
        assertEquals(listOf(reinstalled), merged.servers)
        assertEquals("", merged.servers.single().name)
    }

    @Test
    fun tidyingTwiceChangesNothingAndLosesNoOtherServer() {
        val lists = listOf(
            listOf(home, cabin),
            listOf(home.copy(url = c, lastSeen = 0), cabin, home, SavedServer(c, "x")),
            listOf(SavedServer(c, "", "", "key-home"), SavedServer(b, "", "id-home"), home, cabin.copy(url = "http://10.0.0.9")),
            emptyList(),
        )
        for (list in lists) {
            val once = mergeServers(list)
            val twice = mergeServers(once.servers)
            assertEquals(once.servers, twice.servers)
            assertTrue(twice.moved.isEmpty())
            // Every server that was in the list is still in it, once.
            for (id in list.map { it.serverId }.filter { it.isNotEmpty() }.distinct()) {
                assertEquals(id, 1, once.servers.count { it.serverId == id })
            }
            assertEquals(once.servers.size, once.servers.map { it.url }.distinct().size)
        }
    }

    @Test
    fun aListFromAnOlderVersionLoadsAndIsTidied() {
        val stored = """[{"url":"$c","name":"Home","serverId":"id-home","publicKey":"key-home"},
            {"url":"$a","name":"Home","serverId":"id-home","publicKey":"key-home","fingerprint":"AAAA-AAAA-AAAA","brandLogo":"3"},
            {"url":"$b","name":"Cabin"}]"""
        val old = json.decodeFromString<List<SavedServer>>(stored)
        assertTrue(old.all { it.lastSeen == 0L })
        val merged = mergeServers(old)
        assertEquals(listOf(c, b), merged.servers.map { it.url })
        assertEquals("AAAA-AAAA-AAAA", merged.servers[0].fingerprint)
        // Neither is known to be the more recent: the address the app is using is the one that's kept.
        val inUse = mergeServers(old, current = a)
        assertEquals(listOf(a, b), inUse.servers.map { it.url })
        assertEquals(listOf(c to a), inUse.moved)
        assertEquals(inUse.servers, mergeServers(inUse.servers, current = a).servers)
        // And what's written back is read the same.
        assertEquals(merged.servers, json.decodeFromString<List<SavedServer>>(json.encodeToString(merged.servers)))
    }

    @Test
    fun rememberingKeepsWhenItWasReachedAndFollowsTheKey() {
        val again = home.copy(lastSeen = 0)
        assertEquals(listOf(home, cabin), rememberServer(listOf(cabin, home), again))
        // Found at a new address and proved by its key alone: still the one entry.
        val elsewhere = SavedServer(c, "Home", "", "key-home", lastSeen = 7000)
        assertEquals(listOf(elsewhere, cabin), rememberServer(listOf(home, cabin), elsewhere))
        // Another machine trusted at a remembered address starts with nothing of the old one's.
        val other = SavedServer(a, "New", "id-new", "key-new")
        assertEquals(listOf(other, cabin), rememberServer(listOf(home, cabin), other))
    }

    @Test
    fun reachingARememberedServerUpdatesItWhereItIs() {
        val list = listOf(cabin, home)
        val after = reachedServer(list, SavedServer(c, "", "id-home", "key-home", "AAAA-AAAA-AAAA"), 8000)!!
        assertEquals(listOf(cabin, home.copy(url = c, lastSeen = 8000)), after)
        // It took the address another remembered server had: that one isn't there any more.
        val took = reachedServer(list, SavedServer(b, "", "id-home", "key-home"), 8000)!!
        assertEquals(listOf(home.copy(url = b, lastSeen = 8000)), took)
        assertNull(reachedServer(list, SavedServer(c, "", "id-x", "key-x"), 8000))
        // A look-alike at a remembered address isn't that server.
        assertNull(reachedServer(list, SavedServer(a, "", "id-x", "key-x"), 8000))
    }

    @Test
    fun whatAServerKeptFollowsItOrGoesWithIt() {
        val movedHome = home.copy(url = c)
        assertEquals(listOf(DataStep.Move(a, c)), dataSteps(listOf(home, cabin), listOf(movedHome, cabin)))
        // Pushed out of the list, or replaced at its address by another machine: what it kept goes.
        assertEquals(listOf(DataStep.Wipe(b)), dataSteps(listOf(home, cabin), listOf(home)))
        assertEquals(listOf(DataStep.Wipe(a)), dataSteps(listOf(home), listOf(SavedServer(a, "", "id-new", "key-new"))))
        // Wipes first: Home moves to Cabin's address, and mustn't have its things wiped after they arrive.
        assertEquals(listOf(DataStep.Wipe(b), DataStep.Move(a, b)), dataSteps(listOf(home, cabin), listOf(home.copy(url = b))))
        assertTrue(dataSteps(listOf(home, cabin), listOf(cabin, home.copy(lastSeen = 9))).isEmpty())
    }

    private val keysOfBoth = listOf(
        "server", "signin", "recent",
        "theme:$a", "topMenu:$a|willow", "topMenu:$a|", "tokens:$a|dark|17",
        "theme:$b", "topMenu:$b|willow", "tokens:$b|dark|17",
    )

    @Test
    fun settingsBelongToExactlyOneAddress() {
        assertEquals(listOf("theme:$a", "topMenu:$a|willow", "topMenu:$a|", "tokens:$a|dark|17"), ServerKeys.of(keysOfBoth, a))
        // An address that another one starts with owns nothing of it.
        assertTrue(ServerKeys.of(keysOfBoth, "http://192.168.1.1").isEmpty())
        assertTrue(ServerKeys.of(listOf("theme:http://host:9797"), "http://host").isEmpty())
        assertFalse(ServerKeys.owns("", "theme:"))
        assertFalse(ServerKeys.owns(a, "server"))
        assertEquals("topMenu:$c|willow", ServerKeys.movedTo("topMenu:$a|willow", a, c))
        assertEquals("theme:$c", ServerKeys.movedTo("theme:$a", a, c))
        // Left behind by a server that changed address before this version: nobody's, so they go.
        assertEquals(listOf("theme:$b", "topMenu:$b|willow", "tokens:$b|dark|17"), ServerKeys.orphans(keysOfBoth, listOf(a)))
        assertTrue(ServerKeys.orphans(keysOfBoth, listOf(a, b)).isEmpty())
    }

    @Test
    fun forgettingOneServerLeavesExactlyTheOthers() {
        val plan = planForget(home, listOf(cabin, home), current = b, pin = "key-cabin", keys = keysOfBoth)
        assertEquals(listOf(cabin), plan.recent)
        assertEquals(1, plan.index)
        assertEquals(listOf("theme:$a", "topMenu:$a|willow", "topMenu:$a|", "tokens:$a|dark|17"), plan.removeKeys)
        assertEquals(listOf("server", "signin", "recent", "theme:$b", "topMenu:$b|willow", "tokens:$b|dark|17"), keysOfBoth - plan.removeKeys.toSet())
        // The sign-in is Cabin's, and Cabin is the one in use: both stay.
        assertFalse(plan.wasCurrent)
        assertFalse(plan.forgetSignIn)
    }

    @Test
    fun theSignInGoesOnlyWithItsOwnServer() {
        val list = listOf(cabin, home)
        // The server in use, signed in.
        planForget(home, list, current = a, pin = "key-home", keys = keysOfBoth).let {
            assertTrue(it.wasCurrent)
            assertTrue(it.forgetSignIn)
        }
        // Its sign-in was made before servers proved a key: it's the address in use that says whose it is.
        assertTrue(planForget(home, list, current = a, pin = "", keys = keysOfBoth).forgetSignIn)
        assertFalse(planForget(home, list, current = b, pin = "", keys = keysOfBoth).forgetSignIn)
        // Made for this server's key, though the address in use is out of date.
        assertTrue(planForget(home, list, current = "", pin = "key-home", keys = keysOfBoth).forgetSignIn)
        // Nobody is signed in: there's nothing to forget, or to tell the server.
        assertFalse(planForget(home, list, current = a, pin = null, keys = keysOfBoth).forgetSignIn)
        // A server that was never in the list (only the address in use) still takes its settings along.
        planForget(SavedServer(a, ""), listOf(cabin), current = a, pin = "", keys = keysOfBoth).let {
            assertEquals(listOf(cabin), it.recent)
            assertEquals(-1, it.index)
            assertEquals(4, it.removeKeys.size)
            assertTrue(it.forgetSignIn)
        }
    }

    @Test
    fun undoPutsTheServerBackWhereItWas() {
        val third = SavedServer(c, "Third", "id-3", "key-3")
        val list = listOf(cabin, home, third)
        val plan = planForget(home, list, "", null, emptyList())
        assertEquals(list, putBack(plan.recent, plan))
        // Even when the list changed meanwhile, it comes back once and nothing else is lost.
        assertEquals(listOf(third, home), putBack(listOf(third), plan))
        assertEquals(list, putBack(list, plan))
    }

    @Test
    fun removingServersNotReachedForAWhile() {
        val now = 400 * DAY_MS
        val recently = home.copy(lastSeen = now - 29 * DAY_MS)
        val monthAgo = cabin.copy(lastSeen = now - 30 * DAY_MS)
        val longAgo = SavedServer(c, "Old", "id-old", "key-old", lastSeen = now - 370 * DAY_MS)
        // Remembered before the app kept the time: nobody knows how long it has been, so it's never chosen.
        val unknown = SavedServer("http://10.0.0.9", "Unknown")
        val list = listOf(recently, monthAgo, longAgo, unknown)
        assertEquals(listOf(30, 90, 180, 365), STALE_CHOICES)
        assertEquals(listOf(monthAgo, longAgo), notReachedFor(list, 30, now))
        assertEquals(listOf(longAgo), notReachedFor(list, 90, now))
        assertEquals(listOf(longAgo), notReachedFor(list, 365, now))
        assertTrue(notReachedFor(listOf(recently, unknown), 30, now).isEmpty())
        // The mark on a card: known, and more than 90 days ago.
        assertTrue(isStale(now - 91 * DAY_MS, now))
        assertFalse(isStale(now - 90 * DAY_MS, now))
        assertFalse(isStale(0, now))
    }

    @Test
    fun whenAServerWasLastReachedInWords() {
        val utc = TimeZone.getTimeZone("UTC")
        val noon = 20_000 * DAY_MS + 12 * 60 * 60 * 1000
        assertEquals(Reached.Unknown, reached(0, noon, utc))
        assertEquals(Reached.Today, reached(noon - 11 * 60 * 60 * 1000, noon, utc))
        // Thirteen hours ago was yesterday by the calendar, though less than a day.
        assertEquals(Reached.Yesterday, reached(noon - 13 * 60 * 60 * 1000, noon, utc))
        assertEquals(Reached.DaysAgo(2), reached(noon - 2 * DAY_MS, noon, utc))
        // The same moments are another day somewhere else.
        assertEquals(Reached.Today, reached(noon - 13 * 60 * 60 * 1000, noon, TimeZone.getTimeZone("GMT+02:00")))
        assertEquals(Reached.Yesterday, reached(noon - 11 * 60 * 60 * 1000, noon, TimeZone.getTimeZone("GMT+12:00")))
        // A clock set back since then.
        assertEquals(Reached.Today, reached(noon + 3 * DAY_MS, noon, utc))

        assertEquals("Reached today", reachedWords(words, noon, noon, utc))
        assertEquals("Reached yesterday", reachedWords(words, noon - DAY_MS, noon, utc))
        assertEquals("Reached 12 days ago", reachedWords(words, noon - 12 * DAY_MS, noon, utc))
        assertEquals("Not reached since this app was updated", reachedWords(words, 0, noon, utc))
    }

    @Test
    fun theSharedWordsAreThereAndFilledIn() {
        val needed = listOf(
            "manageServers", "manageServersHint", "rowServers", "editServers", "editServersDone", "serverOptions", "removeServer",
            "removeServerNamed", "remove", "removeConfirmTitle", "removeConfirmBody", "removeConfirmInUse", "removedServer", "undo",
            "removeUndone", "removeAllServers", "removeAllTitle", "removeAllBody", "removedCount", "removeOldServers", "removeOldTitle",
            "removeOldHint", "removeOldNone", "removeOldConfirmTitle", "removeOldConfirmBody", "lastReachedToday", "lastReachedYesterday",
            "lastReachedDays", "lastReachedUnknown", "staleServer", "noServersRemembered", "reinstalledHint", "removeOldOne", "removedOldOne",
        ) + STALE_CHOICES.map { "staleDays$it" }
        assertEquals(emptyList<String>(), needed.filter { words[it].isNullOrEmpty() })
        assertEquals("Remove Home?", fill(words["removeConfirmTitle"], "name" to "Home"))
        val body = fill(words["removeOldConfirmBody"], "period" to words.getValue("staleDays90"), "count" to "2", "names" to namesOf(listOf(home, SavedServer(c, ""))))
        assertTrue(body.startsWith("Not reached for 90 days or more (2): Home, WittyMediaServer."))
        assertFalse(fill(words["removeConfirmBody"], "name" to "Home", "address" to a).contains("{"))
        assertFalse(fill(words["removeAllBody"], "count" to "2", "names" to "Home, Cabin").contains("{"))
        assertEquals("", fill(null, "name" to "Home"))
    }

    @Test
    fun focusAfterARemovalIsNeverNowhere() {
        val cards = listOf("found-1", "recent-a", "recent-b", "recent-c")
        // The next card, else the one before, else none: the caller then gives it to Enter an address.
        assertEquals("recent-b", focusAfterRemoval(cards, "recent-a"))
        assertEquals("recent-b", focusAfterRemoval(cards, "recent-c"))
        assertEquals("found-1", focusAfterRemoval(listOf("found-1", "recent-a"), "recent-a"))
        assertNull(focusAfterRemoval(listOf("recent-a"), "recent-a"))
        assertNull(focusAfterRemoval(cards, "recent-x"))
    }

    @Test
    fun manageServersListsTheMostRecentlyReachedFirst() {
        val unknown = SavedServer(c, "Unknown")
        val other = SavedServer("http://10.0.0.9", "Also unknown")
        assertEquals(listOf(home, cabin, unknown, other), manageOrder(listOf(unknown, cabin, other, home)))
    }

    @Test
    fun theWarningKnowsWhichRememberedServerItIsAbout() {
        // Another key at the address Home was at, or announcing Home's ID: Home is the old one.
        assertEquals(home, oldEntryFor(SavedServer(a, "", "id-new", "key-new"), listOf(cabin, home)))
        assertEquals(home, oldEntryFor(SavedServer(c, "", "id-home", "key-new"), listOf(cabin, home)))
        assertNull(oldEntryFor(SavedServer(c, "", "id-new", "key-new"), listOf(cabin, home)))
        assertNull(oldEntryFor(home, listOf(cabin, home)))
    }

    @Test
    fun aRememberedServerIsTriedWhereItAnnouncesItselfNow() {
        val found = listOf(FoundServer("id-home", "Home", c), FoundServer("id-other", "Other", b))
        assertEquals(c, addressNow(home, found))
        assertEquals(b, addressNow(cabin, emptyList()))
        // With no ID there's nothing to know it by: an announcement with an empty ID isn't it.
        assertEquals(a, addressNow(SavedServer(a, "Old"), listOf(FoundServer("", "x", c))))
    }

    @Test
    fun youHasTheServersOnThisDeviceForEveryone() {
        for (tv in listOf(false, true)) {
            val who = YouWho(admin = false, adult = false, hasGames = false, twoStepAvailable = false, onTv = tv)
            val device = youGroups(who).first { it.key == "groupDevice" }.rows
            assertEquals(YouOpens.Native(YouNative.Servers), device.single { it.key == "rowServers" }.opens)
            assertEquals("rowTheme", device.first().key)
        }
    }
}
