// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import kotlinx.serialization.Serializable
import java.util.Locale

// Which channels the guide shows, in which order (the server's `tv-sets`), how the guide is paged (`tv-guide-paging`),
// finding a channel by its number, watching a programme from its start (`tv-catchup`) and a recording's options
// (`tv-dvr-rules-2`): the rules alone, so GuideSetsTest holds them without a device. The screens are in tv/.

// One set from GET /tv-sets. `id` is what the guide is asked for with `set=`: `all`, `fav`, `set:7`, `src:lib`,
// `grp:News`. `count` is how many of its channels this profile may see.
@Serializable
data class ChannelSet(
    val id: String = "",
    // `all`, `favourites`, `custom`, `source` or `group`.
    val kind: String = "",
    val name: String = "",
    val count: Int = 0,
    val shared: Boolean = false,
    val editable: Boolean = false,
    val mine: Boolean = false,
    // A source's kind of tuner (`iptv`, `xtream`, `hdhomerun`…), for saying what it is.
    val driver: String? = null,
) {
    val isCustom: Boolean get() = kind == "custom"
}

@Serializable
data class ChannelSets(val sets: List<ChannelSet>? = null, val canShare: Boolean = false)

// One custom set as GET /tv-sets/{id} answers: its channels' keys in its own order.
@Serializable
data class ChannelSetDetail(
    val id: String = "",
    val name: String = "",
    val shared: Boolean = false,
    val editable: Boolean = false,
    val channels: List<String>? = null,
)

// A heading of the set picker and the sets under it.
data class SetSection(val title: String, val sets: List<ChannelSet>)

object SetRules {
    const val ALL = "all"
    const val NAME_MAX = 40
    const val MAX_SETS = 50
    const val MAX_CHANNELS = 5000

    // The picker's sections, in the server's order within each: All and Favourites, the account's own sets, the
    // shared ones made by someone else, the sources and the groups. An empty section isn't shown.
    fun sections(sets: List<ChannelSet>): List<SetSection> {
        val top = sets.filter { it.kind == "all" || it.kind == "favourites" }
        val mine = sets.filter { it.isCustom && it.mine }
        val shared = sets.filter { it.isCustom && !it.mine }
        val sources = sets.filter { it.kind == "source" }
        val groups = sets.filter { it.kind == "group" }
        return listOf(
            SetSection("All & Favourites", top),
            SetSection("My sets", mine),
            SetSection("Shared", shared),
            SetSection("Sources", sources),
            SetSection("Groups", groups),
        ).filter { it.sets.isNotEmpty() }
    }

    // The sets whose name has the words in it, whatever their case. All is always kept, so there is a way back.
    fun search(sets: List<ChannelSet>, words: String): List<ChannelSet> {
        val w = words.trim().lowercase(Locale.ROOT)
        if (w.isEmpty()) return sets
        return sets.filter { it.id == ALL || it.name.lowercase(Locale.ROOT).contains(w) }
    }

    // The set to show: the one this device remembers for this server and account while the server still has it, else
    // All. Before the sets are known (null), what was remembered stands, so the first page isn't asked for twice.
    fun remembered(saved: String?, sets: List<ChannelSet>?): String {
        val s = saved?.trim().orEmpty()
        if (s.isEmpty()) return ALL
        if (sets == null) return s
        return if (sets.any { it.id == s }) s else ALL
    }

    // Where this device keeps the chosen set: one for each server and account, so another person on the same TV, or
    // the same person on another server, has their own.
    fun prefKey(server: String, account: Long): String = "wms.tv.set.${server.trim().lowercase(Locale.ROOT)}.$account"

    // The set before or after this one in the picker's order, going round at the ends, for a remote's coloured keys.
    fun cycle(current: String, sets: List<ChannelSet>, step: Int): String? {
        if (sets.isEmpty()) return null
        val ordered = sections(sets).flatMap { it.sets }
        if (ordered.isEmpty()) return null
        val at = ordered.indexOfFirst { it.id == current }
        if (at < 0) return ordered[0].id
        val n = ordered.size
        return ordered[((at + step) % n + n) % n].id
    }

