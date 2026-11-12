// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.tv

import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.text.input.ImeAction
import com.wittywilla.wittymediaclient.net.GuideChannel
import com.wittywilla.wittymediaclient.net.GuidePaging
import com.wittywilla.wittymediaclient.net.GuideRules
import com.wittywilla.wittymediaclient.net.liteChannels
import com.wittywilla.wittymediaclient.net.problemText
import com.wittywilla.wittymediaclient.net.uniqueChannels
import com.wittywilla.wittymediaclient.ui.FieldKind
import com.wittywilla.wittymediaclient.ui.LocalMetrics
import com.wittywilla.wittymediaclient.ui.Nav
import com.wittywilla.wittymediaclient.ui.Symbols
import com.wittywilla.wittymediaclient.ui.WittyField
import com.wittywilla.wittymediaclient.ui.body
import com.wittywilla.wittymediaclient.ui.secondary
import com.wittywilla.wittymediaclient.ui.u
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay

// Finding a channel in the guide: by its number (the field takes digits, for a phone or a remote without them) or
// by some of its name. Choosing one goes to it in the guide; "Show only these" narrows the guide's rows to what was
// typed (the server's `q`), until it's cleared. Searching what's coming up by title stays the schedule's search.
@Composable
fun FindChannel(
    nav: Nav,
    store: GuideStore,
    onJump: (String) -> Unit,
    onNarrow: (String) -> Unit,
    onClose: () -> Unit,
) {
    val api = nav.app.api
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    var words by remember { mutableStateOf(store.search) }
    var found by remember { mutableStateOf<List<GuideChannel>>(emptyList()) }
    var error by remember { mutableStateOf("") }
    val field = remember { FocusRequester() }
    val typed = words.trim()
    val isNumber = typed.isNotEmpty() && typed.all { it.isDigit() || it == '.' || it == '-' }
    // On a server that narrows for itself, it's asked a moment after typing stops; otherwise the channel list the
    // guide already has is looked through.
    LaunchedEffect(typed, store.set) {
        if (typed.isEmpty()) {
            found = emptyList()
            error = ""
            return@LaunchedEffect
        }
        if (!store.hasPaging) {
            val shown = if (store.hasSets) store.lineup else store.lineup.filter { GuideRules.matches(it, store.filter.kind, store.filter.group, store.filter.favourites) }
            found = shown.filter { GuidePaging.matches(it, typed) }.take(LIMIT)
            return@LaunchedEffect
        }
        delay(300)
        try {
            found = uniqueChannels(api.liteChannels(if (store.hasSets) store.set else null, typed, LIMIT).channels)
            error = ""
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            error = problemText(e, "The channels couldn't be searched.")
        }
    }
    LaunchedEffect(Unit) { runCatching { field.requestFocus() } }
    TvListSheet(
        onClose,
        top = {
            SheetHeading("Find a channel")
            val where = store.currentSet?.name ?: if (store.showingAll) "every channel" else "the channels shown"
            Text("A number goes straight to that channel; words find it by name, in $where.", style = MaterialTheme.typography.secondary, color = scheme.onSurfaceVariant)
            WittyField(
                words, { words = it }, "A channel's number or name", kind = FieldKind.Text, icon = Symbols.Search, focusRequester = field,
                imeAction = ImeAction.Go, onAction = { if (typed.isNotEmpty()) onJump(if (isNumber) typed else found.firstOrNull()?.key ?: typed) },
            )
            if (error.isNotEmpty()) Text(error, style = MaterialTheme.typography.body, color = scheme.error)
            Row(Modifier.focusGroup(), horizontalArrangement = Arrangement.spacedBy(metrics.u(16))) {
                if (isNumber) SheetButton("Go to channel $typed", { onJump(typed) }, kind = SheetKind.Primary)
                if (store.hasPaging && typed.isNotEmpty() && !isNumber) SheetButton("Show only these in the guide", { onNarrow(typed) })
                if (store.search.isNotEmpty()) SheetButton("Show every channel again", { onNarrow("") })
            }
        },
        bottom = { SheetButton("Close", onClose, kind = SheetKind.Quiet) },
    ) {
        if (typed.isNotEmpty() && found.isEmpty() && error.isEmpty()) {
            item { Text("No channel here matches that.", style = MaterialTheme.typography.body, color = scheme.onSurfaceVariant) }
        }
        items(found, key = { it.key }) { c ->
            SheetRow("${c.number} ${c.name}", c.group.orEmpty(), { onJump(c.key) })
        }
    }
}

private const val LIMIT = 50
