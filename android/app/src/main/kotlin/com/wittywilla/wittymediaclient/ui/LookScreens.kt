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
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.widthIn
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.contentDescription
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
    fun themeOf(id: String) = themes.firstOrNull { it.id == id }
    BackHandler(enabled = step == 1 && lookRequired == null) { step = 0 }
    // A layer of its own, so the remote and keys stay in it and nothing under it takes them. Drawn with the Design 2
    // page kit, as Apple's chooser: eyebrow, title, lead, cards, then the buttons.
    androidx.compose.ui.window.Dialog(
        onDismissRequest = { if (step == 1 && lookRequired == null) step = 0 },
        properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
    ) {
        // The dialog's window wraps its content and stops at the system bars by default, so Home showed through above
        // and below the chooser on a phone (#80). It fills the screen, opaque, in the page's colour.
        val window = (androidx.compose.ui.platform.LocalView.current.parent as? androidx.compose.ui.window.DialogWindowProvider)?.window
        val page = MaterialTheme.colorScheme.background
        androidx.compose.runtime.LaunchedEffect(window, page) {
            window?.setLayout(android.view.ViewGroup.LayoutParams.MATCH_PARENT, android.view.ViewGroup.LayoutParams.MATCH_PARENT)
            window?.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(page.toArgb()))
            window?.setDimAmount(0f)
        }
        val setBy = lookRequired ?: themeRequired
        val eyebrow = if (who.isEmpty()) s["firstLookWelcome"].orEmpty() else s["firstLookWelcomeName"].orEmpty().replace("{name}", who)
        val title = s[when { both -> "firstLookSetTitle"; step == 0 -> "firstLookTitle"; else -> "firstThemeTitle" }].orEmpty()
        val lead = when {
            both || (step == 1 && setBy != null) -> SduiLook.lockedWords(setBy!!)
            step == 0 -> s["firstLookDetail"].orEmpty()
            else -> s["firstThemeDetail"].orEmpty()
        }
        // Each step is a page of its own, read from the top.
        androidx.compose.runtime.key(step) {
        DesignPage(
            title, Modifier, eyebrow = eyebrow, lead = lead, tag = "chooselook",
            actions = {
                when {
                    both || (step == 0 && themeRequired != null) -> WittyButton(s["continue"].orEmpty(), { finish() }, kind = ButtonKind.Primary, focusKey = "first-continue", takeFocus = both || looks.isEmpty())
                    step == 0 -> WittyButton(s["next"].orEmpty(), { step = 1 }, kind = ButtonKind.Primary, focusKey = "first-next", takeFocus = looks.isEmpty())
                    else -> {
                        WittyButton(s["firstLookUseThis"].orEmpty(), { finish() }, kind = ButtonKind.Primary, focusKey = "first-done", takeFocus = themeRequired != null || themes.isEmpty())
                        if (lookRequired == null) WittyButton(s["back"].orEmpty(), { step = 0 }, kind = ButtonKind.Secondary, focusKey = "first-back")
                    }
                }
            },
        ) {
            if (step == 0 && !both) {
                // Each look in its own theme's colours, as Apple's chooser draws them.
                DesignSection("") {
                    DesignCards(looks.size) { i ->
                        val e = looks[i]
                        val on = e.id == shownLook
                        val wears = themeOf(e.theme)
                        DesignCard(
                            e.name, {
                                if (!busy && !on) {
                                    busy = true
                                    scope.launch { nav.chooseExperience(e.id); busy = false }
                                }
                            },
                            sub = listOfNotNull(e.tagline.ifEmpty { null }, wears?.shownName).joinToString(" · "), on = on,
                            takeFocus = on, focusKey = "first-" + e.id,
                            preview = { ThemedThumb(com.wittywilla.wittymediaclient.net.Wire.of(e.wire, form), e.name, wears, Modifier.fillMaxWidth(), false, portrait) },
                        )
                    }
                }
            } else {
                // The chosen layout, large, in the theme picked.
                val theme = themeOf(shownTheme)
                DesignSection(s["firstThemePreview"].orEmpty()) {
                    // Only a picture: it takes no focus, so the first Down from the heading reaches the themes (#76).
                    PreviewPanel(listOfNotNull(look?.name, theme?.shownName).joinToString(" · "), theme?.let { if (it.scheme == "light") s["themeLight"].orEmpty() else s["themeDark"].orEmpty() }.orEmpty()) {
                        Box(Modifier.fillMaxWidth(), contentAlignment = androidx.compose.ui.Alignment.Center) {
                            // At most 320 tall (460 on a TV), as Apple's, so the one preview never fills the screen.
                            ThemedThumb(wire, look?.name.orEmpty(), theme, if (portrait) Modifier.width(178.dp) else Modifier.widthIn(max = if (LocalMetrics.current.tv) LocalMetrics.current.u(736) else 512.dp), false, portrait)
                        }
                    }
                }
                // The theme shown as chosen takes the focus; when it isn't one of these (a web-only theme), the first does.
                val focusTheme = themes.firstOrNull { it.id == shownTheme }?.id ?: themes.firstOrNull()?.id
                if (themeRequired == null) {
                    DesignSection(s["firstThemeThemes"].orEmpty()) {
                        DesignCards(themes.size) { i ->
                            val t = themes[i]
                            DesignCard(
                                t.shownName, { nav.chooseTheme(t.id) }, sub = if (t.scheme == "light") s["themeLight"].orEmpty() else s["themeDark"].orEmpty(),
                                on = t.id == shownTheme, takeFocus = t.id == focusTheme, focusKey = "first-theme-" + t.id,
                                preview = { ThemedThumb(wire, t.shownName, t, Modifier.fillMaxWidth(), false, portrait) },
                            )
                        }
                    }
                    // A TV has no files to pick from, nor a way through a file picker with a remote.
                    if (!LocalMetrics.current.tv) DesignSection("") {
                        WittyButton(s["themeImport"].orEmpty(), { picker.launch("*/*") }, kind = ButtonKind.Secondary, focusKey = "first-import")
                        if (said.isNotEmpty()) Note(said)
                    }
                }
            }
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

// A card's look without being a control: what the theme page previews. A TV's remote passes over it.
@Composable
private fun PreviewPanel(title: String, sub: String, picture: @Composable () -> Unit) {
    val ds = LocalDesignSizes.current
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    Column(
        Modifier.fillMaxWidth().background(scheme.surface, metrics.corner(10)).padding(ds.gap * 0.8f)
            .semantics(mergeDescendants = true) { contentDescription = listOf(title, sub).filter { it.isNotEmpty() }.joinToString(", ") },
    ) {
        Box(Modifier.fillMaxWidth().clip(metrics.corner(6))) { picture() }
        Spacer(Modifier.height(6.dp))
        Text(title, color = scheme.onSurface, fontSize = ds.small, fontWeight = androidx.compose.ui.text.font.FontWeight.ExtraBold)
        if (sub.isNotEmpty()) Text(sub, color = scheme.onSurfaceVariant, fontSize = ds.tiny)
    }
}
