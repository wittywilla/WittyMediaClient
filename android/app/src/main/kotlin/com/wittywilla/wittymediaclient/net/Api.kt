package com.wittywilla.wittymediaclient.net

import com.wittywilla.wittymediaclient.data.SavedServer
import com.wittywilla.wittymediaclient.diag.ClientLog
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runInterruptible
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.SerializationException
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.net.InetAddress
import java.net.URLEncoder
import java.net.UnknownHostException
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLException

// twoFactor: the password was right, or a code was wrong, and the server wants its authenticator code.
class ApiError(val status: Int, message: String, val location: String = "", val twoFactor: Boolean = false) : Exception(message)

val json = Json {
    ignoreUnknownKeys = true
    coerceInputValues = true // a Go nil list arrives as null
    explicitNulls = false
}

private val JSON_TYPE = "application/json".toMediaType()
private const val API = "/api/v1" // the contract: docs/CLIENT-API.md
private const val QUICK_SECONDS = 5L
private const val QUICK_MAX_BYTES = 256L * 1024
private const val MAX_BYTES = 32L * 1024 * 1024
private const val LOOKUP_MS = 3000L
private const val SPEEDTEST_CUTOFF_NS = 1_500_000_000L
private const val SPEEDTEST_MIN_BYTES = 32L * 1024
private val shared = OkHttpClient() // connections and threads are reused across servers

private data class Answer(val status: Int, val text: String, val requestId: String, val location: String)

// One connection to one server. The token only ever goes to that server, in a
// header, so it stays out of URLs and logs. Redirects are never followed. Quick is
// for questions to an address not yet trusted: short waits and small answers.
class Api(val base: String, val token: String, private val quick: Boolean = false) {
    private val server = base.toHttpUrlOrNull()

    // Images use this too, and may still be drawing just after the app has left a server.
    val http: OkHttpClient = shared.newBuilder()
        .connectTimeout(8, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS) // the first playback request probes the file
        .callTimeout(if (quick) QUICK_SECONDS else 0, TimeUnit.SECONDS)
        .followRedirects(false)
        .followSslRedirects(false)
        .addInterceptor(Interceptor { chain ->
            val req = chain.request()
            val same = server != null && req.url.host == server.host && req.url.port == server.port && req.url.scheme == server.scheme
            chain.proceed(if (same && token.isNotEmpty()) req.newBuilder().header("Authorization", "Bearer $token").build() else req)
        })
        .build()

    private fun errorText(status: Int, text: String) =
        runCatching { json.parseToJsonElement(text).jsonObject["error"]?.jsonPrimitive?.content }.getOrNull()
            ?: "The server answered with an error ($status)."


    private suspend fun raw(method: String, path: String, body: String?): Answer = withContext(Dispatchers.IO) {
        val request = Request.Builder()
            .url("$base$API$path")
            .method(method, body?.toRequestBody(JSON_TYPE))
            .build()
        http.newCall(request).execute().use { res ->
            // Cut off at the limit, an answer that's too long can't be read as JSON either.
            Answer(res.code, res.peekBody(if (quick) QUICK_MAX_BYTES else MAX_BYTES).string(), res.header("X-Request-Id").orEmpty(), res.header("Location").orEmpty())
        }
    }

    // Only for a signed-in connection: an address being tried has its own words on
    // screen. A sign-in that has run out and a stream already gone are normal.
    private fun reportsFailure(method: String, status: Int) =
        !quick && token.isNotEmpty() && status != 401 && !(method == "DELETE" && status == 404)

    private suspend fun call(method: String, path: String, body: String? = null): String {
        val where = "$method ${path.substringBefore('?')}"
        val answer = try {
            raw(method, path, body)
        } catch (e: IOException) {
            if (reportsFailure(method, 0)) ClientLog.warn("network", "$where failed: ${e.javaClass.simpleName}")
            throw e
        }
        if (answer.status !in 200..299) {
            val message = errorText(answer.status, answer.text)
            if (reportsFailure(method, answer.status)) {
                val words = "$where answered ${answer.status}: $message"
                if (answer.status >= 500) ClientLog.error("request", words, request = answer.requestId)
                else ClientLog.warn("request", words, request = answer.requestId)
            }
            throw ApiError(answer.status, message, answer.location, twoFactor = asksForCode(answer.status, answer.text))
        }
        return answer.text
    }

