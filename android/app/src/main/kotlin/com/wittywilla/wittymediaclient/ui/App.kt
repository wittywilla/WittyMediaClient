package com.wittywilla.wittymediaclient.ui

import android.graphics.Color
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.BackHandler
import androidx.activity.enableEdgeToEdge
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
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.core.graphics.ColorUtils
import androidx.core.graphics.toColorInt
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.wittywilla.wittymediaclient.WittyApp
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
import com.wittywilla.wittymediaclient.net.findServerById
import com.wittywilla.wittymediaclient.net.identify
import com.wittywilla.wittymediaclient.player.PlayerScreen
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

    // The server the sign-in screens talk to. Its key waits here for a token to be
    // kept with, unless it was already pinned.
    var server: SavedServer? = null
        private set

    // A notice for after signing in, such as the sign-in not being kept on this device.
    var notice by mutableStateOf("")

    // What each screen last showed, in memory only. Coming back draws it straight away and asks
    // the server again underneath, so a dropped network shows what was there, not a blank screen.
    private val shown = object : LinkedHashMap<String, Any>(REMEMBERED_SCREENS, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Any>?) = size > REMEMBERED_SCREENS
    }
    private val focusMemory = HashMap<String, FocusMemory>()

    @Suppress("UNCHECKED_CAST")
    fun <T : Any> remembered(key: String): T? = shown[key] as? T

    fun remember(key: String, value: Any) {
        shown[key] = value
    }

    fun focusFor(key: String) = focusMemory.getOrPut(key) { FocusMemory() }

    private fun forgetScreens() {
        shown.clear()
        focusMemory.clear()
        app.forgetImages()
    }

    fun push(r: Route) { stack.add(r) }
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
                    themeId = app.api.status().theme
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
        val checked = proof.savedAs(url, status.brandName.ifEmpty { status.name })
        val sameServerAsToken = app.store.server == url || app.store.find(app.store.server)?.publicKey == proof.publicKey
        val step = Identity.nextStep(proof.state, sameServerAsToken && tokenFits(proof))
        if (step != NextStep.Refuse && step != NextStep.Lost) themeId = status.theme
        return when (step) {
            NextStep.Warn -> { push(Route.Mismatch(checked)); null }
            NextStep.Refuse -> s["identityBad"].orEmpty()
            NextStep.Lost -> s["errUnreachable"].orEmpty()
            NextStep.AskCode -> { push(Route.Code(checked)); null }
            NextStep.SignIn -> { signInTo(checked); null }
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

    fun signedIn(token: String) {
        val kept = server ?: SavedServer(app.api.base, "WittyMediaServer")
        if (!app.store.signedIn(kept, token)) notice = s["notKept"].orEmpty()
        app.api = Api(kept.url, token)
        ClientLog.kick()
        forgetScreens()
        reset(Route.Home)
    }

    private fun forgetSignIn() {
        app.store.forgetToken()
        app.api = Api(app.api.base, "")
        forgetScreens()
        reset(Route.SignIn())
    }

    // Ends the session on the server too, so no valid sign-in is left behind.
    private fun endSession() {
        val old = app.api
        if (old.token.isNotEmpty()) app.scope.launch { runCatching { old.logout() } }
    }

    fun signOut() {
        endSession()
        forgetSignIn()
    }

    fun changeServer() {
        endSession()
        server = null
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

    val theme = pickTheme(themes, nav.themeId)
    // The system bars follow this app's theme, not the device's: dark icons on a dark page can't be read.
    DisposableEffect(theme.scheme, theme.colours.background) {
        (context as? ComponentActivity)?.let { showSystemBars(it, theme.scheme == "light", theme.colours.background.toColorInt()) }
        onDispose { }
    }

    WittyTheme(theme, metrics, reduceMotion) {
        LaunchedEffect(Unit) { nav.startUp() }
        LifecycleEventEffect(Lifecycle.Event.ON_START) { scope.launch { nav.recheck() } }
        BackHandler(enabled = nav.backStaysInApp) { nav.back() }
        val route = nav.current
        saveable.SaveableStateProvider(route.key) {
            CompositionLocalProvider(LocalFocusMemory provides nav.focusFor(route.key)) {
                when (route) {
                    Route.Starting -> Screen { Loading() }
                    is Route.Connect -> ConnectScreen(nav, strings, route.message)
                    is Route.Code -> CodeScreen(nav, strings, route.server)
                    is Route.Mismatch -> MismatchScreen(nav, strings, route.server)
                    is Route.SignIn -> SignInScreen(nav, strings, route.way)
                    Route.Home -> Shell(nav) { HomeScreen(nav, strings) }
                    Route.Search -> Shell(nav) { SearchScreen(nav, strings) }
                    Route.Profile -> Shell(nav) { ProfileScreen(nav, strings) }
                    Route.Notices -> NoticesScreen(nav)
                    Route.Logs -> LogsScreen(nav)
                    is Route.Library -> LibraryScreen(nav, strings, route.library)
                    is Route.Show -> ShowScreen(nav, strings, route.id)
                    is Route.Item -> ItemScreen(nav, strings, route.id)
                    is Route.Player -> PlayerScreen(nav, route.id, route.startOver)
                    is Route.Web -> WebPlayerScreen(nav, route)
                }
            }
        }
    }
}

private const val TABLET_WIDTH_DP = 600
private const val NAV_VEIL_ALPHA = 0xB3
