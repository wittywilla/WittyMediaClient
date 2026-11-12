// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.isCtrlPressed
import androidx.compose.ui.input.key.isShiftPressed
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.zIndex
import com.wittywilla.wittymediaclient.net.Dir
import com.wittywilla.wittymediaclient.net.EditorState
import com.wittywilla.wittymediaclient.net.ItemRef
import com.wittywilla.wittymediaclient.net.LayoutApi
import com.wittywilla.wittymediaclient.net.LayoutEditor
import com.wittywilla.wittymediaclient.net.LayoutScope
import com.wittywilla.wittymediaclient.net.LayoutWords
import com.wittywilla.wittymediaclient.net.PlacementsAnswer
import com.wittywilla.wittymediaclient.net.SduiCustomise
import com.wittywilla.wittymediaclient.net.SduiDevice
import com.wittywilla.wittymediaclient.net.SduiPersonal
import com.wittywilla.wittymediaclient.net.problemWords
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.roundToInt

// Edit layout (docs/plans/DESIGN-2.md 7.5; the canvas page LayoutEditor): the page's regions and sections with handles
// and a panel beside it (below it on a phone). One editor, two scopes: For everyone (administrators; the shell's regions,
// kept in the experience policy) and For me (this device; the regions and the page's sections). The rules, the undo stack
// and the words said are in net/LayoutEditor.kt, tested without a screen.
//
// Pick up with OK (or a tap), the arrows move, OK drops, Back puts it back. A drag with a finger or a pointer moves it
// too. Every handle is a named button and every move is announced.

private class Env(
    val ed: EditorState,
    val readOnly: Boolean,
    val requesters: MutableMap<String, FocusRequester>,
    val bounds: MutableMap<String, ClosedFloatingPointRange<Float>>,
    val onFocus: (ItemRef) -> Unit,
    val onPress: (ItemRef) -> Unit,
    val onDragEnd: (ItemRef, Offset) -> Unit,
    val onAct: (ItemRef, ItemAct) -> Unit,
)

private enum class ItemAct { PickUp, Up, Down, Left, Right, Drop, Cancel, Hide, Show }

private fun keyOf(item: ItemRef) = (if (item.section) "section:" else "region:") + item.id