    // The number of a custom set, for its address: `set:7` is /tv-sets/7.
    fun number(id: String): String? = id.removePrefix("set:").takeIf { id.startsWith("set:") && it.isNotEmpty() && it.all(Char::isDigit) }

    // What's wrong with a name for a set, or null. Names are unique for each account, whatever their case; `except` is
    // the set being renamed, which may keep its own name.
    fun nameProblem(name: String, sets: List<ChannelSet>, except: String? = null): String? {
        val n = name.trim()
        if (n.isEmpty()) return "Give the set a name."
        if (n.length > NAME_MAX) return "A set's name can be at most $NAME_MAX characters."
        val clash = sets.any { it.isCustom && it.mine && it.id != except && it.name.trim().equals(n, ignoreCase = true) }
        return if (clash) "You already have a set called $n." else null
    }

    // Whether this account may make another set.
    fun canMakeAnother(sets: List<ChannelSet>): Boolean = sets.count { it.isCustom && it.mine } < MAX_SETS

    // Something in a list one place up (-1) or down (+1); the list as it was when it can't go further.
    fun <T> move(list: List<T>, index: Int, by: Int): List<T> {
        val to = index + by
        if (index !in list.indices || to !in list.indices || by == 0) return list
        val out = list.toMutableList()
        val item = out.removeAt(index)
        out.add(to, item)
        return out
    }

    // The order of the custom sets after one has moved, as PUT /tv-sets/order takes it: every custom set this account
    // sees, its own and the shared ones.
    fun orderAfterMove(sets: List<ChannelSet>, id: String, by: Int): List<String> {
        val ids = sets.filter { it.isCustom }.map { it.id }
        return move(ids, ids.indexOf(id), by)
    }

    // A channel ticked or unticked in the picker: a new one goes at the end, so the order chosen so far stays.
    fun toggle(chosen: List<String>, key: String): List<String> =
        if (key in chosen) chosen - key else if (chosen.size >= MAX_CHANNELS) chosen else chosen + key

    // What changed between a set's channels and what's chosen now, for the smallest request.
    fun changes(before: List<String>, after: List<String>): Pair<List<String>, List<String>> {
        val b = before.toSet()
        val a = after.toSet()
        return after.filter { it !in b } to before.filter { it !in a }
    }

    // "Kids · 30 channels", as a set is named in the picker.
    fun countWords(count: Int, locale: Locale = Locale.getDefault()): String =
        if (count == 1) "1 channel" else "${GuidePaging.number(count, locale)} channels"
}

// The guide a page at a time. A page size of 0 is All: one long list, its rows asked for in pieces as they come on
// screen.
object GuidePaging {
    val SIZES = listOf(25, 50, 75, 100, 0)
    const val ALL = 0
    const val DEFAULT = ALL

    // What All asks for at a time: the server sends at most 200 rows with programmes.
    const val CHUNK = 100

    // How many pieces either side of what's on screen are kept: a long scroll through thousands of channels doesn't
    // keep every row it went past.
    const val KEEP = 3

    // A remembered size the app no longer offers is All.
    fun size(saved: Int): Int = if (saved in SIZES) saved else DEFAULT

    fun label(size: Int): String = if (size == ALL) "All" else size.toString()

    // The first row of the page that holds a row.
    fun pageStart(row: Int, size: Int): Int = if (size <= 0) 0 else maxOf(0, row) - maxOf(0, row) % size

    // How many rows a page shows: the page's size, or fewer on the last.
    fun rowsOn(offset: Int, size: Int, total: Int): Int = if (size <= 0) total else maxOf(0, minOf(size, total - offset))

