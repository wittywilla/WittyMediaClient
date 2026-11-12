// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import java.net.URLDecoder

// One router for every place in the app, driven by the catalogue's routes table (docs/SDUI.md, Routes): a route is
// an SDUI page asked for with parameters, or one of the app's own screens. Nothing here knows a screen by name.

// Where a route leads.
sealed interface SduiTarget {
    // An SDUI page, asked for as pages/{page} with these parameters.
    data class Page(val page: String, val params: Map<String, String>, val route: String) : SduiTarget

    // One of the app's own screens, with what the route named ({item}, {key}, {section}) and its query.
    data class Native(val screen: String, val params: Map<String, String>, val route: String) : SduiTarget

    // A route the table doesn't have: the app's own idea of it, or the server's page.
    data class Unknown(val route: String) : SduiTarget
}

// What an action comes to.
sealed interface SduiEffect {
    data class Open(val target: SduiTarget) : SduiEffect
    data class Play(val item: String, val resume: Boolean) : SduiEffect
    data class External(val url: String) : SduiEffect
    data object Back : SduiEffect
    data class SelectTab(val tab: String) : SduiEffect

    // A Dock's control: sort, filter, view or jump, for the Grid it names.
    data class OpenControl(val control: String, val target: String) : SduiEffect
    data object Refresh : SduiEffect
    // One of the catalogue's commands that changes something on the server; the page is asked for again after.
    data class Command(val spec: SduiCommandSpec, val item: String, val params: Map<String, String> = emptyMap()) : SduiEffect
    // An action of a type, or a command, this app doesn't know: it does nothing.
    data object Nothing : SduiEffect
}

class SduiRouter(routes: List<SduiRouteSpec> = DEFAULT_ROUTES, commands: List<SduiCommandSpec> = DEFAULT_COMMANDS) {
    private val routes = routes.ifEmpty { DEFAULT_ROUTES }
    private val commands = commands.ifEmpty { DEFAULT_COMMANDS }.associateBy { it.op }

    fun resolve(route: String): SduiTarget {
        val path = route.substringBefore('?').substringBefore('#').let { if (it.length > 1) it.trimEnd('/') else it }
        val query = parseQuery(route.substringAfter('?', "").substringBefore('#'))
        val segments = path.trim('/').split('/').filter { it.isNotEmpty() }
        for (spec in routes) {
            val vars = match(spec.pattern, segments) ?: continue
            if (spec.native.isNotEmpty()) return SduiTarget.Native(spec.native, query + vars, route)
            if (spec.page.isEmpty()) continue
            // What the table asks for by name, then whatever else the route's query carried: a library's filters, a tab.
            val params = LinkedHashMap<String, String>()
            for ((name, from) in spec.params) {
                val value = fill(from, vars, query)
                if (value.isNotEmpty()) params[name] = value
            }
            query.forEach { (k, v) -> if (k !in params && v.isNotEmpty()) params[k] = v }
            return SduiTarget.Page(fill(spec.page, vars, query), params, route)
        }
        return SduiTarget.Unknown(route)
    }

    // {name} is from the route, ?name from its query; anything else is itself.
    private fun fill(from: String, vars: Map<String, String>, query: Map<String, String>): String = when {
        from.startsWith("{") && from.endsWith("}") -> vars[from.substring(1, from.length - 1)].orEmpty()
        from.startsWith("?") -> query[from.drop(1)].orEmpty()
        else -> from
    }

    private fun match(pattern: String, segments: List<String>): Map<String, String>? {
        val want = pattern.trim('/').split('/').filter { it.isNotEmpty() }
        if (want.size != segments.size) return null
        val vars = LinkedHashMap<String, String>()
        for (i in want.indices) {
            val w = want[i]
            if (w.startsWith("{") && w.endsWith("}")) vars[w.substring(1, w.length - 1)] = decode(segments[i])
            else if (w != segments[i]) return null
        }
        return vars
    }

