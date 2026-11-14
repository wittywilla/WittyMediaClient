// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.tv

import androidx.compose.material3.ColorScheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.graphics.toArgb
import com.wittywilla.wittymediaclient.net.Api
import com.wittywilla.wittymediaclient.net.ChannelSet
import com.wittywilla.wittymediaclient.net.DialRules
import com.wittywilla.wittymediaclient.net.GuidePaging
import com.wittywilla.wittymediaclient.net.LocateRules
import com.wittywilla.wittymediaclient.net.Located
import com.wittywilla.wittymediaclient.net.SetRules
import com.wittywilla.wittymediaclient.net.channelSets
import com.wittywilla.wittymediaclient.net.liteChannels
import com.wittywilla.wittymediaclient.net.locateChannel
import com.wittywilla.wittymediaclient.net.Guide
import com.wittywilla.wittymediaclient.net.GuideBrand
import com.wittywilla.wittymediaclient.net.GuideChannel
import com.wittywilla.wittymediaclient.net.GuideProgramme
import com.wittywilla.wittymediaclient.net.GuideRules
import com.wittywilla.wittymediaclient.net.LogoInfo
import com.wittywilla.wittymediaclient.net.ReminderRules
import com.wittywilla.wittymediaclient.net.TvAppColours
import com.wittywilla.wittymediaclient.net.TvLook
import com.wittywilla.wittymediaclient.net.TvReminder
import com.wittywilla.wittymediaclient.net.TvSaved
import com.wittywilla.wittymediaclient.net.addReminder
import com.wittywilla.wittymediaclient.net.guidePage
import com.wittywilla.wittymediaclient.net.lineup
import com.wittywilla.wittymediaclient.net.lookupLogos
import com.wittywilla.wittymediaclient.net.problemText
import com.wittywilla.wittymediaclient.net.rawUi
import com.wittywilla.wittymediaclient.net.reminders
import com.wittywilla.wittymediaclient.net.removeReminder
import com.wittywilla.wittymediaclient.net.saveTvLook
import com.wittywilla.wittymediaclient.net.setFavourite
import com.wittywilla.wittymediaclient.net.themeSuggestsTv
import com.wittywilla.wittymediaclient.net.uniqueChannels
import com.wittywilla.wittymediaclient.ui.ExtraColours
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

// What WittyTV's screens on Android TV share: this account's look, the guide's channels a page at a time, the logos,
// and reminders, as Apple TV keeps them (apple/App/TvStores.swift). Each is kept as the server's page keeps it
// (web/src/pages/tv/look.ts, GuidePage.tsx and reminders.tsx), so a change made on any device shows here.

// For what outlives a screen: a look being saved, a reminder being waited for.
internal val tvScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

// The app's theme, for the WittyTV themes that follow it, as Apple TV reads it from its own: the background, panel,
// card, raised, text, secondary text, accent, accent text and on-accent colours, each over the background.
fun tvAppColours(scheme: ColorScheme, extra: ExtraColours): TvAppColours {
    val bg = scheme.background
    fun hex(c: Color): String = "#%06x".format(c.compositeOver(bg).toArgb() and 0xffffff)
    return TvAppColours(
        bg = hex(bg), bg2 = hex(scheme.surface), bg3 = hex(scheme.surfaceVariant), bg4 = hex(extra.raised), fg = hex(scheme.onBackground),
        fg2 = hex(scheme.onSurfaceVariant), accent = hex(scheme.primary), accentText = hex(extra.accentText), accentFg = hex(scheme.onPrimary),
        border = hex(extra.raised),
    )
}

// This account's WittyTV look, as `useLook` works it out on the page.
object TvLookStore {
    // What's saved with the account, as it came.
    private var raw: Map<String, JsonElement> = emptyMap()
    private var owner: String? = null
    private var suggestion: String? = null
    private var app = TvAppColours.fallback
    private var askedFor = ""

    var look by mutableStateOf(TvLook.resolve(null, null, null))
        private set
    var loaded by mutableStateOf(false)
        private set

