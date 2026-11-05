package com.wittywilla.wittymediaclient.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import com.wittywilla.wittymediaclient.net.GuideRules
import com.wittywilla.wittymediaclient.net.Recording
import com.wittywilla.wittymediaclient.net.RecordingRule
import com.wittywilla.wittymediaclient.net.problemText
import com.wittywilla.wittymediaclient.net.recordingRules
import com.wittywilla.wittymediaclient.net.recordings
import com.wittywilla.wittymediaclient.net.removeRecording
import com.wittywilla.wittymediaclient.net.removeRecordingRule
import com.wittywilla.wittymediaclient.ui.LocalExtraColours
import com.wittywilla.wittymediaclient.ui.Nav
import com.wittywilla.wittymediaclient.ui.Route
import com.wittywilla.wittymediaclient.ui.Spinner
import com.wittywilla.wittymediaclient.ui.TvRoute
import com.wittywilla.wittymediaclient.ui.TvScreen
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// Recordings and series, as the server's page lists them (web/src/pages/tv/RecordingsPage.tsx) and Apple TV's
// RecordingsView, in the account's WittyTV look. What's recorded lands in a library the server's owner chose, which is
// where it's played from: Play finds it there.

// Apple TV's safe area at the sides, which the list keeps inside.
private const val SAFE_SIDES = 80f

// What's being asked before something goes.
private data class Asking(val recording: Recording, val deleteFile: Boolean)

@Composable
fun RecordingsScreen(nav: Nav) {
    val api = nav.app.api
    val context = LocalContext.current
    remember { GuideRules.timeFormat = android.text.format.DateFormat.getTimeFormat(context); 0 }
    val scope = rememberCoroutineScope()
    val dark = androidx.compose.foundation.isSystemInDarkTheme()
    val appColours = tvAppColours(MaterialTheme.colorScheme, LocalExtraColours.current)
    LaunchedEffect(appColours) { TvLookStore.follow(appColours) }
    val dress = rememberDress(TvLookStore.look)
    val p = dress.paint
    var list by remember { mutableStateOf<List<Recording>?>(null) }
    var rules by remember { mutableStateOf<List<RecordingRule>>(emptyList()) }
    var error by remember { mutableStateOf("") }
    var asking by remember { mutableStateOf<Asking?>(null) }
    var note by remember { mutableStateOf("") }

    suspend fun load() {
        try {
            list = api.recordings()
            error = ""
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (!nav.handleExpired(e)) error = problemText(e, "The recordings couldn't be loaded.")
        }
        rules = runCatching { api.recordingRules() }.getOrDefault(rules)
    }

    fun remove(r: Recording, deleteFile: Boolean) {
        scope.launch {
            try {
                api.removeRecording(r.id, deleteFile)
                load()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = problemText(e, "That didn't work. Try again.")
            }
        }
    }

    fun stop(rule: RecordingRule) {
        scope.launch {
            try {
                api.removeRecordingRule(rule.id)
                load()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = problemText(e, "That didn't work. Try again.")
            }
        }
    }

    // A finished recording is a file in a library once the server has looked at it again: it's found there by its
    // title and the time it was made, which its file name holds.
    fun play(r: Recording) {
        scope.launch {
            note = ""
            val found = runCatching { api.searchItems(r.title, 40).items }.getOrDefault(emptyList()).distinctBy { it.id }
            val stamp = SimpleDateFormat("yyyy-MM-dd HH.mm", Locale.ROOT).format(Date(r.start * 1000))
            val best = found.firstOrNull { it.title.contains(stamp) } ?: found.firstOrNull { it.title.startsWith(r.title) && it.kind != "audio" }
            if (best != null) {
                nav.push(Route.Player(best.id, startOver = true))
            } else {
                note = "A recording is played from the library it lands in. It shows up there once this server's owner sets a library for recordings, under Live TV options, and that library has been looked at again."
            }
        }
    }

    fun back() {
        if ((nav.current as? TvRoute)?.screen == TvScreen.Recordings) nav.pop()
        val guide = nav.current == Route.LiveTv || nav.stack.any { it is TvRoute && it.screen == TvScreen.Guide }
        if (!guide) nav.push(TvRoute(TvScreen.Guide))
    }

    LaunchedEffect(api) {
        TvLookStore.load(api, nav.effectiveThemeId(dark), appColours)
        while (true) {
            load()
            delay(15_000)
        }
    }

    CompositionLocalProvider(LocalTvApi provides api) {
        Column(
            Modifier
                .fillMaxSize()
                .background(p.bg)
                .verticalScroll(rememberScrollState())
                // The page's edge inside the TV's safe area at the sides, as Apple TV's list keeps it; the top is the page's own.
                .padding(top = dress.pt(dress.top + 16), start = dress.pt(SAFE_SIDES + dress.edge), end = dress.pt(SAFE_SIDES + dress.edge), bottom = dress.pt(24 + dress.foot)),
            verticalArrangement = Arrangement.spacedBy(dress.pt(4)),
        ) {
            Row(Modifier.fillMaxWidth().padding(bottom = dress.pt(12)), verticalAlignment = Alignment.CenterVertically) {
                Text("Recordings", style = dress.font(30f, W.Bold), color = p.accent, modifier = Modifier.weight(1f).semantics { heading() })
                TvButton(dress, "Back to the guide", ::back)
            }
            if (error.isNotEmpty()) Text(error, style = dress.font(21.25f, W.Bold), color = p.err)
            val shown = list
            if (shown != null) {
                if (shown.isEmpty()) {
                    Text(
                        "Nothing recorded yet. Highlight a show on a Live TV channel in the guide, hold Select and choose Record this.",
                        style = dress.font(21.25f), color = p.soft,
                    )
                }
                Column(Modifier.padding(vertical = dress.pt(8)), verticalArrangement = Arrangement.spacedBy(dress.pt(16))) {
                    for (r in shown) RecordingRow(dress, r, nav.me?.isAdmin == true, onPlay = { play(r) }, onRemove = { asking = Asking(r, false) }, onDelete = { asking = Asking(r, true) })
                }
            } else if (error.isEmpty()) {
                Box(Modifier.fillMaxWidth().height(dress.pt(200)), contentAlignment = Alignment.Center) { Spinner(p.text, dress.pt(48)) }
            }
            if (rules.isNotEmpty()) {
                Text("Series", style = dress.font(21.25f, W.Bold), color = p.accent, modifier = Modifier.padding(top = dress.pt(20), bottom = dress.pt(8)).semantics { heading() })
                Column(verticalArrangement = Arrangement.spacedBy(dress.pt(16))) {
                    for (rule in rules) RuleRow(dress, rule) { stop(rule) }
                }
            }
            Text(
                "Recordings are of Live TV channels only. Library channels play what is already in your library. Protected broadcasts are never recorded.",
                style = dress.font(16.25f), color = p.soft, modifier = Modifier.padding(top = dress.pt(18)),
            )
        }
    }
    if (note.isNotEmpty()) {
        TvDialog("Not in a library yet", note, listOf(TvDialogButton("OK", cancel = true) { note = "" }), onClose = { note = "" })
    }
    asking?.let { a ->
        val r = a.recording
        val close = { asking = null }
        when {
            a.deleteFile -> TvDialog(
                "Delete the recording of “${r.title}”?", "Its file goes too. This can’t be undone.",
                listOf(TvDialogButton("Cancel", cancel = true, action = close), TvDialogButton("Delete recording", destructive = true) { close(); remove(r, true) }), close,
            )
            r.isFinished -> TvDialog(
                "Remove “${r.title}” from this list?", "Any file it made stays where it is.",
                listOf(TvDialogButton("Cancel", cancel = true, action = close), TvDialogButton("Remove from list", preferred = true) { close(); remove(r, false) }), close,
            )
            else -> TvDialog(
                "Cancel the recording of “${r.title}”?", null,
                listOf(TvDialogButton("Keep recording", cancel = true, action = close), TvDialogButton("Cancel recording", destructive = true) { close(); remove(r, false) }), close,
            )
        }
    }
}