private fun shortWords(id: String, label: String) = when (id) {
    "nav" -> "Navigation"
    "dock" -> "Controls row (Dock)"
    "hero" -> "Spotlight"
    else -> label.ifEmpty { id }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun LayoutEditorScreen(nav: Nav, s: Map<String, String>) {
    val scope = rememberCoroutineScope()
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val api = nav.app.api
    val device = nav.sduiDevice ?: SduiDevice("android", "phone")
    val layout = remember(api, device) { LayoutApi(api, device) }
    val client = nav.sdui
    val admin = nav.me?.isAdmin == true

    var layoutScope by remember { mutableStateOf(if (admin) LayoutScope.Everyone else LayoutScope.Me) }
    var formFactor by remember { mutableStateOf(device.formFactor) }
    var tick by remember { mutableIntStateOf(0) }
    var loading by remember { mutableStateOf(true) }
    var failed by remember { mutableStateOf("") }
    var answer by remember { mutableStateOf<PlacementsAnswer?>(null) }
    var pageUrl by remember { mutableStateOf("") }
    var sized by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    var ed by remember { mutableStateOf<EditorState?>(null) }
    var busy by remember { mutableStateOf(false) }
    var asking by remember { mutableStateOf<String?>(null) }
    var leaving by remember { mutableStateOf(false) }
    val requesters = remember { HashMap<String, FocusRequester>() }
    val bounds = remember { HashMap<String, ClosedFloatingPointRange<Float>>() }

    val ownDevice = formFactor == device.formFactor
    val readOnly = layoutScope == LayoutScope.Me && answer?.editable == false
    val experienceName = nav.experienceList?.experiences?.firstOrNull { it.id == answer?.experience }?.name ?: "the experience"

    LaunchedEffect(layoutScope, formFactor, tick) {
        loading = ed == null
        try {
            val a = layout.placements(formFactor)
            var page: SduiCustomise? = null
            var url = ""
            var cards = emptyMap<String, String>()
            var navStyle = ""
            if (ownDevice && client != null) {
                val doc = runCatching { client.page("home").value }.getOrNull()
                val info = doc?.personal
                navStyle = doc?.layout?.shell?.nav.orEmpty()
                if (doc != null && info != null && info.editable && info.sections.isNotEmpty()) {
                    val saved = runCatching { client.personal(info.url) }.getOrNull() ?: SduiPersonal()
                    page = SduiCustomise.from(info, saved)
                    url = info.url
                    cards = SduiCustomise.sizeChoices(doc.root).associate { (node, size) -> node.id to size }
                }
            }
            answer = a
            pageUrl = url
            sized = cards
            val before = ed
            val fresh = LayoutEditor.start(a, page, sectionsEditable = layoutScope == LayoutScope.Me && ownDevice, navStyle = navStyle)
            ed = fresh.copy(focus = before?.focus?.takeIf { it in LayoutEditor.items(fresh) } ?: fresh.focus, said = before?.said.orEmpty())
            failed = ""
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (!nav.handleExpired(e)) failed = problemWords(e, "Could not read the layout")
        }
        loading = false
    }

    fun update(change: (EditorState) -> EditorState) {
        val now = ed ?: return
        if (readOnly) { ed = now.copy(said = "Rearranging is turned off for this profile."); return }
        ed = change(now)
    }

    fun act(item: ItemRef, what: ItemAct) = update { e ->
        when (what) {
            ItemAct.PickUp -> LayoutEditor.pickUp(e, item)
            ItemAct.Up -> if (e.held != null) LayoutEditor.move(e, Dir.Up) else LayoutEditor.quickMove(e, item, Dir.Up)
            ItemAct.Down -> if (e.held != null) LayoutEditor.move(e, Dir.Down) else LayoutEditor.quickMove(e, item, Dir.Down)
            ItemAct.Left -> if (e.held != null) LayoutEditor.move(e, Dir.Left) else LayoutEditor.quickMove(e, item, Dir.Left)
            ItemAct.Right -> if (e.held != null) LayoutEditor.move(e, Dir.Right) else LayoutEditor.quickMove(e, item, Dir.Right)
            ItemAct.Drop -> LayoutEditor.drop(e)
            ItemAct.Cancel -> LayoutEditor.cancel(e)
            ItemAct.Hide -> LayoutEditor.setVisible(e, item, false)
            ItemAct.Show -> LayoutEditor.setVisible(e, item, true)
        }
    }

    val stepPx = with(LocalDensity.current) { 72.dp.toPx() }
    fun dragEnd(item: ItemRef, by: Offset) {
        update { e ->
            if (e.held != null) return@update e
            if (item.section) {
                val box = bounds[keyOf(item)] ?: return@update e
                val y = (box.start + box.endInclusive) / 2 + by.y
                val target = bounds.entries.firstOrNull { it.key.startsWith("section:") && it.key != keyOf(item) && y in it.value }?.key?.removePrefix("section:")
                if (target == null) e.copy(said = "Dropped back where it was.") else LayoutEditor.dropSectionOn(e, item.id, target)
            } else {
                val dominant = if (abs(by.x) >= abs(by.y)) by.x else by.y
                val steps = (dominant / stepPx).roundToInt()
                if (steps == 0) e.copy(said = "Dropped back where it was.") else LayoutEditor.stepRegion(e, item.id, steps)
            }
        }
    }

    fun doSave() {
        val e = ed ?: return
        val a = answer ?: return
        if (busy || readOnly) return
        busy = true
        scope.launch {
            try {
                when (layoutScope) {
                    LayoutScope.Me -> {
                        val patch = LayoutEditor.placementsPatch(a.placements, a.own, e)
                        if (patch != a.own) layout.savePlacements(patch)
                        e.doc.page?.takeIf { pageUrl.isNotEmpty() && it != e.saved.page }?.let { client?.savePersonal(pageUrl, it.toPersonal()) }
                    }
                    LayoutScope.Everyone -> layout.updateEveryone { policy ->
                        val layer = LayoutEditor.layerOf(policy, a.experience)
                        LayoutEditor.policyWith(policy, a.experience, LayoutEditor.placementsPatch(a.placements, layer, e))
                    }
                }
                nav.reloadSduiNav()
                ed = LayoutEditor.saved(e, if (layoutScope == LayoutScope.Me) "Saved for you" else "Saved for everyone")
                tick++
            } catch (c: CancellationException) {
                throw c
            } catch (x: Exception) {
                if (!nav.handleExpired(x)) ed = e.copy(said = problemWords(x, "Could not save the layout"))
            }
            busy = false
        }
    }

    fun doReset(everything: Boolean) {
        val e = ed ?: return
        val a = answer ?: return
        if (busy) return
        busy = true
        scope.launch {
            try {
                when (layoutScope) {
                    LayoutScope.Me -> {
                        layout.resetPlacements()
                        if (everything && pageUrl.isNotEmpty()) client?.resetPersonal(pageUrl)
                    }
                    LayoutScope.Everyone -> layout.updateEveryone { policy ->
                        if (everything) LayoutEditor.policyWithoutPlacements(policy) else LayoutEditor.policyWith(policy, a.experience, null)
                    }
                }
                nav.reloadSduiNav()
                ed = e.copy(said = if (everything) "Everything is back to how it came" else "Back to the $experienceName look")
                ed = ed?.let { LayoutEditor.saved(it, it.said) }
                tick++
            } catch (c: CancellationException) {
                throw c
            } catch (x: Exception) {
                if (!nav.handleExpired(x)) ed = e.copy(said = problemWords(x, "Could not reset the layout"))
            }
            busy = false
        }
    }

    // Focus stays with what is carried as it moves from one place to another.
    val current = ed
    LaunchedEffect(current?.doc, current?.held) {
        val held = current?.held ?: return@LaunchedEffect
        withFrameNanos { }
        runCatching { requesters[keyOf(held)]?.requestFocus() }
    }

    BackHandler { if (ed?.dirty == true) leaving = true else nav.pop() }
    BackHandler(enabled = current?.held != null) { act(current!!.held!!, ItemAct.Cancel) }

    val wide = metrics.tv || LocalConfiguration.current.screenWidthDp >= 840
    Screen(
        Modifier.onPreviewKeyEvent { e ->
            val state = ed
            if (e.type != KeyEventType.KeyDown || state == null) return@onPreviewKeyEvent false
            if (state.held != null) {
                val item = state.held
                when (e.key) {
                    Key.DirectionUp -> act(item, ItemAct.Up)
                    Key.DirectionDown -> act(item, ItemAct.Down)
                    Key.DirectionLeft -> act(item, ItemAct.Left)
                    Key.DirectionRight -> act(item, ItemAct.Right)
                    Key.Enter, Key.NumPadEnter, Key.DirectionCenter, Key.ButtonA -> act(item, ItemAct.Drop)
                    Key.Escape, Key.ButtonB -> act(item, ItemAct.Cancel)
                    else -> return@onPreviewKeyEvent false
                }
                true
            } else if (e.isCtrlPressed && e.key == Key.Z) {
                update(if (e.isShiftPressed) LayoutEditor::redo else LayoutEditor::undo); true
            } else if (e.isCtrlPressed && e.key == Key.Y) {
                update(LayoutEditor::redo); true
            } else false
        },
    ) {
        Column(Modifier.fillMaxSize().then(if (metrics.tv) Modifier.padding(horizontal = metrics.gutter, vertical = metrics.edge) else Modifier.safeDrawingPadding())) {
            val state = ed
            when {
                loading -> Loading()
                failed.isNotEmpty() || state == null -> {
                    if (!metrics.tv) BackArrow({ nav.pop() }, Modifier.padding(Space.S1))
                    Problem(failed.ifEmpty { "Could not read the layout" }, Modifier.padding(Space.S4))
                }
                else -> {
                    val env = Env(
                        state, readOnly, requesters, bounds,
                        onFocus = { item -> update { LayoutEditor.focus(it, item) } },
                        onPress = { item ->
                            update { e -> if (e.held == null) LayoutEditor.pickUp(e, item) else if (e.held == item) LayoutEditor.drop(e) else LayoutEditor.focus(e, item) }
                        },
                        onDragEnd = ::dragEnd,
                        onAct = ::act,
                    )
                    TopBar(
                        nav, state, admin, layoutScope, readOnly, busy, experienceName,
                        onBack = { if (state.dirty) leaving = true else nav.pop() },
                        onScope = { layoutScope = it; ed = null; loading = true },
                        onUndo = { update(LayoutEditor::undo) }, onRedo = { update(LayoutEditor::redo) },
                        onReset = { doReset(false) }, onResetAll = { asking = "everything" }, onSave = ::doSave,
                    )
                    if (readOnly) Note("Rearranging is turned off for this profile by the server's settings.", Modifier.padding(horizontal = if (metrics.tv) 0.dp else metrics.gutter, vertical = metrics.u(8)))
                    if (wide) {
                        Row(Modifier.weight(1f).fillMaxWidth().padding(horizontal = if (metrics.tv) 0.dp else metrics.gutter), horizontalArrangement = Arrangement.spacedBy(metrics.u(24))) {
                            Column(Modifier.weight(1f).fillMaxSize().verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(metrics.u(12))) {
                                CanvasPage(env)
                                Legend(state, env)
                                if (admin) FormFactors(formFactor, device.formFactor) { formFactor = it; ed = null; loading = true }
                            }
                            Column(Modifier.width(if (metrics.tv) 420.dp else 360.dp).fillMaxSize().verticalScroll(rememberScrollState()).padding(bottom = metrics.u(24))) {
                                SidePanel(nav, state, sized, ownDevice, layoutScope, experienceName, ::update)
                            }
                        }
                    } else {
                        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = metrics.gutter), verticalArrangement = Arrangement.spacedBy(metrics.u(12))) {
                            CanvasPage(env)
                            Legend(state, env)
                            SidePanel(nav, state, sized, ownDevice, layoutScope, experienceName, ::update)
                            if (admin) FormFactors(formFactor, device.formFactor) { formFactor = it; ed = null; loading = true }
                            Box(Modifier.padding(bottom = Space.S8))
                        }
                    }
                    // What is said to a screen reader, and shown.
                    Text(
                        state.said, color = scheme.onSurfaceVariant, style = MaterialTheme.typography.caption, maxLines = 2, overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(horizontal = if (metrics.tv) 0.dp else metrics.gutter, vertical = metrics.u(6)).fillMaxWidth()
                            .semantics { liveRegion = LiveRegionMode.Polite; contentDescription = state.said },
                    )
                }
            }
        }
    }

    if (asking == "everything") {
        Confirm(
            "Reset everything?",
            if (layoutScope == LayoutScope.Me) "Your own arrangement of the shell and of this page goes back to how the $experienceName look came."
            else "Every experience goes back to how it came, for everyone, wherever an administrator moved or hid something.",
            "Reset everything", { asking = null; doReset(true) }, { asking = null },
        )
    }
    if (leaving) Confirm("Leave without saving?", "What you changed since you last saved is lost.", "Leave", { leaving = false; nav.pop() }, { leaving = false })
}

