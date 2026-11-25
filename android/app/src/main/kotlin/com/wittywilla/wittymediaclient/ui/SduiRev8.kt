// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import android.view.KeyEvent
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.nativeKeyCode
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.wittywilla.wittymediaclient.net.SduiAction
import com.wittywilla.wittymediaclient.net.SduiCardAction
import com.wittywilla.wittymediaclient.net.SduiControlSpec
import com.wittywilla.wittymediaclient.net.SduiFormValues
import com.wittywilla.wittymediaclient.net.SduiItemActions
import com.wittywilla.wittymediaclient.net.SduiRegionsState
import com.wittywilla.wittymediaclient.net.SduiRegionText
import com.wittywilla.wittymediaclient.net.SduiTarget
import com.wittywilla.wittymediaclient.net.SduiView
import com.wittywilla.wittymediaclient.net.isOn
import com.wittywilla.wittymediaclient.net.str
import com.wittywilla.wittymediaclient.net.withValue
import com.wittywilla.wittymediaclient.tv.TvDialog
import com.wittywilla.wittymediaclient.tv.TvDialogButton
import com.wittywilla.wittymediaclient.tv.TvLayer
import kotlinx.serialization.json.JsonPrimitive

// What catalogue revision 8 added to the renderer (the server's docs/SDUI.md: Detail panels, focusGrow and item actions;
// Forms and controls; Shell regions; navigate `as: "layer"` and `confirm`). The rules are in net/SduiRev8.kt, where they are
// tested; this is the part that needs a screen.

// MARK: focusGrow and the detail panel

// A Shelf with focusGrow or detail: which card is the chosen one, how much it grows, and whether a first tap only chooses.
class SduiGrow(val scale: Float, val selected: Boolean, val tapSelects: Boolean, val onSelect: () -> Unit)

// The card takes the shelf's choice when it gets focus (a D-pad), or a mouse or pen comes over it.
fun Modifier.sduiSelects(grow: SduiGrow, @Suppress("UNUSED_PARAMETER") id: String): Modifier =
    onFocusChanged { if (it.hasFocus) grow.onSelect() }.pointerInput(grow.onSelect) {
        awaitPointerEventScope {
            while (true) {
                val event = awaitPointerEvent()
                if (event.type == PointerEventType.Enter) grow.onSelect()
            }
        }
    }