    fun effect(action: SduiAction?): SduiEffect = when (action?.type) {
        "navigate" -> if (action.to.isEmpty()) SduiEffect.Nothing else SduiEffect.Open(resolve(action.to))
        "native" -> {
            val params = action.params.mapNotNull { (k, v) -> (v as? kotlinx.serialization.json.JsonPrimitive)?.content?.let { k to it } }.toMap()
            if (action.to.isEmpty()) SduiEffect.Nothing else SduiEffect.Open(SduiTarget.Native(action.to, params, ""))
        }
        "play" -> if (action.item.isEmpty()) SduiEffect.Nothing else SduiEffect.Play(action.item, action.params.notOff("resume"))
        "external" -> if (action.url.startsWith("http://") || action.url.startsWith("https://")) SduiEffect.External(action.url) else SduiEffect.Nothing
        "back" -> SduiEffect.Back
        "command" -> when (action.op) {
            "control.open" -> SduiEffect.OpenControl(action.params.str("control"), action.params.str("target"))
            "selectTab" -> action.params.str("tab").let { if (it.isEmpty()) SduiEffect.Nothing else SduiEffect.SelectTab(it) }
            "refresh" -> SduiEffect.Refresh
            else -> {
                val given = SduiCommands.given(action.params)
                commands[action.op]?.takeIf { it.path.isNotEmpty() && SduiCommands.request(it, action.item, given) != null }
                    ?.let { SduiEffect.Command(it, action.item, given) } ?: SduiEffect.Nothing
            }
        }
        else -> SduiEffect.Nothing
    }

    companion object {
        private fun decode(text: String): String = runCatching { URLDecoder.decode(text, "UTF-8") }.getOrDefault(text)

        fun parseQuery(query: String): Map<String, String> {
            val out = LinkedHashMap<String, String>()
            query.split('&').forEach { pair ->
                if (pair.isEmpty()) return@forEach
                out[decode(pair.substringBefore('='))] = decode(pair.substringAfter('=', ""))
            }
            return out
        }

        private fun page(pattern: String, page: String, vararg params: Pair<String, String>) = SduiRouteSpec(pattern, page = page, params = params.toMap())
        private fun native(pattern: String, screen: String) = SduiRouteSpec(pattern, native = screen)

        // Catalogue revision 2's table, for the moment before the server's own has been read.
        val DEFAULT_ROUTES: List<SduiRouteSpec> = listOf(
            page("/", "home"),
            page("/libraries", "libraries"),
            page("/library/{library}", "library", "library" to "{library}"),
            page("/item/{item}", "detail", "item" to "{item}"),
            page("/show/{show}", "detail", "show" to "{show}"),
            page("/album/{library}", "detail", "album" to "?album", "artist" to "?artist", "library" to "{library}"),
            // A person's page (catalogue revision 5: cast and crew).
            page("/person/{person}", "detail", "person" to "{person}"),
            page("/collections/{collection}", "detail", "collection" to "{collection}"),
            page("/collections", "collections"),
            page("/search", "search", "q" to "?q"),
            page("/tv", "livetv"),
            page("/music", "music"),
            page("/photos", "photos"),
            page("/books", "books"),
            page("/games", "games"),
            page("/page/{id}", "{id}"),
            native("/settings", "settings"),
            native("/settings/{section}", "settings"),
            native("/tv/guide", "guide"),
            native("/tv/recordings", "guide"),
            native("/tv/watch/{key}", "livePlayer"),
            native("/watch/{item}", "player"),
            native("/play/{item}", "player"),
            native("/read/{item}", "reader"),
            native("/game/{item}", "game"),
            native("/you", "profiles"),
            native("/pair", "pair"),
        )

        val DEFAULT_COMMANDS: List<SduiCommandSpec> = listOf(
            SduiCommandSpec("watchLater.add", "POST", "/api/v1/collections/watch-later/items", "{\"items\":[{item}]}"),
            SduiCommandSpec("watched.set", "POST", "/api/v1/items/{item}/progress", "{\"watched\":true}"),
            SduiCommandSpec("watched.clear", "DELETE", "/api/v1/items/{item}/progress", ""),
            SduiCommandSpec("selectTab", "GET", "", ""),
            SduiCommandSpec("refresh", "GET", "", ""),
        )
    }
}