    private suspend inline fun <reified T> get(path: String): T = json.decodeFromString(call("GET", path))

    // A plain list, which a Go nil sends as null.
    private suspend inline fun <reified T> getList(path: String): List<T> = json.decodeFromString<List<T>?>(call("GET", path)).orEmpty()

    suspend fun capabilities(): Capabilities = get("/capabilities")
    suspend fun status(): ServerStatus = get("/status")
    suspend fun profiles(): Profiles = get("/profiles")
    suspend fun home(): Home = get("/home")
    suspend fun item(id: Long): Item = get("/items/$id")
    suspend fun show(id: Long): ShowDetail = get("/shows/$id")
    suspend fun shows(library: Long, offset: Int, limit: Int): ShowPage = get("/shows?library=$library&offset=$offset&limit=$limit&sort=title")
    suspend fun items(library: Long, offset: Int, limit: Int): ItemPage =
        get("/items?library=$library&offset=$offset&limit=$limit&sort=title")

    private fun query(text: String) = URLEncoder.encode(text, "UTF-8")
    suspend fun searchItems(text: String, limit: Int): ItemPage = get("/items?search=${query(text)}&noEpisodes=1&limit=$limit")
    suspend fun searchShows(text: String, limit: Int): ShowPage = get("/shows?search=${query(text)}&limit=$limit")

    suspend fun libraries(): List<Library> = getList("/libraries")
    suspend fun albums(library: Long, sort: String, artist: String? = null): List<Album> =
        getList("/music/albums?library=$library&sort=$sort" + if (artist != null) "&artist=${query(artist)}" else "")
    suspend fun artists(library: Long): List<Artist> = getList("/music/artists?library=$library")
    // An empty album or artist means none or unknown: it is still asked for by name.
    suspend fun tracks(library: Long, album: String, artist: String): List<Item> =
        getList("/music/tracks?library=$library&album=${query(album)}&artist=${query(artist)}")
    suspend fun songs(library: Long, offset: Int, limit: Int): List<Item> =
        getList("/music/songs?library=$library&offset=$offset&limit=$limit&sort=title")

    suspend fun playback(id: Long, request: PlaybackRequest): Playback =
        json.decodeFromString(call("POST", "/items/$id/playback", json.encodeToString(request)))

    // What to watch after this: the website's Watch next card asks the same.
    suspend fun recommend(id: Long): Recommendation = get("/items/$id/recommend")
    suspend fun playerPrefs(): PlayerPrefs = get("/prefs")

    // The server's streaming mode for viewers away from home: standard or robust.
    suspend fun remoteStreaming(): String =
        runCatching { json.parseToJsonElement(call("GET", "/capabilities")).jsonObject["playback"]?.jsonObject?.get("remoteStreaming")?.jsonPrimitive?.content }
            .getOrNull() ?: "standard"

    // What this connection carries, as the website measures it: a megabyte from the server, timed from its
    // first bytes and cut off at 1.5 s. Null when less than 32 KB came, which is too little to say.
    suspend fun speedtestKbps(): Int? = withContext(Dispatchers.IO) {
        runCatching {
            val request = Request.Builder().url("$base$API/playback/speedtest?kb=1024").build()
            http.newCall(request).execute().use { res ->
                if (!res.isSuccessful) return@use null
                val body = res.body.byteStream()
                val buffer = ByteArray(16 * 1024)
                var first = 0L
                var total = 0L
                while (true) {
                    val n = body.read(buffer)
                    if (n < 0) break
                    val now = System.nanoTime()
                    if (first == 0L) first = now else total += n
                    if (now - first > SPEEDTEST_CUTOFF_NS) break
                }
                val seconds = (System.nanoTime() - first) / 1e9
                if (total < SPEEDTEST_MIN_BYTES || seconds <= 0) null else (total * 8 / 1000 / seconds).toInt()
            }
        }.getOrNull()
    }

