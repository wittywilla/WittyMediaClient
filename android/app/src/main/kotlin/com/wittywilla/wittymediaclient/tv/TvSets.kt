// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.wittywilla.wittymediaclient.net.ChannelSet
import com.wittywilla.wittymediaclient.net.GuideChannel
import com.wittywilla.wittymediaclient.net.GuidePaging
import com.wittywilla.wittymediaclient.net.SetRules
import com.wittywilla.wittymediaclient.net.changeChannelSet
import com.wittywilla.wittymediaclient.net.changeSetChannels
import com.wittywilla.wittymediaclient.net.channelSet
import com.wittywilla.wittymediaclient.net.liteChannels
import com.wittywilla.wittymediaclient.net.makeChannelSet
import com.wittywilla.wittymediaclient.net.orderChannelSets
import com.wittywilla.wittymediaclient.net.problemText
import com.wittywilla.wittymediaclient.net.removeChannelSet
import com.wittywilla.wittymediaclient.net.uniqueChannels
import com.wittywilla.wittymediaclient.ui.FieldKind
import com.wittywilla.wittymediaclient.ui.LocalMetrics
import com.wittywilla.wittymediaclient.ui.Nav
import com.wittywilla.wittymediaclient.ui.Pressable
import com.wittywilla.wittymediaclient.ui.Spinner
import com.wittywilla.wittymediaclient.ui.WittyField
import com.wittywilla.wittymediaclient.ui.body
import com.wittywilla.wittymediaclient.ui.corner
import com.wittywilla.wittymediaclient.ui.label
import com.wittywilla.wittymediaclient.ui.secondary
import com.wittywilla.wittymediaclient.ui.title
import com.wittywilla.wittymediaclient.ui.u
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

// Channel sets (the server's `tv-sets`): which channels the guide shows, in which order, as the server's page offers
// them. The picker lists every set in sections; an account makes its own, names them, chooses and orders their
// channels, and an administrator can share one with every profile. These are in the app's own colours, as the guide's
// other sheets are, and every one works with the remote alone: Back closes, focus starts on what's chosen, and anything
// moved is moved with Move up and Move down.

// What's open over the guide for sets.
sealed interface SetPanel {
    data object Picker : SetPanel
    data object Manager : SetPanel

    // Naming a new set (with a channel to start it, from "Add to set…"), or renaming one.
    data class Name(val editing: ChannelSet? = null, val firstChannel: GuideChannel? = null) : SetPanel
    data class Channels(val set: ChannelSet) : SetPanel
    data class AddTo(val channel: GuideChannel) : SetPanel
}

// A sheet whose middle is a long list, drawn only as it scrolls: the channel picker can have ten thousand rows.
@Composable
fun TvListSheet(
    onClose: () -> Unit,
    state: LazyListState = rememberLazyListState(),
    top: @Composable ColumnScope.() -> Unit,
    bottom: @Composable ColumnScope.() -> Unit = {},
    list: LazyListScope.() -> Unit,
) {
    val scheme = MaterialTheme.colorScheme
    val metrics = LocalMetrics.current
    TvLayer(onClose) {
        Box(Modifier.fillMaxSize().padding(vertical = (60 * TV_UNIT).dp, horizontal = metrics.gutter / 2), contentAlignment = Alignment.Center) {
            Column(
                Modifier
                    .widthIn(max = metrics.u(1300))
                    .fillMaxWidth()
                    .fillMaxHeight()
                    .clip(RoundedCornerShape((64 * TV_UNIT).dp))
                    .background(scheme.background)
                    .padding(horizontal = metrics.gutter, vertical = metrics.edge),
                verticalArrangement = Arrangement.spacedBy(metrics.u(16)),
            ) {
                top()
                LazyColumn(
                    Modifier.weight(1f).fillMaxWidth().focusGroup(),
                    state = state,
                    verticalArrangement = Arrangement.spacedBy(metrics.u(12)),
                    contentPadding = PaddingValues(vertical = metrics.focusRing * 2, horizontal = metrics.focusRing * 2),
                    content = list,
                )
                bottom()
            }
        }
    }
}

