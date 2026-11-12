// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import com.wittywilla.wittymediaclient.net.ApiError
import com.wittywilla.wittymediaclient.net.ModuleSettingRow
import com.wittywilla.wittymediaclient.net.ModuleSettingsEntry
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
    val metrics = LocalMetrics.current
    val accent = LocalExtraColours.current.accentText
    DesignScreen(s["rowModuleSettings"].orEmpty(), nav::pop, eyebrow = s["youTab"].orEmpty(), lead = s["moduleSettingsHint"].orEmpty()) {
        val list = modules
        DesignSection("") {
            when {
                list == null -> Loading()
                list.isEmpty() -> DesignNote(problem.ifEmpty { s["moduleSettingsNone"].orEmpty() })
                else -> list.forEachIndexed { i, m ->
                    DesignRow(
                        m.label.ifEmpty { m.module }, onClick = { nav.push(Route.ModuleSettings(m.url, m.label.ifEmpty { m.module })) },
                        leading = { Icon(sduiIcon(m.icon.ifEmpty { "extension" }), null, tint = accent, modifier = Modifier.size(metrics.u(24))) },
                        trailing = { Icon(Symbols.Next, null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(metrics.u(20))) },
                        focusKey = "module-${m.module}", requestFocus = i == 0,
                    )
                }
            }
        }
    }
}

// One module's settings: its pages one after another, each group a grouped list under its title with its footer under
// it. A change is saved as it is made, and the server's answer is what is shown; a refusal keeps the old value and
// says why by the row.
@Composable
fun ModuleSettingsScreen(nav: Nav, s: Map<String, String>, url: String, title: String) {
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

    DesignScreen(view?.label?.ifEmpty { null } ?: title, nav::pop, eyebrow = s["rowModuleSettings"].orEmpty()) {
        val v = view
        when {
            v == null && problem.isNotEmpty() -> DesignSection("") { DesignNote(problem, error = true) }
            v == null -> Loading()
            else -> v.pages.forEach { page ->
                page.groups.forEach { group ->
                    val rows = group.rows.filter(ModuleSettingsRules::known)
                    DesignSection(group.title.ifEmpty { page.title }) {
                        rows.forEach { row -> SettingRows(v, row, s, rowProblems[row.key].orEmpty(), ::save) }
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
                        DesignNote(group.footer)
                    }
                }
            }
        }
        if (said.isNotEmpty()) DesignNote(said, Modifier.padding(top = LocalDesignSizes.current.gap).semantics { liveRegion = LiveRegionMode.Polite })
    }
}

// One setting's rows, in the order the app's grouped list had them: a switch, a choice (its options as chips), a number
// with − and +, a secret, some text, or something to read, reachable all the same.
@Composable
private fun SettingRows(
    view: ModuleSettingsView, row: ModuleSettingRow, s: Map<String, String>, problem: String,
    save: (ModuleSettingRow, JsonElement?) -> Unit,
) {
    val canEdit = ModuleSettingsRules.editable(view, row)
    val help = listOf(row.help, problem, if (!canEdit && row.kind != "info") s["moduleReadOnly"].orEmpty() else "").filter { it.isNotEmpty() }.joinToString(" · ")
    val key = "setting-${row.key.ifEmpty { row.label }}"
    when (row.kind) {
        "bool" -> {
            val on = ModuleSettingsRules.bool(view, row.key)
            val words = LocalWords.current
            val said = if (on) words["on"] ?: "On" else words["off"] ?: "Off"
            DesignRow(row.label, value = said, sub = help, on = on, state = said, selected = on, focusKey = key, onClick = if (canEdit) ({ save(row, JsonPrimitive(!on)) }) else null)
        }
        "enum" -> {
            val current = ModuleSettingsRules.text(view, row.key)
            if (!canEdit) DesignRow(row.label, value = ModuleSettingsRules.shown(view, row), sub = help, focusKey = key, onClick = {})
            else {
                DesignRow(row.label, value = ModuleSettingsRules.shown(view, row), on = true, sub = help, focusKey = key, onClick = {})
                DesignChips {
                    row.options.forEach { option ->
                        DesignChip(option.label, { if (option.value != current) save(row, JsonPrimitive(option.value)) }, on = option.value == current, focusKey = "$key-${option.value}")
                    }
                }
            }
        }
        "int" -> {
            val now = ModuleSettingsRules.number(view, row.key)
            val shown = ModuleSettingsRules.shown(view, row)
            if (!canEdit) DesignRow(row.label, value = shown, sub = help, focusKey = key)
            else DesignRow(
                row.label, sub = help, focusKey = key, onClick = {}, label = listOf(row.label, help, shown).filter { it.isNotEmpty() }.joinToString(", "),
                trailing = {
                    val ds = LocalDesignSizes.current
                    Row(horizontalArrangement = Arrangement.spacedBy(LocalMetrics.current.u(8)), verticalAlignment = Alignment.CenterVertically) {
                        Text(shown, color = LocalExtraColours.current.accentText, fontSize = ds.small, fontWeight = FontWeight.Bold)
                        WittyButton("−", { save(row, JsonPrimitive(ModuleSettingsRules.stepped(row, now, -1))) }, kind = ButtonKind.Quiet, focusKey = "$key-less")
                        WittyButton("+", { save(row, JsonPrimitive(ModuleSettingsRules.stepped(row, now, 1))) }, kind = ButtonKind.Quiet, focusKey = "$key-more")
                    }
                },
            )
        }
        "secret" -> DesignRow(row.label, value = if (row.key in view.secretsSet) s["moduleSecretSet"].orEmpty() else s["moduleSecretNotSet"].orEmpty(), on = row.key in view.secretsSet, sub = help, focusKey = key, onClick = {})
        "string" -> DesignRow(row.label, value = if (canEdit) "" else ModuleSettingsRules.shown(view, row), sub = help, focusKey = key, onClick = {})
        // Something to read, reachable all the same.
        else -> DesignRow(row.label, sub = row.help, focusKey = key, onClick = {})
    }
}