    // Stops the conversion at once when the viewer leaves.
    suspend fun stopStream(streamId: String) {
        call("DELETE", "/hls/${query(streamId)}")
    }

    // An account with two-factor sign-in answers 401 with twoFactor first; the same again with the code signs in.
    suspend fun login(name: String, password: String, device: String, code: String = ""): LoginResult =
        json.decodeFromString(call("POST", "/login", json.encodeToString(Credentials(name, password, device, code))))


    suspend fun pairStart(device: String, platform: String): PairStart =
        json.decodeFromString(call("POST", "/pair/start", json.encodeToString(PairStartRequest(device, platform))))

    // Denied, expired and slow-down are normal answers here, not errors.
    suspend fun pairPoll(deviceSecret: String): PairPoll {
        val answer = raw("POST", "/pair/poll", json.encodeToString(PairPollRequest(deviceSecret)))
        if (answer.status in 200..299 || answer.status == 403 || answer.status == 410 || answer.status == 429) return json.decodeFromString(answer.text)
        throw ApiError(answer.status, errorText(answer.status, answer.text))
    }

    // Errors carry the server's own plain words: a wrong, expired or used code, or too many tries.
    suspend fun pairRedeem(code: String, device: String, platform: String): LoginResult =
        json.decodeFromString(call("POST", "/pair/redeem", json.encodeToString(PairRedeemRequest(code, device, platform))))

    suspend fun identity(nonce: String): IdentityAnswer =
        json.decodeFromString(call("POST", "/identity", json.encodeToString(IdentityRequest(nonce))))

    suspend fun saveProgress(id: Long, positionSec: Double, durationSec: Double) {
        call("POST", "/items/$id/progress", json.encodeToString(ProgressReport(positionSec, durationSec)))
    }

    // Music has no place to save, but what was played counts towards the server's yearly summary.
    suspend fun recordListen(id: Long, seconds: Double) {
        call("POST", "/items/$id/view", json.encodeToString(ViewReport(seconds)))
    }

    // What this device can do to play a game on someone's own PC. It starts nothing there.
    suspend fun rigPlay(gameId: Long, request: RigPlayRequest): RigPlay =
        json.decodeFromString(call("POST", "/rigs/games/$gameId/play", json.encodeToString(request)))

    suspend fun rigWake(rigId: Long): RigWake =
        json.decodeFromString(call("POST", "/rigs/$rigId/wake", "{}"))

    suspend fun couchStatus(): CouchStatus = get("/couch")
    suspend fun modulePages(): List<Pair<String, ModulePage>> = get<ModuleBundles>("/modules/web").bundles.flatMap { b -> b.pages.map { b.id to it } }
    suspend fun guide(hours: Int, limit: Int): Guide = get("/guide?hours=$hours&limit=$limit")
    suspend fun forYou(): ForYou = get("/me/recommended")
    suspend fun legalNotices(): LegalNotices = get("/legal/notices")
    // Music: a station from a song, this person's liked songs in a library, and liking one.
    suspend fun songRadio(id: Long): List<Item> = getList("/music/radio/$id")
    suspend fun likes(library: Long): List<Long> = getList("/music/likes?library=$library")
    suspend fun react(id: Long, value: Int) { call("PUT", "/items/$id/reaction", "{\"value\":$value}") }
    suspend fun shelves(library: Long): Shelves = get("/browse/shelves?library=$library")
    // The query is the website's: sort, desc, seed and the filters, already encoded.
    suspend fun browse(library: Long, query: String, offset: Int, limit: Int): BrowsePage = get("/browse?library=$library&$query&offset=$offset&limit=$limit")
    suspend fun facets(library: Long): Map<String, List<Facet>> = get("/browse/facets?library=$library")
    suspend fun scan(library: Long) { call("POST", "/libraries/$library/scan", "{}") }
    fun encode(text: String): String = query(text)
    suspend fun collections(): List<Collection> = getList("/collections")
    suspend fun holding(item: Long, show: Long): List<Long> = getList("/collections/holding?item=$item&show=$show")
    suspend fun addToCollection(id: Long, what: CollectionItems) { call("POST", "/collections/$id/items", json.encodeToString(what)) }
    suspend fun removeFromCollection(id: Long, what: CollectionItems) { call("DELETE", "/collections/$id/items", json.encodeToString(what)) }
    suspend fun watchLater(what: CollectionItems): WatchLater = json.decodeFromString(call("POST", "/collections/watch-later/items", json.encodeToString(what)))
    suspend fun newCollection(name: String): Collection = json.decodeFromString(call("POST", "/collections", json.encodeToString(NewCollection(name))))
    suspend fun randomItem(): Item? = get<ItemPage>("/items?sort=random&limit=1&noEpisodes=1&watchable=1").items.firstOrNull()

