// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wittywilla.wittymediaclient.net.AppTheme
import com.wittywilla.wittymediaclient.net.BrandColor
import com.wittywilla.wittymediaclient.net.BrandContrast
import com.wittywilla.wittymediaclient.net.BrandDraft
import com.wittywilla.wittymediaclient.net.BrandEditor
import com.wittywilla.wittymediaclient.net.BrandKinds
import com.wittywilla.wittymediaclient.net.BrandMarkChoice
import com.wittywilla.wittymediaclient.net.BrandName
import com.wittywilla.wittymediaclient.net.BrandServerView
import com.wittywilla.wittymediaclient.net.BrandSurfaces
import com.wittywilla.wittymediaclient.net.LayoutApi
import com.wittywilla.wittymediaclient.net.LetterSelection
import com.wittywilla.wittymediaclient.net.LogoFile
import com.wittywilla.wittymediaclient.net.SduiDevice
import com.wittywilla.wittymediaclient.net.ThemeColour
import com.wittywilla.wittymediaclient.net.problemWords
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// Settings, Appearance, Name and logo (docs/plans/DESIGN-2.md 7.6 and 9; the canvas page BrandEditor): the server's name with
// a colour for every letter or word, presets, the contrast check, the rail's mark, and the name in every frame it appears
// in as it is edited. Saved through PUT /settings (brandName, brandColouring, brandSpans, brandMark) and the logo route.
// The rules are in net/BrandEditor.kt, tested without a screen.

private val THEME_SWATCHES = listOf(
    Triple("Text", BrandColor.FG, "the text colour"),
    Triple("Accent", BrandColor.ACCENT, "the accent"),
    Triple("Success", BrandColor.token("ok"), "success"),
    Triple("Warning", BrandColor.token("warn"), "warning"),
    Triple("Danger", BrandColor.token("danger"), "danger"),
)

private val FIXED_SWATCHES = listOf("Rust" to "#b4491f", "Blue" to "#1e9be0", "Green" to "#3ddc84", "Yellow" to "#ffd84a", "Pink" to "#ff4fa3")

private val GRADIENT_SWATCHES = listOf(
    "Blue to green" to listOf("#0a6aa8", "#1e9be0", "#3aa84a"),
    "Pink to yellow" to listOf("#ff4fa3", "#ffd84a"),
)

private fun colourOf(hex: String): Color = ThemeColour.parse(hex)?.let { Color(it.argb) } ?: Color.Gray

