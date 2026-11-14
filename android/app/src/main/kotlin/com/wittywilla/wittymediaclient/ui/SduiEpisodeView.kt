// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.wittywilla.wittymediaclient.net.SduiView
import com.wittywilla.wittymediaclient.net.str
import kotlinx.coroutines.launch

// How a show's episodes are laid out on its page, as the website's (web/src/sdui/extras/episodeView.ts): as cards with a
// still and synopsis, or as a playlist, one line each. The choice made here, else the show's own (which an administrator
// keeps for everyone), else the server's default (Settings, Playback), else what the page sent.
object EpisodeViews {
    // By show id: "cards" or "list". Someone else's choice lasts while the app runs; an administrator's is also saved.
    val chosen = mutableStateMapOf<Long, String>()
}

// The show a page is about, from its header's item ("show-5").
internal fun sduiShowId(env: SduiEnv): Long? =
    env.screen.visible.firstOrNull { it.type == "DetailHeader" }?.props?.str("itemId")
        ?.let { Regex("^show-(\\d+)$").find(it)?.groupValues?.get(1)?.toLongOrNull() }

// Whether this SeasonList's episodes are a playlist now. Asks the show and the server for their choice the first time.
@Composable
internal fun sduiEpisodesAsList(season: SduiView): Boolean {
    val env = LocalSdui.current
    val show = sduiShowId(env)
    if (show != null) LaunchedEffect(show) {
        if (EpisodeViews.chosen.containsKey(show)) return@LaunchedEffect
        val api = env.nav.app.api
        val own = runCatching { api.show(show).show.view }.getOrNull().orEmpty()
        val server = if (own.isEmpty()) runCatching { api.playerPrefs().episodeView }.getOrNull().orEmpty() else ""
        val v = TitleLook.episodeView(null, own, server).takeIf { own.isNotEmpty() || server.isNotEmpty() }
        if (v != null && !EpisodeViews.chosen.containsKey(show)) EpisodeViews.chosen[show] = v
    }
    val v = show?.let { EpisodeViews.chosen[it] } ?: season.props.str("style")
    return v == "list"
}

// "Layout", then Cards and Playlist together, as the website's switch above a show's episodes.
@Composable
internal fun SduiEpisodeLayout(season: SduiView, side: Dp) {
    val env = LocalSdui.current
    val show = sduiShowId(env) ?: return
    val scheme = MaterialTheme.colorScheme
    val list = sduiEpisodesAsList(season)
    val scope = rememberCoroutineScope()
    val admin = env.nav.me?.isAdmin == true
    fun choose(v: String) {
        if (EpisodeViews.chosen[show] == v) return
        EpisodeViews.chosen[show] = v
        // An administrator's choice is kept for the show, for everyone.
        if (admin) scope.launch { runCatching { env.nav.app.api.setShowView(show, v) } }
    }
    Row(
        Modifier.fillMaxWidth().padding(horizontal = side).padding(bottom = env.space("xs")).then(if (env.tv) Modifier.remoteRow() else Modifier),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(env.space("s")),
    ) {
        Text("Layout", color = LocalExtraColours.current.hint, fontSize = env.size("caption"), modifier = Modifier.semantics { heading() })
        Row(Modifier.clip(Radius.FULL).background(scheme.surfaceVariant).padding(env.pt(if (env.tv) 6 else 3)), horizontalArrangement = Arrangement.spacedBy(env.pt(if (env.tv) 6 else 2))) {
            listOf("cards" to "Cards", "list" to "Playlist").forEach { (v, words) ->
                val on = (v == "list") == list
                Pressable(
                    { choose(v) }, shape = Radius.FULL, fill = if (on) scheme.surface else Color.Transparent, label = "$words layout", selected = on,
                    state = if (on) "Selected" else null, focusKey = (season.id + "~layout~" + v).takeIf { env.tv }, ring = env.tv,
                ) {
                    Box(Modifier.heightIn(min = env.pt(if (env.tv) 56 else 38)).padding(horizontal = env.pt(if (env.tv) 28 else 14)), contentAlignment = Alignment.Center) {
                        Text(words, color = if (on) scheme.onBackground else scheme.onSurfaceVariant, fontSize = env.size("caption"), fontWeight = if (on) FontWeight.SemiBold else FontWeight.Medium, maxLines = 1)
                    }
                }
            }
        }
    }
}

// An episode in the playlist: its number and name, then its length (and "watched"), and its synopsis where the page shows
// them; no still. Pressing it does what the card does.
@Composable
internal fun SduiEpisodeLine(view: SduiView, parent: SduiView) {
    val env = LocalSdui.current
    val scheme = MaterialTheme.colorScheme
    val hint = LocalExtraColours.current.hint
    val press = view.node.action != null
    val watched = "watched" in view.shows
    Pressable(
        { env.act(view.node.action) }, Modifier.fillMaxWidth(), shape = RoundedCornerShape(env.pt(10)), fill = Color.Transparent, label = view.label,
        enabled = press, disabledAlpha = 1f, focusKey = view.id.takeIf { env.tv }, ring = env.tv, pressScale = 1f,
    ) {
        Column(
            Modifier.fillMaxWidth().heightIn(min = env.pt(if (env.tv) 90 else 52)).padding(horizontal = env.pt(if (env.tv) 24 else 4), vertical = env.pt(if (env.tv) 12 else 8)).clearAndSetSemantics { },
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            view.text["title"]?.let { Text(it, color = scheme.onBackground, fontSize = env.size("body"), fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis) }
            val sub = listOfNotNull(view.text["subtitle"], "watched".takeIf { watched }).joinToString(" · ")
            if (sub.isNotEmpty()) Text(sub, color = hint, fontSize = env.size("caption"), maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (parent.props["showSynopsis"]?.toString() != "false") view.text["synopsis"]?.let {
                Text(it, color = scheme.onSurfaceVariant, fontSize = env.size("caption"), maxLines = view.line("synopsis", 2), overflow = TextOverflow.Ellipsis)
            }
            view.progress?.takeIf { it in 1..99 }?.let { percent ->
                Box(Modifier.padding(top = 4.dp).fillMaxWidth().heightIn(min = 3.dp).clip(Radius.FULL).background(scheme.surfaceVariant)) {
                    Box(Modifier.fillMaxWidth(percent / 100f).heightIn(min = 3.dp).background(scheme.primary))
                }
            }
        }
    }
}
