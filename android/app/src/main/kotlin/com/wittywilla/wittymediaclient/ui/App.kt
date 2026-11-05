package com.wittywilla.wittymediaclient.ui

import android.graphics.Color
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.BackHandler
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.core.graphics.ColorUtils
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.wittywilla.wittymediaclient.WittyApp
import com.wittywilla.wittymediaclient.data.LogoCache
import com.wittywilla.wittymediaclient.data.SavedServer
import com.wittywilla.wittymediaclient.diag.ClientLog
import com.wittywilla.wittymediaclient.net.Api
import com.wittywilla.wittymediaclient.net.ApiError
import com.wittywilla.wittymediaclient.net.Identity
import com.wittywilla.wittymediaclient.net.IdentityState
import com.wittywilla.wittymediaclient.net.NextStep
import com.wittywilla.wittymediaclient.net.SendStep
import com.wittywilla.wittymediaclient.net.ServerProof
import com.wittywilla.wittymediaclient.net.ServerStatus
import com.wittywilla.wittymediaclient.net.User
import androidx.compose.runtime.mutableStateMapOf
import com.wittywilla.wittymediaclient.net.json
import com.wittywilla.wittymediaclient.net.ThemeTranslator
import com.wittywilla.wittymediaclient.net.ThemeTokens
import com.wittywilla.wittymediaclient.net.ThemeMakerInput
import com.wittywilla.wittymediaclient.net.ThemeList
import com.wittywilla.wittymediaclient.net.AppTheme
import com.wittywilla.wittymediaclient.net.brandLogoUrl
import com.wittywilla.wittymediaclient.net.GUIDE_PATH
import com.wittywilla.wittymediaclient.net.findServerById
import com.wittywilla.wittymediaclient.net.hasOwnScreen
import com.wittywilla.wittymediaclient.net.identify
import com.wittywilla.wittymediaclient.net.isListening
import com.wittywilla.wittymediaclient.net.isTrack
import com.wittywilla.wittymediaclient.net.keepsPlace
import com.wittywilla.wittymediaclient.net.pagePath
import com.wittywilla.wittymediaclient.net.problemWords
import com.wittywilla.wittymediaclient.player.PlayerScreen
import com.wittywilla.wittymediaclient.player.Start
import com.wittywilla.wittymediaclient.player.placeOn
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.serialization.SerializationException
import java.io.IOException

enum class SignInWay { Usual, Password, ShownCode }

sealed interface Route {
    val key: String
    data object Starting : Route { override val key = "starting" }
    data class Connect(val message: String = "") : Route { override val key = "connect" }
    data class Code(val server: SavedServer) : Route { override val key = "code" }
    data class Mismatch(val server: SavedServer) : Route { override val key = "mismatch" }
    data class SignIn(val way: SignInWay = SignInWay.Usual) : Route { override val key = "signin-$way" }
    data object Home : Route { override val key = "home" }
    data object Search : Route { override val key = "search" }
    data object Profile : Route { override val key = "profile" }
    data object Notices : Route { override val key = "notices" }
    data object Logs : Route { override val key = "logs" }
    data class Library(val library: com.wittywilla.wittymediaclient.net.Library) : Route { override val key = "library-${library.id}" }
    data class Show(val id: Long) : Route { override val key = "show-$id" }
    data class Item(val id: Long) : Route { override val key = "item-$id" }
    data class Player(val id: Long, val startOver: Boolean) : Route { override val key = "player-$id" }
    data class Web(val path: String) : Route { override val key = "web-$path" }
    // The server's own page; with a title, it has a native bar with Back above it, as You's rows do.
    data class Page(val path: String, val title: String = "") : Route { override val key = "page-$path" }
    // One of You's own screens: names, password, two-step, devices, signing in a TV, theme.
    data class You(val screen: YouNative) : Route { override val key = "you-$screen" }
    // A page anyone may read, such as the help on a forgotten password, which opens before signing in.
    data class Help(val path: String) : Route { override val key = "help-$path" }
    // What a TV doesn't open itself: a QR card for a phone, as on Apple TV.
    data class OnPhone(val title: String, val path: String) : Route { override val key = "on-phone-$path" }
    data class Album(val library: Long, val album: String, val artist: String) : Route { override val key = "album-$library-$artist-$album" }
    data class Artist(val library: Long, val name: String) : Route { override val key = "artist-$library-$name" }
    data object NowPlaying : Route { override val key = "now-playing" }