// The letters the first coloured piece covers, or else the second word (the canvas starts on "Media").
private fun firstSelection(d: BrandDraft): LetterSelection {
    val at = d.looks.indexOfFirst { it.color.kind != BrandKinds.FG }
    if (at >= 0) {
        var end = at
        while (end + 1 < d.looks.size && d.looks[end + 1] == d.looks[at]) end++
        return LetterSelection(picked = (at..end).toSet(), cursor = at)
    }
    val words = BrandEditor.words(d.name)
    val word = words.getOrNull(1) ?: words.firstOrNull() ?: return LetterSelection()
    return LetterSelection(picked = word.toSet(), cursor = word.first)
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun BrandEditorScreen(nav: Nav, s: Map<String, String>) {
    val scope = rememberCoroutineScope()
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val metrics = LocalMetrics.current
    val context = LocalContext.current
    val api = nav.app.api
    val layout = remember(api, nav.sduiDevice) { LayoutApi(api, nav.sduiDevice ?: SduiDevice("android", "phone")) }
    val admin = nav.me?.isAdmin == true

    var loading by remember { mutableStateOf(admin) }
    var failed by remember { mutableStateOf("") }
    var draft by remember { mutableStateOf(BrandEditor.autoDraft(BrandName.DEFAULT)) }
    var saved by remember { mutableStateOf(draft) }
    var selection by remember { mutableStateOf(LetterSelection()) }
    var server by remember { mutableStateOf<BrandServerView?>(null) }
    var pendingLogo by remember { mutableStateOf<ByteArray?>(null) }
    var removeLogo by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var problem by remember { mutableStateOf("") }
    var said by remember { mutableStateOf("") }
    var anyColour by remember { mutableStateOf(false) }
    var editStops by remember { mutableStateOf(false) }
    var previewId by remember { mutableStateOf("") }

    val hasLogo = pendingLogo != null || (nav.brandLogo.isNotEmpty() && !removeLogo)
    val logoModel: Any? = pendingLogo ?: nav.brandLogo.takeIf { it.isNotEmpty() && !removeLogo }

    LaunchedEffect(layout, admin) {
        if (!admin) return@LaunchedEffect
        try {
            val settings = layout.settings()
            val view = BrandServerView.from(layout.theme())
            val name = settings["brandName"].orEmpty().ifEmpty { BrandName.DEFAULT }
            val mark = BrandEditor.markFrom(settings["brandMark"].orEmpty())
            val start = view?.parts?.takeIf { it.isNotEmpty() }?.let { BrandEditor.fromParts(name, it, mark) } ?: BrandEditor.autoDraft(name, mark)
            draft = start
            saved = start
            selection = firstSelection(start)
            server = view
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (!nav.handleExpired(e)) failed = problemWords(e, "Could not read the server's name")
        }
        loading = false
    }
    // Every theme's colours, for the contrast check and the preview in other themes.
    LaunchedEffect(nav.themeList) { nav.themeList?.themes?.forEach { nav.wantTheme(it.id) } }

    val themes: List<AppTheme> = nav.themes.values.sortedBy { it.name }
    val current = LocalAppTheme.current
    val surfaces = remember(themes.map { it.id }, current?.id) { (themes.ifEmpty { listOfNotNull(current) }).map { BrandSurfaces.of(it) } }
    val contrast: List<BrandContrast> by remember(draft, surfaces) { derivedStateOf { BrandEditor.contrast(draft, surfaces) } }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            val bytes = withContext(Dispatchers.IO) {
                runCatching {
                    context.contentResolver.openInputStream(uri)?.use { input ->
                        val out = java.io.ByteArrayOutputStream()
                        val buffer = ByteArray(16 * 1024)
                        while (out.size() <= BrandEditor.MAX_LOGO_BYTES) {
                            val n = input.read(buffer)
                            if (n < 0) break
                            out.write(buffer, 0, n)
                        }
                        out.toByteArray()
                    }
                }.getOrNull()
            }
            val why = if (bytes == null) "That file couldn't be read." else LogoFile.problem(bytes)
            if (why != null || bytes == null) {
                problem = why.orEmpty()
                said = problem
            } else {
                problem = ""
                pendingLogo = bytes
                removeLogo = false
                draft = draft.copy(mark = BrandMarkChoice(BrandEditor.MARK_IMAGE))
                val info = LogoFile.read(bytes)
                said = if (info != null && !info.square) "Logo chosen. It isn't square, so it is fitted inside the badge." else "Logo chosen."
            }
        }
    }

    val picked = selection.picked
    val everything = (0 until draft.size).toSet()
    fun paint(color: BrandColor) {
        draft = BrandEditor.painted(draft, picked.ifEmpty { everything }, color)
        said = "Colour applied to ${if (picked.isEmpty()) "the whole name" else "${picked.size} ${if (picked.size == 1) "letter" else "letters"}"}"
    }
    fun preset(next: BrandDraft, name: String) {
        draft = next
        selection = firstSelection(next)
        said = "$name preset applied"
    }
    val chosenLook = draft.looks.getOrNull((picked.minOrNull() ?: 0))
    val chosenColour = chosenLook?.color

    fun save() {
        if (busy) return
        val why = BrandEditor.problem(draft) ?: if (draft.mark.kind == BrandEditor.MARK_IMAGE && !hasLogo) "Upload a logo first, or choose another mark." else null
        if (why != null) { problem = why; said = why; return }
        problem = ""
        busy = true
        scope.launch {
            try {
                pendingLogo?.let { layout.uploadLogo(it, LogoFile.kindOf(it)?.mime ?: "image/png") }
                if (removeLogo && pendingLogo == null) layout.removeLogo()
                layout.saveSettings(BrandEditor.settings(draft))
                nav.reloadBrand()
                server = BrandServerView.from(layout.theme())
                saved = draft
                pendingLogo = null
                removeLogo = false
                said = "Saved"
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (!nav.handleExpired(e)) { problem = problemWords(e, "Could not save the name"); said = problem }
            }
            busy = false
        }
    }

    fun resetToDefault() {
        val fresh = BrandEditor.autoDraft(BrandName.DEFAULT)
        draft = fresh
        selection = firstSelection(fresh)
        pendingLogo = null
        removeLogo = nav.brandLogo.isNotEmpty()
        said = "Back to the default name. Save to keep it."
    }

    BackHandler { nav.pop() }

    val wide = metrics.tv || LocalConfiguration.current.screenWidthDp >= 840
    Screen {
        Column(Modifier.fillMaxSize().then(if (metrics.tv) Modifier.padding(horizontal = metrics.gutter, vertical = metrics.edge) else Modifier.safeDrawingPadding())) {
            if (!metrics.tv) BackArrow({ nav.pop() }, Modifier.padding(Space.S1))
            when {
                !admin -> Note("Only an administrator can change the server's name and logo.", Modifier.padding(Space.S4))
                loading -> Loading()
                failed.isNotEmpty() -> Problem(failed, Modifier.padding(Space.S4))
                else -> {
                    val controls: @Composable () -> Unit = {
                        EditorControls(
                            nav = nav, draft = draft, selection = selection, hasLogo = hasLogo, logoModel = logoModel,
                            themes = themes, chosenColour = chosenColour, chosenBold = chosenLook?.bold == true, picked = picked,
                            contrast = contrast, server = server, problem = problem, busy = busy, dirty = draft != saved || pendingLogo != null || removeLogo,
                            onName = { text -> draft = BrandEditor.renamed(draft, text); selection = selection.within(draft.size) },
                            onSelection = { selection = it },
                            onPaint = ::paint,
                            onBold = { on -> draft = BrandEditor.bolded(draft, picked.ifEmpty { everything }, on) },
                            onPreset = ::preset,
                            onMark = { m -> draft = draft.copy(mark = m); if (m.kind != BrandEditor.MARK_IMAGE) said = "Mark: ${BrandEditor.markShown(draft.name, m)}" },
                            onUpload = { picker.launch("image/*") },
                            onRemoveLogo = { pendingLogo = null; removeLogo = true; if (draft.mark.kind == BrandEditor.MARK_IMAGE) draft = draft.copy(mark = BrandMarkChoice()) },
                            onAnyColour = { anyColour = true },
                            onEditStops = { editStops = true },
                            onSave = ::save, onReset = ::resetToDefault,
                        )
                    }
                    val previews: @Composable () -> Unit = {
                        PreviewColumn(nav, draft, logoModel, themes, previewId) { previewId = it }
                    }
                    if (wide) {
                        Row(Modifier.fillMaxSize().padding(horizontal = if (metrics.tv) 0.dp else metrics.gutter), horizontalArrangement = Arrangement.spacedBy(metrics.u(40))) {
                            Column(Modifier.weight(1f).widthIn(max = 640.dp).fillMaxSize().verticalScroll(rememberScrollState()).padding(bottom = metrics.u(24))) { controls() }
                            Column(Modifier.weight(1f).fillMaxSize().verticalScroll(rememberScrollState()).padding(bottom = metrics.u(24))) { previews() }
                        }
                    } else {
                        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = Space.S4).padding(bottom = Space.S6)) {
                            controls()
                            previews()
                        }
                    }
                }
            }
        }
        // What was done and what went wrong, spoken as it happens and kept out of sight.
        Box(Modifier.semantics { liveRegion = LiveRegionMode.Polite; contentDescription = said }.size(1.dp))
    }

    if (anyColour) {
        val start = (chosenColour?.takeIf { it.kind == BrandKinds.STATIC }?.hex ?: "#b4491f")
        ColourPickerDialog("Any colour", start, { hex -> anyColour = false; paint(BrandColor.fixed(hex)) }, { anyColour = false })
    }
    if (editStops) {
        val g = chosenColour?.takeIf { it.kind == BrandKinds.GRADIENT }
        GradientDialog(g?.stops.orEmpty(), g?.angle ?: 90, { stops, angle -> editStops = false; paint(BrandColor.gradient(stops, angle)) }, { editStops = false })
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun EditorControls(
    nav: Nav, draft: BrandDraft, selection: LetterSelection, hasLogo: Boolean, logoModel: Any?, themes: List<AppTheme>,
    chosenColour: BrandColor?, chosenBold: Boolean, picked: Set<Int>, contrast: List<BrandContrast>, server: BrandServerView?,
    problem: String, busy: Boolean, dirty: Boolean,
    onName: (String) -> Unit, onSelection: (LetterSelection) -> Unit, onPaint: (BrandColor) -> Unit, onBold: (Boolean) -> Unit,
    onPreset: (BrandDraft, String) -> Unit, onMark: (BrandMarkChoice) -> Unit, onUpload: () -> Unit, onRemoveLogo: () -> Unit,
    onAnyColour: () -> Unit, onEditStops: () -> Unit, onSave: () -> Unit, onReset: () -> Unit,
) {
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val metrics = LocalMetrics.current
    EdLabel("Settings · Appearance · Name and logo", accent = true)
    Text("Your server's name", color = scheme.onBackground, style = MaterialTheme.typography.title, modifier = Modifier.semantics { heading() })

    EdLabel("Name")
    WittyField(draft.name, onName, "Server name", Modifier.fillMaxWidth(), maxLength = BrandEditor.MAX_RUNES, imeAction = androidx.compose.ui.text.input.ImeAction.Done)

    // The letters, to choose one by one, or a word at a time.
    EdLabel("Choose letters or words to colour")
    val letters = draft.letters
    Row(Modifier.onPreviewKeyEvent { e ->
        if (e.type == KeyEventType.KeyDown && e.key == Key.Spacebar) { onSelection(selection.space()); true } else false
    }) {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(metrics.u(4)), verticalArrangement = Arrangement.spacedBy(metrics.u(4)), modifier = Modifier.semantics { contentDescription = "Letters of the name" }) {
            letters.forEachIndexed { i, letter ->
                val on = i in picked
                val look = draft.looks[i]
                val tint = when (look.color.kind) {
                    BrandKinds.STATIC -> colourOf(look.color.hex)
                    BrandKinds.GRADIENT -> look.color.stops.firstOrNull()?.let(::colourOf) ?: scheme.onSurface
                    BrandKinds.ACCENT -> extra.brandAccent
                    BrandKinds.TOKEN -> LocalAppTheme.current?.let { t -> BrandEditor.tokenColour(look.color.token, t) }?.let { Color(it.argb) } ?: scheme.onSurface
                    else -> scheme.onSurface
                }
                Pressable(
                    { onSelection(selection.tap(i)) },
                    Modifier.onFocusChanged { if (it.isFocused) onSelection(selection.moveTo(i, letters.size)) },
                    shape = RoundedCornerShape(metrics.u(8)), fill = if (on) scheme.primary.copy(alpha = 0.25f) else scheme.surfaceVariant,
                    label = "Letter ${if (letter.isBlank()) "space" else letter}, ${i + 1} of ${letters.size}", state = if (on) "Chosen" else null, selected = on,
                    focusKey = "~letter$i",
                ) {
                    Box(
                        Modifier.size(width = if (metrics.tv) metrics.u(56) else 36.dp, height = if (metrics.tv) metrics.u(66) else 44.dp)
                            .then(if (on) Modifier.border(2.dp, extra.accentText, RoundedCornerShape(metrics.u(8))) else Modifier),
                        contentAlignment = Alignment.Center,
                    ) { Text(if (letter.isBlank()) "·" else letter, color = tint, fontSize = (18 * (if (metrics.tv) 1.4f else 1f)).sp, fontWeight = FontWeight.ExtraBold) }
                }
            }
        }
    }
    Text(
        "Tap letters, or use the arrows and Space to take a range. Nothing chosen colours the whole name.",
        color = scheme.onSurfaceVariant, style = MaterialTheme.typography.caption, modifier = Modifier.padding(top = metrics.u(6)),
    )
    val words = BrandEditor.words(draft.name)
    FlowRow(Modifier.padding(top = metrics.u(8)), horizontalArrangement = Arrangement.spacedBy(metrics.u(8)), verticalArrangement = Arrangement.spacedBy(metrics.u(8))) {
        words.forEachIndexed { n, range ->
            val text = letters.subList(range.first, range.last + 1).joinToString("")
            WittyButton(text, { onSelection(selection.onlyWord(range)) }, Modifier.semantics { contentDescription = "Choose the word $text" }, pill = true, focusKey = "~word$n")
        }
        WittyButton("All", { onSelection(selection.all(draft.size)) }, pill = true, focusKey = "~all")
        WittyButton("None", { onSelection(selection.none()) }, pill = true, focusKey = "~none")
    }

    EdLabel("Colour for the selection")
    Text("Follows the theme (changes with the theme)", color = scheme.onBackground, style = MaterialTheme.typography.label)
    FlowRow(horizontalArrangement = Arrangement.spacedBy(metrics.u(10)), verticalArrangement = Arrangement.spacedBy(metrics.u(8)), modifier = Modifier.padding(top = metrics.u(6))) {
        THEME_SWATCHES.forEach { (name, color, words2) ->
            val shown = when (color.kind) {
                BrandKinds.FG -> scheme.onBackground
                BrandKinds.ACCENT -> extra.brandAccent
                else -> when (color.token) { "ok" -> extra.ok; "warn" -> extra.warn; else -> scheme.error }
            }
            Swatch(shown, null, "$name, follows the theme: $words2", chosenColour == color, focusKey = "~theme-$name") { onPaint(color) }
        }
    }
    Text("Fixed colour (stays the same in every theme)", color = scheme.onBackground, style = MaterialTheme.typography.label, modifier = Modifier.padding(top = metrics.u(14)))
    FlowRow(horizontalArrangement = Arrangement.spacedBy(metrics.u(10)), verticalArrangement = Arrangement.spacedBy(metrics.u(8)), modifier = Modifier.padding(top = metrics.u(6))) {
        FIXED_SWATCHES.forEach { (name, hex) ->
            Swatch(colourOf(hex), null, "$name, fixed $hex", chosenColour?.kind == BrandKinds.STATIC && chosenColour.hex == hex, focusKey = "~fixed-$name") { onPaint(BrandColor.fixed(hex)) }
        }
        WittyButton("Any colour…", onAnyColour, pill = true, focusKey = "~any")
        chosenColour?.takeIf { it.kind == BrandKinds.STATIC }?.let { WittyButton(it.hex.uppercase(), onAnyColour, Modifier.semantics { contentDescription = "Fixed colour ${it.hex}. Change it" }, pill = true) }
    }
    Text("Gradient", color = scheme.onBackground, style = MaterialTheme.typography.label, modifier = Modifier.padding(top = metrics.u(14)))
    FlowRow(horizontalArrangement = Arrangement.spacedBy(metrics.u(10)), verticalArrangement = Arrangement.spacedBy(metrics.u(8)), modifier = Modifier.padding(top = metrics.u(6))) {
        GRADIENT_SWATCHES.forEach { (name, stops) ->
            val on = chosenColour?.kind == BrandKinds.GRADIENT && chosenColour.stops == stops
            Pressable(
                { onPaint(BrandColor.gradient(stops)) }, Modifier.size(width = 120.dp, height = if (metrics.tv) metrics.u(66) else 44.dp),
                shape = RoundedCornerShape(50), label = "Gradient, $name", selected = on, state = if (on) "Chosen" else null, focusKey = "~gradient-$name",
            ) {
                Box(Modifier.fillMaxSize().background(Brush.horizontalGradient(stops.map(::colourOf)), RoundedCornerShape(50)).then(if (on) Modifier.border(3.dp, scheme.onBackground, RoundedCornerShape(50)) else Modifier))
            }
        }
        WittyButton("Edit stops…", onEditStops, pill = true, focusKey = "~stops")
    }
    Row(Modifier.padding(top = metrics.u(14)), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(metrics.u(10))) {
        WittyButton(
            if (chosenBold) "Heavy weight: on" else "Heavy weight: off", { onBold(!chosenBold) },
            Modifier.semantics { this.selected = chosenBold }, kind = if (chosenBold) ButtonKind.Primary else ButtonKind.Secondary, pill = true, focusKey = "~bold",
        )
    }

    EdLabel("Presets")
    val media = words.getOrNull(1)?.let { draft.letters.subList(it.first, it.last + 1).joinToString("") }
    FlowRow(horizontalArrangement = Arrangement.spacedBy(metrics.u(8)), verticalArrangement = Arrangement.spacedBy(metrics.u(8))) {
        val auto = BrandEditor.matchesAuto(draft)
        WittyButton(if (media != null) "Accent on \"$media\"" else "Accent", { onPreset(BrandEditor.presetAccentOnMedia(draft), "Accent") }, kind = if (auto) ButtonKind.Primary else ButtonKind.Secondary, pill = true, focusKey = "~preset-accent")
        WittyButton("Two-tone", { onPreset(BrandEditor.presetTwoTone(draft), "Two-tone") }, pill = true, focusKey = "~preset-two")
        WittyButton("One colour", { onPreset(BrandEditor.presetOneColour(draft), "One colour") }, pill = true, focusKey = "~preset-one")
        WittyButton("Plain", { onPreset(BrandEditor.presetPlain(draft), "Plain") }, pill = true, focusKey = "~preset-plain")
        WittyButton("Rainbow letters", { onPreset(BrandEditor.presetRainbow(draft), "Rainbow") }, pill = true, focusKey = "~preset-rainbow")
        WittyButton("Gradient", { onPreset(BrandEditor.presetGradient(draft), "Gradient") }, pill = true, focusKey = "~preset-gradient")
    }

    // The rail's mark.
    EdLabel("Mark for the rail and small spaces")
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(metrics.u(10))) {
        BrandMarkBadge(draft.name, draft.parts, draft.mark, logoModel, if (metrics.tv) metrics.u(66) else 52.dp)
        Text(
            when (draft.mark.kind) {
                BrandEditor.MARK_IMAGE -> "Your logo"
                else -> "Shows ${BrandEditor.markShown(draft.name, draft.mark).ifEmpty { "W" }}"
            },
            color = scheme.onSurfaceVariant, style = MaterialTheme.typography.caption,
        )
    }
    val first = BrandEditor.markShown(draft.name, BrandMarkChoice())
    val initials = BrandEditor.markShown(draft.name, BrandMarkChoice(BrandEditor.MARK_INITIALS))
    val markChoices = buildList {
        add(BrandEditor.MARK_LETTER to "Letter · $first")
        add(BrandEditor.MARK_INITIALS to "Initials · $initials")
        add(BrandEditor.MARK_TEXT to "Your own · 1 to 2 characters")
        if (hasLogo) add(BrandEditor.MARK_IMAGE to "Logo")
    }
    EdChoices(markChoices, draft.mark.kind, "Mark", Modifier.padding(top = metrics.u(8)), focusKey = "~mark") { kind ->
        onMark(BrandMarkChoice(kind, if (kind == BrandEditor.MARK_TEXT) draft.mark.text else ""))
    }
    if (draft.mark.kind == BrandEditor.MARK_TEXT) {
        WittyField(draft.mark.text, { onMark(BrandMarkChoice(BrandEditor.MARK_TEXT, it.take(2))) }, "Your one or two characters", Modifier.padding(top = metrics.u(8)).widthIn(max = 280.dp), maxLength = 2)
    }
    Row(Modifier.padding(top = metrics.u(8)), horizontalArrangement = Arrangement.spacedBy(metrics.u(8))) {
        if (!metrics.tv) WittyButton("Upload a logo…", onUpload, pill = true, focusKey = "~upload")
        if (hasLogo) WittyButton("Remove the logo", onRemoveLogo, pill = true, focusKey = "~remove-logo")
    }
    Text(
        "The mark is always centred in a square badge. A logo is square (PNG or JPEG, up to 2 MB), shown fitted inside the badge, and falls back to the letter on a server it can't load from. It follows the name's colours.",
        color = scheme.onSurfaceVariant, style = MaterialTheme.typography.caption, modifier = Modifier.padding(top = metrics.u(8)),
    )

    // The contrast check: a fixed colour that is hard to read on a surface of a theme.
    if (contrast.isNotEmpty() || (server?.warnings?.isNotEmpty() == true)) {
        Column(
            Modifier.padding(top = metrics.u(20)).fillMaxWidth().background(extra.warn.copy(alpha = 0.13f), RoundedCornerShape(metrics.u(10))).padding(metrics.u(14))
                .semantics(mergeDescendants = true) { },
            verticalArrangement = Arrangement.spacedBy(metrics.u(6)),
        ) {
            if (contrast.isNotEmpty()) {
                Text("Check", color = extra.warn, style = MaterialTheme.typography.label, fontWeight = FontWeight.Bold)
                contrast.take(3).forEach { Text(it.words, color = scheme.onBackground, style = MaterialTheme.typography.secondary) }
                if (contrast.size > 3) Text("and ${contrast.size - 3} more in other themes.", color = scheme.onSurfaceVariant, style = MaterialTheme.typography.caption)
                Text("You can still save it.", color = scheme.onSurfaceVariant, style = MaterialTheme.typography.caption)
            }
            server?.warnings?.takeIf { it.isNotEmpty() }?.let { list ->
                Text("The server says, for the name as it is saved", color = extra.warn, style = MaterialTheme.typography.label, fontWeight = FontWeight.Bold)
                list.take(4).forEach { Text(it.words, color = scheme.onBackground, style = MaterialTheme.typography.secondary) }
            }
        }
    }
    if (problem.isNotEmpty()) Problem(problem, Modifier.padding(top = metrics.u(12)))
    Row(Modifier.padding(top = metrics.u(20)), horizontalArrangement = Arrangement.spacedBy(metrics.u(10)), verticalAlignment = Alignment.CenterVertically) {
        WittyButton("Save", onSave, kind = ButtonKind.Primary, busy = busy, pill = true, focusKey = "~save")
        WittyButton("Reset to default", onReset, pill = true, focusKey = "~reset")
        if (dirty) Text("Not saved yet", color = LocalExtraColours.current.hint, style = MaterialTheme.typography.caption)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun PreviewColumn(nav: Nav, draft: BrandDraft, logo: Any?, themes: List<AppTheme>, previewId: String, onTheme: (String) -> Unit) {
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    EdLabel("Live preview, everywhere the name appears", modifier = Modifier.padding(top = if (metrics.tv) metrics.u(0) else 0.dp))
    if (themes.size > 1) {
        Text("Preview in", color = scheme.onSurfaceVariant, style = MaterialTheme.typography.caption)
        EdChoices(listOf("" to "This theme") + themes.map { it.id to it.name }, previewId, "Preview in theme", Modifier.padding(bottom = metrics.u(10)), focusKey = "~theme-preview", onPick = onTheme)
    }
    val theme = themes.firstOrNull { it.id == previewId }
    PreviewInTheme(theme) {
        // The frames sit on the theme's own page colour, so a theme's surfaces show as they are.
        Column(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.background, RoundedCornerShape(metrics.u(14))).padding(metrics.u(10))) {
            BrandFrames(draft.parts, draft.name, draft.mark, logo, nav.remembered<String>("you-version").orEmpty())
        }
    }
}

