// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.wittywilla.wittymediaclient.net.ExtrasFeature
import com.wittywilla.wittymediaclient.net.StemList
import com.wittywilla.wittymediaclient.net.makeApproximateStems
import com.wittywilla.wittymediaclient.net.problemWords
import com.wittywilla.wittymediaclient.net.separateStems
import com.wittywilla.wittymediaclient.net.stems
import com.wittywilla.wittymediaclient.player.StemMixing
import com.wittywilla.wittymediaclient.player.StemPlan
import com.wittywilla.wittymediaclient.player.StemRules
import com.wittywilla.wittymediaclient.player.StemSession
import com.wittywilla.wittymediaclient.player.StemState
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// The stems mixer: a fader for each part of the song the server has (the voice, the music, or drums, bass and the
// rest), mixed in step with the song by the listening player itself (StemMixer.kt). In karaoke on a phone or tablet,
// and from Now Playing on a TV. It is for the song, not for good: leaving puts the song back as it is. A song with no
// parts can have an approximate instrumental made by the server, and an administrator can run the server's separator.

// One song's stems, as the panel shows and changes them.
class StemsUi internal constructor(private val nav: Nav, val job: ExtrasJob) {
    var trackId by mutableStateOf(0L)
        private set
    var list by mutableStateOf<StemList?>(null)
        private set
    var listing by mutableStateOf(false)
        private set
    var problem by mutableStateOf("")
        private set
    var open by mutableStateOf(false)
    var levels by mutableStateOf<Map<String, Double>>(emptyMap())
        private set
    var session by mutableStateOf<StemSession?>(null)
        private set
    var state by mutableStateOf(StemState.Loading)
        internal set
    var failure by mutableStateOf("")
        internal set

    val plan: StemPlan? get() = list?.let { StemRules.plan(it.stems) }
    val mixing: Boolean get() = session != null
    val admin: Boolean get() = nav.me?.isAdmin == true
    val canApproximate: Boolean get() = nav.has(ExtrasFeature.STEMS_APPROXIMATE) && list?.separation?.approximate?.available == true && list?.stems?.none { it.name == "instrumental" } == true
    val canSeparate: Boolean get() = admin && nav.has(ExtrasFeature.STEMS_SEPARATE) && list?.separation?.external?.available == true

    // Worth a button at all: the server has stems for songs, and this song has some or can have some made.
    // Music only: a book or a podcast has no voice to take out of anything.
    val offered: Boolean get() = nav.has(ExtrasFeature.STEMS) && trackId > 0 && !nav.app.listening.keepsPlace && (plan != null || canApproximate || canSeparate)

    // The song changed, or the list is wanted afresh after something was made. A mix that was on comes back on for
    // the new song when it has parts too.
    internal suspend fun load(id: Long, keepOn: Boolean) {
        val wasOn = mixing && keepOn
        turnOff()
        if (id != trackId) {
            list = null
            levels = emptyMap()
        }
        trackId = id
        problem = ""
        if (id <= 0 || !nav.has(ExtrasFeature.STEMS)) return
        listing = true
        try {
            list = nav.app.api.stems(id)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (!nav.handleExpired(e)) problem = problemWords(e, "The song's parts couldn't be read from your server.")
        } finally {
            listing = false
        }
        val found = plan
        if (found != null && levels.keys != found.faders.toSet()) levels = StemRules.startLevels(found)
        if (wasOn && found != null) turnOn()
    }

    fun turnOn() {
        val found = plan ?: return
        failure = ""
        state = StemState.Loading
        try {
            session = StemMixing.start(trackId, found, nav.app.api, levels)
            // The stems do what "voice lower" guesses at, so the guess is turned off.
            nav.app.listening.setSound { it.copy(vocalCut = 0.0) }
        } catch (e: Exception) {
            failure = e.message ?: "The parts couldn't be opened."
            state = StemState.Failed
        }
    }

    fun turnOff() {
        if (session == null) return
        StemMixing.stop()
        session = null
    }

    fun setLevel(name: String, level: Double) {
        levels = levels + (name to level)
        session?.setLevel(name, level)
    }

    fun makeApproximate(again: () -> Unit) {
        val id = trackId
        job.start("Making an approximate instrumental", { it.makeApproximateStems(id) }, settled = { api -> api.stems(id).separation.approximate.task.isEmpty() }) { again() }
    }

    fun separate(again: () -> Unit) {
        val id = trackId
        job.start("Separating the song into its parts", { it.separateStems(id) }) { again() }
    }

    // What to say under the faders.
    fun stateWords(): String = when {
        !mixing -> ""
        state == StemState.Failed -> "The parts couldn't be played, so the song is playing as it is. ${failure.trim()}".trim()
        state == StemState.InStep -> "Playing the parts, in step with the song."
        state == StemState.CatchingUp -> "Catching up with the song…"
        else -> "Getting the parts ready. The song plays as it is until they are."
    }
}

