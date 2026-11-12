// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import com.wittywilla.wittymediaclient.net.ApiError
import com.wittywilla.wittymediaclient.net.SduiAction
import com.wittywilla.wittymediaclient.net.SduiClient
import com.wittywilla.wittymediaclient.net.SduiEffect
import com.wittywilla.wittymediaclient.net.SduiLayout
import com.wittywilla.wittymediaclient.net.SduiPage
import com.wittywilla.wittymediaclient.net.SduiScreen
import com.wittywilla.wittymediaclient.net.SduiTokens
import com.wittywilla.wittymediaclient.net.SduiUnsupported
import com.wittywilla.wittymediaclient.net.problemWords
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.IOException

// One of the server's pages on screen (the server's docs/SDUI.md): asked for, kept, refreshed, paged, and drawn by
// SduiRender.kt from what net/SduiScreen.kt lays out. The rules are in net/Sdui*.kt, where they're tested; this is
// the part that needs a screen.

// What every part of a page draws with: the page as laid out, the device's units, and what a press does.
class SduiEnv(
    val nav: Nav,
    val screen: SduiScreen,
    // dp in one of the page's points: 1 on a phone or tablet, and a TV's 1920-point canvas across its width.
    val unit: Float,
    val tv: Boolean,
    val tablet: Boolean,
    // What the page was asked for with: the route's own parameters and what was chosen since (a filter, a tab, a search).
    val params: Map<String, String>,
    val act: (SduiAction?) -> Unit,
    // Asks for a section's next page of items: a deferred section's first, a row's next, or again after a failure.
    val more: (section: String, retry: Boolean) -> Unit,
    // Asks for another season's episodes, at the address the season gave.
    val season: (section: String, url: String) -> Unit,
    // Asks for the page again with these parameters changed; an empty value takes one away.
    val ask: (Map<String, String>) -> Unit,
    // The sections with a request on its way.
    val loading: List<String>,
) {
    val layout: SduiLayout get() = screen.layout
    fun pt(points: Int): Dp = (points * unit).dp
    fun pt(points: Float): Dp = (points * unit).dp
    fun space(step: String): Dp = pt(layout.space(step))

    // A text role's size. In sp, so it follows the person's own text size; a TV's points are half a dp, as its other sizes.
    fun size(role: String): TextUnit = (layout.textSize(role) * unit).sp

    // A picture's or a section's address on the server the app is signed in to.
    fun url(path: String): String = if (path.startsWith("/")) nav.app.api.base + path else ""
}

val LocalSdui = staticCompositionLocalOf<SduiEnv> { error("no page") }

// What a page last showed, kept while the app runs, so going back draws it at once with its rows where they were.
private class SduiHeld(val client: SduiClient, val asked: Map<String, String>, val page: SduiPage)

// Why a page isn't there.
private class SduiProblem(val words: String, val gone: Boolean, val offline: Boolean)

private val paramsSaver = Saver<Map<String, String>, ArrayList<String>>(
    save = { map -> ArrayList(map.flatMap { listOf(it.key, it.value) }) },
    restore = { list -> list.chunked(2).associate { it[0] to it[1] } },
)

private const val RETRY_MS = 5000L
private const val COOL_MS = 8000L

