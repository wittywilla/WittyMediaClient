// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import android.content.Context
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import com.wittywilla.wittymediaclient.net.ApiError
import com.wittywilla.wittymediaclient.net.ModuleSettingRow
import com.wittywilla.wittymediaclient.net.TV_FULL
import com.wittywilla.wittymediaclient.net.TV_VIEW
import com.wittywilla.wittymediaclient.net.TvSettingsFile
import com.wittywilla.wittymediaclient.net.TvSettingsRow
import com.wittywilla.wittymediaclient.net.TvSettingsRules
import com.wittywilla.wittymediaclient.net.json
import com.wittywilla.wittymediaclient.net.problemWords
import com.wittywilla.wittymediaclient.net.saveTvSetting
import com.wittywilla.wittymediaclient.net.tvSettingsStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

// The desktop Settings pages a TV draws itself (docs/TV-SETTINGS-PARITY.md): Video quality, Skipping and content,
// Playback, Appearance, Activity, Sharing and About, from shared/data/tv-settings.json. In the TV's own Settings
// design, the same rows as a module's settings (ModuleSettingsScreens.kt): a switch's value says On or Off and a press
// changes it, a choice opens its chips, a number has − and +. Every change is saved as it is made, through the same
// endpoints the server's own pages use. A page the server keeps as `view` on a TV shows its values, each row still a
// stop for the remote; a part kept for a computer is a row that opens its QR card, never a dead end.

object TvSettingsData {
    @Volatile private var cached: TvSettingsFile? = null

    fun file(context: Context): TvSettingsFile = cached ?: runCatching {
        json.decodeFromString<TvSettingsFile>(context.assets.open("tv-settings.json").bufferedReader().use { it.readText() })
    }.getOrDefault(TvSettingsFile()).also { cached = it }
}