// The stems of whatever is playing, for as long as the screen that asked is up.
@Composable
fun rememberStems(nav: Nav): StemsUi {
    val job = rememberExtrasJob(nav)
    val ui = remember(nav.app.api) { StemsUi(nav, job) }
    val playing = nav.app.listening.now?.mediaId?.toLongOrNull() ?: 0L
    val has = nav.has(ExtrasFeature.STEMS)
    LaunchedEffect(playing, has) { ui.load(playing, keepOn = true) }
    // What the mixer says about itself, a few times a second while it's on.
    LaunchedEffect(ui.session) {
        val session = ui.session ?: return@LaunchedEffect
        while (true) {
            ui.state = session.state
            ui.failure = session.failure
            delay(300)
        }
    }
    DisposableEffect(ui) { onDispose { ui.turnOff() } }
    return ui
}

// MARK: karaoke, on a phone or tablet

// The chip in karaoke's row of controls: lit while the parts are being mixed.
@Composable
internal fun StemsChip(ui: StemsUi) {
    if (!ui.offered) return
    NpChip("Stems", on = ui.mixing, label = if (ui.mixing) "Stems, on. Open the mixer" else "Stems. Open the mixer") { ui.open = true }
}

// The mixer over karaoke: on the player's own near-black, from the foot of the screen. A press outside closes it.
@Composable
internal fun StemsPanel(ui: StemsUi) {
    if (!ui.open) return
    val scope = rememberCoroutineScope()
    val again: () -> Unit = { scope.launch { ui.load(ui.trackId, keepOn = true) } }
    androidx.activity.compose.BackHandler { ui.open = false }
    Box(Modifier.fillMaxSize().background(Color(0x99000000)).clickable(remember { MutableInteractionSource() }, null) { ui.open = false }, contentAlignment = Alignment.BottomCenter) {
        Column(
            Modifier.navigationBarsPadding().padding(12.dp).widthIn(max = 520.dp).fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(Np.panel).border(1.dp, Np.line, RoundedCornerShape(20.dp))
                .clickable(remember { MutableInteractionSource() }, null) {}
                .verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Stems", color = Np.fg, fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f).semantics { heading() })
                NpRound(WebIcons.Close, "Close the mixer", 44.dp, 20.dp) { ui.open = false }
            }
            val plan = ui.plan
            when {
                ui.listing && ui.list == null -> Text("Looking for this song's parts…", color = Np.fg2, fontSize = 14.sp)
                ui.problem.isNotEmpty() -> {
                    Text(ui.problem, color = Np.fg2, fontSize = 14.sp)
                    NpChip("Try again", small = true) { again() }
                }
                plan == null -> Text("This song has no separate parts yet.", color = Np.fg2, fontSize = 14.sp)
                else -> {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text("Mix the parts", color = Np.fg, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                        NpChip(if (ui.mixing) "On" else "Off", on = ui.mixing, label = "Mix the parts, ${if (ui.mixing) "on" else "off"}") { if (ui.mixing) ui.turnOff() else ui.turnOn() }
                    }
                    plan.faders.forEach { name ->
                        val part = plan.parts.firstOrNull { it.name == name }
                        val level = ui.levels[name] ?: 0.0
                        Fader(part?.label ?: StemRules.label(name), level, enabled = ui.mixing) { ui.setLevel(name, it) }
                    }
                    if (plan.approximate) {
                        Text(
                            ui.list?.separation?.approximate?.note.orEmpty().ifEmpty { "Approximate: the voice is quieter, not gone, and the music is mono." },
                            color = Np.fg2, fontSize = 13.sp, lineHeight = 1.45.em,
                        )
                    }
                    val words = ui.stateWords()
                    Text(words.ifEmpty { "Off: the song plays as it is." }, color = Np.fg2, fontSize = 13.sp, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
                }
            }
            if (ui.canApproximate && !ui.job.busy) {
                NpChip("Make an approximate instrumental", small = true) { ui.makeApproximate(again) }
                Text(ui.list?.separation?.approximate?.note.orEmpty(), color = Np.fg2, fontSize = 13.sp, lineHeight = 1.45.em)
            }
            if (ui.canSeparate && !ui.job.busy) NpChip("Separate with the server's separator", small = true) { ui.separate(again) }
            if (ui.admin && ui.list?.separation?.external?.reason == "not-configured" && ui.plan?.approximate != false) {
                Text("For real parts, name a stem separator where your server starts: see Lyrics and karaoke in its help.", color = Np.fg3, fontSize = 12.sp, lineHeight = 1.45.em)
            }
            ExtrasJobCard(ui.job)
        }
    }
}