    fun hasNext(offset: Int, size: Int, total: Int): Boolean = size > 0 && offset + size < total
    fun hasPrevious(offset: Int, size: Int): Boolean = size > 0 && offset > 0

    fun next(offset: Int, size: Int, total: Int): Int = if (hasNext(offset, size, total)) offset + size else offset
    fun previous(offset: Int, size: Int): Int = if (hasPrevious(offset, size)) maxOf(0, offset - size) else offset

    // A page that was showing, held to the rows there are now (a set that has got shorter).
    fun clamp(offset: Int, size: Int, total: Int): Int {
        if (size <= 0 || total <= 0) return 0
        return pageStart(minOf(offset, total - 1), size)
    }

    // "51–100 of 10,423", as the page says where it is.
    fun rangeWords(offset: Int, size: Int, total: Int, locale: Locale = Locale.getDefault()): String {
        if (total <= 0) return "No channels"
        if (size <= 0) return if (total == 1) "1 channel" else "${number(total, locale)} channels"
        val last = offset + rowsOn(offset, size, total)
        return "${number(offset + 1, locale)}–${number(last, locale)} of ${number(total, locale)}"
    }

    fun number(n: Int, locale: Locale = Locale.getDefault()): String = String.format(locale, "%,d", n)

    // The piece a row is asked for in: the page itself when paged, else a CHUNK (or the older server's 30).
    fun chunk(size: Int, paging: Boolean): Int = if (size > 0) size else if (paging) CHUNK else GuideRules.PAGE

    // The pieces to keep while these rows are on screen; everything else can go and be asked for again.
    fun keep(visible: kotlin.collections.Collection<Int>, chunk: Int, margin: Int = KEEP): IntRange {
        if (visible.isEmpty() || chunk <= 0) return IntRange.EMPTY
        val low = visible.min() / chunk - margin
        val high = visible.max() / chunk + margin
        return maxOf(0, low)..high
    }

    // Whether a channel matches what was typed, as the server's `q` does: its number starts with it, or its name has it.
    fun matches(channel: GuideChannel, q: String): Boolean {
        val w = q.trim().lowercase(Locale.ROOT)
        if (w.isEmpty()) return true
        return channel.number.lowercase(Locale.ROOT).startsWith(w) || channel.name.lowercase(Locale.ROOT).contains(w)
    }

    // The query for a page of the guide on a server with sets and paging: a stretch of the schedule, a page of a set's
    // channels, what was typed to narrow them, and the channel to find.
    fun query(from: Long, offset: Int, limit: Int, set: String?, q: String = "", locate: String = ""): String {
        val b = StringBuilder("/guide?from=$from&hours=${GuideRules.FETCH_HOURS}&offset=${maxOf(0, offset)}&limit=${limit.coerceIn(1, 200)}")
        if (!set.isNullOrEmpty()) b.append("&set=").append(GuideRules.queryValue(set))
        if (q.isNotBlank()) b.append("&q=").append(GuideRules.queryValue(q.trim()))
        if (locate.isNotBlank()) b.append("&locate=").append(GuideRules.queryValue(locate.trim()))
        return b.toString()
    }

    // Every channel of a set with only what dialling and the picker need.
    fun liteQuery(set: String?, q: String = "", limit: Int = 20000, locate: String = ""): String {
        val b = StringBuilder("/guide?list=1&lite=1&limit=${limit.coerceIn(1, 20000)}")
        if (!set.isNullOrEmpty()) b.append("&set=").append(GuideRules.queryValue(set))
        if (q.isNotBlank()) b.append("&q=").append(GuideRules.queryValue(q.trim()))
        if (locate.isNotBlank()) b.append("&locate=").append(GuideRules.queryValue(locate.trim()))
        return b.toString()
    }
}

// Typing a channel's number on a remote, and finding it.
object DialRules {
    const val MAX_DIGITS = 6

    // How long after the last digit the number is gone to.
    const val WAIT_MS = 1800L

