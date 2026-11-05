package com.wittywilla.wittymediaclient.net

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put

// WittyTV's routes: live channels, the guide, recordings, reminders, logos and the account's look. The same calls
// Apple TV makes (WittyKit's WittyClient.swift), on this app's own connection.

private suspend inline fun <reified T> Api.read(path: String): T = json.decodeFromString(call("GET", path))

// A plain list, which a Go nil sends as null.
private suspend inline fun <reified T> Api.readList(path: String): List<T> = json.decodeFromString<List<T>?>(call("GET", path)).orEmpty()

// A channel to watch. `streamToken` puts a short-lived pass in the stream's address, as the page's player has it.
suspend fun Api.tune(key: String, viewer: String): Tuned =
    read("/tv/${GuideRules.pathPart(key)}/tune?streamToken=1&viewer=${GuideRules.pathPart(viewer)}")

// This player has left the channel, so the server can stop a stream nobody watches.
suspend fun Api.leaveChannel(key: String, viewer: String) {
    call("POST", "/tv/${GuideRules.pathPart(key)}/leave?viewer=${GuideRules.pathPart(viewer)}", "{}")
}

// A page of the guide's channels with their schedule: see GuideRules.query.
suspend fun Api.guidePage(query: String): Guide = read(query)

// Every channel's number and name, for going through them without the schedule.
suspend fun Api.lineup(): Guide = read("/guide?list=1&limit=20000")

// A day of one channel's schedule.
suspend fun Api.guideDay(key: String, from: Long): List<GuideProgramme> =
    read<Guide>("/guide?from=$from&hours=24&limit=1&channel=${GuideRules.queryValue(key)}").channels.firstOrNull()?.programmes.orEmpty()

// What's coming up that matches some words.
suspend fun Api.searchGuide(words: String, days: Int = 7): List<GuideHit> {
    val trimmed = words.trim().take(200)
    if (trimmed.length < 2) return emptyList()
    return readList("/guide/search?q=${GuideRules.queryValue(trimmed)}&days=$days&limit=60")
}

suspend fun Api.setFavourite(key: String, on: Boolean) {
    call(if (on) "PUT" else "DELETE", "/tv/favourites/${GuideRules.pathPart(key)}", if (on) "{}" else null)
}

suspend fun Api.recordings(): List<Recording> = readList("/recordings")
suspend fun Api.recordingRules(): List<RecordingRule> = readList("/recording-rules")

@Serializable
private data class RecordAsk(val channel: String, val title: String, val sub: String?, val start: Long, val stop: Long)

@Serializable
private data class SeriesAsk(val channel: String, val title: String)

@Serializable
private data class ReminderAsk(val channel: String, val title: String, val sub: String?, val start: Long, val end: Long)

// Records one programme of a tuner channel.
suspend fun Api.record(channel: String, title: String, sub: String?, start: Long, stop: Long) {
    call("POST", "/recordings", json.encodeToString(RecordAsk.serializer(), RecordAsk(channel, title, sub, start, stop)))
}

// Cancels one to come, or takes a finished one off the list. Only an administrator can delete its file too.
suspend fun Api.removeRecording(id: Long, deleteFile: Boolean = false) {
    call("DELETE", "/recordings/$id" + if (deleteFile) "?deleteFile=1" else "")
}

// Records every airing of a title on a channel.
suspend fun Api.recordSeries(channel: String, title: String) {
    call("POST", "/recording-rules", json.encodeToString(SeriesAsk.serializer(), SeriesAsk(channel, title)))
}

suspend fun Api.removeRecordingRule(id: Long) {
    call("DELETE", "/recording-rules/$id")
}

suspend fun Api.reminders(): List<TvReminder> = readList("/tv/reminders")

suspend fun Api.addReminder(channel: String, title: String, sub: String?, start: Long, end: Long): TvReminder =
    json.decodeFromString(call("POST", "/tv/reminders", json.encodeToString(ReminderAsk.serializer(), ReminderAsk(channel, title, sub, start, end))))

suspend fun Api.removeReminder(id: Long) {
    call("DELETE", "/tv/reminders/$id")
}

@Serializable
private data class LogoAnswer(val logos: List<LogoInfo>? = null)

// What the logo service has for some networks or studios, in one request.
suspend fun Api.lookupLogos(brands: List<GuideBrand>): List<LogoInfo> {
    val body = buildJsonObject {
        put("logos", buildJsonArray { brands.take(200).forEach { add(buildJsonObject { put("kind", it.kind); put("name", it.name) }) } })
    }
    return json.decodeFromString<LogoAnswer>(call("POST", "/logos/lookup", body.toString())).logos.orEmpty()
}

// A logo's picture, white for a dark background, dark for a light one, or as it is for one on a plate.
fun Api.logoImageUrl(logo: LogoInfo, variant: String): String? {
    val id = logo.id ?: return null
    return runCatching { mediaUrl("/api/logos/$id/image?variant=${GuideRules.queryValue(variant)}&v=${logo.version ?: 0}") }.getOrNull()
}

@Serializable
private data class Notice(val text: String = "")

@Serializable
private data class Notices(val notices: Map<String, Notice>? = null)

// The short legal notices by kind (`tv`, `logos`, `logosBrief` and so on): the same words everywhere.
suspend fun Api.legalNotices(): Map<String, String> = read<Notices>("/legal/notices").notices.orEmpty().mapValues { it.value.text }

@Serializable
private data class SuggestingTheme(val other: Map<String, String>? = null)

// What the server's theme suggests for WittyTV, from its tokens: the page reads the same from its CSS.
suspend fun Api.themeSuggestsTv(themeId: String): String? =
    read<SuggestingTheme>("/themes/${GuideRules.pathPart(themeId)}/tokens.json").other?.get("tv-theme")

// GET /me/ui as it is: every interface choice the account has, for reading one and keeping the rest.
suspend fun Api.rawUi(): JsonObject = runCatching { json.parseToJsonElement(call("GET", "/me/ui")).jsonObject }.getOrDefault(JsonObject(emptyMap()))

// Changes some of this account's WittyTV choices, and keeps everything else in /me/ui as it was, as the page does: the
// server keeps an account's interface choices whole. A null takes a choice away.
suspend fun Api.saveTvLook(change: Map<String, JsonElement?>) {
    val ui = json.parseToJsonElement(call("GET", "/me/ui")) as? JsonObject ?: JsonObject(emptyMap())
    val look = (ui["tvLook"] as? JsonObject)?.toMutableMap() ?: mutableMapOf()
    for ((key, value) in change) {
        if (value == null || value is JsonNull) look.remove(key) else look[key] = value
    }
    // Beside the theme, what it comes to in the two looks an older app knows about.
    val theme = (look["theme"] as? JsonPrimitive)?.takeIf { it.isString }?.content
    val named = TvTheme.byId(theme)
    if (theme != null && named != null) {
        val shapeId = ((look["custom"] as? JsonObject)?.get("shape") as? JsonPrimitive)?.content
        val shape = if (theme == "custom") TvShape.of(shapeId) ?: TvShape.Modern else named.shape
        val (layout, colours) = TvLook.legacyOf(theme, shape)
        look["layout"] = JsonPrimitive(layout)
        look["colours"] = JsonPrimitive(colours)
    }
    val whole = ui.toMutableMap()
    whole["tvLook"] = JsonObject(look)
    call("PUT", "/me/ui", JsonObject(whole).toString())
}

// The server's error words, or a plain fallback: what Apple TV says too.
fun problemText(e: Throwable, fallback: String): String = (e as? ApiError)?.message?.takeIf { it.isNotEmpty() } ?: fallback
