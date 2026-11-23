// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull

// The desktop Settings pages a TV draws itself (docs/TV-SETTINGS-PARITY.md): shared/data/tv-settings.json, the twin of
// Apple's WittyKit TvSettings. Each page is in the shape of a module's settings (ModuleSettings.kt), so it is drawn by the
// same rows, with where each value is kept on the server: `server` (GET and PUT /settings, the administrator's), `ui`
// (/me/ui, the profile's own choices), `streaming` (/me/streaming) and `about` (/about, to read). These are the endpoints
// the server's own Settings pages use, so a change made on a TV is the same setting everywhere. A page's level is the
// server's TV level (docs/TV-MODE.md): full rows change here, view rows are read, desktopOnly rows open the QR card.
// Nothing here touches Android, so it can be tested.

@Serializable
data class TvSettingsFile(val stores: Map<String, TvSettingsStore> = emptyMap(), val pages: List<TvSettingsPage> = emptyList())

@Serializable
data class TvSettingsStore(val get: String = "", val put: String = "", val write: String = "", val root: String = "", val admin: Boolean = false)

@Serializable
data class TvSettingsPage(
    val id: String = "",
    val path: String = "",
    val title: String = "",
    val lead: String = "",
    val icon: String = "",
    val level: String = TV_FULL,
    val admin: Boolean = false,
    val groups: List<TvSettingsGroup> = emptyList(),
)

@Serializable
data class TvSettingsGroup(val title: String = "", val footer: String = "", val admin: Boolean = false, val rows: List<TvSettingsRow> = emptyList())

@Serializable
data class TvSettingsItem(val label: String = "", val value: String = "")

@Serializable
data class TvSettingsRow(
    val id: String = "",
    val store: String = "",
    val key: String = "",
    // bool, enum, int, info, list (one row for each thing in a list), link (another screen), desktopOnly (the QR card).
    val kind: String = "",
    val label: String = "",
    val help: String = "",
    val level: String = "",
    val admin: Boolean = false,
    val default: JsonElement? = null,
    // How the value is kept: "flag" ("1" or "0"), "string" (a number as text), "number"; or as it is.
    val encode: String = "",
    // A switch that says the opposite of what is kept (Show the activity button, kept as activityHidden).
    val invert: Boolean = false,
    val options: List<ModuleSettingOption> = emptyList(),
    // What a value none of the options has is called.
    val other: String = "",
    val min: Long? = null,
    val max: Long? = null,
    val step: Long = 1,
    val unit: String = "",
    // Kept with the same value as well, when it isn't empty (Disc menus and sound tracks: menuLanguage).
    val also: List<String> = emptyList(),
    // A link's screen ("app:theme", "tv:skipping"), or a desktopOnly row's address on the server.
    val to: String = "",
    val format: String = "",
    val item: TvSettingsItem? = null,
) {
    // Unique on its page: what the shared rows know it by.
    val rowKey: String get() = if (store.isNotEmpty() && key.isNotEmpty()) "$store:$key" else "row:" + id.ifEmpty { label }
}

object TvSettingsRules {
    private val DRAWN = setOf("bool", "enum", "int", "info", "list", "link", "desktopOnly")

    fun page(file: TvSettingsFile, id: String): TvSettingsPage? = file.pages.firstOrNull { it.id == id }

    // What this profile sees of a page: what's for administrators only to them, rows of a kind this app doesn't know left out.
    fun visible(file: TvSettingsFile, page: TvSettingsPage, admin: Boolean): List<TvSettingsGroup> =
        page.groups.filter { admin || !it.admin }.map { g ->
            g.copy(rows = g.rows.filter { r -> r.kind in DRAWN && (admin || (!r.admin && file.stores[r.store]?.admin != true)) })
        }.filter { it.rows.isNotEmpty() }

    fun pageVisible(page: TvSettingsPage, admin: Boolean) = admin || !page.admin

    // The stores a page reads.
    fun stores(groups: List<TvSettingsGroup>): Set<String> = groups.flatMap { g -> g.rows.map { it.store } }.filter { it.isNotEmpty() }.toSet()

    fun level(page: TvSettingsPage, row: TvSettingsRow): String = row.level.ifEmpty { page.level }

    // Whether a row is changed here: a full one, kept somewhere that can be written.
    fun editable(file: TvSettingsFile, page: TvSettingsPage, row: TvSettingsRow): Boolean =
        row.kind in setOf("bool", "enum", "int") && level(page, row) == TV_FULL && file.stores[row.store]?.put?.isNotEmpty() == true