@Composable
fun TvSettingsScreen(nav: Nav, s: Map<String, String>, pageId: String) {
    val context = LocalContext.current
    val file = remember { TvSettingsData.file(context) }
    val admin = nav.me?.isAdmin == true
    val page = TvSettingsRules.page(file, pageId)?.takeIf { TvSettingsRules.pageVisible(it, admin) }
    val words: (String) -> String = { k -> if (k.isEmpty()) "" else s[k] ?: k }
    if (page == null) {
        DesignScreen(s["groupServer"].orEmpty(), nav::pop) { DesignSection("") { DesignNote(s["errLost"].orEmpty(), error = true) } }
        return
    }
    val groups = remember(page, admin) { TvSettingsRules.visible(file, page, admin) }
    val scope = rememberCoroutineScope()
    var stores by remember { mutableStateOf<Map<String, JsonElement>?>(null) }
    var problem by remember { mutableStateOf("") }
    val rowProblems = remember { mutableStateMapOf<String, String>() }
    var said by remember { mutableStateOf("") }

    LaunchedEffect(page.id, admin) {
        val got = mutableMapOf<String, JsonElement>()
        for (id in TvSettingsRules.stores(groups)) {
            val store = file.stores[id] ?: continue
            try {
                got[id] = nav.app.api.tvSettingsStore(store)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                problem = problemWords(e, s["errLost"].orEmpty())
            }
        }
        stores = got
    }

    fun specRow(key: String): TvSettingsRow? = groups.firstNotNullOfOrNull { g -> g.rows.firstOrNull { it.rowKey == key } }

    fun save(row: ModuleSettingRow, value: JsonElement?) {
        val spec = specRow(row.key) ?: return
        val store = file.stores[spec.store] ?: return
        if (value == null) return
        rowProblems.remove(row.key)
        said = ""
        scope.launch {
            try {
                // A merge starts from what is there now: other screens and devices write there too.
                val fresh = if (store.write == "merge") nav.app.api.tvSettingsStore(store) else null
                nav.app.api.saveTvSetting(store, TvSettingsRules.body(store, fresh, spec, value))
                val now = nav.app.api.tvSettingsStore(store)
                stores = stores.orEmpty() + (spec.store to now)
                said = s["moduleSaved"].orEmpty()
            } catch (e: CancellationException) {
                throw e
            } catch (e: ApiError) {
                rowProblems[row.key] = e.message.orEmpty().ifEmpty { s["tvsCouldNotSave"].orEmpty() }
            } catch (e: Exception) {
                rowProblems[row.key] = problemWords(e, s["errLost"].orEmpty())
            }
        }
    }

    fun open(row: TvSettingsRow, title: String) {
        val to = row.to
        when {
            to == "app:theme" -> nav.push(Route.You(YouNative.Theme))
            to == "app:look" -> nav.push(Route.You(YouNative.Look))
            to.startsWith("tv:") -> nav.push(Route.TvSettings(to.removePrefix("tv:")))
            else -> nav.push(Route.OnPhone(title, to))
        }
    }

    val metrics = LocalMetrics.current
    val hint = MaterialTheme.colorScheme.onSurfaceVariant
    val readOnly = s["tvsReadOnlyHere"].orEmpty()
    DesignScreen(words(page.title), nav::pop, eyebrow = s["youTab"].orEmpty(), lead = words(page.lead), tag = "tv-settings.${page.id}") {
        val got = stores
        if (got == null) {
            Loading()
            return@DesignScreen
        }
        if (problem.isNotEmpty()) DesignSection("") { DesignNote(problem, error = true) }
        // A page a TV only shows says once, at its top, where it is changed.
        if (page.level == TV_VIEW) DesignNote(readOnly, Modifier.padding(top = LocalDesignSizes.current.gap), tone = true)
        val view = TvSettingsRules.asModule(file, page, groups, got, words)
        var first = true
        view.pages.first().groups.forEachIndexed { gi, group ->
            val specs = groups[gi].rows
            DesignSection(group.title) {
                group.rows.forEachIndexed { ri, row ->
                    val spec = specs[ri]
                    val focus = first
                    first = false
                    val chevron: @Composable () -> Unit = { Icon(Symbols.Next, null, tint = hint, modifier = Modifier.size(metrics.u(20))) }
                    when (spec.kind) {
                        "link" -> DesignRow(row.label, sub = row.help, onClick = { open(spec, row.label) }, trailing = chevron, focusKey = "tvs-${page.id}-${spec.rowKey}", requestFocus = focus)
                        "desktopOnly" -> {
                            val now = (view.values[row.key] as? JsonPrimitive)?.contentOrNull.orEmpty()
                            DesignRow(
                                row.label, value = now, sub = listOf(row.help, s["tvsOnAComputer"].orEmpty()).filter { it.isNotEmpty() }.joinToString(" · "),
                                onClick = { open(spec, row.label) }, focusKey = "tvs-${page.id}-${spec.rowKey}", requestFocus = focus,
                                trailing = if (now.isEmpty()) chevron else null,
                            )
                        }
                        "list" -> TvSettingsRules.items(spec, got).forEachIndexed { i, (name, value) ->
                            DesignRow(name, value = value, onClick = {}, focusKey = "tvs-${page.id}-${spec.rowKey}-$i", requestFocus = focus && i == 0)
                        }
                        else -> SettingRows(
                            view, row, s, rowProblems[row.key].orEmpty(), ::save,
                            // A row a view page only shows needs no note of its own: the page says it at its top.
                            readOnly = if (TvSettingsRules.level(page, spec) == TV_FULL || page.level == TV_VIEW) "" else readOnly,
                            requestFocus = focus,
                        )
                    }
                }
                DesignNote(group.footer)
            }
        }
        if (said.isNotEmpty()) DesignNote(said, Modifier.padding(top = LocalDesignSizes.current.gap).semantics { liveRegion = LiveRegionMode.Polite })
    }
}