// One line of a list in a sheet: its words, what's under them, and a mark on the chosen one.
@Composable
internal fun SheetRow(
    words: String,
    detail: String,
    onClick: () -> Unit,
    chosen: Boolean = false,
    takeFocus: Boolean = false,
    tick: Boolean? = null,
) {
    val scheme = MaterialTheme.colorScheme
    val metrics = LocalMetrics.current
    Pressable(
        onClick, Modifier.fillMaxWidth(), shape = metrics.corner(10), fill = scheme.surfaceVariant, label = "$words, $detail",
        selected = chosen || tick == true, state = if (chosen || tick == true) "Selected" else null, takeFocus = takeFocus,
    ) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = metrics.u(20), vertical = metrics.u(12)),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(metrics.u(16)),
        ) {
            if (tick != null) {
                Icon(if (tick) TvSymbols.Ticked else TvSymbols.Unticked, contentDescription = null, tint = scheme.primary, modifier = Modifier.size(metrics.u(40)))
            }
            Text(words, style = MaterialTheme.typography.label, color = scheme.onBackground, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            if (detail.isNotEmpty()) Text(detail, style = MaterialTheme.typography.secondary, color = scheme.onSurfaceVariant, maxLines = 1)
            if (chosen) Icon(TvSymbols.Chosen, contentDescription = null, tint = scheme.primary, modifier = Modifier.size(metrics.u(40)))
        }
    }
}

@Composable
internal fun SheetHeading(words: String) {
    Text(words, style = MaterialTheme.typography.title, color = MaterialTheme.colorScheme.onBackground, modifier = Modifier.semantics { heading() })
}

@Composable
private fun SectionHeading(words: String) {
    val metrics = LocalMetrics.current
    Text(
        words, style = MaterialTheme.typography.label, color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(top = metrics.u(12)).semantics { heading() },
    )
}

// What's said under a set's name: how many channels, and whether everyone sees it.
private fun setDetail(set: ChannelSet): String = buildList {
    add(SetRules.countWords(set.count))
    if (set.isCustom && set.shared) add("Shared")
}.joinToString(" · ")

// Everything to do with sets, whichever is open.
@Composable
fun SetPanels(
    nav: Nav,
    store: GuideStore,
    panel: SetPanel,
    onPanel: (SetPanel?) -> Unit,
    onChoose: (String) -> Unit,
    onChanged: (String?) -> Unit,
    onSaid: (String) -> Unit,
) {
    when (panel) {
        SetPanel.Picker -> SetPicker(store, onChoose = { onPanel(null); onChoose(it) }, onManage = { onPanel(SetPanel.Manager) }, onNew = { onPanel(SetPanel.Name()) }, onClose = { onPanel(null) })
        SetPanel.Manager -> SetManager(nav, store, onPanel, onChanged, onSaid)
        is SetPanel.Name -> SetName(nav, store, panel, onPanel, onChanged, onSaid)
        is SetPanel.Channels -> SetChannels(nav, panel.set, onClose = { onPanel(SetPanel.Manager) }, onSaved = { words -> onPanel(SetPanel.Manager); onChanged(panel.set.id); onSaid(words) })
        is SetPanel.AddTo -> AddToSet(nav, store, panel.channel, onPanel, onChanged, onSaid)
    }
}

