// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import com.wittywilla.wittymediaclient.data.fill
import com.wittywilla.wittymediaclient.net.ApiError
import com.wittywilla.wittymediaclient.net.ModuleSettingRow
import com.wittywilla.wittymediaclient.net.ModuleSettingsEntry
import com.wittywilla.wittymediaclient.net.SettingsSlotPage
import com.wittywilla.wittymediaclient.net.settingsSlot
import com.wittywilla.wittymediaclient.net.ModuleSettingsRules
import com.wittywilla.wittymediaclient.net.ModuleSettingsView
import com.wittywilla.wittymediaclient.net.moduleSettings
import com.wittywilla.wittymediaclient.net.moduleSettingsList
import com.wittywilla.wittymediaclient.net.problemWords
import com.wittywilla.wittymediaclient.net.saveModuleSetting
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive

// You, Modules: each module that has settings this profile may see (docs/SDUI-MODULES.md, "Drawing them in an app").
// In the app's own style and controls, never the module's colours.
@Composable
fun ModuleSettingsListScreen(nav: Nav, s: Map<String, String>) {
    var modules by remember { mutableStateOf<List<ModuleSettingsEntry>?>(null) }
    var problem by remember { mutableStateOf("") }
    LaunchedEffect(Unit) {
        try {
            modules = nav.app.api.moduleSettingsList().modules.filter { ModuleSettingsRules.path(it.url) != null }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            problem = problemWords(e, s["errLost"].orEmpty())
            modules = emptyList()
        }
    }
    SettingsPage(nav, s["rowModuleSettings"].orEmpty(), s["moduleSettingsHint"].orEmpty()) {
        val list = modules
        when {
            list == null -> Loading()
            list.isEmpty() -> Note(problem.ifEmpty { s["moduleSettingsNone"].orEmpty() })
            else -> GroupedList("", list.mapIndexed { i, m ->
                GroupRow(m.label.ifEmpty { m.module }, onClick = { nav.push(Route.ModuleSettings(m.url, m.label.ifEmpty { m.module })) }, icon = sduiIcon(m.icon.ifEmpty { "extension" }), focusKey = "module-${m.module}", requestFocus = i == 0)
            })
        }
    }
}

