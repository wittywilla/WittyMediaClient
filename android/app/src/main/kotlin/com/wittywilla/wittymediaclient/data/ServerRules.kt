// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.data

import com.wittywilla.wittymediaclient.net.FoundServer
import java.util.TimeZone

// The rules for the list of servers this device remembers: which entries are one server, how a stored list is
// tidied, what goes when a server is removed, and the words for when one was last reached. Nothing here touches
// Android, so all of it is tested on its own (ServerRulesTest).

const val DAY_MS = 24L * 60 * 60 * 1000

// A remembered server is marked "Not reached lately" after this long.
const val STALE_AFTER_DAYS = 90

// The fixed choices of "Remove servers not reached for…", in days: 30 days, 90 days, 6 months, 1 year.
val STALE_CHOICES = listOf(30, 90, 180, 365)

// The same machine, whatever its address: the ID or the key it proved.
fun sameIdentity(a: SavedServer, b: SavedServer): Boolean =
    (a.serverId.isNotEmpty() && a.serverId == b.serverId) || (a.publicKey.isNotEmpty() && a.publicKey == b.publicKey)

// One entry in the list: the same machine, or the same address. The list has each address once.
fun sameServer(a: SavedServer, b: SavedServer): Boolean = a.url == b.url || sameIdentity(a, b)

// Two machines for certain: each proved a key, and they aren't the same key. What one kept is never the other's.
fun differentServer(a: SavedServer, b: SavedServer): Boolean =
    a.publicKey.isNotEmpty() && b.publicKey.isNotEmpty() && a.publicKey != b.publicKey

// The entry in a list that is this server.
fun entryFor(recent: List<SavedServer>, server: SavedServer): SavedServer? =
    recent.firstOrNull { sameServer(it, server) && !differentServer(it, server) }

private fun joined(winner: SavedServer, loser: SavedServer): SavedServer {
    val takeKey = winner.publicKey.isEmpty()
    return winner.copy(
        name = winner.name.ifEmpty { loser.name },
        serverId = winner.serverId.ifEmpty { loser.serverId },
        publicKey = if (takeKey) loser.publicKey else winner.publicKey,
        fingerprint = when {
            takeKey -> loser.fingerprint
            winner.fingerprint.isEmpty() && loser.publicKey == winner.publicKey -> loser.fingerprint
            else -> winner.fingerprint
        },
        brandLogo = winner.brandLogo.ifEmpty { loser.brandLogo },
        lastSeen = maxOf(winner.lastSeen, loser.lastSeen),
    )
}

// A tidied list, and the addresses whose kept things now belong under another address (from, to), in order.
data class Merged(val servers: List<SavedServer>, val moved: List<Pair<String, String>> = emptyList())

private fun mergeOnce(stored: List<SavedServer>): Merged {
    val out = mutableListOf<SavedServer>()
    val moved = mutableListOf<Pair<String, String>>()
    for (entry in stored) {
        if (entry.url.isEmpty()) continue
        var merged = entry
        var at = -1
        var changed = true
        // Again after each join: the joined entry may have gained an ID or a key that an earlier one has.
        while (changed) {
            changed = false
            val i = out.indexOfFirst { sameIdentity(it, merged) || (it.url == merged.url && !differentServer(it, merged)) }
            if (i >= 0) {
                // The list is the most recent first, so the one already in it wins a tie.
                val earlier = out.removeAt(i)
                val (winner, loser) = if (merged.lastSeen > earlier.lastSeen) merged to earlier else earlier to merged
                if (loser.url != winner.url) moved += loser.url to winner.url
                merged = joined(winner, loser)
                at = if (at < 0) i else minOf(at, i)
                changed = true
            }
        }
        // Another machine remembered at this very address: one address is one entry, and the more recent has it.
        val clash = out.indexOfFirst { it.url == merged.url }
        when {
            clash >= 0 && merged.lastSeen > out[clash].lastSeen -> out[clash] = merged
            clash >= 0 -> Unit
            at < 0 -> out += merged
            else -> out.add(at, merged)
        }
    }
    return Merged(out, moved)
}

// A stored list with each server in it once. Entries that are the same machine (by ID or key, whatever the address)
// or share an address become one: the most recently reached wins, and what it lacks is filled in from the others.
// Doing it again changes nothing.
fun mergeServers(stored: List<SavedServer>): Merged {
    var now = Merged(stored)
    while (true) {
        val next = mergeOnce(now.servers)
        if (next.servers == now.servers) return Merged(next.servers, now.moved)
        now = Merged(next.servers, now.moved + next.moved)
    }
}