@Composable
private fun Confirm(title: String, words: String, action: String, onYes: () -> Unit, onNo: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val metrics = LocalMetrics.current
    Dialog(onDismissRequest = onNo, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(
            Modifier.padding(metrics.u(16)).widthIn(max = 480.dp).background(scheme.surface, RoundedCornerShape(metrics.u(20))).border(1.dp, scheme.outline, RoundedCornerShape(metrics.u(20))).padding(metrics.u(20)),
            verticalArrangement = Arrangement.spacedBy(metrics.u(12)),
        ) {
            Text(title, color = scheme.onSurface, style = MaterialTheme.typography.title, modifier = Modifier.semantics { heading() })
            Text(words, color = scheme.onSurfaceVariant, style = MaterialTheme.typography.body)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(metrics.u(8), Alignment.End)) {
                WittyButton("Cancel", onNo, pill = true, focusKey = "~confirm-no", requestFocus = true)
                WittyButton(action, onYes, kind = ButtonKind.Destructive, pill = true, focusKey = "~confirm-yes")
            }
        }
    }
}

// The title, the two scopes, undo and redo, the resets and Save.
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun TopBar(
    nav: Nav, state: EditorState, admin: Boolean, scope: LayoutScope, readOnly: Boolean, busy: Boolean, experience: String,
    onBack: () -> Unit, onScope: (LayoutScope) -> Unit, onUndo: () -> Unit, onRedo: () -> Unit, onReset: () -> Unit, onResetAll: () -> Unit, onSave: () -> Unit,
) {
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    FlowRow(
        Modifier.fillMaxWidth().padding(horizontal = if (metrics.tv) 0.dp else metrics.gutter, vertical = metrics.u(8)),
        horizontalArrangement = Arrangement.spacedBy(metrics.u(10)), verticalArrangement = Arrangement.spacedBy(metrics.u(8)), itemVerticalAlignment = Alignment.CenterVertically,
    ) {
        if (!metrics.tv) BackArrow(onBack)
        Text("Edit layout", color = scheme.onBackground, style = MaterialTheme.typography.title, modifier = Modifier.semantics { heading() })
        if (admin) {
            Row(Modifier.background(scheme.surface, RoundedCornerShape(50)).padding(4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                for ((value, label) in listOf(LayoutScope.Everyone to "For everyone", LayoutScope.Me to "For me")) {
                    WittyButton(
                        label, { onScope(value) }, Modifier.semantics { contentDescription = "$label${if (scope == value) ", selected" else ""}" },
                        kind = if (scope == value) ButtonKind.Primary else ButtonKind.Quiet, pill = true, focusKey = "~scope-$label",
                    )
                }
            }
        }
        WittyButton("Undo", onUndo, enabled = state.canUndo && !readOnly, pill = true, focusKey = "~undo")
        WittyButton("Redo", onRedo, enabled = state.canRedo && !readOnly, pill = true, focusKey = "~redo")
        WittyButton("Reset to $experience", onReset, enabled = !busy, pill = true, focusKey = "~reset")
        WittyButton("Reset everything", onResetAll, enabled = !busy, pill = true, focusKey = "~reset-all")
        WittyButton(if (scope == LayoutScope.Me) "Save for me" else "Save for everyone", onSave, kind = ButtonKind.Primary, busy = busy, enabled = state.dirty && !readOnly && state.held == null, pill = true, focusKey = "~save")
    }
}

// The page as the editor draws it: the shell's regions where they are, then the sections in order.
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CanvasPage(env: Env) {
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    val ed = env.ed
    val zones = LayoutEditor.zones(ed.caps.regions, ed.doc, ed.caps.navDefault)
    val gap = metrics.u(8)
    Column(
        Modifier.fillMaxWidth().background(scheme.surface, RoundedCornerShape(metrics.u(14))).border(1.dp, scheme.outline, RoundedCornerShape(metrics.u(14))).padding(metrics.u(10))
            .semantics { contentDescription = "The page: ${LayoutEditor.items(ed).size} things you can move" },
        verticalArrangement = Arrangement.spacedBy(gap),
    ) {
        if (zones.top.isNotEmpty()) Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(gap)) {
            zones.top.forEach { id -> key(id) { ItemBox(env, ItemRef.region(id), Modifier.weight(1f)) } }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(gap)) {
            if (zones.left.isNotEmpty()) Column(Modifier.width(metrics.u(112).coerceAtLeast(104.dp)), verticalArrangement = Arrangement.spacedBy(gap)) {
                zones.left.forEach { id -> key(id) { ItemBox(env, ItemRef.region(id), Modifier.fillMaxWidth()) } }
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(gap)) {
                zones.body.forEach { id -> key(id) { ItemBox(env, ItemRef.region(id), Modifier.fillMaxWidth(), tall = id == "hero") } }
                ed.doc.page?.sections?.filter { !it.hidden }?.forEach { section -> key(section.id) { ItemBox(env, ItemRef.section(section.id), Modifier.fillMaxWidth()) } }
            }
            if (zones.right.isNotEmpty()) Column(Modifier.width(metrics.u(112).coerceAtLeast(104.dp)), verticalArrangement = Arrangement.spacedBy(gap)) {
                zones.right.forEach { id -> key(id) { ItemBox(env, ItemRef.region(id), Modifier.fillMaxWidth()) } }
            }
        }
        if (zones.bottom.isNotEmpty()) Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(gap)) {
            zones.bottom.forEach { id -> key(id) { ItemBox(env, ItemRef.region(id), Modifier.weight(1f)) } }
        }
        val hiddenSections = LayoutEditor.hiddenSections(ed.doc)
        if (zones.hidden.isNotEmpty() || hiddenSections.isNotEmpty()) {
            Text("Hidden", color = scheme.onSurfaceVariant, style = MaterialTheme.typography.caption, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = metrics.u(6)).semantics { heading() })
            FlowRow(horizontalArrangement = Arrangement.spacedBy(gap), verticalArrangement = Arrangement.spacedBy(gap)) {
                zones.hidden.forEach { id -> HiddenChip(env, ItemRef.region(id)) }
                hiddenSections.forEach { id -> HiddenChip(env, ItemRef.section(id)) }
            }
        }
    }
}