// One module's settings: its pages one after another, each group a grouped list under its title with its footer under
// it. A change is saved as it is made, and the server's answer is what is shown; a refusal keeps the old value and
// says why by the row.
@Composable
fun ModuleSettingsScreen(nav: Nav, s: Map<String, String>, url: String, title: String, only: String = "") {
    val path = remember(url) { ModuleSettingsRules.path(url) }
    val scope = rememberCoroutineScope()
    var view by remember { mutableStateOf<ModuleSettingsView?>(null) }
    var problem by remember { mutableStateOf("") }
    val rowProblems = remember { mutableStateMapOf<String, String>() }
    val drafts = remember { mutableStateMapOf<String, String>() }
    var said by remember { mutableStateOf("") }
    LaunchedEffect(path) {
        if (path == null) return@LaunchedEffect
        try {
            view = nav.app.api.moduleSettings(path)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            problem = problemWords(e, s["errLost"].orEmpty())
        }
    }

    fun save(row: ModuleSettingRow, value: JsonElement?) {
        val at = path ?: return
        rowProblems.remove(row.key)
        said = ""
        scope.launch {
            try {
                view = nav.app.api.saveModuleSetting(ModuleSettingsRules.writePath(at, row), ModuleSettingsRules.change(row.key, value))
                drafts.remove(row.key)
                said = s["moduleSaved"].orEmpty()
            } catch (e: CancellationException) {
                throw e
            } catch (e: ApiError) {
                rowProblems[row.key] = e.message.orEmpty()
            } catch (e: Exception) {
                rowProblems[row.key] = problemWords(e, s["errLost"].orEmpty())
            }
        }
    }

    SettingsPage(nav, if (only.isNotEmpty()) title else view?.label?.ifEmpty { null } ?: title, "") {
        val v = view
        when {
            v == null && problem.isNotEmpty() -> Note(problem)
            v == null -> Loading()
            else -> v.pages.filter { only.isEmpty() || it.id == only }.forEach { page ->
                page.groups.forEach { group ->
                    val rows = group.rows.filter(ModuleSettingsRules::known)
                    GroupedList(group.title.ifEmpty { page.title }, rows.flatMap { row -> rowsFor(v, row, s, drafts, rowProblems[row.key].orEmpty(), ::save) })
                    // Fields for text and secrets sit under their group, one per row that takes typing.
                    rows.filter { ModuleSettingsRules.editable(v, it) && (it.kind == "string" || it.kind == "secret") }.forEach { row ->
                        val secret = row.kind == "secret"
                        WittyField(
                            drafts[row.key] ?: if (secret) "" else ModuleSettingsRules.text(v, row.key),
                            { drafts[row.key] = it.take(ModuleSettingsRules.limit(row)) },
                            if (secret) row.label + " · " + s["moduleSecretNew"].orEmpty() else row.label,
                            Modifier.fillMaxWidth(),
                            kind = if (secret) FieldKind.Password else FieldKind.Text,
                            error = rowProblems[row.key].orEmpty(),
                            onAction = { drafts[row.key]?.let { typed -> save(row, JsonPrimitive(typed)) } },
                            maxLength = ModuleSettingsRules.limit(row),
                        )
                        if (secret && row.key in v.secretsSet) WittyButton(s["moduleSecretClear"].orEmpty() + " · " + row.label, { save(row, null) }, kind = ButtonKind.Quiet, focusKey = "clear-${row.key}")
                    }
                    if (group.footer.isNotEmpty()) Text(group.footer, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.secondary)
                }
            }
        }
        if (said.isNotEmpty()) Text(said, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.secondary, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
    }
}

// The rows of the app's own grouped list for one setting.
private fun rowsFor(
    view: ModuleSettingsView, row: ModuleSettingRow, s: Map<String, String>, drafts: Map<String, String>, problem: String,
    save: (ModuleSettingRow, JsonElement?) -> Unit,
): List<GroupRow> {
    val canEdit = ModuleSettingsRules.editable(view, row)
    val help = listOf(row.help, problem, if (!canEdit && row.kind != "info") s["moduleReadOnly"].orEmpty() else "").filter { it.isNotEmpty() }.joinToString(" · ")
    val key = "setting-${row.key.ifEmpty { row.label }}"
    return when (row.kind) {
        "bool" -> {
            val on = ModuleSettingsRules.bool(view, row.key)
            listOf(GroupRow(row.label, onClick = if (canEdit) ({ save(row, JsonPrimitive(!on)) }) else null, detail = help, focusKey = key, chevron = false,
                trailing = { Toggle(on) }, value = if (canEdit) "" else if (on) "On" else "Off"))
        }
        "enum" -> {
            val current = ModuleSettingsRules.text(view, row.key)
            if (!canEdit) listOf(GroupRow(row.label, value = ModuleSettingsRules.shown(view, row), detail = help, focusKey = key, chevron = false, onClick = {}))
            else listOf(GroupRow(row.label, detail = help, focusKey = key, chevron = false, onClick = {})) +
                row.options.map { option ->
                    GroupRow("    " + option.label, onClick = { if (option.value != current) save(row, JsonPrimitive(option.value)) }, selected = option.value == current,
                        chevron = false, focusKey = "$key-${option.value}", trailing = if (option.value == current) ({ Text("✓", color = MaterialTheme.colorScheme.primary) }) else null)
                }
        }
        "int" -> {
            val now = ModuleSettingsRules.number(view, row.key)
            listOf(GroupRow(row.label, value = ModuleSettingsRules.shown(view, row), detail = help, focusKey = key, chevron = false, onClick = if (canEdit) ({}) else null,
                trailing = if (!canEdit) null else ({
                    Row(horizontalArrangement = Arrangement.spacedBy(LocalMetrics.current.u(8))) {
                        WittyButton("−", { save(row, JsonPrimitive(ModuleSettingsRules.stepped(row, now, -1))) }, kind = ButtonKind.Quiet, focusKey = "$key-less")
                        WittyButton("+", { save(row, JsonPrimitive(ModuleSettingsRules.stepped(row, now, 1))) }, kind = ButtonKind.Quiet, focusKey = "$key-more")
                    }
                })))
        }
        "secret" -> listOf(GroupRow(row.label, value = if (row.key in view.secretsSet) s["moduleSecretSet"].orEmpty() else s["moduleSecretNotSet"].orEmpty(), detail = help, focusKey = key, chevron = false, onClick = {}))
        "string" -> listOf(GroupRow(row.label, value = if (canEdit) "" else ModuleSettingsRules.shown(view, row), detail = help, focusKey = key, chevron = false, onClick = {}))
        // Something to read, reachable all the same.
        else -> listOf(GroupRow(row.label, detail = row.help, focusKey = key, chevron = false, onClick = {}))
    }
}


// The settings pages modules put in one place of the hand-built Settings (the server's GET /api/sdui/slots/{slot}): a group of
// rows, each opening that page of the module's settings in the app's own controls. Nothing when no module has one there.
@Composable
fun SettingsSlotRows(nav: Nav, slot: String, caption: String = "") {
    var pages by remember(slot) { mutableStateOf<List<SettingsSlotPage>>(emptyList()) }
    LaunchedEffect(slot, nav.sdui) {
        pages = runCatching { nav.app.api.settingsSlot(slot).pages.filter { ModuleSettingsRules.path(it.url) != null } }.getOrDefault(emptyList())
    }
    if (pages.isEmpty()) return
    GroupedList(caption, pages.map { p ->
        GroupRow(p.title.ifEmpty { p.label }, onClick = { nav.push(Route.ModuleSettings(p.url, p.title.ifEmpty { p.label }, p.id)) }, icon = sduiIcon(p.icon.ifEmpty { "extension" }), detail = p.label, focusKey = "slot-$slot-${p.module}-${p.id}")
    })
}