// A command as a request. Items are numbers, but a show's is "show-<n>", which the catalogue's templates were not
// written for: Watch later takes a show under `shows`, and there is no request that marks a whole show watched.
object SduiCommands {
    class Request(val method: String, val path: String, val body: String?)

    private fun showId(item: String): Long? = item.removePrefix("show-").takeIf { it != item }?.toLongOrNull()

    fun bodyItem(item: String): String = item.toLongOrNull()?.toString() ?: ("\"" + item.replace("\\", "\\\\").replace("\"", "\\\"") + "\"")

    // The server's apiRevision, read with its capabilities. From 16 its templates hold {item} inside a JSON string and
    // its routes take a show's "show-<n>" (marking a whole show watched included), so nothing needs working round.
    @Volatile
    var serverRevision = 0

    private const val SHOW_IDS_FROM = 16

    // An action's params as text, for the command's own {name} values.
    fun given(params: Map<String, kotlinx.serialization.json.JsonElement>): Map<String, String> =
        params.mapNotNull { (k, v) -> (v as? kotlinx.serialization.json.JsonPrimitive)?.let { k to it.content } }.toMap()

    private fun inPath(v: String) = java.net.URLEncoder.encode(v, "UTF-8").replace("+", "%20")
    private fun inString(v: String) = v.replace("\\", "\\\\").replace("\"", "\\\"")

    // The command's {name} values: in the path escaped for a URL, in the body escaped for a JSON string; an int takes the
    // place of its quoted token ("{name}") as a number; one not given is an empty string, and a required one not given
    // refuses the command.
    private fun fill(spec: SduiCommandSpec, path: String, body: String, given: Map<String, String>): Pair<String, String>? {
        var p = path
        var b = body
        for (param in spec.params) {
            val v = given[param.name].orEmpty()
            if (v.isEmpty() && param.required) return null
            if (param.type == "int") {
                val n = v.toLongOrNull()
                if (v.isNotEmpty() && n == null) return null
                b = b.replace("\"{${param.name}}\"", n?.toString() ?: "\"\"")
                p = p.replace("{${param.name}}", n?.toString().orEmpty())
            } else {
                p = p.replace("{${param.name}}", inPath(v))
                b = b.replace("{${param.name}}", inString(v))
            }
        }
        return p to b
    }

    fun request(spec: SduiCommandSpec, item: String, given: Map<String, String> = emptyMap()): Request? {
        if (spec.path.isEmpty()) return null
        if (spec.params.isNotEmpty()) {
            val filled = fill(spec, spec.path, spec.body, given) ?: return null
            val itemSpec = spec.copy(path = filled.first, body = filled.second, params = emptyList())
            return if ("{item}" in itemSpec.path || "{item}" in itemSpec.body) request(itemSpec, item) else Request(itemSpec.method, itemSpec.path, itemSpec.body.takeIf { it.isNotEmpty() })
        }
        if (serverRevision >= SHOW_IDS_FROM) {
            if (item.isEmpty() || item.any { it.isISOControl() }) return null
            val inPath = java.net.URLEncoder.encode(item, "UTF-8").replace("+", "%20")
            val inString = item.replace("\\", "\\\\").replace("\"", "\\\"")
            return Request(spec.method, spec.path.replace("{item}", inPath), spec.body.takeIf { it.isNotEmpty() }?.replace("{item}", inString))
        }
        val show = showId(item)
        if (show != null) {
            return if (spec.op == "watchLater.add") Request(spec.method, spec.path, "{\"shows\":[$show]}") else null
        }
        if ("{item}" in spec.path && item.toLongOrNull() == null) return null
        return Request(spec.method, spec.path.replace("{item}", item), spec.body.takeIf { it.isNotEmpty() }?.replace("{item}", bodyItem(item)))
    }
}