@Composable
private fun HiddenChip(env: Env, item: ItemRef) {
    val name = LayoutEditor.label(env.ed, item)
    WittyButton("Show $name", { env.onAct(item, ItemAct.Show) }, Modifier.semantics { contentDescription = "Show $name again" }, pill = true, enabled = !env.readOnly, focusKey = "~show-${keyOf(item)}")
}

// One region or section on the page: a dashed box with its name and its handle. Picked up it is solid, and a line under it
// says where it would be dropped.
@Composable
private fun ItemBox(env: Env, item: ItemRef, modifier: Modifier = Modifier, tall: Boolean = false) {
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val ed = env.ed
    val name = LayoutEditor.label(ed, item)
    val held = ed.held == item
    val selected = ed.focus == item
    val region = if (item.section) null else ed.caps.region(item.id)
    val state = if (item.section) null else ed.doc.regions[item.id]
    val section = if (item.section) ed.doc.page?.sections?.firstOrNull { it.id == item.id } else null
    val locked = section?.locked == true || (region?.locked == true && (region.positions.size < 2))
    val shown = if (item.section) name else shortWords(item.id, name) + (state?.position?.takeIf { it.isNotEmpty() }?.let { " · $it" } ?: if (item.id == "hero") state?.style?.takeIf { it.isNotEmpty() }?.let { " · $it" }.orEmpty() else "")
    val note = buildString {
        if (held) append(" · picked up")
        else if (section?.pinned == true) append(" · pinned")
        else if (section?.locked == true) append(" · always here")
    }
    val accent = extra.accentText
    val shape = RoundedCornerShape(metrics.u(12))
    val target = metrics.minTarget
    var drag by remember(item) { mutableStateOf(Offset.Zero) }
    val requester = remember(item) { env.requesters.getOrPut(keyOf(item)) { FocusRequester() } }
    Column(modifier.zIndex(if (held || drag != Offset.Zero) 2f else 0f)) {
        Box(
            Modifier.fillMaxWidth()
                .graphicsLayer { translationX = drag.x; translationY = drag.y }
                .heightIn(min = if (tall) metrics.u(120) else if (item.section) metrics.u(72) else metrics.u(56))
                .onGloballyPositioned { c -> val top = c.positionInRoot().y; env.bounds[keyOf(item)] = top..(top + c.size.height) }
                .pointerInput(item) { detectTapGestures { env.onFocus(item) } }
                .background(if (held) scheme.surfaceVariant else accent.copy(alpha = 0.06f), shape)
                .then(
                    if (held) Modifier.border(2.dp, scheme.onBackground, shape)
                    else Modifier.dashedBorder(if (selected) accent else accent.copy(alpha = 0.55f), metrics.u(12), if (selected) 2.dp else 1.dp),
                ),
        ) {
            Text(
                shown + note, color = if (held) scheme.onBackground else accent, fontSize = (12.5f * (if (metrics.tv) 1.4f else 1f)).sp, fontWeight = FontWeight.Bold,
                maxLines = 2, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.align(Alignment.TopStart).padding(start = metrics.u(12), top = metrics.u(10), end = target + metrics.u(10)),
            )
            val actions = remember(held, locked, item, section, region) {
                buildList {
                    if (!held) {
                        if (!locked) add(CustomAccessibilityAction("Pick up") { env.onAct(item, ItemAct.PickUp); true })
                        if (!locked) {
                            add(CustomAccessibilityAction(if (item.section) "Move up" else "Move to the previous place") { env.onAct(item, ItemAct.Up); true })
                            add(CustomAccessibilityAction(if (item.section) "Move down" else "Move to the next place") { env.onAct(item, ItemAct.Down); true })
                        }
                        if (section?.locked != true && !(region?.locked == true)) add(CustomAccessibilityAction("Hide") { env.onAct(item, ItemAct.Hide); true })
                    } else {
                        add(CustomAccessibilityAction("Move up") { env.onAct(item, ItemAct.Up); true })
                        add(CustomAccessibilityAction("Move down") { env.onAct(item, ItemAct.Down); true })
                        if (!item.section) {
                            add(CustomAccessibilityAction("Move left") { env.onAct(item, ItemAct.Left); true })
                            add(CustomAccessibilityAction("Move right") { env.onAct(item, ItemAct.Right); true })
                        }
                        add(CustomAccessibilityAction("Drop") { env.onAct(item, ItemAct.Drop); true })
                        add(CustomAccessibilityAction("Cancel") { env.onAct(item, ItemAct.Cancel); true })
                    }
                }
            }
            Pressable(
                { env.onPress(item) },
                Modifier.align(Alignment.TopEnd).padding(metrics.u(6)).size(target)
                    .onFocusChanged { if (it.isFocused) env.onFocus(item) }
                    .pointerInput(item) {
                        detectDragGestures(
                            onDragStart = { env.onFocus(item) },
                            onDrag = { change, by -> change.consume(); drag += by },
                            onDragEnd = { val total = drag; drag = Offset.Zero; env.onDragEnd(item, total) },
                            onDragCancel = { drag = Offset.Zero },
                        )
                    },
                shape = RoundedCornerShape(metrics.u(8)), fill = if (held) scheme.onBackground else scheme.primary,
                label = when {
                    held -> "$name, picked up. Arrow keys move it, OK drops it, Back puts it back"
                    locked -> "$name. Always here, it can't be moved or hidden"
                    else -> "Move $name. OK picks it up"
                },
                state = if (held) "Picked up" else null, focusKey = "~handle-${keyOf(item)}", focusRequester = requester,
                actions = actions,
            ) {
                Icon(WebIcons.Grip, null, tint = if (held) scheme.background else scheme.onPrimary, modifier = Modifier.size(target * 0.5f))
            }
        }
        if (held) {
            val where = if (item.section) {
                val order = ed.doc.page?.sections?.filter { !it.hidden }.orEmpty()
                val at = order.indexOfFirst { it.id == item.id }
                order.getOrNull(at - 1)?.let { "after ${it.title.ifEmpty { it.id }}" } ?: "first"
            } else LayoutWords.position(state?.position.orEmpty())
            Text(
                "Drop here · $where", color = extra.ok, fontSize = (12.5f * (if (metrics.tv) 1.4f else 1f)).sp, fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(top = metrics.u(6)).fillMaxWidth().dashedBorder(extra.ok, metrics.u(10)).padding(metrics.u(10)),
            )
        }
    }
}

