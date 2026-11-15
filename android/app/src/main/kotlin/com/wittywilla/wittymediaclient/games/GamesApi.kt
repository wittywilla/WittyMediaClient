// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.games

import com.wittywilla.wittymediaclient.diag.ClientLog
import com.wittywilla.wittymediaclient.net.Api
import com.wittywilla.wittymediaclient.net.ApiError
import com.wittywilla.wittymediaclient.net.json
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

// The games routes this app uses: exactly the ones the website's player uses (the server's docs/GAMING-API.md).
// The game API is WittyPlay's (module API 5), under /api/v1/modules/wittyplay; a game's items, metadata and
// versions stay the server's, under /api/v1. It rides on the app's own connection, so the sign-in goes in a header to that server only, the
// WebSocket's included, and never in an address. Nothing here sends or receives a game's file.

private const val API = "/api/v1"
// WittyPlay answers its own API under the module prefix (module API 5); a server without it answers 424.
private const val WITTYPLAY = "/modules/wittyplay"
private const val GAMES = "$WITTYPLAY/games"
private const val PLAY = "$WITTYPLAY/play"
private val JSON_TYPE = "application/json".toMediaType()
private const val MAX_BYTES = 8L * 1024 * 1024
private val LAYOUT = MapSerializer(String.serializer(), Placement.serializer())

class GamesApi(val api: Api) {
    // Starting a big game can take a while on a small server; the app's own client waits a minute.
    private val slow: OkHttpClient by lazy { api.http.newBuilder().readTimeout(5, TimeUnit.MINUTES).build() }

    // A game's socket stays open as long as the game; a ping finds a dead one within seconds.
    private val socketClient: OkHttpClient by lazy {
        api.http.newBuilder().readTimeout(0, TimeUnit.MILLISECONDS).pingInterval(5, TimeUnit.SECONDS).build()
    }

    private suspend fun call(method: String, path: String, body: String? = null, client: OkHttpClient = api.http): String = withContext(Dispatchers.IO) {
        val request = Request.Builder()
            .url(api.base + API + path)
            .method(method, body?.toRequestBody(JSON_TYPE) ?: if (method == "POST" || method == "PUT") "{}".toRequestBody(JSON_TYPE) else null)
            .build()
        client.newCall(request).execute().use { res ->
            val text = res.peekBody(MAX_BYTES).string()
            if (res.code !in 200..299) {
                val words = problemFrom(res.code, text)
                if (res.code >= 500) ClientLog.error("game", "$method ${path.substringBefore('?')} answered ${res.code}: $words")
                throw ApiError(res.code, words)
            }
            text
        }
    }

    private suspend inline fun <reified T> get(path: String): T = json.decodeFromString(call("GET", path))

    fun q(text: String): String = URLEncoder.encode(text, "UTF-8")

    suspend fun home(library: Long): GamesHome = get("$GAMES/home?library=$library")
    suspend fun consoles(library: Long? = null): List<GameConsole> =
        json.decodeFromString<List<GameConsole>?>(call("GET", "$GAMES/consoles" + (library?.let { "?library=$it" } ?: ""))).orEmpty()

    // `sort` is title, newest, oldest, rating or added.
    suspend fun games(library: Long, console: String = "", sort: String = "rating", search: String = "", offset: Int = 0, limit: Int = 60): GameItemPage {
        val descending = sort == "rating" || sort == "added"
        return get("/items?library=$library&kind=game&sort=${q(sort)}&desc=${if (descending) 1 else 0}&console=${q(console)}&search=${q(search)}&offset=$offset&limit=$limit")
    }

    suspend fun item(id: Long): GameItem = get("/items/$id")
    suspend fun check(id: Long): GameCheck = get("$GAMES/$id/check")
    suspend fun details(id: Long): GameDetails = get("/games/$id/metadata")
    suspend fun personal(id: Long): GamePersonal = get("$GAMES/$id/meta")
    suspend fun versions(id: Long): GameVersions = get("/games/$id/versions")

    suspend fun setFavourite(id: Long, on: Boolean): GamePersonal =
        json.decodeFromString(call("PUT", "$GAMES/$id/meta", buildJsonObject { put("favourite", on) }.toString()))

    suspend fun saves(id: Long): List<GameSave> = json.decodeFromString<List<GameSave>?>(call("GET", "$GAMES/$id/saves")).orEmpty()

    suspend fun deleteSave(id: Long, slot: Int) {
        call("DELETE", "$GAMES/$id/saves/$slot")
    }

    suspend fun settings(item: Long): GameSettings = get("$GAMES/settings?item=$item")

    suspend fun controls(console: String, device: String, game: Long = 0): GameControls =
        get("$WITTYPLAY/consoles/${q(console)}/controls?device=${q(device)}" + if (game > 0) "&game=$game" else "")

    // A touch layout belongs to the device that saved it. `null` goes back to the console's own.
    suspend fun saveTouchLayout(console: String, device: String, orientation: String, layout: Map<String, Placement>?) {
        val body = buildJsonObject {
            put("kind", "touch")
            put("key", device)
            put("orientation", orientation)
            put("data", layout?.let { json.encodeToJsonElement(LAYOUT, it) } ?: JsonNull)
        }
        call("PUT", "$WITTYPLAY/consoles/${q(console)}/controls", body.toString())
    }