// A pad's X and Y on a card that has an action carrying that glyph run it, as the glyph on its button says.
@Composable
fun Modifier.sduiPadKeys(view: SduiView): Modifier {
    val env = LocalSdui.current
    if (view.props["actions"] == null) return this
    return onPreviewKeyEvent { event ->
        if (event.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
        val glyph = when (event.key.nativeKeyCode) {
            KeyEvent.KEYCODE_BUTTON_X -> "x"
            KeyEvent.KEYCODE_BUTTON_Y -> "y"
            else -> return@onPreviewKeyEvent false
        }
        val action = SduiItemActions.forGlyph(view, glyph) ?: return@onPreviewKeyEvent false
        env.act(action)
        true
    }
}

// The presence dot on a person's avatar, in the tone the card style gives the badge: the same on every app.
@Composable
fun PresenceDot(tone: String, modifier: Modifier = Modifier) {
    val env = LocalSdui.current
    val extra = LocalExtraColours.current
    val colour = when (tone) { "ok" -> extra.ok; "warn" -> extra.warn; else -> extra.hint }
    val size = env.pt(if (env.tv) 26 else 14)
    Box(modifier.size(size).clip(CircleShape).background(MaterialTheme.colorScheme.background).padding(env.pt(if (env.tv) 4 else 2))) {
        Box(Modifier.fillMaxSize().clip(CircleShape).background(colour))
    }
}

// A key's glyph in a small ring: A, B, X, Y of the shared pad map.
@Composable
fun GlyphChip(glyph: String, modifier: Modifier = Modifier) {
    val env = LocalSdui.current
    val scheme = MaterialTheme.colorScheme
    Box(
        modifier.size(env.pt(if (env.tv) 40 else 24)).border(env.pt(if (env.tv) 2 else 1), scheme.outline, CircleShape).clearAndSetSemantics { },
        contentAlignment = Alignment.Center,
    ) { Text(glyph.uppercase(), color = scheme.onBackground, fontSize = env.size("caption"), fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis) }
}

// The panel under a row for the chosen card: its title large, its subtitle as one line, and its actions as buttons that
// carry their key glyphs.
@Composable
fun SduiDetailPanel(card: SduiView?, side: Dp) {
    val env = LocalSdui.current
    val scheme = MaterialTheme.colorScheme
    if (card == null) return
    val buttons = SduiItemActions.buttons(card)
    Column(Modifier.fillMaxWidth().padding(horizontal = side).padding(top = env.space("s")), verticalArrangement = Arrangement.spacedBy(env.space("xs"))) {
        Text(
            card.props.str("title"), color = scheme.onBackground, fontSize = env.size("heading"), fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.semantics { heading() },
        )
        card.props.str("subtitle").takeIf { it.isNotEmpty() }?.let {
            Text(it, color = scheme.onSurfaceVariant, fontSize = env.size("body"), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (buttons.isNotEmpty()) Row(Modifier.padding(top = env.space("xs")).focusGroup(), horizontalArrangement = Arrangement.spacedBy(env.space("s"))) {
            buttons.forEach { SduiGlyphButton(card, it) }
        }
    }
}

// An item's own buttons (a friend's Invite, an invite's Accept and Decline) under it, as the website's: beside the row or
// card, never inside it, so a button is never inside a button. A Shelf with a detail panel shows them there instead.
@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
fun SduiItemButtons(item: SduiView, modifier: Modifier = Modifier) {
    val env = LocalSdui.current
    val buttons = SduiItemActions.of(item.props)
    if (buttons.isEmpty()) return
    androidx.compose.foundation.layout.FlowRow(
        modifier.fillMaxWidth().padding(top = env.space("xs"), bottom = env.space("s")).focusGroup().then(if (env.tv) Modifier.remoteRow() else Modifier),
        horizontalArrangement = Arrangement.spacedBy(env.space("s")), verticalArrangement = Arrangement.spacedBy(env.space("xs")),
    ) { buttons.forEach { SduiGlyphButton(item, it) } }
}

@Composable
private fun SduiGlyphButton(card: SduiView, button: SduiCardAction) {
    val env = LocalSdui.current
    val scheme = MaterialTheme.colorScheme
    Pressable(
        { env.act(button.action) }, Modifier.heightIn(min = env.pt(if (env.tv) 66 else 44)), shape = Radius.FULL, fill = scheme.surfaceVariant, label = button.label,
        focusKey = "${card.id}~${button.id}".takeIf { env.tv }, ring = env.tv,
    ) {
        Row(
            Modifier.heightIn(min = env.pt(if (env.tv) 66 else 44)).padding(horizontal = env.pt(if (env.tv) 24 else 14)),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(env.space("xs")),
        ) {
            if (button.glyph.isNotEmpty()) GlyphChip(button.glyph)
            Text(button.label, color = scheme.onBackground, fontSize = env.size("body"), fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

// MARK: controls and the Form

// The Form a row is in, when it is in one: its controls run nothing when changed, the form's Save runs everything.
class SduiFormHold(val values: SduiFormValues) {
    var revision by mutableIntStateOf(0)
        private set

    fun set(name: String, value: kotlinx.serialization.json.JsonElement) { values.set(name, value); revision++ }
    fun saved() { values.saved(); revision++ }
    fun value(name: String): kotlinx.serialization.json.JsonElement? { revision; return values[name] }
}

val LocalSduiForm = compositionLocalOf<SduiFormHold?> { null }

// The refusal of the last command, for the Form's line under Save.
val LocalSduiCommandError = compositionLocalOf<androidx.compose.runtime.MutableState<String>?> { null }

// One row of a List that carries a control: the row's words at the start, the control at the end (a field under the words).
@Composable
fun SduiControlLine(view: SduiView, spec: SduiControlSpec) {
    val env = LocalSdui.current
    val scheme = MaterialTheme.colorScheme
    val hint = LocalExtraColours.current.hint
    val form = LocalSduiForm.current
    val p = view.props
    // What the person sees: the form's value while it is edited, else what the page said; a flip outside a form shows at once and
    // is replaced by what the server has when the page is asked for again.
    var picked by remember(view.node) { mutableStateOf<kotlinx.serialization.json.JsonElement?>(null) }
    val shown = (if (form != null && spec.name.isNotEmpty() && !spec.disabled) form.value(spec.name) else null) ?: picked ?: spec.value
    val enabled = !spec.disabled
    // A switch's action is what flipping it does, the new value already in its params; the others take the value as `value`.
    fun choose(value: kotlinx.serialization.json.JsonElement) {
        picked = value
        if (form != null) { form.set(spec.name, value); return }
        val action = view.node.action ?: return
        env.act(if (spec.type == "switch") action else action.withValue(value))
    }
    val on = (shown as? JsonPrimitive)?.content == "true"
    var choosing by remember { mutableStateOf(false) }
    val label = view.label.ifEmpty { p.str("title") }
    Column(Modifier.fillMaxWidth().then(if (enabled) Modifier else Modifier.semantics { }).padding(vertical = env.pt(if (env.tv) 8 else 2))) {
        val toggles = spec.type == "switch"
        Pressable(
            { if (toggles) choose(JsonPrimitive(!on)) else if (spec.type == "select") choosing = true },
            Modifier.fillMaxWidth(), shape = RoundedCornerShape(env.pt(10)), fill = Color.Transparent, label = label + if (toggles) (if (on) ", on" else ", off") else "",
            selected = toggles && on, focusKey = view.id.takeIf { env.tv }, requestFocus = env.tv && view.id == env.screen.focus.default,
            enabled = enabled && (toggles || spec.type == "select"), disabledAlpha = if (enabled) 1f else 0.45f, ring = env.tv, pressScale = 1f,
        ) {
            Row(
                Modifier.fillMaxWidth().heightIn(min = env.pt(if (env.tv) 90 else 56)).padding(horizontal = env.pt(if (env.tv) 24 else 4)).clearAndSetSemantics { },
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(env.space("s")),
            ) {
                if (p.str("icon").isNotEmpty()) Icon(sduiIcon(p.str("icon")), null, tint = scheme.onSurfaceVariant, modifier = Modifier.size(env.pt(if (env.tv) 40 else 22)))
                Column(Modifier.weight(1f)) {
                    Text(view.text["title"].orEmpty(), color = scheme.onBackground, fontSize = env.size("body"), maxLines = view.line("title", 1), overflow = TextOverflow.Ellipsis)
                    view.text["subtitle"]?.let { Text(it, color = hint, fontSize = env.size("caption"), maxLines = view.line("subtitle", 2), overflow = TextOverflow.Ellipsis) }
                }
                view.text["trailing"]?.let { Text(it, color = hint, fontSize = env.size("caption"), maxLines = 1, overflow = TextOverflow.Ellipsis) }
                when (spec.type) {
                    "switch" -> Switch(on, null, enabled = enabled)
                    "select" -> {
                        Text(spec.options.firstOrNull { it.first == (shown as? JsonPrimitive)?.content }?.second ?: (shown as? JsonPrimitive)?.content.orEmpty(), color = hint, fontSize = env.size("caption"), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Icon(WebIcons.Down, null, tint = hint, modifier = Modifier.size(env.pt(if (env.tv) 32 else 16)))
                    }
                    "slider" -> Text(sliderWords(spec, (shown as? JsonPrimitive)?.content?.toDoubleOrNull() ?: spec.number), color = hint, fontSize = env.size("caption"), maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
        if (spec.type == "field" && enabled) SduiFieldControl(view, spec, (shown as? JsonPrimitive)?.content.orEmpty(), ::choose)
        if (spec.type == "slider" && enabled) SduiSliderControl(view, spec, (shown as? JsonPrimitive)?.content?.toDoubleOrNull() ?: spec.number, ::choose, form != null)
        if (spec.disabled && spec.why.isNotEmpty()) Text(spec.why, color = hint, fontSize = env.size("caption"), modifier = Modifier.padding(horizontal = env.pt(if (env.tv) 24 else 4)))
    }
    if (choosing) SduiChooser(label, spec.options.map { it.second to it.first }, (shown as? JsonPrimitive)?.content.orEmpty(), { choosing = false }) { choose(JsonPrimitive(it)) }
}

private fun sliderWords(spec: SduiControlSpec, value: Double): String {
    val whole = value == Math.floor(value)
    return (if (whole) value.toLong().toString() else "%.1f".format(value)) + if (spec.unit.isEmpty()) "" else " ${spec.unit}"
}

// A text field under its row: saved on Enter or when it loses focus; inside a Form it only keeps the value.
@Composable
private fun SduiFieldControl(view: SduiView, spec: SduiControlSpec, value: String, choose: (kotlinx.serialization.json.JsonElement) -> Unit) {
    val env = LocalSdui.current
    val form = LocalSduiForm.current
    var draft by remember(view.node, value) { mutableStateOf(value) }
    fun commit() { if (draft != value) choose(JsonPrimitive(draft)) }
    val kind = FieldKind.Text
    WittyField(
        draft, { draft = if (spec.maxLength > 0) it.take(spec.maxLength) else it; if (form != null) choose(JsonPrimitive(draft)) },
        spec.placeholder.ifEmpty { view.props.str("title") },
        Modifier.fillMaxWidth().padding(horizontal = env.pt(if (env.tv) 24 else 4)).onFocusChanged { if (!it.hasFocus && form == null) commit() },
        kind = kind, onAction = { if (form == null) commit() }, maxLength = if (spec.maxLength > 0) spec.maxLength else Int.MAX_VALUE,
    )
}

// A slider under its row: a release is the choice.
@Composable
private fun SduiSliderControl(view: SduiView, spec: SduiControlSpec, value: Double, choose: (kotlinx.serialization.json.JsonElement) -> Unit, inForm: Boolean) {
    val env = LocalSdui.current
    var live by remember(view.node, value) { mutableStateOf(value.toFloat()) }
    val steps = (((spec.max - spec.min) / spec.step).toInt() - 1).coerceAtLeast(0)
    fun finish() {
        val snapped = Math.round((live - spec.min) / spec.step) * spec.step + spec.min
        choose(JsonPrimitive(if (snapped == Math.floor(snapped)) snapped.toLong() else snapped))
    }
    Slider(
        live, { live = it; if (inForm) finish() }, Modifier.fillMaxWidth().padding(horizontal = env.pt(if (env.tv) 24 else 4)).semantics { contentDescription = view.label },
        valueRange = spec.min.toFloat()..spec.max.toFloat(), steps = steps, onValueChangeFinished = { if (!inForm) finish() },
    )
}

// The Form: its rows as they are, and at the foot a Save and a Cancel. Controls inside it run nothing when changed; Save runs the
// form's command with every named control's value under its name.
@Composable
fun SduiFormView(view: SduiView, side: Dp) {
    val env = LocalSdui.current
    val scheme = MaterialTheme.colorScheme
    val hold = remember(view.node) { SduiFormHold(SduiFormValues.of(view)) }
    val p = view.props
    val submit = view.node.action
    CompositionLocalProvider(LocalSduiForm provides hold) {
        Column(Modifier.fillMaxWidth().then(if (env.tv) Modifier else Modifier.widthIn(max = 720.dp)).semantics { contentDescription = p.str("title") }, verticalArrangement = Arrangement.spacedBy(env.space("s"))) {
            p.str("title").takeIf { it.isNotEmpty() }?.let {
                Text(it, color = scheme.onBackground, fontSize = env.size("heading"), fontWeight = FontWeight.Bold, modifier = Modifier.padding(horizontal = side).semantics { heading() })
            }
            view.children.forEach { SduiNode(it, view, topLevel = side > 0.dp) }
            val refused = LocalSduiCommandError.current?.value.orEmpty()
            if (refused.isNotEmpty()) Text(refused, color = scheme.error, fontSize = env.size("caption"), modifier = Modifier.padding(horizontal = side).semantics { liveRegion = androidx.compose.ui.semantics.LiveRegionMode.Assertive })
            Row(Modifier.fillMaxWidth().padding(horizontal = side).padding(top = env.space("xs")), horizontalArrangement = Arrangement.spacedBy(env.space("s"))) {
                val save = p.str("submitLabel").ifEmpty { "Save" }
                // On a television Save is off until something has changed; elsewhere it is always there to press.
                val ready = submit != null && (!env.tv || hold.revision >= 0 && hold.values.changed)
                if (env.tv) WittyButton(save, { submit?.let { env.act(hold.values.submit(it)); hold.saved() } }, kind = ButtonKind.Primary, pill = true, enabled = ready, focusKey = view.id + "~save")
                else WebButton(save, { submit?.let { env.act(hold.values.submit(it)); hold.saved() } }, WebButtonKind.Primary, enabled = ready)
                p.str("cancelLabel").takeIf { it.isNotEmpty() }?.let { cancel ->
                    if (env.tv) WittyButton(cancel, { env.act(SduiAction(type = "back")) }, kind = ButtonKind.Secondary, pill = true, focusKey = view.id + "~cancel")
                    else WebButton(cancel, { env.act(SduiAction(type = "back")) }, WebButtonKind.Secondary)
                }
            }
        }
    }
}

// MARK: layers and questions

// What closes the layer a page is shown in: a press that opens a route closes the layer first.
val LocalSduiLayerClose = compositionLocalOf<(() -> Unit)?> { null }

// A page shown over the screen (navigate `as: "layer"`): a sheet from the foot on a touch screen, a panel over a dimmed screen on a TV.
// Back closes it and focus stays in it.
@Composable
fun SduiLayer(nav: Nav, target: SduiTarget.Page, close: () -> Unit) {
    val tv = LocalMetrics.current.tv
    val scheme = MaterialTheme.colorScheme
    CompositionLocalProvider(LocalSduiLayerClose provides close) {
        if (tv) {
            // Focus goes into the panel as it opens, to its first control once the page has drawn one (the page under it
            // kept focus before, so the first press only moved into the panel).
            val into = remember { androidx.compose.ui.focus.FocusRequester() }
            var inside by remember { androidx.compose.runtime.mutableStateOf(false) }
            LaunchedEffect(Unit) {
                repeat(40) {
                    if (inside) return@LaunchedEffect
                    kotlinx.coroutines.delay(100)
                    runCatching { into.requestFocus() }
                }
            }
            TvLayer(close) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Box(
                        Modifier.fillMaxWidth(0.62f).fillMaxHeight(0.78f).clip(RoundedCornerShape(32.dp)).background(scheme.background)
                            .focusRequester(into).onFocusChanged { inside = it.hasFocus }.focusGroup(),
                    ) {
                        SduiPageScreen(nav, target.page, target.params, layered = true)
                    }
                }
            }
        } else {
            val height = (LocalConfiguration.current.screenHeightDp * 0.72f).dp
            WebSheet("", close, fromRight = false) {
                Box(Modifier.fillMaxWidth().height(height)) { SduiPageScreen(nav, target.page, target.params, layered = true) }
            }
        }
    }
}

// A command's question (action.confirm): the command's label confirms, Cancel keeps things as they are.
@Composable
fun SduiConfirm(question: String, yes: String, onYes: () -> Unit, onNo: () -> Unit) {
    if (LocalMetrics.current.tv) {
        TvDialog("", question, listOf(TvDialogButton(yes, destructive = false, preferred = false, action = onYes), TvDialogButton("Cancel", cancel = true, action = onNo)), onNo)
    } else {
        Confirm(question, yes, "Cancel", onYes, onNo)
    }
}

// MARK: shell regions

// The status bar and the system dock of a page that supplied them (docs/SDUI.md, Shell regions): the shell draws them around
// the screen while the page, or another of the same theme scope, shows.
@Composable
fun SduiRegionsFrame(nav: Nav, content: @Composable () -> Unit) {
    val state = nav.regions
    if (state == null) {
        content()
        return
    }
    // Leaving the module's pages for anything that isn't one of the server's pages takes them away.
    LaunchedEffect(nav.current) { if (nav.current !is Route.Sdui && nav.current != Route.Home) nav.regions = null }
    val bar = !state.hideStatusBar && state.regions.statusBar.isNotEmpty()
    val dock = !state.hideSystemDock && state.regions.systemDock.isNotEmpty()
    val side = dock && state.dockOnSide
    // A remote arrives on the page, not on the bar above it: the bar's button is first in reading order, and Down from it
    // lands on a tab, which is chosen as focus rests there.
    val page = remember { androidx.compose.ui.focus.FocusRequester() }
    // Going from one of its pages to the next, the focused row goes with the old page and focus falls to the bar: bring it
    // into the new page as soon as that has something to stand on.
    var onBar by remember { mutableStateOf(false) }
    LaunchedEffect(nav.current) {
        repeat(PAGE_FOCUS_TRIES) {
            kotlinx.coroutines.delay(PAGE_FOCUS_STEP_MS)
            if (onBar && page.requestFocus()) return@LaunchedEffect
        }
    }
    Column(
        Modifier.fillMaxSize()
            .focusProperties { onEnter = { if (requestedFocusDirection == androidx.compose.ui.focus.FocusDirection.Enter && page.requestFocus()) cancelFocusChange() } }
            .focusGroup(),
    ) {
        if (bar) Box(Modifier.onFocusChanged { onBar = it.hasFocus }) { SduiStatusBar(nav, state) }
        Row(Modifier.weight(1f).fillMaxWidth()) {
            if (side) SduiSystemDock(nav, state, vertical = true)
            Box(Modifier.weight(1f).fillMaxHeight().focusRequester(page).focusGroup()) {
                CompositionLocalProvider(LocalDockBelow provides (dock && !side)) { content() }
            }
        }
        if (dock && !side) SduiSystemDock(nav, state, vertical = false)
    }
}

// The frame draws its system dock under the page, so the page needn't keep the screen's bottom edge itself.
val LocalDockBelow = compositionLocalOf { false }

private const val PAGE_FOCUS_TRIES = 15
private const val PAGE_FOCUS_STEP_MS = 100L

// Up to six items: the profile's name with its line under it, the server's name drawn from the brand (so its colours survive), text.
// The clock is the shell's own.
@Composable
private fun SduiStatusBar(nav: Nav, state: SduiRegionsState) {
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    val user = nav.me?.let { avatarName(it.displayName, it.name) }.orEmpty()
    val server = nav.brandName
    Row(
        // On a TV, inside the safe area (90 at the sides, 60 at the top), as every TV page is.
        // On a TV the bar sits over the page, as Apple TV's; a phone's has its band.
        Modifier.fillMaxWidth().background(if (metrics.tv) Color.Transparent else scheme.surface)
            .padding(start = metrics.u(if (metrics.tv) 90 else 12), end = metrics.u(if (metrics.tv) 90 else 12), top = metrics.u(if (metrics.tv) 48 else 6), bottom = metrics.u(if (metrics.tv) 12 else 6))
            .semantics { contentDescription = "Status" },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(metrics.u(if (metrics.tv) 32 else 16)),
    ) {
        state.regions.statusBar.forEach { item ->
            when (item.kind) {
                "profile" -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(metrics.u(10))) {
                    Avatar(user.ifEmpty { "?" }, metrics.u(if (metrics.tv) 44 else 32))
                    Column {
                    Text(user, color = scheme.onSurface, style = MaterialTheme.typography.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    SduiRegionText.fill(item.text, user, server).takeIf { it.isNotEmpty() }?.let { Text(it, color = scheme.onSurfaceVariant, style = MaterialTheme.typography.caption, maxLines = 1, overflow = TextOverflow.Ellipsis) }
                    }
                }
                "server" -> Text(com.wittywilla.wittymediaclient.ui.brandAnnotated(server, nav.brandParts, scheme.onSurface, LocalExtraColours.current.brandAccent), style = MaterialTheme.typography.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
                else -> Text(SduiRegionText.fill(item.text, user, server), color = scheme.onSurface, style = MaterialTheme.typography.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        Spacer(Modifier.weight(1f))
        StatusClock()
        // Out of WittyPlay's frame, back to the server's Home.
        Pressable(
            { nav.regions = null; nav.reset(Route.Home) }, shape = CircleShape, fill = scheme.primary.copy(alpha = 0.22f),
            label = "Return To Server", focusKey = "status~return".takeIf { metrics.tv },
        ) {
            Text("Return To Server", color = scheme.onSurface, style = MaterialTheme.typography.label, maxLines = 1, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(horizontal = metrics.u(12), vertical = metrics.u(6)))
        }
    }
}

@Composable
private fun StatusClock() {
    val scheme = MaterialTheme.colorScheme
    val context = androidx.compose.ui.platform.LocalContext.current
    var now by remember { mutableStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { now = System.currentTimeMillis(); kotlinx.coroutines.delay(15_000) } }
    Text(android.text.format.DateFormat.getTimeFormat(context).format(java.util.Date(now)), color = scheme.onSurface, style = MaterialTheme.typography.label, maxLines = 1, overflow = TextOverflow.Ellipsis)
}

// Up to seven round buttons; the one whose route is the page showing carries its label under it.
@Composable
private fun SduiSystemDock(nav: Nav, state: SduiRegionsState, vertical: Boolean) {
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    // 10-foot round buttons on a TV, as Apple TV's 104.
    val size = metrics.u(if (metrics.tv) 104 else 48)
    val home = com.wittywilla.wittymediaclient.net.SduiSystemButton(id = "home", label = "Home", icon = "home", route = com.wittywilla.wittymediaclient.net.WittyPlayPlace.HOME)
    val entries = com.wittywilla.wittymediaclient.net.WittyPlayPlace.dockFor(state.regions.systemDock, { it.id }, { it.route }, home)
    // Search is the app's own; WittyPlay's settings are its server page; a layer goes over; anything else takes this page's place.
    fun press(b: com.wittywilla.wittymediaclient.net.SduiSystemButton) {
        val path = b.route.substringBefore('?')
        when {
            path == "/search" -> nav.reset(Route.Search)
            path == com.wittywilla.wittymediaclient.net.WittyPlayPlace.SETTINGS || path.startsWith(com.wittywilla.wittymediaclient.net.WittyPlayPlace.SETTINGS + "/") ->
                nav.push(Route.Sdui(com.wittywilla.wittymediaclient.net.WittyPlayPlace.SETTINGS_PAGE, emptyMap(), b.label))
            b.layer == "layer" -> nav.go(nav.sduiRouter.resolve(b.route), layer = true)
            else -> nav.routeOf(nav.sduiRouter.resolve(b.route))?.let { nav.replace(it) } ?: nav.go(nav.sduiRouter.resolve(b.route))
        }
    }
    val buttons: @Composable () -> Unit = {
        // The server says which entry is current where it knows (a page under one, as the store under Settings); else the page's address does.
        val told = entries.any { it.current }
        entries.forEach { b ->
            val current = if (told) b.current else (nav.current as? Route.Sdui)?.let { com.wittywilla.wittymediaclient.net.WittyPlayPlace.isCurrent(b.route, it.page, it.params) } == true
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(metrics.u(4))) {
                Pressable(
                    { press(b) }, Modifier.size(size), shape = CircleShape,
                    fill = if (current) scheme.primary else scheme.surfaceVariant, label = b.label, selected = current, focusKey = ("dock~" + b.id).takeIf { metrics.tv },
                ) {
                    Box(Modifier.size(size), contentAlignment = Alignment.Center) {
                        Icon(sduiIcon(b.icon), null, tint = if (current) scheme.onPrimary else scheme.onSurface, modifier = Modifier.size(size / 2))
                    }
                }
                if (current) Text(b.label, color = scheme.onBackground, style = MaterialTheme.typography.caption, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
    if (vertical) Column(Modifier.fillMaxHeight().background(scheme.surface).padding(metrics.u(8)).focusGroup(), verticalArrangement = Arrangement.spacedBy(metrics.u(8)), horizontalAlignment = Alignment.CenterHorizontally) { buttons() }
    else Row(Modifier.fillMaxWidth().background(if (metrics.tv) Color.Transparent else scheme.surface).padding(top = metrics.u(8), bottom = metrics.u(if (metrics.tv) 48 else 8)).focusGroup(), horizontalArrangement = Arrangement.spacedBy(metrics.u(16), Alignment.CenterHorizontally), verticalAlignment = Alignment.Top) { buttons() }
}

// MARK: QR

// The QR component: `value` is an address or, when `isRoute`, a route on the server the app is signed in to (a join link for a
// friend's phone); `size` s, m or l. Black on white whatever the theme, the label under it.
@Composable
fun SduiQr(view: SduiView, side: Dp) {
    val env = LocalSdui.current
    val p = view.props
    val value = p.str("value")
    if (value.isEmpty()) return
    val address = if (p.isOn("isRoute")) env.nav.app.api.base.trimEnd('/') + value else value
    val units = when (p.str("size")) { "s" -> 120; "l" -> 240; else -> 180 } * (if (env.tv) 1.5f else 1f)
    QrCard(address, p.str("label"), Modifier.padding(horizontal = side).fillMaxWidth(), size = units.toInt())
}
