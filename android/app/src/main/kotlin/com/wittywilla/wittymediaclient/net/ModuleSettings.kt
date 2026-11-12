// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.longOrNull

// A module's settings, as the module describes them and the server keeps them (the server's docs/SDUI-MODULES.md,
// Settings). The app draws them in its own Settings, with its own controls: You, Modules, then the module.

@Serializable
data class ModuleSettingsList(val modules: List<ModuleSettingsEntry> = emptyList())

@Serializable
data class ModuleSettingsEntry(val module: String = "", val label: String = "", val icon: String = "", val url: String = "")

@Serializable
data class ModuleSettingsView(
    val module: String = "",
    val label: String = "",
    val pages: List<ModuleSettingsPage> = emptyList(),
    val values: JsonObject = JsonObject(emptyMap()),
    val secretsSet: List<String> = emptyList(),
    val editable: Boolean = false,
)

@Serializable
data class ModuleSettingsPage(val id: String = "", val title: String = "", val icon: String = "", val admin: Boolean = false, val groups: List<ModuleSettingsGroup> = emptyList())

@Serializable
data class ModuleSettingsGroup(val title: String = "", val footer: String = "", val rows: List<ModuleSettingRow> = emptyList())

@Serializable
data class ModuleSettingOption(val value: String = "", val label: String = "")

@Serializable
data class ModuleSettingRow(
    val key: String = "",
    val kind: String = "",
    val label: String = "",
    val help: String = "",
    val scope: String = "server",
    val options: List<ModuleSettingOption> = emptyList(),
    val min: Long? = null,
    val max: Long? = null,
    val unit: String = "",
    val maxLength: Int = 0,
)

object ModuleSettingsRules {
    private const val ROOT = "/api/v1/sdui/modules/"
    private val KINDS = setOf("bool", "enum", "int", "string", "secret", "info")

    // Only the server's own module settings addresses are followed.
    fun path(url: String): String? = url.takeIf { it.startsWith(ROOT) && it.endsWith("/settings") && !it.contains("..") && it.indexOf("//", 1) < 0 }?.removePrefix("/api/v1")

    // Where a change to this row is sent: the server's values, or this profile's own.
    fun writePath(path: String, row: ModuleSettingRow): String = if (row.scope == "profile") "$path/personal" else path

    // Rows this app knows how to draw; one of a kind from a newer server is left out rather than guessed at.
    fun known(row: ModuleSettingRow): Boolean = row.kind in KINDS

    // Whether this profile may change the row here: its own values always, the server's only as an administrator.
    fun editable(view: ModuleSettingsView, row: ModuleSettingRow): Boolean =
        row.kind != "info" && (row.scope == "profile" || view.editable)

    fun bool(view: ModuleSettingsView, key: String): Boolean = (view.values[key] as? JsonPrimitive)?.booleanOrNull == true

    fun text(view: ModuleSettingsView, key: String): String = (view.values[key] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.contentOrNull.orEmpty()

    fun number(view: ModuleSettingsView, key: String): Long? = (view.values[key] as? JsonPrimitive)?.longOrNull

    // The row's value in words: an option's label, a number with its unit, the text itself.
    fun shown(view: ModuleSettingsView, row: ModuleSettingRow): String = when (row.kind) {
        "enum" -> text(view, row.key).let { v -> row.options.firstOrNull { it.value == v }?.label ?: v }
        "int" -> number(view, row.key)?.let { n -> if (row.unit.isEmpty()) "$n" else "$n ${row.unit}" }.orEmpty()
        "string" -> text(view, row.key)
        else -> ""
    }

    // One step of a number: within the row's bounds.
    fun stepped(row: ModuleSettingRow, now: Long?, by: Long): Long {
        val next = (now ?: row.min ?: 0) + by
        val low = row.min ?: Long.MIN_VALUE
        val high = row.max ?: Long.MAX_VALUE
        return next.coerceIn(low, high)
    }

    // What the PUT carries: one value, or null to go back to the default.
    fun change(key: String, value: JsonElement?): String =
        JsonObject(mapOf("values" to JsonObject(mapOf(key to (value ?: JsonNull))))).toString()

    // Text the module may say, as text: one line for a label, no control characters.
    fun limit(row: ModuleSettingRow): Int = if (row.maxLength > 0) row.maxLength else 1000
}

suspend fun Api.moduleSettingsList(): ModuleSettingsList = json.decodeFromString(call("GET", "/sdui/modules/settings"))

suspend fun Api.moduleSettings(path: String): ModuleSettingsView = json.decodeFromString(call("GET", path))

suspend fun Api.saveModuleSetting(path: String, body: String): ModuleSettingsView = json.decodeFromString(call("PUT", path, body))