    // Home's choices in /me/ui: how it's arranged, and the newer version an administrator put off. Saving reads the
    // rest first and keeps it, as the website does.
    suspend fun homeChoices(): HomeChoices = readHomeChoices(call("GET", "/me/ui"))
    suspend fun saveHomeLayout(layout: HomeLayout) = setChoice("home", layout.toJson())
    suspend fun putOffUpdate(version: String) = setChoice("updateLater", JsonPrimitive(version))
    private suspend fun setChoice(key: String, value: JsonElement) {
        call("PUT", "/me/ui", withChoice(call("GET", "/me/ui"), key, value))
    }

    // A title's page, as the website's (see TitlePage.kt): an item or a show, and the rest of what its page shows,
    // from one answer.
    suspend fun itemPage(id: Long): Pair<Item, ItemFacts> {
        val text = call("GET", "/items/$id")
        return json.decodeFromString<Item>(text) to ItemFacts.read(text)
    }

    suspend fun showPage(id: Long): Pair<ShowDetail, ShowFacts> {
        val text = call("GET", "/shows/$id")
        return json.decodeFromString<ShowDetail>(text) to ShowFacts.read(text)
    }

    suspend fun attached(target: TitleTarget, id: Long): TitleAttached = get("/meta/${target.word}/$id/attached")
    suspend fun listings(target: TitleTarget, id: Long): TitleListings = get("/meta/${target.word}/$id/listings")

    // What the logo service has for some studios, networks or streaming services: up to 200 at a time.
    suspend fun lookUpLogos(names: List<Pair<String, String>>): List<LogoAnswer> =
        json.decodeFromString<LogoAnswers>(call("POST", "/logos/lookup", json.encodeToString(LogoLookup(names.take(200).map { LogoAsk(it.first, it.second) })))).logos

    // A show's episode layout for everyone: "cards", "list", or "" for the server's. Administrators only.
    suspend fun setShowView(id: Long, view: String) {
        call("PUT", "/shows/$id/view", json.encodeToString(ShowView(view)))
    }

    // What the server knows about a newer version of itself, for administrators.
    suspend fun updateStatus(): UpdateStatus = get("/update")

    // Themes: docs/APP-DESIGN.md, Themes. The list and each theme's tokens are public; the person's own look is theirs.
    suspend fun themes(): ThemeList = get("/themes")
    suspend fun themeTokens(id: String): ThemeTokens = get("/themes/${query(id)}/tokens.json")

    // /me/ui is the web's own settings, any JSON: only customTheme is read, and one that doesn't parse is none.
    suspend fun customTheme(): ThemeMakerInput? {
        val ui = json.parseToJsonElement(call("GET", "/me/ui")).jsonObject
        val made = ui["customTheme"] ?: return null
        return runCatching { json.decodeFromJsonElement(ThemeMakerInput.serializer(), made) }.getOrNull()
    }

    // You and settings.
    suspend fun updateProfile(id: Long, change: ProfileUpdate): User =
        json.decodeFromString(call("PUT", "/users/$id/profile", json.encodeToString(change)))

    suspend fun changePassword(id: Long, current: String, password: String) {
        call("PUT", "/users/$id/password", json.encodeToString(PasswordChange(password, current)))
    }