// Every set, in the server's sections, with a search for a long list of groups. Select shows a set.
@Composable
private fun SetPicker(store: GuideStore, onChoose: (String) -> Unit, onManage: () -> Unit, onNew: () -> Unit, onClose: () -> Unit) {
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    var words by remember { mutableStateOf("") }
    val all = store.sets
    val sections = remember(all, words) { SetRules.sections(SetRules.search(all.orEmpty(), words)) }
    val state = rememberLazyListState()
    // The chosen set in view, so focus can start on it.
    LaunchedEffect(sections) {
        var i = 0
        for (s in sections) {
            i++
            val at = s.sets.indexOfFirst { it.id == store.set }
            if (at >= 0) {
                state.scrollToItem((i + at - 2).coerceAtLeast(0))
                return@LaunchedEffect
            }
            i += s.sets.size
        }
    }
    TvListSheet(
        onClose, state,
        top = {
            SheetHeading("Channel sets")
            Text("Which channels the guide shows. This device remembers your choice.", style = MaterialTheme.typography.secondary, color = scheme.onSurfaceVariant)
            if (all.orEmpty().size > 8) {
                WittyField(words, { words = it }, "Find a set", kind = FieldKind.Text, icon = com.wittywilla.wittymediaclient.ui.Symbols.Search, imeAction = ImeAction.Search)
            }
        },
        bottom = {
            Row(Modifier.focusGroup(), horizontalArrangement = Arrangement.spacedBy(metrics.u(16))) {
                SheetButton("New set", onNew)
                if (all.orEmpty().any { it.isCustom }) SheetButton("Edit sets", onManage)
                SheetButton("Close", onClose, kind = SheetKind.Quiet)
            }
        },
    ) {
        if (all == null) {
            item { Box(Modifier.fillMaxWidth().padding(metrics.u(40)), contentAlignment = Alignment.Center) { Spinner(scheme.onBackground, metrics.u(48)) } }
        } else if (sections.isEmpty()) {
            item { Text("No set's name has that in it.", style = MaterialTheme.typography.body, color = scheme.onSurfaceVariant) }
        }
        for (section in sections) {
            item(key = "h:" + section.title) { SectionHeading(section.title) }
            items(section.sets, key = { "s:" + it.id }) { s ->
                SheetRow(s.name, setDetail(s), { onChoose(s.id) }, chosen = s.id == store.set, takeFocus = s.id == store.set)
            }
        }
    }
}

// The account's sets and the shared ones: their order, and for those it may change, their name, channels and sharing.
@Composable
private fun SetManager(nav: Nav, store: GuideStore, onPanel: (SetPanel?) -> Unit, onChanged: (String?) -> Unit, onSaid: (String) -> Unit) {
    val api = nav.app.api
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    val scope = rememberCoroutineScope()
    var error by remember { mutableStateOf("") }
    var deleting by remember { mutableStateOf<ChannelSet?>(null) }
    val custom = store.sets.orEmpty().filter { it.isCustom }

    fun act(failure: String, work: suspend () -> Unit) {
        scope.launch {
            try {
                work()
                error = ""
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = problemText(e, failure)
            }
        }
    }

    fun move(set: ChannelSet, by: Int) = act("The sets couldn't be put in that order.") {
        val ids = SetRules.orderAfterMove(store.sets.orEmpty(), set.id, by)
        if (ids == custom.map { it.id }) return@act
        api.orderChannelSets(ids)
        store.reloadSets()
    }

    TvListSheet(
        { onPanel(null) },
        top = {
            SheetHeading("Your channel sets")
            Text(
                "Move a set up or down to change where it comes in the list. A shared set is seen by every profile on this server.",
                style = MaterialTheme.typography.secondary, color = scheme.onSurfaceVariant,
            )
            if (error.isNotEmpty()) Text(error, style = MaterialTheme.typography.body, color = scheme.error)
        },
        bottom = {
            Row(Modifier.focusGroup(), horizontalArrangement = Arrangement.spacedBy(metrics.u(16))) {
                if (SetRules.canMakeAnother(store.sets.orEmpty())) SheetButton("New set", { onPanel(SetPanel.Name()) })
                SheetButton("Back to the sets", { onPanel(SetPanel.Picker) })
                SheetButton("Done", { onPanel(null) }, kind = SheetKind.Primary)
            }
        },
    ) {
        if (custom.isEmpty()) {
            item { Text("You haven't made a set yet.", style = MaterialTheme.typography.body, color = scheme.onSurfaceVariant) }
        }
        itemsIndexed(custom, key = { _, s -> s.id }) { i, s ->
            Column(
                Modifier
                    .fillMaxWidth()
                    .clip(metrics.corner(10))
                    .background(scheme.surface)
                    .padding(metrics.u(16))
                    .focusGroup(),
                verticalArrangement = Arrangement.spacedBy(metrics.u(12)),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(metrics.u(16))) {
                    Text(s.name, style = MaterialTheme.typography.label, color = scheme.onBackground, modifier = Modifier.weight(1f))
                    Text(setDetail(s) + if (!s.mine) " · Not yours" else "", style = MaterialTheme.typography.secondary, color = scheme.onSurfaceVariant)
                }
                Row(horizontalArrangement = Arrangement.spacedBy(metrics.u(16)), modifier = Modifier.focusGroup()) {
                    SheetButton("Move up", { move(s, -1) }, takeFocus = i == 0)
                    SheetButton("Move down", { move(s, 1) })
                    if (s.editable) {
                        SheetButton("Channels", { onPanel(SetPanel.Channels(s)) })
                        SheetButton("Rename", { onPanel(SetPanel.Name(editing = s)) })
                        if (store.canShare) {
                            SheetButton(
                                "Shared with everyone", {
                                    act("That set's sharing couldn't be changed.") {
                                        api.changeChannelSet(s.id, shared = !s.shared)
                                        store.reloadSets()
                                        onSaid(if (s.shared) "${s.name} is yours alone now" else "${s.name} is shared with every profile")
                                    }
                                },
                                selected = s.shared, icon = if (s.shared) TvSymbols.Ticked else TvSymbols.Unticked,
                            )
                        }
                        SheetButton("Delete", { deleting = s }, kind = SheetKind.Quiet)
                    }
                }
            }
        }
    }
    deleting?.let { s ->
        val close = { deleting = null }
        TvDialog(
            "Delete the set “${s.name}”?",
            if (s.shared) "It goes for every profile that sees it. The channels themselves stay." else "The channels themselves stay; only this set goes.",
            listOf(
                TvDialogButton("Cancel", cancel = true, action = close),
                TvDialogButton("Delete set", destructive = true) {
                    close()
                    act("That set couldn't be deleted.") {
                        api.removeChannelSet(s.id)
                        store.reloadSets()
                        onChanged(s.id)
                        onSaid("${s.name} deleted")
                    }
                },
            ),
            close,
        )
    }
}