    // "a.b" inside an answer.
    fun at(root: JsonElement?, path: String): JsonElement? {
        if (path.isEmpty()) return root
        var here: JsonElement? = root
        for (part in path.split('.')) here = (here as? JsonObject)?.get(part) ?: return null
        return here
    }

    private fun text(e: JsonElement?): String? = (e as? JsonPrimitive)?.takeIf { it !is JsonNull }?.contentOrNull

    fun bool(row: TvSettingsRow, raw: JsonElement?): Boolean {
        val p = raw as? JsonPrimitive
        val kept: Boolean? = when {
            p == null || p is JsonNull -> null
            p.isString -> when (p.content) { "1", "true" -> true; "0", "false" -> false; else -> null }
            else -> p.booleanOrNull ?: p.doubleOrNull?.let { it != 0.0 }
        }
        // The default is what is kept when nothing is (activityHidden: false), as the web reads it.
        val stored = kept ?: (row.default as? JsonPrimitive)?.let { it.booleanOrNull ?: (it.content == "1") } ?: false
        return if (row.invert) !stored else stored
    }

    fun choice(row: TvSettingsRow, raw: JsonElement?): String {
        val p = raw as? JsonPrimitive
        val v = when {
            p == null || p is JsonNull -> null
            p.isString -> p.content
            else -> p.doubleOrNull?.let { if (it == Math.floor(it)) it.toLong().toString() else it.toString() }
        }
        return if (v.isNullOrEmpty() && row.options.none { it.value == v.orEmpty() }) text(row.default) ?: v.orEmpty() else v.orEmpty()
    }

    fun number(row: TvSettingsRow, raw: JsonElement?): Long =
        (text(raw)?.trim()?.toDoubleOrNull()?.toLong()) ?: (row.default as? JsonPrimitive)?.longOrNull ?: row.min ?: 0

    // A row's value as the module rows hold it: a switch's true or false, a choice's value, a number.
    fun value(row: TvSettingsRow, stores: Map<String, JsonElement>, words: (String) -> String): JsonElement? {
        val raw = at(stores[row.store], row.key)
        return when (row.kind) {
            "bool" -> JsonPrimitive(bool(row, raw))
            "enum" -> JsonPrimitive(choice(row, raw))
            "int" -> JsonPrimitive(number(row, raw))
            "info", "desktopOnly" -> if (row.key.isEmpty()) null else JsonPrimitive(shownInfo(row, raw, words))
            else -> null
        }
    }

    // An info row's words: the text, or a limit as the web's Video quality says it.
    fun shownInfo(row: TvSettingsRow, raw: JsonElement?, words: (String) -> String): String = when (row.format) {
        "limit" -> limitWords(raw, words)
        else -> text(raw).orEmpty()
    }

    fun limitWords(raw: JsonElement?, words: (String) -> String): String {
        val height = (at(raw, "maxHeight") as? JsonPrimitive)?.longOrNull ?: 0
        val kbps = (at(raw, "maxKbps") as? JsonPrimitive)?.longOrNull ?: 0
        val size = if (height >= 2160) "4K" else "${height}p"
        val rate = if (kbps >= 1000) (if (kbps % 1000 == 0L) "${kbps / 1000}" else "%.1f".format(java.util.Locale.ROOT, kbps / 1000.0)) + " Mb/s" else "$kbps kb/s"
        return when {
            height > 0 && kbps > 0 -> words("tvsLimitBoth").replace("{size}", size).replace("{rate}", rate)
            height > 0 -> words("tvsLimitSize").replace("{size}", size)
            kbps > 0 -> words("tvsLimitRate").replace("{rate}", rate)
            else -> words("tvsNoLimit")
        }
    }

    // A list row's things, as a label and a value each.
    fun items(row: TvSettingsRow, stores: Map<String, JsonElement>): List<Pair<String, String>> {
        val list = at(stores[row.store], row.key) as? JsonArray ?: return emptyList()
        val item = row.item ?: TvSettingsItem("name", "version")
        return list.mapNotNull { e -> text(at(e, item.label))?.let { it to text(at(e, item.value)).orEmpty() } }
    }