const val MAX_RECENT = 8

// The most recent first, once per address and once per server. When it was last reached is never lost by this.
fun rememberServer(recent: List<SavedServer>, server: SavedServer): List<SavedServer> {
    val before = recent.filter { sameServer(it, server) && !differentServer(it, server) }.maxOfOrNull { it.lastSeen } ?: 0
    val others = recent.filterNot { sameServer(it, server) }
    return (listOf(server.copy(lastSeen = maxOf(server.lastSeen, before))) + others).take(MAX_RECENT)
}

// A remembered server has just proved itself again, perhaps at a new address: its entry is brought up to date where
// it is in the list. Null when it isn't remembered.
fun reachedServer(recent: List<SavedServer>, server: SavedServer, now: Long): List<SavedServer>? {
    val entry = entryFor(recent, server) ?: return null
    val updated = entry.copy(
        url = server.url,
        serverId = server.serverId.ifEmpty { entry.serverId },
        publicKey = server.publicKey.ifEmpty { entry.publicKey },
        fingerprint = server.fingerprint.ifEmpty { entry.fingerprint },
        lastSeen = maxOf(now, entry.lastSeen),
    )
    return recent.mapNotNull {
        when {
            it === entry -> updated
            // Whatever else was remembered at the address it's at now isn't there any more.
            it.url == updated.url -> null
            else -> it
        }
    }
}

// What to do with the things kept under an address when the list changes.
sealed interface DataStep {
    data class Move(val from: String, val to: String) : DataStep
    data class Wipe(val url: String) : DataStep
}

// After the list changed from `before` to `after`: what a server kept follows it to its new address, and what was
// kept for a server that is no longer in the list goes. Wipes come first, so nothing is moved in and then wiped.
fun dataSteps(before: List<SavedServer>, after: List<SavedServer>): List<DataStep> {
    val steps = before.mapNotNull { old ->
        val heir = entryFor(after, old)
        when {
            heir == null -> DataStep.Wipe(old.url)
            heir.url != old.url -> DataStep.Move(old.url, heir.url)
            else -> null
        }
    }
    return steps.filterIsInstance<DataStep.Wipe>() + steps.filterIsInstance<DataStep.Move>()
}

// The settings this app keeps for one server, each under a name that starts with a kind and the server's address.
object ServerKeys {
    const val THEME = "theme:"
    const val TOP_MENU = "topMenu:"
    const val TOKENS = "tokens:"
    private val KINDS = listOf(THEME, TOP_MENU, TOKENS)

    private fun kind(key: String): String? = KINDS.firstOrNull { key.startsWith(it) }

    fun isPerServer(key: String): Boolean = kind(key) != null

    // Kept for the server at this address? "http://a" doesn't own what "http://a:8080" kept.
    fun owns(url: String, key: String): Boolean {
        val rest = key.substring((kind(key) ?: return false).length)
        return url.isNotEmpty() && (rest == url || rest.startsWith("$url|"))
    }

    fun of(keys: Collection<String>, url: String): List<String> = keys.filter { owns(url, it) }

    // The same setting, under another address.
    fun movedTo(key: String, from: String, to: String): String {
        val kind = kind(key) ?: return key
        return kind + to + key.substring(kind.length + from.length)
    }

    // Kept for an address no remembered server has: left behind by a server that moved or was pushed out.
    fun orphans(keys: Collection<String>, urls: Collection<String>): List<String> =
        keys.filter { key -> isPerServer(key) && urls.none { owns(it, key) } }
}

// What removing a server does to what's stored: the list without it, the settings to delete, and whether the
// address in use and the sign-in go too.
data class ForgetPlan(
    val recent: List<SavedServer>,
    // Where it was in the list, so undoing puts it back there. -1 when it wasn't in it.
    val index: Int,
    val removed: List<SavedServer>,
    val urls: List<String>,
    val removeKeys: List<String>,
    val wasCurrent: Boolean,
    val forgetSignIn: Boolean,
)

// `current` is the address the app last used, `pin` the key the kept sign-in was made for (null: there is no
// sign-in, empty: it was made for a server that proved no key), `keys` every name in the settings file.
// Only what belongs to this server is in the plan: the sign-in goes only when it is for this server.
fun planForget(target: SavedServer, recent: List<SavedServer>, current: String, pin: String?, keys: Collection<String>): ForgetPlan {
    val removed = recent.filter { sameServer(it, target) && !differentServer(it, target) }
    val urls = (removed.map { it.url } + target.url).distinct().filter { it.isNotEmpty() }
    val wasCurrent = current.isNotEmpty() && current in urls
    val ownKey = (removed.map { it.publicKey } + target.publicKey).filter { it.isNotEmpty() }
    return ForgetPlan(
        recent = recent - removed.toSet(),
        index = recent.indexOfFirst { it in removed },
        removed = removed,
        urls = urls,
        removeKeys = keys.filter { key -> urls.any { ServerKeys.owns(it, key) } },
        wasCurrent = wasCurrent,
        forgetSignIn = pin != null && (wasCurrent || pin in ownKey),
    )
}