    // The app's own screens leave room for the mini player. A film, a server's page and signing in don't have it.
    val hasMiniPlayer: Boolean
        get() = when (this) {
            Home, Search, Profile, Notices, Logs, is Library, is Show, is Item, is Album, is Artist, is You -> true
            else -> false
        }
}

// How long a saved server's ID is looked for when its address stops answering.
private const val FIND_AGAIN_MS = 6000L
private const val REMEMBERED_SCREENS = 24

// The app's state and its screen stack. Back pops one screen, and only leaves
// the app from the top level.
class Nav(val app: WittyApp, private val s: Map<String, String>) {
    val stack = mutableStateListOf<Route>(Route.Starting)
    val current: Route get() = stack.last()
    var themeId by mutableStateOf("default")

    // Whether this server has a guide to offer.
    var hasGuide by mutableStateOf(false)

    // A remote's Guide button, from anywhere that's signed in.
    fun openGuide() {
        val onPage = current as? Route.Page
        if (hasGuide && app.api.token.isNotEmpty() && onPage?.path != GUIDE_PATH) push(Route.Page(GUIDE_PATH))
    }

    // The server the sign-in screens talk to. Its key waits here for a token to be
    // kept with, unless it was already pinned.
    var server: SavedServer? = null
        private set

    // A notice for after signing in, such as the sign-in not being kept on this device.
    var notice by mutableStateOf("")

    // The server's own name and logo for the sign-in screens, once it has been chosen. Empty for the app's own.
    var brandName by mutableStateOf("")
        private set
    var brandLogo by mutableStateOf("")
        private set

    // Who is signed in, for the avatar on the You tab.
    var me by mutableStateOf<User?>(null)

    // The website's menus: the library strip and the Menu drawer. Loaded once for each sign-in.
    var menu by mutableStateOf<List<MenuEntry>>(emptyList())
        private set
    var serverVersion by mutableStateOf("")
        private set
    private var menuFor = ""

    suspend fun loadMenu() {
        val api = app.api
        if (api.token.isEmpty() || menuFor == api.token) return
        menuFor = api.token
        val libraries = runCatching { api.libraries() }.getOrDefault(emptyList())
        val list = libraries.filter { it.inMainMenus }.map { MenuEntry("lib:" + it.id, it.name, WebIcons.forLibrary(it.type), Route.Library(it)) }.toMutableList()
        if (libraries.isNotEmpty()) list += MenuEntry("collections", "Collections", WebIcons.Library, Route.Page("/collections", "Collections"))
        if (runCatching { api.couchStatus().allowed }.getOrDefault(false)) list += MenuEntry("couch", "Game PCs", WebIcons.Gamepad, Route.Page("/couch", "Game PCs"))
        runCatching { api.modulePages() }.getOrDefault(emptyList()).filter { it.second.where == "main" }.forEach { (module, page) ->
            list += MenuEntry("m:$module:${page.id}", page.title, if (page.icon == "chart") WebIcons.Chart else WebIcons.Plug, Route.Page("/m/$module/${page.id}", page.title))
        }
        menu = list
        serverVersion = runCatching { api.status().version }.getOrDefault("")
    }

    // A place in the menus opens as a page of its own, with nothing to go back to: Home is below it.
    fun openMenu(entry: MenuEntry) {
        reset(Route.Home)
        if (entry.route != Route.Home) push(entry.route)
    }

    // The video playing on a phone or tablet, full screen or in the mini player dock, as the website's /play.
    var video by mutableStateOf<com.wittywilla.wittymediaclient.player.VideoSession?>(null)
        private set

