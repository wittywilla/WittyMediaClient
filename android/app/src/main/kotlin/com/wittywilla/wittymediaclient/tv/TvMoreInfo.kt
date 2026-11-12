// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.tv

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.wittywilla.wittymediaclient.net.MoreInfo
import com.wittywilla.wittymediaclient.net.MoreInfoRules
import com.wittywilla.wittymediaclient.net.problemText
import com.wittywilla.wittymediaclient.net.programmeInfo
import com.wittywilla.wittymediaclient.ui.Nav
import java.text.DateFormat
import java.util.Date

// WittyTV's More info (docs/plans/DESIGN-2.md section 9): a pop-up over the guide or the banner, without leaving it. The
// programme's logo, title, times and description, then Watch now, Record, Remind me, Watchlist and Open item page where the
// server offers them, the people, other airings and trailers. Back closes it.
class MoreInfoActions(
    val watch: () -> Unit,
    val record: (() -> Unit)?,
    val remind: (() -> Unit)?,
    val openItem: ((Long, Long) -> Unit)?,
)

@Composable
fun MoreInfoSheet(nav: Nav, key: String, start: Long, actions: MoreInfoActions, onClose: () -> Unit) {
    var info by remember(key, start) { mutableStateOf<MoreInfo?>(null) }
    var failed by remember(key, start) { mutableStateOf("") }
    LaunchedEffect(key, start) {
        runCatching { MoreInfoRules.parse(nav.app.api.programmeInfo(key, start)) }
            .onSuccess { info = it }.onFailure { failed = problemText(it, "More about this isn't available.") }
    }
    BackHandler(onBack = onClose)
    val scheme = MaterialTheme.colorScheme
    TvSheet(onClose) {
        Column(Modifier.padding(horizontal = 48.dp, vertical = 32.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            val i = info
            when {
                i != null -> {
                    Text(i.title, color = scheme.onBackground, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.semantics { heading() })
                    val clock = DateFormat.getTimeInstance(DateFormat.SHORT)
                    Text(
                        listOfNotNull(i.channelNumber.takeIf { it.isNotEmpty() }, i.channelName.takeIf { it.isNotEmpty() }).joinToString(" ") + (if (i.start > 0) " · " + clock.format(Date(i.start * 1000)) + " to " + clock.format(Date(i.end * 1000)) else ""),
                        color = scheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium,
                    )
                    if (i.sub.isNotEmpty()) Text(i.sub, color = scheme.onBackground, style = MaterialTheme.typography.titleMedium, maxLines = 2)
                    if (i.facts.isNotEmpty()) Text(i.facts.joinToString(" · "), color = scheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
                    if (i.desc.isNotEmpty()) Text(i.desc, color = scheme.onBackground, style = MaterialTheme.typography.bodyLarge, maxLines = 6, overflow = TextOverflow.Ellipsis)
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        if (i.actions.watch) SheetButton("Watch now", { onClose(); actions.watch() }, kind = SheetKind.Primary, takeFocus = true)
                        if (i.actions.record && actions.record != null) SheetButton("Record", { onClose(); actions.record.invoke() })
                        if (i.actions.remind && actions.remind != null) SheetButton(if (i.actions.reminded) "Remove reminder" else "Remind me", { onClose(); actions.remind.invoke() })
                        if (i.actions.open && (i.itemId > 0 || i.showId > 0) && actions.openItem != null) SheetButton("Open item page", { onClose(); actions.openItem.invoke(i.itemId, i.showId) })
                    }
                    if (i.people.isNotEmpty()) {
                        Text("Cast and crew", color = scheme.onBackground, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, modifier = Modifier.semantics { heading() })
                        // A person only the guide knows has no page: plain words, nothing to focus.
                        Text(i.people.take(12).joinToString(" · ") { p -> p.name + if (p.role.isNotEmpty()) " (${p.role})" else "" }, color = scheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium, maxLines = 4, overflow = TextOverflow.Ellipsis)
                    }
                    if (i.schedule.size > 1) {
                        Text("Also on", color = scheme.onBackground, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, modifier = Modifier.semantics { heading() })
                        val day = DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT)
                        i.schedule.filter { !it.here }.take(6).forEach { a ->
                            Text(listOf(a.number, a.channel).filter { it.isNotEmpty() }.joinToString(" ") + " · " + day.format(Date(a.start * 1000)), color = scheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                    if (i.trailers.isNotEmpty()) Text("Trailers: " + i.trailers.take(3).joinToString(", "), color = scheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
                }
                failed.isNotEmpty() -> {
                    Text(failed, color = scheme.onBackground, style = MaterialTheme.typography.bodyLarge)
                    SheetButton("Close", onClose, takeFocus = true)
                }
                else -> Text("Loading…", color = scheme.onSurfaceVariant, style = MaterialTheme.typography.bodyLarge)
            }
        }
    }
}