// The list with a removed server back where it was.
fun putBack(recent: List<SavedServer>, plan: ForgetPlan): List<SavedServer> {
    val without = recent.filterNot { now -> plan.removed.any { sameServer(it, now) } }
    val at = plan.index.coerceIn(0, without.size)
    return without.take(at) + plan.removed + without.drop(at)
}

// "Remove servers not reached for…": those last reached at least that many days ago. A server remembered before
// this app kept the time (0) is never chosen by this, as nobody knows how long it has been: it is shown as such,
// and goes only when the person removes it themselves or removes all.
fun notReachedFor(recent: List<SavedServer>, days: Int, now: Long): List<SavedServer> =
    recent.filter { it.lastSeen > 0 && now - it.lastSeen >= days * DAY_MS }

fun isStale(lastSeen: Long, now: Long): Boolean = lastSeen > 0 && now - lastSeen > STALE_AFTER_DAYS * DAY_MS

// When a server was last reached, by the days of the calendar where the device is.
sealed interface Reached {
    data object Unknown : Reached
    data object Today : Reached
    data object Yesterday : Reached
    data class DaysAgo(val days: Int) : Reached
}

fun reached(lastSeen: Long, now: Long, zone: TimeZone = TimeZone.getDefault()): Reached {
    if (lastSeen <= 0) return Reached.Unknown
    fun day(at: Long) = Math.floorDiv(at + zone.getOffset(at), DAY_MS)
    // A clock that was set back since: it was reached, so today.
    return when (val days = (day(now) - day(lastSeen)).coerceAtLeast(0).toInt()) {
        0 -> Reached.Today
        1 -> Reached.Yesterday
        else -> Reached.DaysAgo(days)
    }
}

// The shared words with their {name}-style blanks filled in.
fun fill(words: String?, vararg blanks: Pair<String, String>): String =
    blanks.fold(words.orEmpty()) { text, (name, value) -> text.replace("{$name}", value) }

fun reachedWords(s: Map<String, String>, lastSeen: Long, now: Long, zone: TimeZone = TimeZone.getDefault()): String =
    when (val r = reached(lastSeen, now, zone)) {
        Reached.Unknown -> s["lastReachedUnknown"].orEmpty()
        Reached.Today -> s["lastReachedToday"].orEmpty()
        Reached.Yesterday -> s["lastReachedYesterday"].orEmpty()
        is Reached.DaysAgo -> fill(s["lastReachedDays"], "days" to r.days.toString())
    }

fun shownName(server: SavedServer): String = server.name.ifEmpty { "WittyMediaServer" }

fun namesOf(servers: List<SavedServer>): String = servers.joinToString(", ") { shownName(it) }

// Where focus goes when the thing with this key is removed from a list: the next one, else the one before,
// else null, which is the screen's own way out ("Enter an address").
fun focusAfterRemoval(keys: List<String>, removed: String): String? {
    val at = keys.indexOf(removed)
    if (at < 0) return null
    return keys.getOrNull(at + 1) ?: keys.getOrNull(at - 1)
}

// Manage servers: the most recently reached first, then those whose time isn't known, in the order they were used.
fun manageOrder(recent: List<SavedServer>): List<SavedServer> =
    recent.sortedWith(compareByDescending<SavedServer> { it.lastSeen > 0 }.thenByDescending { it.lastSeen })

// The remembered server the identity warning is about: the one this address or ID was, with another key.
fun oldEntryFor(shown: SavedServer, recent: List<SavedServer>): SavedServer? =
    recent.firstOrNull {
        it.publicKey.isNotEmpty() && it.publicKey != shown.publicKey &&
            (it.url == shown.url || (it.serverId.isNotEmpty() && it.serverId == shown.serverId))
    }

// Where to try a remembered server: where it's announcing itself now, when it is, else where it was. Anyone can
// announce an ID, so its identity is still checked there before anything about it is believed or changed.
fun addressNow(server: SavedServer, found: List<FoundServer>): String =
    found.firstOrNull { server.serverId.isNotEmpty() && it.id == server.serverId }?.url ?: server.url