    // Asks the server what this account chose, and what the app's theme suggests.
    suspend fun load(api: Api, themeId: String?, app: TvAppColours) {
        this.app = app
        val asking = api.base + "|" + (themeId ?: "")
        if (askedFor != asking) {
            askedFor = asking
            suggestion = null
            if (!themeId.isNullOrEmpty()) suggestion = runCatching { api.themeSuggestsTv(themeId) }.getOrNull()
        }
        runCatching { api.rawUi() }.getOrNull()?.let { ui -> raw = (ui["tvLook"] as? JsonObject).orEmpty() }
        loaded = true
        resolve()
    }

    // The app's own colours changed: the themes that follow it follow.
    fun follow(app: TvAppColours) {
        if (app == this.app) return
        this.app = app
        resolve()
    }

    // The owner's starting look comes with every page of the guide.
    fun learnOwner(guide: Guide) {
        val next = guide.theme
        if (next == owner) return
        owner = next
        resolve()
    }

    private fun resolve() {
        look = TvLook.resolve(TvSaved.from(JsonObject(raw)), suggestion, owner?.ifEmpty { null }, app)
    }

    // A change shows at once, and goes to the account to follow it to other devices. A null takes a choice away.
    fun change(patch: Map<String, JsonElement?>, api: Api) {
        val next = raw.toMutableMap()
        for ((key, value) in patch) {
            if (value == null) next.remove(key) else next[key] = value
        }
        raw = next
        resolve()
        tvScope.launch { runCatching { api.saveTvLook(patch) } }
    }

    fun change(key: String, value: Any?, api: Api) = change(mapOf(key to value.json()), api)

    // Picks a theme. Custom starts from what's on the screen, so there's nothing to set up to begin with.
    fun pick(theme: String, api: Api) {
        val patch = mutableMapOf<String, JsonElement?>("theme" to JsonPrimitive(theme))
        if (theme == "custom" && raw["custom"] == null) patch["custom"] = custom(look.shape.id, look.font)
        change(patch, api)
    }

    fun custom(shape: String, font: String): JsonElement = JsonObject(mapOf("shape" to JsonPrimitive(shape), "font" to JsonPrimitive(font)))

    // A plain value as JSON.
    private fun Any?.json(): JsonElement? = when (this) {
        null -> null
        is JsonElement -> this
        is Boolean -> JsonPrimitive(this)
        is Number -> JsonPrimitive(this)
        else -> JsonPrimitive(toString())
    }
}

// Everything that decides which rows the guide has: a change to any of it starts the rows afresh.
data class GuideView(val set: String = SetRules.ALL, val search: String = "", val pageSize: Int = GuidePaging.ALL)

// The guide's channels, a page at a time, for the stretch of hours on screen. Only the rows near what's shown are
// asked for, and the rest let go, so a playlist of ten thousand channels stays quick. The rows are a set's, narrowed by
// what's typed, and a channel is found by its number. A page size of a number shows that many rows at a time; All scrolls through them all.
class GuideStore(private val api: Api) {
    val rows = mutableStateMapOf<Int, GuideChannel>()
    var total by mutableStateOf<Int?>(null)
        private set
    var lineup by mutableStateOf<List<GuideChannel>>(emptyList())
        private set
    var error by mutableStateOf("")
    var view by mutableStateOf(GuideView())
        private set

    // The sets, once asked for, and whether this account may share one.
    var sets by mutableStateOf<List<ChannelSet>?>(null)
        private set
    var canShare by mutableStateOf(false)
        private set

    // The first row of the page on screen, when paged.
    var pageOffset by mutableStateOf(0)
        private set
    private var fetchFrom = 0L
    private val loaded = HashSet<String>()
    private var lineupFor = ""

    val set: String get() = view.set
    val search: String get() = view.search
    val pageSize: Int get() = view.pageSize
    val paged: Boolean get() = view.pageSize > 0

    // Showing everything: nothing chosen to narrow the channels.
    val showingAll: Boolean get() = view.search.isBlank() && view.set == SetRules.ALL

    val currentSet: ChannelSet? get() = sets?.firstOrNull { it.id == view.set }

    // The rows the grid has: a page's, or all of them.
    val firstRow: Int get() = if (paged) pageOffset else 0
    val rowCount: Int get() = total?.let { GuidePaging.rowsOn(firstRow, view.pageSize, it) } ?: 0