    // `controller` is vendor:product in lowercase hex, or id:<name> for a pad without numbers.
    suspend fun resolvePad(controller: String, console: String, game: Long): ResolvedPad =
        get("$WITTYPLAY/game-profiles/resolve?kind=gamepad&controller=${q(controller)}&console=${q(console)}&game=$game")

    // For a game in an archive: about once a second until it's ready, then play.
    suspend fun prepare(id: Long): GamePrepare = json.decodeFromString(call("POST", "$GAMES/$id/prepare", "{}"))

    // Starts a game. Starting another saves and ends whatever this account was playing, anywhere.
    suspend fun play(id: Long, resume: Boolean, safeMode: Boolean): GameSession {
        val body = buildJsonObject {
            put("resume", resume)
            put("client", "native")
            if (safeMode) put("safeMode", true)
        }
        return json.decodeFromString(call("POST", "$GAMES/$id/play", body.toString(), slow))
    }

    // A seat (seat = true) asks as the host's player does, for what to stream.
    suspend fun session(sid: String, seat: Boolean = false): GameSession = get("$PLAY/${q(sid)}" + if (seat) "?client=native" else "")

    // Accepts a friend's invite to their game: the answer is the game's session, played as a seat.
    suspend fun acceptInvite(invite: String): String =
        (json.parseToJsonElement(call("POST", "$WITTYPLAY/games/online/invites/${q(invite)}/accept", "{}")) as? JsonObject)
            ?.get("sid")?.let { (it as? JsonPrimitive)?.content }.orEmpty().ifEmpty { throw ApiError(502, "The invite didn't give a seat.") }

    // Administrators: the game looked up again from the start, in the background; what people chose stays.
    suspend fun refreshDetails(id: Long) {
        call("POST", "$GAMES/$id/metadata/refresh", "{}")
    }

    // Gives up this account's seat in someone else's game; their game goes on.
    suspend fun leaveSeat(sid: String, me: Long) {
        call("DELETE", "$PLAY/${q(sid)}/seats/$me")
    }

    // Answers the server's own answer, which for `speed` is the speed it was held to.
    suspend fun action(sid: String, action: GameAction): String = call("POST", "$PLAY/${q(sid)}/action", json.encodeToString(action))

    // Saves and stops. The answer comes once everything is written, battery save and all.
    suspend fun stop(sid: String) {
        call("DELETE", "$PLAY/${q(sid)}", client = slow)
    }

    fun posterUrl(game: GameItem, width: Int = 480): String = "${api.base}$API/items/${game.id}/poster?v=${game.updatedAt}&w=${width.coerceIn(64, 800)}"
    fun backdropUrl(game: GameItem): String = "${api.base}$API/items/${game.id}/backdrop?v=${game.updatedAt}"
    fun saveThumbUrl(game: Long, slot: Int, version: Long): String = "${api.base}$API$GAMES/$game/saves/$slot/thumb?v=$version"

    // Version 2's stream address for a session (docs/GAMING-STREAM.md): a POST for WebRTC, a WebSocket otherwise.
    fun streamEndpoint(sid: String) = StreamEndpoint(api.base + API + "$PLAY/${q(sid)}/stream")

    // WebRTC's offer and answer, at an address the endpoint gives.
    suspend fun postStream(url: String, body: String): String = withContext(Dispatchers.IO) {
        val request = Request.Builder().url(url).post(body.toRequestBody(JSON_TYPE)).build()
        slow.newCall(request).execute().use { res ->
            val text = res.peekBody(MAX_BYTES).string()
            if (res.code !in 200..299) throw ApiError(res.code, problemFrom(res.code, text))
            text
        }
    }

    fun openWebSocketUrl(url: String, listener: WebSocketListener): WebSocket =
        socketClient.newWebSocket(Request.Builder().url(url).build(), listener)
}

// The server's own words for what went wrong, and plain ones where it gives none (docs/GAMING-API.md, starting a game).
fun problemFrom(status: Int, text: String): String {
    val body = runCatching { json.parseToJsonElement(text) as? JsonObject }.getOrNull()
    val error = (body?.get("error") as? JsonPrimitive)?.content.orEmpty()
    fun flag(name: String) = (body?.get(name) as? JsonPrimitive)?.booleanOrNull == true
    return when {
        error.isNotEmpty() -> error
        status == 409 && flag("needCore") -> "This server has no core for this console yet. Ask whoever runs it to install one."
        status == 409 && flag("needBios") -> "This game needs a BIOS file the server doesn't have yet."
        status == 409 && flag("rig") -> "This game plays on a PC, not on the server."
        status == 422 -> "This file can't be played."
        status == 424 -> "WittyPlay isn't installed on this server. Ask whoever runs it to add it."
        status == 429 -> "The server is busy with games just now. Try again in a little while."
        status == 503 -> "The server is running as many games as it can just now. Try again in a little while."
        status == 404 -> "This game isn't on the server any more."
        else -> "The server answered with an error ($status)."
    }
}