    suspend fun twoFactor(): TwoFactorStatus = get("/me/2fa")
    suspend fun twoFactorSetup(password: String): TwoFactorSetup =
        json.decodeFromString(call("POST", "/me/2fa/setup", json.encodeToString(PasswordOnly(password))))
    suspend fun twoFactorConfirm(code: String): RecoveryCodes =
        json.decodeFromString(call("POST", "/me/2fa/confirm", json.encodeToString(CodeOnly(code))))
    suspend fun twoFactorDisable(password: String, code: String) {
        call("POST", "/me/2fa/disable", json.encodeToString(PasswordAndCode(password, code)))
    }

    suspend fun sessions(): List<DeviceSession> = getList("/sessions")
    suspend fun endSession(id: String) {
        call("DELETE", "/sessions/${query(id)}")
    }
    suspend fun endOtherSessions() {
        call("DELETE", "/sessions")
    }

    // Signing in a TV from here: what's asking, then yes (as someone) or no. Or a code for the TV to type.
    suspend fun pairInfo(code: String): PairInfo =
        json.decodeFromString(call("POST", "/pair/info", json.encodeToString(CodeOnly(code))))
    suspend fun pairApprove(code: String, userId: Long) {
        call("POST", "/pair/approve", json.encodeToString(PairAnswer(code, userId)))
    }
    suspend fun pairDeny(code: String) {
        call("POST", "/pair/deny", json.encodeToString(PairAnswer(code)))
    }
    suspend fun pairInvite(userId: Long): PairInvite =
        json.decodeFromString(call("POST", "/pair/invite", json.encodeToString(UserIdOnly(userId))))

    suspend fun logout() {
        call("POST", "/logout", "{}")
    }

    // This app's own errors, for the server's log. The answer is all that comes back:
    // it skips `call`, so a report that fails can't become a report of its own.
    suspend fun sendClientLog(body: String): Int = raw("POST", "/logs/client", body).status

    fun posterUrl(it: Item) = "$base$API/items/${it.id}/poster?v=${it.updatedAt}"
    fun coverUrl(item: Long) = "$base$API/items/$item/poster"
    fun backdropUrl(it: Item) = "$base$API/items/${it.id}/backdrop?v=${it.updatedAt}"
    fun itemBackdropUrl(id: Long) = "$base$API/items/$id/backdrop"
    fun showPosterUrl(s: Show) = "$base$API/shows/${s.id}/art/poster?v=${s.updatedAt}"
    fun showBackdropUrl(s: Show) = "$base$API/shows/${s.id}/art/backdrop?v=${s.updatedAt}"
    fun seasonPosterUrl(s: Show, n: Int) = "$base$API/shows/${s.id}/art/season?n=$n&v=${s.updatedAt}"
    // A title's logo, drawn in place of its name where it has one.
    fun titleLogoUrl(target: TitleTarget, id: Long, version: Long) = "$base$API/meta/${target.word}/$id/art/logo?v=$version"
    // A studio's, network's or service's logo: white for a dark page, dark for a light one, or as it was drawn.
    fun logoImageUrl(logo: LogoAnswer, variant: String): String? = logo.id?.let { "$base$API/logos/$it/image?variant=${queryValue(variant)}&v=${logo.version}" }

    // Addresses in answers start with /api/: the server's address goes in front, nothing else
    // changes. A server's answer can't point the player, with what it carries, somewhere else.
    fun mediaUrl(path: String): String {
        val url = (base + path).toHttpUrlOrNull()
        if (!path.startsWith("/") || path.startsWith("//") || url == null || server == null || url.host != server.host || url.port != server.port || url.scheme != server.scheme) {
            throw ApiError(0, "The server sent an address that can't be used.")
        }
        return base + path
    }
}

// A refused sign-in that asks for the authenticator's code: {"error": "...", "twoFactor": true}.
fun asksForCode(status: Int, text: String): Boolean =
    status == 401 && runCatching { json.parseToJsonElement(text).jsonObject["twoFactor"]?.jsonPrimitive?.content == "true" }.getOrDefault(false)

// The server's own logo, at the version /status gave, or empty for the app's mark. It's public: the
// sign-in screens show it.
fun brandLogoUrl(base: String, version: String): String =
    if (version.isEmpty() || base.isEmpty()) "" else "$base$API/branding/logo?v=" + URLEncoder.encode(version, "UTF-8")