    // The full player for this video: the one already playing when it's the same, otherwise a new one.
    fun attachVideo(id: Long, startSec: Double?): com.wittywilla.wittymediaclient.player.VideoSession {
        video?.let { if (it.id == id && startSec == null) return it }
        video?.close()
        return com.wittywilla.wittymediaclient.player.VideoSession(this, id, startSec).also { video = it }
    }

    // Back and the mini player button: go back, keep playing in the dock. With nothing to go back to, the item's page.
    fun minimizeVideo() {
        val playing = video ?: return
        playing.mini = true
        if (current is Route.Player) {
            if (stack.size > 1) pop() else replace(Route.Item(playing.id))
        }
    }

    fun expandVideo() {
        val playing = video ?: return
        playing.mini = false
        if (current !is Route.Player) push(Route.Player(playing.id, false))
    }

    // Stop: the session ends, the place saved and the conversion stopped.
    fun closeVideo() {
        video?.close()
        video = null
        if (current is Route.Player) { if (stack.size > 1) pop() else reset(Route.Home) }
    }

    fun playVideoInstead(id: Long) {
        video?.close()
        video = null
        if (current is Route.Player) playInstead(id) else push(Route.Player(id, false))
    }

    // This device's theme for the server: "" for the server's own, "auto", or a theme's id.
    var themeChoice by mutableStateOf("")
        private set

    fun chooseTheme(choice: String) {
        themeChoice = choice
        server?.let { app.store.chooseTheme(it.url, choice) }
        wantTheme(choice.ifEmpty { themeId })
    }

    // The server's themes (docs/APP-DESIGN.md, Themes): its list, each one read and translated as it's wanted,
    // and the person's own look. The built-in ones in shared/data stand in until then.
    var themeList by mutableStateOf<ThemeList?>(null)
        private set
    val themes = mutableStateMapOf<String, AppTheme>()
    var customTheme by mutableStateOf<ThemeMakerInput?>(null)
        private set

    // Reads the list, then the themes in use. Quiet on failure: the built-ins and what was kept stand in.
    fun loadThemes(signedIn: Boolean) {
        val base = server?.url ?: return
        val api = app.api
        app.scope.launch {
            runCatching { api.themes() }.getOrNull()?.let { if (server?.url == base) themeList = it }
            wantTheme(themeId)
            if (themeChoice.isNotEmpty() && themeChoice != AUTO_THEME) wantTheme(themeChoice)
            if (signedIn) customTheme = runCatching { api.customTheme() }.getOrNull()
        }
    }

    // One theme's tokens, from what was kept when its modTime hasn't changed, else from the server.
    fun wantTheme(id: String) {
        if (id.isEmpty() || id == AUTO_THEME || id == ThemeTranslator.CUSTOM_THEME) return
        val base = server?.url ?: return
        val summary = themeList?.themes?.firstOrNull { it.id == id }
        val modTime = summary?.modTime ?: 0
        app.store.themeTokens(base, id, modTime)?.let { kept ->
            runCatching { json.decodeFromString<ThemeTokens>(kept) }.getOrNull()?.let {
                themes[id] = ThemeTranslator.translate(it, summary?.preview)
                return
            }
        }
        val api = app.api
        app.scope.launch {
            val tokens = runCatching { api.themeTokens(id) }.getOrNull() ?: return@launch
            if (server?.url != base) return@launch
            app.store.keepThemeTokens(base, id, modTime, json.encodeToString(ThemeTokens.serializer(), tokens))
            themes[id] = ThemeTranslator.translate(tokens, summary?.preview)
        }
    }

    private fun forgetThemes() {
        themeList = null
        themes.clear()
        customTheme = null
    }

    private fun showBrand(base: String, status: ServerStatus) {
        brandName = status.brandName
        brandLogo = brandLogoUrl(base, status.brandLogo)
    }