// OK picks up, the arrows move, OK drops, Back cancels; with something held, the same as buttons for a finger or a switch.
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Legend(state: EditorState, env: Env) {
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    val held = state.held
    if (held != null) {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(metrics.u(8)), verticalArrangement = Arrangement.spacedBy(metrics.u(8)), itemVerticalAlignment = Alignment.CenterVertically) {
            Text("Moving ${LayoutEditor.label(state, held)}", color = scheme.onBackground, style = MaterialTheme.typography.label, fontWeight = FontWeight.Bold)
            WittyButton("Up", { env.onAct(held, ItemAct.Up) }, Modifier.semantics { contentDescription = "Move up" }, icon = WebIcons.Up, pill = true, focusKey = "~mv-up")
            WittyButton("Down", { env.onAct(held, ItemAct.Down) }, Modifier.semantics { contentDescription = "Move down" }, icon = WebIcons.Down, pill = true, focusKey = "~mv-down")
            if (!held.section) {
                WittyButton("Left", { env.onAct(held, ItemAct.Left) }, Modifier.semantics { contentDescription = "Move left" }, icon = WebIcons.Left, pill = true, focusKey = "~mv-left")
                WittyButton("Right", { env.onAct(held, ItemAct.Right) }, Modifier.semantics { contentDescription = "Move right" }, icon = WebIcons.Right, pill = true, focusKey = "~mv-right")
            }
            WittyButton("Drop", { env.onAct(held, ItemAct.Drop) }, kind = ButtonKind.Primary, pill = true, focusKey = "~mv-drop")
            WittyButton("Cancel", { env.onAct(held, ItemAct.Cancel) }, pill = true, focusKey = "~mv-cancel")
        }
    } else {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(metrics.u(14)), verticalArrangement = Arrangement.spacedBy(metrics.u(6)), itemVerticalAlignment = Alignment.CenterVertically) {
            for ((key, words) in listOf("OK" to "pick up", "▲ ▼ ◀ ▶" to "move", "OK" to "drop", "Back" to "cancel")) {
                Row(horizontalArrangement = Arrangement.spacedBy(metrics.u(6)), verticalAlignment = Alignment.CenterVertically) {
                    Text(key, color = scheme.onSurface, style = MaterialTheme.typography.caption, fontWeight = FontWeight.Bold, modifier = Modifier.background(scheme.surfaceVariant, RoundedCornerShape(metrics.u(8))).padding(horizontal = metrics.u(10), vertical = metrics.u(6)))
                    Text(words, color = scheme.onSurfaceVariant, style = MaterialTheme.typography.caption)
                }
            }
        }
        Text("Moves are announced to screen readers. Dragging a handle works with a finger or a pointer.", color = scheme.onSurfaceVariant, style = MaterialTheme.typography.caption)
    }
}

