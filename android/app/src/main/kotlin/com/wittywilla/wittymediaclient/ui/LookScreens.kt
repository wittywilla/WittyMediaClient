// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.dp
import com.wittywilla.wittymediaclient.net.SduiLook
import kotlinx.coroutines.launch

// Look (a UI: layout, shell, shape, finish, type) and Theme (colour) are two choices (docs/plans/DESIGN-2.md section 8).
// The server lists the experiences and says which this profile has on this device, and whether an administrator requires one.

// Settings, Look: every experience the server offers, the chosen one marked, or the requirement shown locked with who set it.
@Composable
fun LookScreen(nav: Nav, s: Map<String, String>) {
    val scope = rememberCoroutineScope()
    var problem by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    val list = nav.experienceList
    val state = nav.experienceState
    val required = state?.choice?.required
    val current = state?.choice?.current.orEmpty()
    val chosen = state?.choice?.chosen.orEmpty()
    fun pick(id: String?) {
        if (busy || required != null) return
        busy = true
        problem = ""
        scope.launch {
            nav.chooseExperience(id)?.let { problem = it }
            busy = false
        }
    }
    val check: @Composable (Boolean) -> Unit = { on ->
        Icon(Symbols.Check, null, tint = LocalExtraColours.current.accentText, modifier = Modifier.padding(0.dp).graphicsLayer { alpha = if (on) 1f else 0f })
    }
    SettingsPage(nav, s["rowLook"].orEmpty(), s["lookHint"].orEmpty()) {
        if (list == null || list.experiences.isEmpty()) {
            Note(s["lookNone"].orEmpty())
            return@SettingsPage
        }
        if (required != null) {
            GroupedList("", listOf(GroupRow(list.experiences.firstOrNull { it.id == required.value }?.name ?: required.value, icon = Symbols.Password, detail = SduiLook.lockedWords(required), chevron = false, focusKey = "look-required", requestFocus = true)))
        } else {
            GroupedList("", listOf(GroupRow(s["lookServer"].orEmpty(), onClick = { pick(null) }, icon = Symbols.Server, chevron = false, selected = chosen.isEmpty(), detail = list.experiences.firstOrNull { it.id == list.default }?.name.orEmpty(), focusKey = "look-server", requestFocus = chosen.isEmpty(), trailing = { check(chosen.isEmpty()) })))
            GroupedList("", list.experiences.map { e ->
                GroupRow(
                    e.name, onClick = { pick(e.id) }, chevron = false, selected = chosen == e.id, detail = e.tagline, focusKey = "look-" + e.id, requestFocus = chosen == e.id,
                    // A wireframe of the look's layout in the colours in use: where the menu is, Home, the cards.
                    leading = { LayoutThumb(com.wittywilla.wittymediaclient.net.Wire.of(e.wire, nav.experienceForm), e.name, Modifier.width(120.dp), selected = chosen == e.id) },
                    trailing = { check(chosen == e.id) },
                )
            })
        }
        if (problem.isNotEmpty()) Note(problem)
    }
}

// The first time the app connects to a server, after the profile is chosen: the look, then the theme, unless an
// administrator requires them (then this is never shown). Either can be changed any time in Settings.
@Composable
fun FirstLookScreen(nav: Nav, s: Map<String, String>) {
    val scope = rememberCoroutineScope()
    var step by remember { mutableStateOf(0) }
    var busy by remember { mutableStateOf(false) }
    val list = nav.experienceList?.experiences.orEmpty()
    val state = nav.experienceState
    val theme = nav.themeList?.themes.orEmpty()
    BackHandler(enabled = step == 1) { step = 0 }
    // A layer of its own, so the remote and keys stay in it and nothing under it takes them.
    androidx.compose.ui.window.Dialog(
        onDismissRequest = { if (step == 1) step = 0 },
        properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = true),
    ) {
    androidx.compose.foundation.layout.Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
    SignInLayout(
        onBack = if (step == 1) ({ step = 0 }) else null,
        words = {
            SignInHeading(s[if (step == 0) "firstLookTitle" else "firstThemeTitle"].orEmpty(), detail = s[if (step == 0) "firstLookDetail" else "firstThemeDetail"].orEmpty())
        },
        actions = {
            // The list scrolls in about half the screen; Next and Done stay pinned below it, always in sight.
            val most = (androidx.compose.ui.platform.LocalConfiguration.current.screenHeightDp / 2).coerceIn(200, 420).dp
            Column(Modifier.heightIn(max = most).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (step == 0) {
                    list.forEachIndexed { i, e ->
                        val on = (state?.choice?.chosen?.ifEmpty { state.choice.current }) == e.id
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                        LayoutThumb(com.wittywilla.wittymediaclient.net.Wire.of(e.wire, nav.experienceForm), e.name, Modifier.width(160.dp), selected = on)
                        WittyButton(e.name + if (e.tagline.isNotEmpty()) " · " + e.tagline else "", {
                            if (busy) return@WittyButton
                            busy = true
                            scope.launch { nav.chooseExperience(e.id); busy = false }
                        }, kind = if (on) ButtonKind.Primary else ButtonKind.Secondary, takeFocus = i == 0, focusKey = "first-" + e.id)
                        }
                    }
                } else {
                    theme.forEachIndexed { i, t ->
                        WittyButton(t.shownName, { nav.chooseTheme(t.id) }, kind = if (nav.themeChoice == t.id) ButtonKind.Primary else ButtonKind.Secondary, takeFocus = i == 0, focusKey = "first-theme-" + t.id)
                    }
                }
            }
            if (step == 0) WittyButton(s["next"].orEmpty(), { step = 1 }, kind = ButtonKind.Primary, tall = true, focusKey = "first-next")
            else WittyButton(s["done"].orEmpty(), { nav.finishFirstLook() }, kind = ButtonKind.Primary, tall = true, focusKey = "first-done")
        },
    )
    }
    }
}