// A name for a new set, or another name for one; a new one goes on to choosing its channels.
@Composable
private fun SetName(nav: Nav, store: GuideStore, panel: SetPanel.Name, onPanel: (SetPanel?) -> Unit, onChanged: (String?) -> Unit, onSaid: (String) -> Unit) {
    val api = nav.app.api
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    val scope = rememberCoroutineScope()
    val editing = panel.editing
    var name by remember { mutableStateOf(editing?.name.orEmpty()) }
    var shared by remember { mutableStateOf(editing?.shared ?: false) }
    var error by remember { mutableStateOf("") }
    var refused by remember { mutableStateOf(0) }
    var saving by remember { mutableStateOf(false) }
    val back = { onPanel(if (editing != null) SetPanel.Manager else if (panel.firstChannel != null) null else SetPanel.Picker) }

    fun save() {
        if (saving) return
        SetRules.nameProblem(name, store.sets.orEmpty(), editing?.id)?.let {
            error = it
            refused++
            return
        }
        saving = true
        scope.launch {
            try {
                if (editing != null) {
                    api.changeChannelSet(editing.id, name = name, shared = if (store.canShare && shared != editing.shared) shared else null)
                    store.reloadSets()
                    onChanged(editing.id)
                    onSaid("Renamed to ${name.trim()}")
                    onPanel(SetPanel.Manager)
                } else {
                    val first = panel.firstChannel
                    val made = api.makeChannelSet(name, listOfNotNull(first?.key), store.canShare && shared)
                    store.reloadSets()
                    if (first != null) {
                        onSaid("${first.name} is in ${made.name.ifEmpty { name.trim() }}")
                        onPanel(null)
                    } else {
                        val fresh = store.sets.orEmpty().firstOrNull { it.id == made.id } ?: made
                        onPanel(SetPanel.Channels(fresh))
                    }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = problemText(e, "That set couldn't be saved.")
                refused++
            } finally {
                saving = false
            }
        }
    }

    TvSheet(back) {
        Column(
            Modifier.widthIn(max = metrics.u(1000)).fillMaxWidth().padding(horizontal = metrics.gutter, vertical = metrics.edge),
            verticalArrangement = Arrangement.spacedBy(metrics.u(16)),
        ) {
            SheetHeading(if (editing != null) "Rename “${editing.name}”" else "New channel set")
            if (panel.firstChannel != null) {
                Text("Starting with ${panel.firstChannel.number} ${panel.firstChannel.name}.", style = MaterialTheme.typography.body, color = scheme.onSurfaceVariant)
            }
            WittyField(
                name, { name = it.take(SetRules.NAME_MAX); error = "" }, "Name", kind = FieldKind.Text, error = error, isError = error.isNotEmpty(), shake = refused,
                imeAction = ImeAction.Done, onAction = ::save, maxLength = SetRules.NAME_MAX,
            )
            if (store.canShare && (editing == null || editing.editable)) {
                SheetButton("Share with every profile on this server", { shared = !shared }, selected = shared, icon = if (shared) TvSymbols.Ticked else TvSymbols.Unticked)
            }
            Row(Modifier.focusGroup(), horizontalArrangement = Arrangement.spacedBy(metrics.u(16))) {
                SheetButton(if (editing != null) "Save" else if (panel.firstChannel != null) "Make the set" else "Next: choose channels", ::save, kind = SheetKind.Primary)
                SheetButton("Cancel", back, kind = SheetKind.Quiet)
            }
        }
    }
}

// Choosing a set's channels from every channel, by ticking them, and putting them in order.
@Composable
private fun SetChannels(nav: Nav, set: ChannelSet, onClose: () -> Unit, onSaved: (String) -> Unit) {
    val api = nav.app.api
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    val scope = rememberCoroutineScope()
    var before by remember { mutableStateOf<List<String>?>(null) }
    var chosen by remember { mutableStateOf<List<String>>(emptyList()) }
    var everything by remember { mutableStateOf<List<GuideChannel>?>(null) }
    var words by remember { mutableStateOf("") }
    var ordering by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf("") }
    var saving by remember { mutableStateOf(false) }
    LaunchedEffect(set.id) {
        try {
            val detail = api.channelSet(set.id)
            before = detail.channels.orEmpty()
            chosen = detail.channels.orEmpty()
            everything = uniqueChannels(api.liteChannels(SetRules.ALL).channels)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            error = problemText(e, "That set's channels couldn't be loaded.")
        }
    }
    val byKey = remember(everything) { everything.orEmpty().associateBy { it.key } }
    val shown = remember(everything, words) { everything.orEmpty().filter { GuidePaging.matches(it, words) } }
    val ticked = remember(chosen) { chosen.toHashSet() }

    fun save() {
        val was = before ?: return
        if (saving) return
        if (was == chosen) {
            onClose()
            return
        }
        saving = true
        scope.launch {
            try {
                val (added, removed) = SetRules.changes(was, chosen)
                // Only some added or taken away, in the same order: the smaller request. Anything moved: the whole list.
                if (was.filter { it !in removed } + added == chosen) api.changeSetChannels(set.id, added, removed)
                else api.changeChannelSet(set.id, channels = chosen)
                onSaved("${set.name} saved")
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = problemText(e, "That set couldn't be saved.")
            } finally {
                saving = false
            }
        }
    }

    TvListSheet(
        onClose,
        top = {
            SheetHeading("Channels in ${set.name}")
            Row(Modifier.focusGroup(), horizontalArrangement = Arrangement.spacedBy(metrics.u(16)), verticalAlignment = Alignment.CenterVertically) {
                SheetButton("Choose channels", { ordering = false }, selected = !ordering)
                SheetButton("Order (${chosen.size})", { ordering = true }, selected = ordering)
            }
            if (!ordering && everything != null) {
                WittyField(words, { words = it }, "A channel's number or name", kind = FieldKind.Text, icon = com.wittywilla.wittymediaclient.ui.Symbols.Search, imeAction = ImeAction.Search)
            }
            if (error.isNotEmpty()) Text(error, style = MaterialTheme.typography.body, color = scheme.error)
        },
        bottom = {
            Row(Modifier.focusGroup(), horizontalArrangement = Arrangement.spacedBy(metrics.u(16))) {
                SheetButton(if (saving) "Saving…" else "Save", ::save, kind = SheetKind.Primary)
                SheetButton("Cancel", onClose, kind = SheetKind.Quiet)
            }
        },
    ) {
        when {
            everything == null && error.isEmpty() -> item {
                Box(Modifier.fillMaxWidth().padding(metrics.u(40)), contentAlignment = Alignment.Center) { Spinner(scheme.onBackground, metrics.u(48)) }
            }
            ordering -> {
                if (chosen.isEmpty()) item { Text("No channels chosen yet.", style = MaterialTheme.typography.body, color = scheme.onSurfaceVariant) }
                itemsIndexed(chosen, key = { _, k -> "o:$k" }) { i, k ->
                    val c = byKey[k]
                    Row(
                        Modifier.fillMaxWidth().clip(metrics.corner(10)).background(scheme.surface).padding(horizontal = metrics.u(16), vertical = metrics.u(8)).focusGroup(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(metrics.u(16)),
                    ) {
                        Text("${i + 1}.", style = MaterialTheme.typography.secondary, color = scheme.onSurfaceVariant)
                        Text(
                            c?.let { "${it.number} ${it.name}" } ?: "A channel you can't see", style = MaterialTheme.typography.label, color = scheme.onBackground,
                            maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f),
                        )
                        SheetButton("Move up", { chosen = SetRules.move(chosen, i, -1) })
                        SheetButton("Move down", { chosen = SetRules.move(chosen, i, 1) })
                        SheetButton("Remove", { chosen = chosen - k }, kind = SheetKind.Quiet)
                    }
                }
            }
            else -> {
                if (shown.isEmpty() && everything != null) item { Text("No channel matches that.", style = MaterialTheme.typography.body, color = scheme.onSurfaceVariant) }
                items(shown, key = { "c:" + it.key }) { c ->
                    SheetRow("${c.number} ${c.name}", c.group.orEmpty(), { chosen = SetRules.toggle(chosen, c.key) }, tick = c.key in ticked)
                }
            }
        }
    }
}

