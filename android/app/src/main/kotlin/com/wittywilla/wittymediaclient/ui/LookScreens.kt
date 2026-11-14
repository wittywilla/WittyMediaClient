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
import com.wittywilla.wittymediaclient.net.ThemeColour
import com.wittywilla.wittymediaclient.net.ThemeList
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
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
                    leading = { LayoutThumb(com.wittywilla.wittymediaclient.net.Wire.of(e.wire, nav.experienceForm), e.name, Modifier.width(if (nav.experienceForm == "phone") 56.dp else 120.dp), selected = chosen == e.id, portrait = nav.experienceForm == "phone") },
                    trailing = { check(chosen == e.id) },
                )
            })
        }
        if (problem.isNotEmpty()) Note(problem)
    }
}

// The first time the app connects to a server, after the profile is chosen: two pages, as Apple's and the website's
// setup. "Choose a look" draws every look as it is on this device (a phone's upright, with its own menu); "Choose a
// theme" previews the chosen look large in the theme picked, and every theme card draws that look in its own colours.
// What an administrator requires is locked: a required look opens on the theme page, both required is one page.
@Composable
fun FirstLookScreen(nav: Nav, s: Map<String, String>) {
    val scope = rememberCoroutineScope()
    val context = androidx.compose.ui.platform.LocalContext.current
    val looks = nav.experienceList?.experiences.orEmpty()
    val state = nav.experienceState
    val lookRequired = state?.choice?.required
    val themeRequired = nav.requiredTheme
    val themes = nav.themeList?.themes.orEmpty().filter { !it.webOnly }
    var step by remember { mutableStateOf(if (lookRequired != null) 1 else 0) }
    var busy by remember { mutableStateOf(false) }
    var said by remember { mutableStateOf("") }
    val form = nav.experienceForm
    val portrait = form == "phone"
    val shownLook = state?.choice?.chosen?.ifEmpty { state.choice.current }.orEmpty().ifEmpty { looks.firstOrNull()?.id.orEmpty() }
    val look = looks.firstOrNull { it.id == shownLook }
    val wire = look?.let { com.wittywilla.wittymediaclient.net.Wire.of(it.wire, form) } ?: com.wittywilla.wittymediaclient.net.SduiWire()
    // The theme the theme page shows as chosen: the one picked, else the one the chosen look wears.
    val shownTheme = themeRequired?.value ?: nav.themeChoice.ifEmpty { look?.theme.orEmpty() }
    val who = nav.me?.let { it.displayName.ifEmpty { it.name } }.orEmpty()
    val picker = androidx.activity.compose.rememberLauncherForActivityResult(androidx.activity.result.contract.ActivityResultContracts.GetContent()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            val bytes = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) { runCatching { context.contentResolver.openInputStream(uri)?.use { it.readBytes() } }.getOrNull() }
            said = if (bytes == null) s["errInvalid"].orEmpty() else nav.app.api.importTheme(bytes, forEveryone = false) ?: s["themeImported"].orEmpty()
            nav.loadThemes(true)
        }
    }
    fun finish() = nav.finishFirstLook()
    val both = lookRequired != null && themeRequired != null
    BackHandler(enabled = step == 1 && lookRequired == null) { step = 0 }
    // A layer of its own, so the remote and keys stay in it and nothing under it takes them.
    androidx.compose.ui.window.Dialog(
        onDismissRequest = { if (step == 1 && lookRequired == null) step = 0 },
        properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = true),
    ) {
        Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).statusBarsPadding().navigationBarsPadding()) {
            Column(
                Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 24.dp)
                    .widthIn(max = 720.dp).align(androidx.compose.ui.Alignment.CenterHorizontally),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Text(
                    (if (who.isEmpty()) s["firstLookWelcome"].orEmpty() else s["firstLookWelcomeName"].orEmpty().replace("{name}", who)).uppercase(),
                    style = MaterialTheme.typography.labelMedium, color = LocalExtraColours.current.accentText,
                )
                Text(
                    s[when { both -> "firstLookSetTitle"; step == 0 -> "firstLookTitle"; else -> "firstThemeTitle" }].orEmpty(),
                    style = MaterialTheme.typography.headlineMedium, color = MaterialTheme.colorScheme.onBackground,
                    modifier = Modifier.semantics { heading() },
                )
                val setBy = lookRequired ?: themeRequired
                Text(
                    when {
                        both || (step == 1 && lookRequired != null) || (step == 1 && themeRequired != null) -> com.wittywilla.wittymediaclient.net.SduiLook.lockedWords(setBy!!)
                        step == 0 -> s["firstLookDetail"].orEmpty()
                        else -> s["firstThemeDetail"].orEmpty()
                    },
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (step == 0 && !both) {
                    CardGrid(looks.map { e ->
                        val on = e.id == shownLook
                        Choice(e.id, e.name, e.tagline, on, com.wittywilla.wittymediaclient.net.Wire.of(e.wire, form), null) {
                            if (busy || on) return@Choice
                            busy = true
                            scope.launch { nav.chooseExperience(e.id); busy = false }
                        }
                    }, portrait)
                } else {
                    // The chosen look, large, in the theme picked.
                    val theme = themes.firstOrNull { it.id == shownTheme }
                    Text(listOfNotNull(look?.name, theme?.shownName).joinToString(" · "), style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onBackground)
                    Box(Modifier.fillMaxWidth(), contentAlignment = androidx.compose.ui.Alignment.Center) {
                        ThemedThumb(wire, look?.name.orEmpty(), theme, if (portrait) Modifier.width(200.dp) else Modifier.fillMaxWidth(), false, portrait)
                    }
                    if (themeRequired == null) {
                        Text(s["firstThemeThemes"].orEmpty(), style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onBackground)
                        CardGrid(themes.map { t ->
                            Choice(t.id, t.shownName, if (t.scheme == "light") s["themeLight"].orEmpty() else s["themeDark"].orEmpty(), t.id == shownTheme, wire, t) { nav.chooseTheme(t.id) }
                        }, portrait)
                        WittyButton(s["themeImport"].orEmpty(), { picker.launch("*/*") }, kind = ButtonKind.Secondary, focusKey = "first-import")
                        if (said.isNotEmpty()) Note(said)
                    }
                }
            }
            // The buttons stay in sight below the page.
            Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                when {
                    both -> WittyButton(s["continue"].orEmpty(), { finish() }, kind = ButtonKind.Primary, tall = true, focusKey = "first-continue", modifier = Modifier.weight(1f))
                    step == 0 && themeRequired != null -> WittyButton(s["continue"].orEmpty(), { finish() }, kind = ButtonKind.Primary, tall = true, focusKey = "first-continue", modifier = Modifier.weight(1f))
                    step == 0 -> WittyButton(s["next"].orEmpty(), { step = 1 }, kind = ButtonKind.Primary, tall = true, focusKey = "first-next", modifier = Modifier.weight(1f))
                    else -> {
                        if (lookRequired == null) WittyButton(s["back"].orEmpty(), { step = 0 }, kind = ButtonKind.Secondary, tall = true, focusKey = "first-back", modifier = Modifier.weight(1f))
                        WittyButton(s["firstLookUseThis"].orEmpty(), { finish() }, kind = ButtonKind.Primary, tall = true, focusKey = "first-done", modifier = Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

private class Choice(val id: String, val name: String, val detail: String, val on: Boolean, val wire: com.wittywilla.wittymediaclient.net.SduiWire, val theme: ThemeList.ThemeSummary?, val pick: () -> Unit)

// Cards two across (three on a wide screen), each a wireframe with its name and a line under it.
@Composable
private fun CardGrid(cards: List<Choice>, portrait: Boolean) {
    val across = if (portrait) 2 else if (androidx.compose.ui.platform.LocalConfiguration.current.screenWidthDp >= 900) 4 else 3
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        cards.chunked(across).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                row.forEach { c ->
                    Pressable(c.pick, Modifier.weight(1f), label = c.name, selected = c.on, focusKey = "first-" + c.id) {
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            ThemedThumb(c.wire, c.name, c.theme, Modifier.fillMaxWidth(), c.on, portrait)
                            Text(c.name, style = MaterialTheme.typography.titleSmall, color = if (c.on) LocalExtraColours.current.accentText else MaterialTheme.colorScheme.onBackground, maxLines = 1)
                            if (c.detail.isNotEmpty()) Text(c.detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2)
                        }
                    }
                }
                repeat(across - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

// A look's wireframe in a theme's own colours (its preview swatch), or in the colours in use.
@Composable
private fun ThemedThumb(wire: com.wittywilla.wittymediaclient.net.SduiWire, name: String, theme: ThemeList.ThemeSummary?, modifier: Modifier, selected: Boolean, portrait: Boolean) {
    val p = theme?.preview
    fun c(hex: String?, or: Color): Color = hex?.let { ThemeColour.parse(it) }?.let { Color(it.argb) } ?: or
    val bg = c(p?.bg, MaterialTheme.colorScheme.background)
    val panel = c(p?.surface, MaterialTheme.colorScheme.surface)
    val ink = c(p?.text, MaterialTheme.colorScheme.onSurfaceVariant)
    val accent = c(p?.accent, MaterialTheme.colorScheme.primary)
    LayoutThumb(wire, name, modifier, selected, bg = bg, panel = panel, card = androidx.compose.ui.graphics.lerp(panel, ink, 0.12f), accent = accent, ink = ink, portrait = portrait)
}
