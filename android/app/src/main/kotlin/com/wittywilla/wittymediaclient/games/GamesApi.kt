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

// The games routes this app uses: exactly the ones the website's player uses (the server's docs/GAMING-API.md),
// under /api/v1. It rides on the app's own connection, so the sign-in goes in a header to that server only, the
// WebSocket's included, and never in an address. Nothing here sends or receives a game's file.

private const val API = "/api/v1"
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
                if (res.code >= 500) ClientLog.error("games", "$method ${path.substringBefore('?')} answered ${res.code}: $words")
                throw ApiError(res.code, words)
            }
            text
        }
    }

    private suspend inline fun <reified T> get(path: String): T = json.decodeFromString(call("GET", path))

    fun q(text: String): String = URLEncoder.encode(text, "UTF-8")

    suspend fun home(library: Long): GamesHome = get("/games/home?library=$library")
    suspend fun consoles(library: Long? = null): List<GameConsole> =
        json.decodeFromString<List<GameConsole>?>(call("GET", "/games/consoles" + (library?.let { "?library=$it" } ?: ""))).orEmpty()

    // `sort` is popular, title, newest, oldest, rating or added, as the website's.
    suspend fun games(library: Long, console: String = "", sort: String = "popular", search: String = "", offset: Int = 0, limit: Int = 60): GameItemPage {
        val descending = sort == "rating" || sort == "added"
        return get("/items?library=$library&kind=game&sort=${q(sort)}&desc=${if (descending) 1 else 0}&console=${q(console)}&search=${q(search)}&offset=$offset&limit=$limit")
    }

    suspend fun item(id: Long): GameItem = get("/items/$id")
    suspend fun check(id: Long): GameCheck = get("/games/$id/check")
    suspend fun details(id: Long): GameDetails = get("/games/$id/metadata")
    suspend fun personal(id: Long): GamePersonal = get("/games/$id/meta")
    suspend fun versions(id: Long): GameVersions = get("/games/$id/versions")

    suspend fun setFavourite(id: Long, on: Boolean): GamePersonal =
        json.decodeFromString(call("PUT", "/games/$id/meta", buildJsonObject { put("favourite", on) }.toString()))

    suspend fun saves(id: Long): List<GameSave> = json.decodeFromString<List<GameSave>?>(call("GET", "/games/$id/saves")).orEmpty()

    suspend fun deleteSave(id: Long, slot: Int) {
        call("DELETE", "/games/$id/saves/$slot")
    }

    suspend fun settings(item: Long): GameSettings = get("/games/settings?item=$item")

    suspend fun controls(console: String, device: String, game: Long = 0): GameControls =
        get("/consoles/${q(console)}/controls?device=${q(device)}" + if (game > 0) "&game=$game" else "")

    // A touch layout belongs to the device that saved it. `null` goes back to the console's own.
    suspend fun saveTouchLayout(console: String, device: String, orientation: String, layout: Map<String, Placement>?) {
        val body = buildJsonObject {
            put("kind", "touch")
            put("key", device)
            put("orientation", orientation)
            put("data", layout?.let { json.encodeToJsonElement(LAYOUT, it) } ?: JsonNull)
        }
        call("PUT", "/consoles/${q(console)}/controls", body.toString())
    }

    // `controller` is vendor:product in lowercase hex, or id:<name> for a pad without numbers.
    suspend fun resolvePad(controller: String, console: String, game: Long): ResolvedPad =
        get("/game-profiles/resolve?kind=gamepad&controller=${q(controller)}&console=${q(console)}&game=$game")

    // For a game in an archive: about once a second until it's ready, then play.
    suspend fun prepare(id: Long): GamePrepare = json.decodeFromString(call("POST", "/games/$id/prepare", "{}"))

    // Starts a game. Starting another saves and ends whatever this account was playing, anywhere.
    suspend fun play(id: Long, resume: Boolean, safeMode: Boolean): GameSession {
        val body = buildJsonObject {
            put("resume", resume)
            put("client", "native")
            if (safeMode) put("safeMode", true)
        }
        return json.decodeFromString(call("POST", "/games/$id/play", body.toString(), slow))
    }

    suspend fun session(sid: String): GameSession = get("/play/${q(sid)}")

    // Answers the server's own answer, which for `speed` is the speed it was held to.
    suspend fun action(sid: String, action: GameAction): String = call("POST", "/play/${q(sid)}/action", json.encodeToString(action))

    // Saves and stops. The answer comes once everything is written, battery save and all.
    suspend fun stop(sid: String) {
        call("DELETE", "/play/${q(sid)}", client = slow)
    }

    fun posterUrl(game: GameItem, width: Int = 480): String = "${api.base}$API/items/${game.id}/poster?v=${game.updatedAt}&w=${width.coerceIn(64, 800)}"
    fun backdropUrl(game: GameItem): String = "${api.base}$API/items/${game.id}/backdrop?v=${game.updatedAt}"
    fun saveThumbUrl(game: Long, slot: Int, version: Long): String = "${api.base}$API/games/$game/saves/$slot/thumb?v=$version"

    // Version 2's stream address for a session (docs/GAMING-STREAM.md): a POST for WebRTC, a WebSocket otherwise.
    fun streamEndpoint(sid: String) = StreamEndpoint(api.base + API + "/play/${q(sid)}/stream")

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

    // A game's WebSocket, at a path under /api/v1 (see GameTransport.kt). OkHttp turns ws into http for the upgrade, so
    // the app's connection adds the sign-in header to it as to any request to this server, and never to an address.
    fun openWebSocket(path: String, listener: WebSocketListener): WebSocket {
        val request = Request.Builder().url(api.base + API + path).build()
        return socketClient.newWebSocket(request, listener)
    }
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
        status == 503 -> "The server is running as many games as it can just now. Try again in a little while."
        status == 404 -> "This game isn't on the server any more."
        else -> "The server answered with an error ($status)."
    }
}