// "Add to set…" from a channel: the sets it can go in, or a new one that starts with it.
@Composable
private fun AddToSet(nav: Nav, store: GuideStore, channel: GuideChannel, onPanel: (SetPanel?) -> Unit, onChanged: (String?) -> Unit, onSaid: (String) -> Unit) {
    val api = nav.app.api
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    val scope = rememberCoroutineScope()
    var error by remember { mutableStateOf("") }
    LaunchedEffect(Unit) { if (store.sets == null) store.reloadSets() }
    val editable = store.sets.orEmpty().filter { it.isCustom && it.editable }
    TvListSheet(
        { onPanel(null) },
        top = {
            SheetHeading("Add ${channel.number} ${channel.name} to a set")
            if (error.isNotEmpty()) Text(error, style = MaterialTheme.typography.body, color = scheme.error)
        },
        bottom = {
            Row(Modifier.focusGroup(), horizontalArrangement = Arrangement.spacedBy(metrics.u(16))) {
                if (SetRules.canMakeAnother(store.sets.orEmpty())) SheetButton("New set with this channel", { onPanel(SetPanel.Name(firstChannel = channel)) }, takeFocus = editable.isEmpty())
                SheetButton("Cancel", { onPanel(null) }, kind = SheetKind.Quiet)
            }
        },
    ) {
        if (editable.isEmpty()) item { Text("You have no sets of your own yet.", style = MaterialTheme.typography.body, color = scheme.onSurfaceVariant) }
        itemsIndexed(editable, key = { _, s -> s.id }) { i, s ->
            SheetRow(s.name, setDetail(s), {
                scope.launch {
                    try {
                        api.changeSetChannels(s.id, listOf(channel.key))
                        store.reloadSets()
                        onChanged(s.id)
                        onSaid("${channel.name} added to ${s.name}")
                        onPanel(null)
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        error = problemText(e, "That channel couldn't be added.")
                    }
                }
            }, takeFocus = i == 0)
        }
    }
}