// Asks an address whether it is a WittyMediaServer this app can use. With appVersion left
// empty, no version of this app is compared.
sealed interface Probe {
    data class Found(val status: ServerStatus, val url: String) : Probe
    data class Failed(val reason: String) : Probe
}

// An http address that says it has moved to https on the same host, or null. Nothing else is
// followed: a redirect is never how a token or a question reaches another machine.
fun httpsUpgrade(url: String, location: String): String? {
    val from = url.toHttpUrlOrNull() ?: return null
    val to = location.toHttpUrlOrNull() ?: return null
    if (from.isHttps || !to.isHttps || from.host != to.host) return null
    return if (to.port == 443) "https://${to.host}" else "https://${to.host}:${to.port}"
}

suspend fun probeServer(url: String, appVersion: String = "", followUpgrade: Boolean = true): Probe {
    val api = Api(url, "", quick = true)
    return try {
        val caps = api.capabilities()
        when {
            caps.server != "WittyMediaServer" -> Probe.Failed("not-server")
            else -> Compat.problem(caps, appVersion)?.let { Probe.Failed(it) } ?: Probe.Found(api.status(), url)
        }
    } catch (_: SSLException) {
        Probe.Failed("certificate")
    } catch (_: IOException) {
        Probe.Failed("unreachable")
    } catch (e: ApiError) {
        val upgrade = if (followUpgrade && e.status in 300..399) httpsUpgrade(url, e.location) else null
        if (upgrade != null) return probeServer(upgrade, appVersion, followUpgrade = false)
        // No /capabilities: an older server, if it says it is one at all.
        val old = e.status == 404 && runCatching { api.status().name == "WittyMediaServer" }.getOrDefault(false)
        Probe.Failed(if (old) "server-old" else "not-server")
    } catch (_: SerializationException) {
        Probe.Failed("not-server")
    }
}

// Plain http to a name goes only where that name really is on the local network. No answer in
// time lets it through, as the connection itself then fails or the name is local anyway.
suspend fun plainHttpStaysLocal(url: String): Boolean = withContext(Dispatchers.IO) {
    val parsed = url.toHttpUrlOrNull() ?: return@withContext false
    if (parsed.isHttps || Address.isLiteral(parsed.host)) return@withContext true
    val found = withTimeoutOrNull(LOOKUP_MS) {
        try {
            runInterruptible { InetAddress.getAllByName(parsed.host).mapNotNull { it.hostAddress } }
        } catch (_: UnknownHostException) {
            null
        }
    }
    found == null || Address.staysLocal(found)
}

// Has the server at this address proved it holds its key, and is that a key we
// remember? A new nonce every time, and no token goes with the question.
suspend fun identify(url: String, saved: List<SavedServer>): ServerProof {
    if (!plainHttpStaysLocal(url)) return ServerProof(IdentityState.Bad)
    val nonce = Identity.newNonce()
    return try {
        val answer = Api(url, "", quick = true).identity(nonce)
        val state = withContext(Dispatchers.Default) { Identity.judge(answer, nonce, url, saved) }
        if (state == IdentityState.Bad) ServerProof(state)
        else ServerProof(state, answer.serverId, answer.publicKey, Identity.fingerprint(answer.publicKey))
    } catch (_: IOException) {
        ServerProof(IdentityState.Unreachable)
    } catch (e: ApiError) {
        ServerProof(if (e.status == 404) Identity.unanswered(url, saved) else IdentityState.Bad)
    } catch (_: SerializationException) {
        ServerProof(IdentityState.Bad)
    }
}

// Words for whatever went wrong, for a screen to show. It never shows an exception's own text,
// which may be a stack of technical words or an address. Cancelling isn't a failure: it goes on up.
fun problemWords(e: Exception, lost: String): String = when (e) {
    is CancellationException -> throw e
    is ApiError -> e.message.orEmpty().ifEmpty { lost }
    is SerializationException -> "The server sent an answer this app can't read. Updating both may help."
    else -> lost
}