// The same screen's colours, from another theme: a name drawn in it as it would be there.
@Composable
fun PreviewInTheme(theme: AppTheme?, content: @Composable () -> Unit) {
    if (theme == null) { content(); return }
    fun c(colour: ThemeColour) = Color(colour.argb)
    val base = MaterialTheme.colorScheme
    val scheme = base.copy(
        primary = c(theme.accent), onPrimary = c(theme.onAccent), background = c(theme.background), onBackground = c(theme.text),
        surface = c(theme.panel), onSurface = c(theme.text), surfaceVariant = c(theme.card), onSurfaceVariant = c(theme.textSecondary),
        outline = c(theme.border), outlineVariant = c(theme.control), error = c(theme.danger),
    )
    val extra = LocalExtraColours.current.copy(
        hint = c(theme.textHint), accentText = c(theme.accentText), ok = c(theme.ok), raised = c(theme.raised), control = c(theme.control),
        warn = c(theme.warn), accentPressed = c(theme.accentPressed), scrim = c(theme.scrim), brandAccent = c(theme.brandAccent), focus = c(theme.focus),
    )
    CompositionLocalProvider(LocalExtraColours provides extra, LocalAppTheme provides theme) {
        MaterialTheme(colorScheme = scheme, typography = MaterialTheme.typography, content = content)
    }
}