// TV, Desktop, Tablet, Phone, Headset: an administrator looks at the shell as it is on another kind of device.
@Composable
private fun FormFactors(current: String, own: String, onPick: (String) -> Unit) {
    val metrics = LocalMetrics.current
    Column {
        EdLabel("Look at the shell on")
        EdChoices(LayoutWords.formFactors, current, "Form factor", focusKey = "~ff", onPick = onPick)
        if (current != own) Text("This is the ${LayoutWords.formFactors.firstOrNull { it.first == current }?.second ?: current} layout. Changes for everyone apply to every kind of device that uses this experience.", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.caption, modifier = Modifier.padding(top = metrics.u(6)))
    }
}

// The panel beside the page: the selected thing's settings, the shell's choices, spacing, and what can be added.
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SidePanel(
    nav: Nav, state: EditorState, sized: Map<String, String>, ownDevice: Boolean, scope: LayoutScope, experience: String,
    update: ((EditorState) -> EditorState) -> Unit,
) {
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val focus = state.focus
    Column(
        Modifier.fillMaxWidth().background(scheme.surface, RoundedCornerShape(metrics.u(14))).border(1.dp, scheme.outline, RoundedCornerShape(metrics.u(14))).padding(metrics.u(14)),
        verticalArrangement = Arrangement.spacedBy(metrics.u(6)),
    ) {
        if (focus != null) {
            val name = LayoutEditor.label(state, focus)
            EdLabel("Selected", accent = true)
            Text(name, color = scheme.onBackground, style = MaterialTheme.typography.title, modifier = Modifier.semantics { heading() })
            val visible = LayoutEditor.isVisible(state, focus)
            val region = if (focus.section) null else state.caps.region(focus.id)
            val section = if (focus.section) state.doc.page?.sections?.firstOrNull { it.id == focus.id } else null
            PanelRow("Show") {
                EdChoices(listOf("on" to "On", "off" to "Off"), if (visible) "on" else "off", "Show $name", enabled = section?.locked != true, focusKey = "~show") { v ->
                    update { LayoutEditor.setVisible(it, focus, v == "on") }
                }
            }
            if (section != null) {
                if (state.doc.page?.canPin == true) PanelRow("Pin to top") {
                    EdChoices(listOf("on" to "On", "off" to "Off"), if (section.pinned) "on" else "off", "Pin $name to the top", enabled = !section.locked && state.caps.sectionsEditable, focusKey = "~pin") { v ->
                        if ((v == "on") != section.pinned) update { LayoutEditor.togglePinned(it, focus.id) }
                    }
                }
                if (focus.id in sized && state.doc.page?.canCardSize == true) PanelRow("Card size") {
                    val now = state.doc.page?.cardSize?.get(focus.id) ?: sized[focus.id].orEmpty()
                    EdChoices(listOf("s" to "Small", "m" to "Medium", "l" to "Large"), now, "Card size of $name", enabled = state.caps.sectionsEditable, focusKey = "~size") { v ->
                        update { LayoutEditor.setCardSize(it, focus.id, v) }
                    }
                }
                if (section.locked) Text("This section is always here. It's how you reach what you need.", color = scheme.onSurfaceVariant, style = MaterialTheme.typography.caption)
            }
            if (region != null) {
                if (region.positions.size > 1) PanelRow("Place") {
                    EdChoices(LayoutEditor.ordered(region.positions).map { it to LayoutWords.choice(it) }, state.doc.regions[region.id]?.position.orEmpty(), "Place for $name", focusKey = "~place") { v ->
                        update { LayoutEditor.setPosition(it, region.id, v) }
                    }
                }
                if (region.styles.isNotEmpty()) PanelRow("Style") {
                    EdChoices(region.styles.map { it to LayoutWords.style(it) }, state.doc.regions[region.id]?.style.orEmpty(), "Style of $name", focusKey = "~style") { v ->
                        update { LayoutEditor.setStyle(it, region.id, v) }
                    }
                }
                if (region.locked) Text("${region.label} can't be hidden. It's how you reach Settings and You.", color = scheme.onSurfaceVariant, style = MaterialTheme.typography.caption)
            }
        } else {
            Text("Choose something on the page to change it.", color = scheme.onSurfaceVariant, style = MaterialTheme.typography.body)
        }

        // The shell: where the menu, search, the server's name and the dock are.
        EdLabel("Shell")
        for (def in state.caps.regions) {
            if (def.id == "hero" || def.positions.isEmpty() && def.id != "clock" && def.id != "legend") continue
            val st = state.doc.regions[def.id]
            val options = buildList {
                LayoutEditor.ordered(def.positions).forEach { add(it to LayoutWords.choice(it)) }
                if (!def.locked) add("hidden" to "Hidden")
                if (def.positions.isEmpty()) { add("on" to "Shown"); add("hidden" to "Hidden") }
            }
            val now = if (st?.visible == false) "hidden" else if (def.positions.isEmpty()) "on" else st?.position.orEmpty()
            PanelRow(shortWords(def.id, def.label)) {
                EdChoices(options, now, shortWords(def.id, def.label), focusKey = "~shell-${def.id}") { v ->
                    update { e ->
                        when {
                            v == "hidden" -> LayoutEditor.setVisible(e, ItemRef.region(def.id), false)
                            v == "on" -> LayoutEditor.setVisible(e, ItemRef.region(def.id), true)
                            else -> LayoutEditor.setPosition(LayoutEditor.setVisible(e, ItemRef.region(def.id), true), def.id, v)
                        }
                    }
                }
                if (def.id == "brand" && nav.me?.isAdmin == true) {
                    WittyButton("Edit name…", { nav.push(Route.You(YouNative.NameAndLogo)) }, kind = ButtonKind.Quiet, pill = true, focusKey = "~edit-name")
                }
            }
        }
        state.caps.region("hero")?.let { hero ->
            PanelRow("Spotlight") {
                val st = state.doc.regions["hero"]
                EdChoices(
                    hero.styles.map { it to LayoutWords.style(it) } + ("hidden" to "Hidden"), if (st?.visible == false) "hidden" else st?.style.orEmpty(), "Spotlight", focusKey = "~shell-hero",
                ) { v ->
                    update { e -> if (v == "hidden") LayoutEditor.setVisible(e, ItemRef.region("hero"), false) else LayoutEditor.setStyle(LayoutEditor.setVisible(e, ItemRef.region("hero"), true), "hero", v) }
                }
            }
        }
        if (state.doc.page?.canDensity == true) {
            EdLabel("Spacing")
            val now = state.doc.page?.density?.ifEmpty { "comfortable" } ?: "comfortable"
            EdChoices(listOf("compact" to "Compact", "comfortable" to "Comfortable", "spacious" to "Spacious"), now, "Spacing", enabled = state.caps.sectionsEditable, focusKey = "~density") { v ->
                update { LayoutEditor.setDensity(it, v) }
            }
        }
        if (!ownDevice) Text("Page sections can be arranged on this device only.", color = scheme.onSurfaceVariant, style = MaterialTheme.typography.caption)
        Text(
            "Settings and You can't be hidden. Reset puts everything back to the $experience look.",
            color = extra.hint, style = MaterialTheme.typography.caption, modifier = Modifier.padding(top = metrics.u(10)),
        )
    }
}

@Composable
private fun PanelRow(label: String, content: @Composable () -> Unit) {
    val metrics = LocalMetrics.current
    Column(Modifier.fillMaxWidth().padding(vertical = metrics.u(4)), verticalArrangement = Arrangement.spacedBy(metrics.u(6))) {
        Text(label, color = MaterialTheme.colorScheme.onSurface, style = MaterialTheme.typography.label, fontWeight = FontWeight.SemiBold)
        content()
    }
}