    // A server whose identity has been checked: keep its name and logo with it, the picture on the device.
    private fun keepBrand(opened: SavedServer, status: ServerStatus): SavedServer {
        val named = opened.copy(name = status.brandName.ifEmpty { opened.name.ifEmpty { "WittyMediaServer" } }, brandLogo = status.brandLogo)
        if (status.brandLogo.isNotEmpty()) app.scope.launch { LogoCache.keep(app, named.url, status.brandLogo) }
        return named
    }

    private fun forgetBrand() {
        brandName = ""
        brandLogo = ""
    }

    // What each screen last showed, in memory only. Coming back draws it straight away and asks
    // the server again underneath, so a dropped network shows what was there, not a blank screen.
    private val shown = object : LinkedHashMap<String, Any>(REMEMBERED_SCREENS, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Any>?) = size > REMEMBERED_SCREENS
    }
    private val focusMemory = HashMap<String, FocusMemory>()
    private val libraryTypes = HashMap<Long, String>()

    @Suppress("UNCHECKED_CAST")
    fun <T : Any> remembered(key: String): T? = shown[key] as? T

    fun remember(key: String, value: Any) {
        shown[key] = value
    }

    fun focusFor(key: String) = focusMemory.getOrPut(key) { FocusMemory() }

    private fun forgetScreens() {
        shown.clear()
        focusMemory.clear()
        libraryTypes.clear()
        app.listening.forget()
        app.forgetImages()
    }

    fun push(r: Route) { stack.add(r) }

    // This app's own screens for what it has them for, and the server's page for all the rest.
    fun open(library: com.wittywilla.wittymediaclient.net.Library) = push(if (library.hasOwnScreen) Route.Library(library) else Route.Page(library.pagePath()))
    fun open(item: com.wittywilla.wittymediaclient.net.Item) = push(
        when {
            item.isTrack -> Route.Album(item.libraryId, item.album, item.albumArtist.ifEmpty { item.artist })
            item.hasOwnScreen -> Route.Item(item.id)
            else -> Route.Page(item.pagePath())
        },
    )

    // Which kind of library, for what the lists of its tracks don't say. Asked for once.
    suspend fun libraryType(id: Long): String {
        libraryTypes[id]?.let { return it }
        runCatching { app.api.libraries() }.getOrDefault(emptyList()).forEach { libraryTypes[it.id] = it.type }
        return libraryTypes[id].orEmpty()
    }

    // A queue starts. A TV goes to the player, as there's little else to look at from across a room. A phone stays
    // where it is, with the mini player showing.
    fun startListening(tracks: List<com.wittywilla.wittymediaclient.net.Item>, start: Start, books: Boolean) {
        app.listening.play(tracks, start, books)
        // AppRoot opens it as soon as the queue is there.
        if (app.isTv) app.listening.wantsScreen = true
    }

    // Play on a track shown on its own, on Home: its album or book, from that track.
    fun playTrack(track: com.wittywilla.wittymediaclient.net.Item) {
        app.scope.launch {
            try {
                val books = keepsPlace(libraryType(track.libraryId))
                val tracks = app.api.tracks(track.libraryId, track.album, track.albumArtist.ifEmpty { track.artist }).distinctBy { it.id }
                val index = tracks.indexOfFirst { it.id == track.id }.coerceAtLeast(0)
                if (tracks.isNotEmpty()) startListening(tracks, Start(index, placeOn(tracks[index], books)), books)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (!handleExpired(e)) notice = problemWords(e, s["errLost"].orEmpty())
            }
        }
    }

    fun openNowPlaying() {
        if (current != Route.NowPlaying) push(Route.NowPlaying)
    }

    fun closeNowPlaying() {
        if (current == Route.NowPlaying) pop()
    }

    fun replace(r: Route) { stack[stack.lastIndex] = r }
    fun reset(r: Route) { stack.clear(); stack.add(r) }
    fun pop() { if (stack.size > 1) stack.removeAt(stack.lastIndex) }

    // The next episode takes this one's place, so Back leads to its page and not the one just finished.
    fun playInstead(id: Long) {
        val below = stack.lastIndex - 1
        if (below >= 0 && stack[below] is Route.Item) stack[below] = Route.Item(id)
        replace(Route.Player(id, false))
    }

    // Back from the middle of the app goes up a level, and from a tab goes to Home.
    val backStaysInApp: Boolean get() = stack.size > 1 || current == Route.Search || current == Route.Profile

    fun back() {
        if (stack.size > 1) pop() else if (backStaysInApp) reset(Route.Home)
    }

    // The warning, with the safe way out of it underneath.
    private fun warn(about: SavedServer) { reset(Route.Connect()); push(Route.Mismatch(about)) }

    // Only for a server whose identity has just been checked.
    private fun openServer(opening: SavedServer, token: String = "") {
        server = opening
        themeChoice = app.store.themeChoice(opening.url)
        app.store.server = opening.url
        app.api = Api(opening.url, token)
        if (token.isNotEmpty()) ClientLog.kick()
    }

    // On to signing in, for a server that has been checked.
    fun signInTo(opening: SavedServer, way: SignInWay = SignInWay.Usual) {
        app.store.forgetToken()
        forgetScreens()
        openServer(opening)
        reset(Route.SignIn(way))
    }

    // Opens a server with a token that was kept with its key.
    private suspend fun openWithToken(opening: SavedServer): String? = try {
        app.store.remember(opening)
        openServer(opening, app.store.token)
        val status = app.api.status()
        themeId = status.theme
        showBrand(opening.url, status)
        keepBrand(opening, status).let {
            server = it
            app.store.remember(it)
        }
        loadThemes(status.user != null)
        me = status.user
        reset(if (status.user != null) Route.Home else Route.SignIn())
        null
    } catch (_: IOException) {
        s["errLost"].orEmpty()
    } catch (e: ApiError) {
        e.message.orEmpty()
    } catch (_: SerializationException) {
        s["errNotServer"].orEmpty()
    }

    // The sign-in carries the key it was made for, so this asks about that key, not the list's.
    private fun tokenFits(proof: ServerProof): Boolean {
        val kept = app.store.signIn ?: return false
        return Identity.fits(kept.pin, proof)
    }

    // What the last run was using, if it still is who it was. Its token goes
    // nowhere until then.
    suspend fun startUp() {
        val url = app.store.server
        if (url.isEmpty()) { reset(Route.Connect()); return }
        var saved = app.store.find(url) ?: SavedServer(url, "WittyMediaServer")
        var proof = identify(url, listOf(saved))
        if (proof.state == IdentityState.Unreachable && saved.serverId.isNotEmpty()) {
            val found = findServerById(app, saved.serverId, FIND_AGAIN_MS)
            if (found != null) {
                saved = saved.copy(url = found.url)
                proof = identify(found.url, listOf(saved))
            }
        }
        val checked = proof.savedAs(saved.url, saved.name)
        when (Identity.stepAtStart(proof.state, tokenFits(proof))) {
            NextStep.Warn -> warn(checked)
            NextStep.Refuse -> reset(Route.Connect(s["identityBad"].orEmpty()))
            NextStep.Lost -> reset(Route.Connect(s["errLost"].orEmpty()))
            NextStep.Open -> openWithToken(checked)?.let { reset(Route.Connect(it)) }
            else -> {
                openServer(checked)
                try {
                    val status = app.api.status()
                    themeId = status.theme
                    showBrand(checked.url, status)
                    server = keepBrand(checked, status)
                    loadThemes(false)
                    reset(Route.SignIn())
                } catch (_: Exception) {
                    reset(Route.Connect(s["errLost"].orEmpty()))
                }
            }
        }
    }

    // Coming back to an app left running counts as starting it. Nothing answering is
    // left to the screens, as the network is often still waking up.
    suspend fun recheck() {
        val using = server ?: return
        if (app.api.token.isEmpty()) return
        val proof = identify(using.url, listOf(using))
        if (proof.state != IdentityState.Different && proof.state != IdentityState.Bad) return
        server = null
        app.api = Api("", "")
        forgetScreens()
        if (proof.state == IdentityState.Bad) reset(Route.Connect(s["identityBad"].orEmpty()))
        else warn(proof.savedAs(using.url, using.name))
    }

    // Someone chose this server, and it says it's a WittyMediaServer. Its identity
    // decides what comes next. Answers words to show if that's nowhere.
    suspend fun arrive(url: String, status: ServerStatus): String? {
        val proof = identify(url, app.store.recent)
        val checked = proof.savedAs(url, status.brandName.ifEmpty { status.name }).copy(brandLogo = status.brandLogo)
        val sameServerAsToken = app.store.server == url || app.store.find(app.store.server)?.publicKey == proof.publicKey
        val step = Identity.nextStep(proof.state, sameServerAsToken && tokenFits(proof))
        if (step != NextStep.Refuse && step != NextStep.Lost) {
            themeId = status.theme
            showBrand(url, status)
        }
        return when (step) {
            NextStep.Warn -> { push(Route.Mismatch(checked)); null }
            NextStep.Refuse -> s["identityBad"].orEmpty()
            NextStep.Lost -> s["errUnreachable"].orEmpty()
            NextStep.AskCode -> { push(Route.Code(keepBrand(checked, status))); null }
            NextStep.SignIn -> { signInTo(keepBrand(checked, status)); loadThemes(false); null }
            NextStep.Open -> openWithToken(checked)
        }
    }

    // "This is my server, trust it". The key pinned is the one the warning showed, or
    // it asks again, and the old sign-in isn't kept: docs/CLIENT-API.md says sign in again.
    suspend fun trust(shown: SavedServer): String? {
        val proof = identify(shown.url, emptyList())
        return when {
            proof.state == IdentityState.Unreachable -> s["errUnreachable"].orEmpty()
            proof.state != IdentityState.New -> s["identityBad"].orEmpty()
            proof.publicKey != shown.publicKey -> { replace(Route.Mismatch(proof.savedAs(shown.url, shown.name))); null }
            else -> {
                app.store.forgetToken()
                app.store.remember(shown)
                forgetScreens()
                reset(Route.Connect())
                push(Route.Code(shown))
                null
            }
        }
    }

    // Right before a code or a password leaves this device: has the server just proved it's the
    // one the person was shown? Answers words to show, or null to go ahead.
    suspend fun clearToSend(to: SavedServer): String? {
        val proof = identify(to.url, listOf(to))
        return when (Identity.beforeSending(to.publicKey, proof)) {
            SendStep.Send -> null
            SendStep.Unreachable -> s["errUnreachable"]
            SendStep.Refuse -> s["identityBad"]
            SendStep.Changed -> {
                warn(proof.savedAs(to.url, to.name))
                s["identityChanged"].orEmpty()
            }
        }
    }

    // A code typed on this device. Answers words to show on failure.
    suspend fun redeem(to: SavedServer, code: String): String? {
        clearToSend(to)?.let { return it }
        return try {
            val result = Api(to.url, "", quick = true).pairRedeem(code, app.deviceName, app.platformName)
            if (result.token.isEmpty()) return s["errInvalid"]
            openServer(to)
            signedIn(result.token)
            null
        } catch (e: ApiError) {
            e.message
        } catch (_: IOException) {
            s["errUnreachable"]
        } catch (_: SerializationException) {
            s["errInvalid"]
        }
    }

    fun signedIn(token: String, user: User? = null) {
        val kept = server ?: SavedServer(app.api.base, "WittyMediaServer")
        me = user
        if (!app.store.signedIn(kept, token)) notice = s["notKept"].orEmpty()
        app.api = Api(kept.url, token)
        loadThemes(true)
        ClientLog.kick()
        forgetScreens()
        reset(Route.Home)
    }

    private fun forgetSignIn() {
        me = null
        app.store.forgetToken()
        app.api = Api(app.api.base, "")
        forgetScreens()
        reset(Route.SignIn())
    }

    // Ends the session on the server too, so no valid sign-in is left behind.
    private fun endSession() {
        val old = app.api
        video?.close()
        video = null
        // The last place on a track goes first, while the sign-in is still good.
        val placeSent = app.listening.forget()
        if (old.token.isNotEmpty()) app.scope.launch {
            placeSent.join()
            runCatching { old.logout() }
        }
    }

    fun signOut() {
        endSession()
        forgetSignIn()
    }

    fun changeServer() {
        endSession()
        server = null
        me = null
        themeChoice = ""
        themeId = "default"
        forgetThemes()
        forgetBrand()
        app.store.server = ""
        app.store.forgetToken()
        app.api = Api("", "")
        forgetScreens()
        reset(Route.Connect())
    }

    // A sign-in the server no longer accepts means signing in again.
    fun handleExpired(e: Throwable): Boolean {
        if (e is ApiError && e.status == 401) { forgetSignIn(); return true }
        return false
    }
}