@Composable
private fun RecordingRow(dress: TvDress, r: Recording, admin: Boolean, onPlay: () -> Unit, onRemove: () -> Unit, onDelete: () -> Unit) {
    val p = dress.paint
    val size = r.sizeWords
    val shape = RoundedCornerShape(dress.pt(dress.radius))
    Row(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(p.panel)
            .strokeInside(p.line, dress.pt(1), dress.pt(dress.radius))
            .then(if (dress.bevel) Modifier.bevel(dress.pt(2)) else Modifier)
            .padding(horizontal = dress.pt(12), vertical = dress.pt(8))
            .focusGroup(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(dress.pt(16)),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(dress.pt(2))) {
            Text(r.title, style = dress.font(25f, W.Bold), color = p.text)
            r.sub?.takeIf { it.isNotEmpty() }?.let { Text(it, style = dress.font(21.25f, W.Bold), color = p.accent) }
            Text(
                "${GuideRules.dayName(r.start)}, ${GuideRules.span(r.start, r.stop)} · Channel ${r.number.orEmpty()} ${r.channel}" + if (size.isEmpty()) "" else " · $size",
                style = dress.font(18.75f), color = p.soft,
            )
            r.error?.takeIf { it.isNotEmpty() }?.let { Text(it, style = dress.font(18.75f, W.Bold), color = p.err) }
        }
        Text(r.statusWords, style = dress.font(18.75f, W.Bold), color = if (r.status == "recording") p.accent else p.text)
        if (r.status == "done") TvButton(dress, "Play", onPlay, on = true, icon = TvSymbols.Play)
        TvButton(dress, if (r.isFinished) "Remove" else "Cancel", onRemove)
        if (admin && r.path?.isNotEmpty() == true && r.status != "recording" && r.status != "scheduled") TvButton(dress, "Delete file", onDelete)
    }
}

@Composable
private fun RuleRow(dress: TvDress, rule: RecordingRule, onStop: () -> Unit) {
    val p = dress.paint
    val shape = RoundedCornerShape(dress.pt(dress.radius))
    Row(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(p.panel)
            .strokeInside(p.line, dress.pt(1), dress.pt(dress.radius))
            .padding(horizontal = dress.pt(12), vertical = dress.pt(8))
            .focusGroup(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(dress.pt(16)),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(dress.pt(2))) {
            Text(rule.title, style = dress.font(25f, W.Bold), color = p.text)
            Text("Every airing on ${rule.channel}", style = dress.font(18.75f), color = p.soft)
        }
        TvButton(dress, "Stop", onStop)
    }
}

// A reminder coming due, on whatever screen is showing: watch the channel, or let it go.
@Composable
fun TvReminderAlert(nav: Nav) {
    val api = nav.app.api
    LaunchedEffect(api, nav.me?.id) { if (api.token.isNotEmpty()) TvReminders.load(api) }
    val r = TvReminders.due ?: return
    val started = r.start <= nowSeconds()
    TvDialog(
        r.title + if (started) " has started" else " is about to start", r.sub,
        listOf(
            TvDialogButton("Dismiss", cancel = true) { TvReminders.dismiss(r) },
            TvDialogButton("Watch", preferred = true) {
                TvReminders.dismiss(r)
                nav.watchChannel(r.channel)
            },
        ),
        onClose = { TvReminders.dismiss(r) },
    )
}