    private val chunk: Int get() = GuidePaging.chunk(view.pageSize)

    fun configure(pageSize: Int) {
        val next = view.copy(pageSize = GuidePaging.size(pageSize))
        if (next != view) start(next)
    }

    private fun start(next: GuideView) {
        view = next
        loaded.clear()
        rows.clear()
        total = null
        pageOffset = 0
    }

    fun chooseSet(id: String) {
        if (id == view.set) return
        start(view.copy(set = id))
    }

    fun chooseSearch(words: String) {
        val w = words.trim()
        if (w == view.search) return
        start(view.copy(search = w))
    }

    fun choosePageSize(size: Int) {
        val s = GuidePaging.size(size)
        if (s == view.pageSize) return
        start(view.copy(pageSize = s))
    }

    // Everything again, from the start: the All set, nothing typed.
    fun showAll() {
        start(view.copy(set = SetRules.ALL, search = ""))
    }

    // The page that holds a row; true when that's another page.
    fun pageFor(row: Int): Boolean {
        if (!paged) return false
        val at = GuidePaging.pageStart(row, view.pageSize)
        if (at == pageOffset) return false
        pageOffset = at
        return true
    }

    // A new stretch of hours keeps the rows until the new ones come, so the highlight has somewhere to be.
    fun setFrom(from: Long) {
        val start = (from / GuideRules.FETCH_SPAN) * GuideRules.FETCH_SPAN
        if (start != fetchFrom) {
            fetchFrom = start
            loaded.clear()
        }
    }

    // Everything again, as the page does every few minutes while it's open.
    fun refresh() = loaded.clear()

    suspend fun ensure(row: Int) {
        val size = chunk
        val page = maxOf(0, row) / size
        val asked = view
        val key = "$fetchFrom|$asked|$page"
        if (!loaded.add(key)) return
        val query = GuidePaging.query(fetchFrom, page * size, size, set = asked.set, q = asked.search)
        try {
            val g = api.guidePage(query)
            if (asked != view) return
            TvLookStore.learnOwner(g)
            total = g.total ?: g.channels.size
            val at = g.offset ?: (page * size)
            g.channels.forEachIndexed { i, c -> rows[at + i] = c }
            error = ""
        } catch (e: CancellationException) {
            loaded.remove(key)
            throw e
        } catch (e: Exception) {
            loaded.remove(key)
            error = problemText(e, "The guide couldn't be loaded.")
        }
    }

    // Lets go of the rows far from those on screen, so scrolling through thousands of channels doesn't keep them all.
    fun trim(visible: Collection<Int>) {
        if (paged || rows.size <= chunk * (GuidePaging.KEEP * 2 + 2)) return
        val keep = GuidePaging.keep(visible, chunk)
        if (keep.isEmpty()) return
        val size = chunk
        rows.keys.filter { it / size !in keep }.forEach { rows.remove(it) }
        loaded.removeAll { k -> k.substringAfterLast('|').toIntOrNull()?.let { it !in keep } ?: false }
    }

    // The sets, and this device's choice among them for this server and account. Unknown or gone: All.
    suspend fun loadSets(saved: String?): String {
        val answer = runCatching { api.channelSets() }.getOrNull()
        if (answer != null) {
            sets = answer.sets.orEmpty()
            canShare = answer.canShare
        }
        return SetRules.remembered(saved, sets)
    }

    suspend fun reloadSets() {
        runCatching { api.channelSets() }.getOrNull()?.let {
            sets = it.sets.orEmpty()
            canShare = it.canShare
        }
    }

    // Every channel's number and name in the set: for favourites, Last, dialling, and finding a channel by its key.
    suspend fun loadLineup(force: Boolean = false) {
        val wanted = view.set
        if (!force && wanted == lineupFor && lineup.isNotEmpty()) return
        val fresh = runCatching { api.liteChannels(wanted) }.getOrNull() ?: return
        lineupFor = wanted
        lineup = uniqueChannels(fresh.channels)
    }

    // A channel's row in what the guide shows.
    fun index(key: String): Int? {
        val narrowed = if (view.search.isNotBlank()) lineup.filter { GuidePaging.matches(it, view.search) } else lineup
        return narrowed.indexOfFirst { it.key == key }.takeIf { it >= 0 }
    }