    // The digits typed so far with one more; a number already as long as any can be starts again.
    fun append(typed: String, digit: Char): String {
        if (!digit.isDigit()) return typed
        return if (typed.length >= MAX_DIGITS) digit.toString() else typed + digit
    }

    // Where a channel is in a list the app already has: its number exactly, else a number that is the same once
    // leading zeros go, else its key. -1 when it isn't there.
    fun locate(channels: List<GuideChannel>, wanted: String): Int {
        val w = wanted.trim()
        if (w.isEmpty()) return -1
        channels.indexOfFirst { it.number == w }.takeIf { it >= 0 }?.let { return it }
        val bare = w.trimStart('0').ifEmpty { "0" }
        channels.indexOfFirst { it.number.trimStart('0').ifEmpty { "0" } == bare }.takeIf { it >= 0 }?.let { return it }
        return channels.indexOfFirst { it.key == w }
    }
}

// What finding a channel came to: in the set on screen, only in All (so the person is asked whether to switch), or
// nowhere.
sealed interface Located {
    data class Here(val row: Int) : Located
    data class InAll(val row: Int) : Located
    data object Nowhere : Located
}

object LocateRules {
    // `inSet` is the row in what's showing (-1 when absent); `inAll` the row in All, when it was looked for there.
    // Showing All with nothing typed to narrow it, a miss is a miss.
    fun decide(inSet: Int, inAll: Int?, showingAll: Boolean): Located = when {
        inSet >= 0 -> Located.Here(inSet)
        showingAll -> Located.Nowhere
        inAll != null && inAll >= 0 -> Located.InAll(inAll)
        else -> Located.Nowhere
    }
}

// Watching a programme from its start, on a channel whose source keeps an archive.
object CatchupRules {
    // A programme that has started, on a channel that keeps the last `catchupDays`, while its start is still kept.
    fun canWatchFromStart(channel: GuideChannel, programme: GuideProgramme?, now: Long): Boolean {
        val days = channel.catchupDays ?: 0
        if (days <= 0 || programme == null || !channel.canTune) return false
        if (programme.kind == "slate" || programme.kind == "none" || programme.end <= programme.start) return false
        return programme.start <= now && now - programme.start <= days * 86400L
    }

    fun path(key: String, programme: GuideProgramme, viewer: String): String =
        "/tv/${GuideRules.pathPart(key)}/catchup?start=${programme.start}&end=${programme.end}&viewer=${GuideRules.pathPart(viewer)}"
}

// A recording's options, as POST /recordings and /recording-rules take them on a server with `tv-dvr-rules-2`.
object DvrRules {
    // Minutes before and after, as the person chooses them.
    val PADDING = listOf(0, 1, 2, 5, 10, 15, 30, 60)
    const val PAD_MAX = 60

    // How many of a series' recordings are kept: 0 keeps every one.
    val KEEP = listOf(0, 1, 2, 3, 5, 10, 20)

    fun pad(minutes: Int): Int = minutes.coerceIn(0, PAD_MAX)
    fun keep(n: Int): Int = maxOf(0, n)

    fun padWords(minutes: Int): String = if (minutes <= 0) "None" else "$minutes min"
    fun keepWords(n: Int): String = if (n <= 0) "Keep all" else if (n == 1) "Keep the newest" else "Keep the newest $n"

    // What a rule does, in a line under its title.
    fun ruleWords(rule: RecordingRule): String {
        val parts = mutableListOf(if (rule.anyChannel) "Every airing on any channel" else "Every airing on ${rule.channel}")
        if (rule.newOnly) parts.add("new episodes only")
        if (rule.keep > 0) parts.add(keepWords(rule.keep).lowercase(Locale.ROOT))
        if (rule.padBefore > 0 || rule.padAfter > 0) parts.add("starts ${rule.padBefore} min early, ends ${rule.padAfter} min late")
        return parts.joinToString(" · ")
    }
}