    // One step of a number, by the row's step, inside its bounds.
    fun stepped(row: TvSettingsRow, now: Long, by: Int): Long =
        (now + by * row.step.coerceAtLeast(1)).coerceIn(row.min ?: Long.MIN_VALUE, row.max ?: Long.MAX_VALUE)

    // How a value chosen here is kept.
    fun encode(row: TvSettingsRow, value: JsonElement): JsonElement {
        val p = value as? JsonPrimitive ?: return value
        return when (row.kind) {
            "bool" -> {
                val on = p.booleanOrNull == true
                val kept = if (row.invert) !on else on
                if (row.encode == "flag") JsonPrimitive(if (kept) "1" else "0") else JsonPrimitive(kept)
            }
            "enum" -> if (row.encode == "number") JsonPrimitive(p.content.toDoubleOrNull()?.toLong() ?: 0) else JsonPrimitive(p.content)
            "int" -> if (row.encode == "string") JsonPrimitive(p.content.toDoubleOrNull()?.toLong()?.toString() ?: p.content) else JsonPrimitive(p.longOrNull ?: 0)
            else -> p
        }
    }

    // What a change sends to the store's `put`: for "patch", the keys alone (the server keeps the rest); for "merge",
    // everything there now (fresh: other screens write there too) with this change, at the store's root.
    fun body(store: TvSettingsStore, fresh: JsonElement?, row: TvSettingsRow, value: JsonElement): JsonElement {
        val kept = encode(row, value)
        val changes = buildMap {
            put(row.key, kept)
            val text = (kept as? JsonPrimitive)?.contentOrNull.orEmpty()
            if (text.isNotEmpty()) row.also.forEach { put(it, kept) }
        }
        if (store.write == "patch") return JsonObject(changes)
        val prefix = if (store.root.isEmpty()) "" else store.root + "."
        var base = at(fresh, store.root) as? JsonObject ?: JsonObject(emptyMap())
        for ((k, v) in changes) {
            if (prefix.isNotEmpty() && !k.startsWith(prefix)) continue
            base = put(base, k.removePrefix(prefix).split('.'), v)
        }
        return base
    }

    private fun put(obj: JsonObject, path: List<String>, value: JsonElement): JsonObject {
        val head = path.first()
        if (path.size == 1) return JsonObject(obj + (head to value))
        val inner = obj[head] as? JsonObject ?: JsonObject(emptyMap())
        return JsonObject(obj + (head to put(inner, path.drop(1), value)))
    }

    // The page as a module's settings, for the rows ModuleSettingsScreens.kt draws: words looked up, values filled in.
    fun asModule(file: TvSettingsFile, page: TvSettingsPage, groups: List<TvSettingsGroup>, stores: Map<String, JsonElement>, words: (String) -> String): ModuleSettingsView {
        val values = mutableMapOf<String, JsonElement>()
        val mod = groups.map { g ->
            ModuleSettingsGroup(
                words(g.title), words(g.footer),
                g.rows.map { r ->
                    value(r, stores, words)?.let { values[r.rowKey] = it }
                    val options = r.options.map { ModuleSettingOption(it.value, words(it.label)) }
                    val chosen = (values[r.rowKey] as? JsonPrimitive)?.contentOrNull
                    val withOther = if (r.kind == "enum" && chosen != null && options.none { it.value == chosen } && r.other.isNotEmpty()) options + ModuleSettingOption(chosen, words(r.other)) else options
                    ModuleSettingRow(
                        key = r.rowKey, kind = r.kind, label = words(r.label), help = words(r.help),
                        // Editable rows say "profile", so ModuleSettingsRules lets them change; the rest are read.
                        scope = if (editable(file, page, r)) "profile" else "server",
                        options = withOther, min = r.min, max = r.max, unit = words(r.unit), step = r.step,
                    )
                },
            )
        }
        return ModuleSettingsView(module = page.id, label = words(page.title), pages = listOf(ModuleSettingsPage(page.id, words(page.title), page.icon, page.admin, mod)), values = JsonObject(values), editable = false)
    }

    // A desktopOnly row's address on the server, without its section.
    fun cardPath(row: TvSettingsRow): String = row.to.ifEmpty { "/settings" }
}

suspend fun Api.tvSettingsStore(store: TvSettingsStore): JsonElement = json.parseToJsonElement(call("GET", store.get.removePrefix("/api")))

suspend fun Api.saveTvSetting(store: TvSettingsStore, body: JsonElement) {
    call("PUT", store.put.removePrefix("/api"), body.toString())
}