@Composable
fun SduiPageScreen(nav: Nav, page: String, params: Map<String, String>, top: Boolean = false, title: String = "") {
    val client = nav.sdui
    if (client == null) {
        // The first frame, before the window has said how big it is.
        Loading()
        return
    }
    LaunchedEffect(client) { nav.loadSdui() }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val memoryKey = "sdui:$page:" + params.entries.sortedBy { it.key }.joinToString("&") { "${it.key}=${it.value}" }
    // What was chosen on the page itself since it opened: a filter, a sort, a tab, what was searched for.
    var chosen by rememberSaveable(stateSaver = paramsSaver) { mutableStateOf(emptyMap()) }
    val asked = remember(params, chosen) { (params + chosen).filterValues { it.isNotEmpty() } }
    val held = remember(client) { nav.remembered<SduiHeld>(memoryKey)?.takeIf { it.client === client } }
    var model by remember(client) { mutableStateOf(held?.page) }
    var shownFor by remember(client) { mutableStateOf(held?.asked) }
    var problem by remember { mutableStateOf<SduiProblem?>(null) }
    var offline by remember { mutableStateOf(false) }
    var refreshing by remember { mutableStateOf(false) }
    var attempt by remember { mutableIntStateOf(0) }
    var toast by remember { mutableStateOf("") }
    var customising by rememberSaveable { mutableStateOf(false) }
    val flying = remember { mutableStateListOf<String>() }
    val cooling = remember { HashMap<String, Long>() }

    SideEffect { model?.let { m -> shownFor?.let { nav.remember(memoryKey, SduiHeld(client, it, m)) } } }

    fun failed(e: Exception, whole: Boolean) {
        if (nav.handleExpired(e)) return
        val words = when (e) {
            is SduiUnsupported -> e.message.orEmpty()
            else -> problemWords(e, "Can't reach the server.")
        }
        if (whole) problem = SduiProblem(words, gone = e is ApiError && e.status == 404, offline = e is IOException) else toast = words
    }

    LaunchedEffect(client, asked, attempt) {
        if (model == null || shownFor != asked) {
            // What was kept from the last run shows at once, while the server is asked.
            withContext(Dispatchers.IO) { client.keptPage(page, asked)?.let { SduiPage(it).ready() } }?.let {
                if (model == null || shownFor != asked) { model = it; shownFor = asked }
            }
        }
        try {
            val have = model
            val fresh = shownFor != asked
            val loaded = withContext(Dispatchers.Default) {
                val loaded = client.page(page, asked)
                val next = when {
                    have == null || fresh -> SduiPage(loaded.value)
                    have.base.meta.etag == loaded.value.meta.etag && have.base == loaded.value -> have
                    else -> have.withBase(loaded.value)
                }
                loaded to next.ready()
            }
            model = loaded.second
            shownFor = asked
            offline = loaded.first.offline
            problem = null
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            failed(e, whole = model == null || shownFor != asked)
            if (shownFor != asked && e is ApiError && e.status != 404) {
                // A choice the server refused: the page stays as it was, without the choice.
                chosen = emptyMap()
            }
        }
        refreshing = false
    }
    // A server out of reach is tried again every few seconds, so the page comes back by itself.
    LaunchedEffect(offline, problem) {
        if (!offline && problem?.offline != true) return@LaunchedEffect
        delay(RETRY_MS)
        attempt++
    }

    suspend fun refresh() {
        val have = model ?: return
        val forWhat = shownFor ?: return
        try {
            val fresh = withContext(Dispatchers.Default) { client.refreshed(page, forWhat, have.base) }
            if (fresh != null && shownFor == forWhat) {
                val now = model
                model = withContext(Dispatchers.Default) { now?.withBase(fresh)?.ready() }
            }
            offline = false
        } catch (e: CancellationException) {
            throw e
        } catch (e: IOException) {
            offline = true
        } catch (e: Exception) {
            failed(e, whole = false)
        }
    }

    // Something changed for every page (more screen time): asked again now.
    val stamp = nav.pagesStamp
    LaunchedEffect(stamp) { if (stamp > 0) refresh() }

    // The page says how long it is good for: asked again after that while it is on screen, and when the app comes back.
    val etag = model?.base?.meta?.etag
    val ttl = model?.base?.meta?.ttlSeconds ?: 0
    val owner = LocalLifecycleOwner.current
    LaunchedEffect(client, etag, ttl, owner) {
        if (etag == null) return@LaunchedEffect
        var first = true
        owner.lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            if (!first) refresh()
            first = false
            while (ttl > 0) {
                delay(ttl * 1000L)
                refresh()
            }
        }
    }

    fun fetch(section: String, url: String) {
        if (url.isEmpty() || section in flying) return
        flying += section
        scope.launch {
            try {
                val answer = withContext(Dispatchers.Default) { client.items(url) }
                val have = model
                val next = withContext(Dispatchers.Default) { have?.withItems(section, answer)?.ready() }
                // Another answer may have landed meanwhile: lay this one over that.
                model = if (model === have) next else withContext(Dispatchers.Default) { model?.withItems(section, answer)?.ready() }
                cooling.remove(section)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (!nav.handleExpired(e)) {
                    val have = model
                    model = withContext(Dispatchers.Default) { have?.withFailure(section)?.ready() }
                    cooling[section] = System.currentTimeMillis()
                }
            } finally {
                flying -= section
            }
        }
    }

    val screen = model?.screen
    val screenTime = model?.base?.screenTime

    fun act(action: SduiAction?) {
        when (val effect = nav.sduiRouter.effect(action)) {
            is SduiEffect.Open -> nav.go(effect.target)
            // The server sends no Play when screen time is over; one kept from before is answered with why.
            is SduiEffect.Play -> if (screenTime != null) toast = screenTime.message.ifEmpty { "Screen time is over for now." } else nav.playById(effect.item, effect.resume)
            is SduiEffect.External -> if (screen?.layout?.externalLinks != false) runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(effect.url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
            SduiEffect.Back -> nav.back()
            is SduiEffect.SelectTab -> chosen = chosen + ("tab" to effect.tab)
            SduiEffect.Refresh -> scope.launch { refresh() }
            is SduiEffect.Command -> scope.launch {
                try {
                    client.command(effect.spec, effect.item)
                    toast = when (effect.spec.op) {
                        "watchLater.add" -> "Added to Watch later"
                        "watched.set" -> "Marked as watched"
                        "watched.clear" -> "Marked as unwatched"
                        else -> "Done"
                    }
                    refresh()
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    failed(e, whole = false)
                }
            }
            SduiEffect.Nothing -> Unit
        }
    }

    BackHandler(customising) { customising = false }
    val metrics = LocalMetrics.current
    val configuration = androidx.compose.ui.platform.LocalConfiguration.current
    Box(Modifier.fillMaxSize()) {
        val trouble = problem
        when {
            screen == null && trouble != null -> SduiTrouble(nav, trouble.words, trouble.gone) { problem = null; attempt++ }
            screen == null -> SduiSkeleton(top)
            else -> {
                // A TV's canvas is the layout's own, 1920 points across whatever the screen measures in dp.
                val canvas = screen.layout.canvas.width
                val unit = if (metrics.tv && canvas > 0) configuration.screenWidthDp.toFloat() / canvas else if (metrics.tv) 0.5f else 1f
                val env = SduiEnv(
                    nav, screen, unit, metrics.tv, tablet = screen.layout.formFactor == "tablet", params = asked,
                    act = ::act,
                    more = { section, retry ->
                        val cooled = retry || System.currentTimeMillis() - (cooling[section] ?: 0L) > COOL_MS
                        if (cooled) model?.moreUrl(section)?.let { fetch(section, it) }
                    },
                    season = ::fetch,
                    ask = { change -> chosen = (chosen + change).filter { (k, v) -> v.isNotEmpty() || params[k]?.isNotEmpty() == true } },
                    loading = flying,
                )
                val base = LocalAppTheme.current
                val pageTokens = screen.document.theme?.tokens.orEmpty()
                val body = @Composable {
                    CompositionLocalProvider(LocalSdui provides env) {
                        val document = screen.document
                        val personal = document.personal
                        if (customising && personal != null) {
                            SduiCustomiseScreen(nav, client, document, personal) { changed ->
                                customising = false
                                if (changed) attempt++
                            }
                        } else {
                            SduiPageView(
                                top = top, title = title.ifEmpty { screen.title }, offline = offline, screenTime = screenTime,
                                refreshing = refreshing, onRefresh = { refreshing = true; attempt++ },
                                customise = if (personal?.editable == true && personal.allow.isNotEmpty() && personal.sections.isNotEmpty()) ({ customising = true }) else null,
                            )
                        }
                    }
                }
                if (base != null && pageTokens.isNotEmpty()) ThemeScope(remember(base, pageTokens) { SduiTokens.over(base, pageTokens) }, body) else body()
            }
        }
        if (toast.isNotEmpty()) Toast(toast, { toast = "" }, Modifier.align(Alignment.BottomCenter).padding(bottom = if (metrics.tv) metrics.u(60) else LocalBottomRoom.current - 4.dp))
    }
}