// Transparent over the page. A three-button bar keeps a veil of the page's own colour, so its
// buttons can still be seen with a poster passing underneath.
fun showSystemBars(activity: ComponentActivity, light: Boolean, background: Int) {
    val veil = ColorUtils.setAlphaComponent(background, NAV_VEIL_ALPHA)
    activity.enableEdgeToEdge(
        statusBarStyle = if (light) SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT) else SystemBarStyle.dark(Color.TRANSPARENT),
        navigationBarStyle = if (light) SystemBarStyle.light(veil, veil) else SystemBarStyle.dark(veil),
    )
}

@Composable
fun AppRoot(app: WittyApp) {
    val context = LocalContext.current
    val themes = remember { Assets.themes(context) }
    val strings = remember { Assets.strings(context) }
    val nav = remember { Nav(app, strings) }
    val saveable = rememberSaveableStateHolder()
    val scope = rememberCoroutineScope()
    val width = LocalConfiguration.current.screenWidthDp
    val metrics = if (app.isTv) TvMetrics else if (width >= TABLET_WIDTH_DP) TabletMetrics else PhoneMetrics
    val reduceMotion = remember { runCatching { Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }.getOrDefault(false) }

    // The person's choice on this device, else the server's. Automatic follows the device's light or dark; Made by you
    // is the account's own look, made as the website makes it. A theme not read yet stands in as the built-in one.
    val dark = isSystemInDarkTheme()
    val wanted = when (nav.themeChoice) {
        "" -> nav.themeId
        AUTO_THEME -> if (dark) themes.defaultTheme else LIGHT_THEME
        else -> nav.themeChoice
    }
    val custom = nav.customTheme
    val theme = remember(wanted, nav.themes[wanted], custom) {
        when {
            wanted == ThemeTranslator.CUSTOM_THEME && custom != null -> ThemeTranslator.translateMade(custom)
            nav.themes[wanted] != null -> nav.themes.getValue(wanted)
            else -> bundledTheme(themes, if (wanted == ThemeTranslator.CUSTOM_THEME) nav.themeId else wanted)
        }
    }
    LaunchedEffect(wanted) { nav.wantTheme(wanted) }
    // The system bars follow this app's theme, not the device's: dark icons on a dark page can't be read.
    DisposableEffect(theme.isLight, theme.background) {
        (context as? ComponentActivity)?.let { showSystemBars(it, theme.isLight, theme.background.argb or (0xFF shl 24)) }
        onDispose { }
    }

    WittyTheme(theme, metrics, reduceMotion, strings) {
        LaunchedEffect(Unit) { nav.startUp() }
        DisposableEffect(Unit) {
            app.onGuideKey = nav::openGuide
            onDispose { app.onGuideKey = null }
        }
        LifecycleEventEffect(Lifecycle.Event.ON_START) {
            scope.launch { nav.recheck() }
            app.listening.appeared()
        }
        LifecycleEventEffect(Lifecycle.Event.ON_STOP) {
            app.listening.disappeared()
            // A film stops when the app is left, with its place kept.
            nav.video?.backgrounded()
        }
        BackHandler(enabled = nav.backStaysInApp) { nav.back() }
        val route = nav.current
        // Once the app's own screens are up, whichever way it started.
        val hasQueue = app.listening.now != null
        LaunchedEffect(app.listening.wantsScreen, route.hasMiniPlayer, hasQueue) {
            if (app.listening.wantsScreen && route.hasMiniPlayer && hasQueue) {
                app.listening.wantsScreen = false
                nav.openNowPlaying()
            }
        }
        val showing = @Composable {
            saveable.SaveableStateProvider(route.key) {
                CompositionLocalProvider(LocalFocusMemory provides nav.focusFor(route.key)) {
                    when (route) {
                        Route.Starting -> Screen { Loading() }
                        is Route.Connect -> ConnectScreen(nav, strings, route.message)
                        is Route.Code -> CodeScreen(nav, strings, route.server)
                        is Route.Mismatch -> MismatchScreen(nav, strings, route.server)
                        is Route.SignIn -> SignInScreen(nav, strings, route.way)
                        Route.Home -> Shell(nav) { HomeScreen(nav, strings) }
                        Route.Search -> Shell(nav) { if (LocalMetrics.current.tv) SearchScreen(nav, strings) else PhoneSearch(nav, strings) }
                        Route.Profile -> Shell(nav) { YouScreen(nav, strings) }
                        Route.Notices -> NoticesScreen(nav)
                        Route.Logs -> LogsScreen(nav)
                        is Route.Library -> PageShell(nav) { if (route.library.isListening) ListeningLibraryScreen(nav, strings, route.library) else if (LocalMetrics.current.tv) LibraryScreen(nav, strings, route.library) else PhoneLibrary(nav, route.library) }
                        is Route.Show -> PageShell(nav) { if (LocalMetrics.current.tv) ShowScreen(nav, strings, route.id) else PhoneShow(nav, strings, route.id) }
                        is Route.Item -> PageShell(nav) { if (LocalMetrics.current.tv) ItemScreen(nav, strings, route.id) else PhoneItem(nav, strings, route.id) }
                        is Route.Album -> PageShell(nav) { AlbumScreen(nav, strings, route) }
                        is Route.Artist -> PageShell(nav) { ArtistScreen(nav, strings, route.library, route.name) }
                        Route.NowPlaying -> if (LocalMetrics.current.tv) NowPlayingScreen(nav) else WebNowPlaying(nav)
                        is Route.Player -> if (LocalMetrics.current.tv) PlayerScreen(nav, route.id, route.startOver) else VideoPlayerScreen(nav, route)
                        is Route.Web -> ServerPageScreen(nav, route, route.path, keptToGames = true)
                        is Route.Page -> ServerPageScreen(nav, route, route.path, keptToGames = false, title = route.title)
                        is Route.You -> YouSettingScreen(nav, strings, route.screen)
                        is Route.Help -> ServerPageScreen(nav, route, route.path, keptToGames = false, public = true)
                        is Route.OnPhone -> OnPhoneScreen(nav, strings, route.title, route.path)
                    }
                }
            }
        }
        // A phone's tabs float at the bottom, and the shell puts the mini player above them. Elsewhere it has its
        // own strip along the bottom, which also takes care of the system's bar.
        // On a phone or tablet every page in the website's shell has the shell's own mini bar.
        val tabs = !metrics.tv && (route == Route.Home || route == Route.Search || route == Route.Profile || route is Route.Library ||
            route is Route.Show || route is Route.Item || route is Route.Album || route is Route.Artist)
        if (hasQueue && route.hasMiniPlayer && !tabs) {
            Column(Modifier.fillMaxSize()) {
                Box(Modifier.weight(1f).consumeWindowInsets(WindowInsets.navigationBars)) { showing() }
                // Its colour goes on under the system's bar, so the bar has a page behind it.
                Box(Modifier.background(MaterialTheme.colorScheme.surface).navigationBarsPadding()) { MiniPlayer(nav) }
            }
        } else {
            showing()
        }
    }
}

private const val TABLET_WIDTH_DP = 600
const val AUTO_THEME = "auto"
private const val LIGHT_THEME = "light"
private const val NAV_VEIL_ALPHA = 0xB3
