// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
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
    // `layer`: shown over the current screen (a sheet, an overlay), and Back closes it.
    data class Open(val target: SduiTarget, val layer: Boolean = false) : SduiEffect
    data class Play(val item: String, val resume: Boolean) : SduiEffect
    data class External(val url: String) : SduiEffect
    data object Back : SduiEffect
    data class SelectTab(val tab: String) : SduiEffect

    // A Dock's control: sort, filter, view or jump, for the Grid it names.
    data class OpenControl(val control: String, val target: String) : SduiEffect
    data object Refresh : SduiEffect
    // One of the catalogue's commands that changes something on the server; the page is asked for again after.
    // `confirm` is a question to ask first (the command's label is the confirming button), `params` the action's values.
    data class Command(val spec: SduiCommandSpec, val item: String, val params: JsonObject = JsonObject(emptyMap()), val confirm: String = "") : SduiEffect
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
        "navigate" -> if (action.to.isEmpty()) SduiEffect.Nothing else SduiEffect.Open(resolve(action.to), layer = action.asLayer)
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
            else -> commands[action.op]?.takeIf { it.path.isNotEmpty() && SduiCommands.request(it, action.item, action.params) != null }
                ?.let { SduiEffect.Command(it, action.item, action.params, action.confirm) } ?: SduiEffect.Nothing
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
            // Catalogue revision 8: the pages the server serves for every app, opened about something.
            page("/studio/{name}", "studio", "name" to "{name}"),
            page("/network/{name}", "network", "name" to "{name}"),
            page("/category/{name}", "category", "name" to "{name}"),
            page("/versions/{item}", "versions", "item" to "{item}"),
            page("/save-to/{item}", "save-to", "item" to "{item}"),
            page("/devices", "devices"),
            page("/creators", "creators"),
            page("/creator/{item}", "creator", "item" to "{item}"),
            page("/comments/{item}", "comments", "item" to "{item}"),
            page("/markers/{item}", "markers", "item" to "{item}"),
            page("/canvas/{item}", "canvas", "item" to "{item}"),
            page("/smart-list", "smart-list"),
            page("/year", "year"),
            page("/activity", "activity"),
            page("/notifications", "notifications"),
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
            SduiCommandSpec("watchLater.add", "POST", "/api/v1/collections/watch-later/items", "{\"items\":[\"{item}\"]}"),
            SduiCommandSpec("watched.set", "POST", "/api/v1/items/{item}/progress", "{\"watched\":true}"),
            SduiCommandSpec("watched.clear", "DELETE", "/api/v1/items/{item}/progress", ""),
            SduiCommandSpec("selectTab", "GET", "", ""),
            SduiCommandSpec("refresh", "GET", "", ""),
        )
    }
}

// A command as a request. The catalogue's templates quote {item} in bodies, and its routes take a show's "show-<n>".
object SduiCommands {
    class Request(val method: String, val path: String, val body: String?)

    // A command's request, from its catalogue entry: {item} and each of the entry's params by name go into the path and the
    // body where the template has them (docs/SDUI.md, Action). An int parameter replaces its string and quotes with the
    // number, a bool with true or false, an ints one (a list of numbers) with a JSON array; a string is JSON-escaped inside
    // its quotes and URL-escaped in the path. A parameter that wasn't given is an empty string.
    fun request(spec: SduiCommandSpec, item: String, params: JsonObject = JsonObject(emptyMap())): Request? {
        if (spec.path.isEmpty()) return null
        val base = baseRequest(spec, item) ?: return null
        var path = base.path
        var body = base.body
        for (param in spec.params) {
            val value = params[param.name]
            if (param.required && (value == null || (value is JsonPrimitive && value.isString && value.content.isEmpty()))) return null
            val text = (value as? JsonPrimitive)?.content.orEmpty()
            path = path.replace("{" + param.name + "}", java.net.URLEncoder.encode(text, "UTF-8").replace("+", "%20"))
            body = body?.let { template ->
                val quoted = "\"{" + param.name + "}\""
                when (param.type) {
                    "int" -> {
                        val number = text.toDoubleOrNull()?.takeIf { it == Math.floor(it) }?.toLong() ?: return null
                        template.replace(quoted, number.toString())
                    }
                    "bool" -> template.replace(quoted, if (text == "true") "true" else if (text == "false") "false" else return null)
                    "ints" -> template.replace(quoted, ints(value) ?: return null)
                    "object" -> template.replace(quoted, (value as? JsonObject ?: JsonObject(emptyMap())).toString())
                    else -> template.replace("{" + param.name + "}", text.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n"))
                }
            }
        }
        return Request(base.method, path, body)
    }

    // A list of numbers as a JSON array: from an array, or from numbers written with commas.
    private fun ints(value: kotlinx.serialization.json.JsonElement?): String? {
        val list = when (value) {
            is JsonArray -> value.map { (it as? JsonPrimitive)?.content?.toLongOrNull() ?: return null }
            is JsonPrimitive -> value.content.split(',').map { it.trim() }.filter { it.isNotEmpty() }.map { it.toLongOrNull() ?: return null }
            else -> emptyList()
        }
        return list.joinToString(",", "[", "]")
    }

    private fun baseRequest(spec: SduiCommandSpec, item: String): Request? {
        if (item.isEmpty() && ("{item}" in spec.path || "{item}" in spec.body)) return null
        if (item.any { it.isISOControl() }) return null
        val inPath = java.net.URLEncoder.encode(item, "UTF-8").replace("+", "%20")
        val inString = item.replace("\\", "\\\\").replace("\"", "\\\"")
        return Request(spec.method, spec.path.replace("{item}", inPath), spec.body.takeIf { it.isNotEmpty() }?.replace("{item}", inString))
    }
}