    // Where a channel (a number or a key) is in what's showing, and in All when it isn't there.
    suspend fun locate(wanted: String): Located {
        val here = api.locateChannel(view.set, view.search, wanted)
        val all = if (here < 0 && !showingAll) api.locateChannel(SetRules.ALL, "", wanted) else null
        return LocateRules.decide(here, all, showingAll)
    }

    // Marks a channel a favourite or not, at once, then tells the server.
    suspend fun setFavourite(channel: GuideChannel, on: Boolean) {
        for ((i, c) in rows.toMap()) if (c.key == channel.key) rows[i] = c.copy(favourite = on)
        lineup = lineup.map { if (it.key == channel.key) it.copy(favourite = on) else it }
        api.setFavourite(channel.key, on)
    }
}

// Channel logos from the logo service, asked for once per name.
object TvLogos {
    val known = mutableStateMapOf<String, LogoInfo>()
    private val asked = HashSet<String>()

    private fun key(b: GuideBrand) = b.kind + "|" + b.name.lowercase()

    fun info(brand: GuideBrand?): LogoInfo? = brand?.let { known[key(it)] }

    suspend fun ask(brands: List<GuideBrand>, api: Api) {
        val fresh = brands.filter { asked.add(key(it)) }
        if (fresh.isEmpty()) return
        val found = runCatching { api.lookupLogos(fresh) }.getOrNull() ?: return
        for (logo in found) known[logo.kind + "|" + logo.name.lowercase()] = logo
    }

    // Another server's logos aren't this one's.
    fun forget() {
        known.clear()
        asked.clear()
    }
}

// "Tell me when this starts": the account's reminders, asked for once, and the one coming due.
object TvReminders {
    var list by mutableStateOf<List<TvReminder>>(emptyList())
        private set
    var due by mutableStateOf<TvReminder?>(null)
    private val shown = HashSet<Long>()
    private var loadedFor = ""
    private var waiting: Job? = null
    private var api = Api("", "")

    fun has(channel: String, start: Long) = list.any { it.channel == channel && it.start == start }

    suspend fun load(api: Api) {
        this.api = api
        if (loadedFor == api.base + api.token) return
        loadedFor = api.base + api.token
        list = runCatching { api.reminders() }.getOrDefault(emptyList()).sortedBy { it.start }
        watch()
    }

    // Sets a reminder, or takes it away. Answers what to say.
    suspend fun toggle(channel: String, p: GuideProgramme): String {
        val found = list.firstOrNull { it.channel == channel && it.start == p.start }
        if (found != null) {
            return try {
                api.removeReminder(found.id)
                list = list.filter { it.id != found.id }
                watch()
                "Reminder for ${p.title} removed"
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                problemText(e, "That didn't work. Try again.")
            }
        }
        return try {
            val r = api.addReminder(channel, p.title, p.sub, p.start, p.end)
            list = (list + r).sortedBy { it.start }
            watch()
            "We'll tell you when ${p.title} starts"
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            problemText(e, "That didn't work. Try again.")
        }
    }

    // Once a reminder has been seen it goes: the server would drop it once the programme ends anyway.
    fun dismiss(r: TvReminder) {
        if (due?.id == r.id) due = null
        list = list.filter { it.id != r.id }
        val using = api
        tvScope.launch { runCatching { using.removeReminder(r.id) } }
        watch()
    }

    // One wait, for the next reminder: a TV left on does nothing until one is due.
    private fun watch() {
        waiting?.cancel()
        val now = System.currentTimeMillis() / 1000
        if (due == null) {
            ReminderRules.due(list, shown, now)?.let {
                shown.add(it.id)
                due = it
            }
        }
        val at = ReminderRules.nextCheck(list, shown, now) ?: return
        waiting = tvScope.launch {
            val wait = maxOf(1L, at - System.currentTimeMillis() / 1000)
            delay(minOf(wait, 3600L) * 1000)
            watch()
        }
    }

    // Signed out or on another server: nothing of this account's is kept.
    fun forget() {
        waiting?.cancel()
        list = emptyList()
        due = null
        shown.clear()
        loadedFor = ""
    }
}