// One fader: its name, − and + in 44 circles either side of how far up it is. A screen reader hears the part and its
// level as one thing, then the two buttons.
@Composable
private fun Fader(label: String, level: Double, enabled: Boolean, set: (Double) -> Unit) {
    Row(
        Modifier.fillMaxWidth().semantics { contentDescription = label; stateDescription = StemRules.percent(level) },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(label, color = if (enabled) Np.fg else Np.fg2, fontSize = 15.sp, modifier = Modifier.weight(1f))
        @Composable
        fun Step(sign: String, spoken: String, can: Boolean, to: Double) {
            Pressable({ set(to) }, Modifier.size(44.dp), shape = CircleShape, fill = Np.chip, label = spoken, enabled = enabled && can, disabledAlpha = 0.4f, ring = false) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text(sign, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold) }
            }
        }
        Step("−", "$label quieter", level > 0.0, StemRules.stepped(level, up = false))
        Text(
            StemRules.percent(level), color = Np.fg, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center,
            style = TextStyle(fontFeatureSettings = "tnum"), modifier = Modifier.widthIn(min = 52.dp),
        )
        Step("+", "$label louder", level < 1.0, StemRules.stepped(level, up = true))
    }
}

// MARK: Now Playing, on a TV

// The button under a TV's transport, when this song has parts or can have them made.
@Composable
fun TvStemsButton(ui: StemsUi) {
    if (!ui.offered) return
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        ActionButton(if (ui.mixing) "Stems: on" else "Stems", { ui.open = true }, selected = ui.mixing, pill = true, focusKey = "np-stems")
    }
}

// The mixer on a TV: a window of its own, so a remote's arrows stay inside it and Back closes it.
@Composable
fun TvStemsDialog(ui: StemsUi) {
    if (!ui.open) return
    val scope = rememberCoroutineScope()
    val scheme = MaterialTheme.colorScheme
    val again: () -> Unit = { scope.launch { ui.load(ui.trackId, keepOn = true) } }
    Dialog({ ui.open = false }, DialogProperties(usePlatformDefaultWidth = false)) {
        Box(Modifier.fillMaxSize().background(Color(0xB3000000)), contentAlignment = Alignment.Center) {
            Column(
                Modifier.widthIn(max = 620.dp).heightIn(max = 520.dp).clip(Radius.LG).background(scheme.surface).verticalScroll(rememberScrollState()).padding(Space.S5),
                verticalArrangement = Arrangement.spacedBy(Space.S3),
            ) {
                Heading("Stems")
                val plan = ui.plan
                var first = true
                fun focusFirst(): Boolean = first.also { first = false }
                when {
                    ui.listing && ui.list == null -> Secondary("Looking for this song's parts…")
                    ui.problem.isNotEmpty() -> {
                        ErrorText(ui.problem)
                        ActionButton("Try again", again, takeFocus = focusFirst())
                    }
                    plan == null -> Secondary("This song has no separate parts yet.")
                    else -> {
                        ActionButton(
                            if (ui.mixing) "Mix the parts: on" else "Mix the parts: off", { if (ui.mixing) ui.turnOff() else ui.turnOn() },
                            primary = !ui.mixing, selected = ui.mixing, takeFocus = focusFirst(), focusKey = "stems-on",
                        )
                        plan.faders.forEach { name ->
                            val label = plan.parts.firstOrNull { it.name == name }?.label ?: StemRules.label(name)
                            val level = ui.levels[name] ?: 0.0
                            Row(
                                Modifier.fillMaxWidth().remoteRow().semantics { contentDescription = label; stateDescription = StemRules.percent(level) },
                                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.S2),
                            ) {
                                Text("$label  ${StemRules.percent(level)}", color = scheme.onSurface, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
                                ActionButton("−", { ui.setLevel(name, StemRules.stepped(level, up = false)) }, enabled = ui.mixing && level > 0.0, state = "$label quieter", focusKey = "stem-$name-down")
                                ActionButton("+", { ui.setLevel(name, StemRules.stepped(level, up = true)) }, enabled = ui.mixing && level < 1.0, state = "$label louder", focusKey = "stem-$name-up")
                            }
                        }
                        if (plan.approximate) Secondary(ui.list?.separation?.approximate?.note.orEmpty().ifEmpty { "Approximate: the voice is quieter, not gone, and the music is mono." })
                        Text(
                            ui.stateWords().ifEmpty { "Off: the song plays as it is." }, color = scheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
                        )
                    }
                }
                if (ui.canApproximate && !ui.job.busy) {
                    ActionButton("Make an approximate instrumental", { ui.makeApproximate(again) }, takeFocus = focusFirst(), focusKey = "stems-approx")
                    Secondary(ui.list?.separation?.approximate?.note.orEmpty())
                }
                if (ui.canSeparate && !ui.job.busy) ActionButton("Separate with the server's separator", { ui.separate(again) }, takeFocus = focusFirst(), focusKey = "stems-separate")
                ExtrasJobCard(ui.job)
                ActionButton("Close", { ui.open = false }, takeFocus = focusFirst(), focusKey = "stems-close")
            }
        }
    }
}
