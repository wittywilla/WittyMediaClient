// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import com.wittywilla.wittymediaclient.net.pageFillsScreen
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
import androidx.compose.runtime.key
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
import com.wittywilla.wittymediaclient.data.ForgetServer
import com.wittywilla.wittymediaclient.data.Forgotten
import com.wittywilla.wittymediaclient.data.LogoCache
import com.wittywilla.wittymediaclient.data.TvHome
import com.wittywilla.wittymediaclient.net.TvHomePlan
import com.wittywilla.wittymediaclient.data.entryFor
import com.wittywilla.wittymediaclient.data.SavedServer
import com.wittywilla.wittymediaclient.diag.ClientLog
import com.wittywilla.wittymediaclient.net.Api
import com.wittywilla.wittymediaclient.net.BrandPart
import com.wittywilla.wittymediaclient.net.ApiError
import com.wittywilla.wittymediaclient.net.SduiCardStyles
import com.wittywilla.wittymediaclient.net.SduiClient
import com.wittywilla.wittymediaclient.net.SduiExperienceList
import com.wittywilla.wittymediaclient.net.SduiExperienceState
import com.wittywilla.wittymediaclient.net.SduiLook
import com.wittywilla.wittymediaclient.net.SduiRequired
import com.wittywilla.wittymediaclient.net.SduiDevice
import com.wittywilla.wittymediaclient.net.SduiFileStore
import com.wittywilla.wittymediaclient.net.SduiNavItem
import com.wittywilla.wittymediaclient.net.SduiNavigation
import com.wittywilla.wittymediaclient.net.SduiRouter
import com.wittywilla.wittymediaclient.net.SduiTarget
import com.wittywilla.wittymediaclient.net.isRigGame
import com.wittywilla.wittymediaclient.tv.watchChannel
import com.wittywilla.wittymediaclient.net.Identity
import com.wittywilla.wittymediaclient.net.IdentityState
import com.wittywilla.wittymediaclient.net.PeerAnswer
import com.wittywilla.wittymediaclient.net.PeerInvite
import com.wittywilla.wittymediaclient.net.PeerRoute
import com.wittywilla.wittymediaclient.net.PeerRules
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
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
import com.wittywilla.wittymediaclient.tv.TvLogos
import com.wittywilla.wittymediaclient.tv.TvReminderAlert
import com.wittywilla.wittymediaclient.tv.TvReminders
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
    // A TV's own tabs, beside Home, Search and You: see TvTabs.kt.
    data object Libraries : Route { override val key = "libraries" }
    data object Games : Route { override val key = "games" }
    data object LiveTv : Route { override val key = "live-tv" }
    // A library added to a TV's top menu, as a tab of its own.
    data class Pinned(val library: com.wittywilla.wittymediaclient.net.Library) : Route { override val key = "pinned-${library.id}" }
    data object Notices : Route { override val key = "notices" }
    // A device that has never been at home with its server shows a code for it (ui/AwayScreens.kt).
    data object JoinAway : Route { override val key = "join-away" }
    // One module's settings, at the address the server gave (ui/ModuleSettingsScreens.kt).
    // `page` is the one page of the module's settings to show; empty shows them all.
    data class ModuleSettings(val url: String, val title: String, val page: String = "") : Route { override val key = "module-settings:$url:$page" }
    data object Logs : Route { override val key = "logs" }
    // With something chosen, as the website's /library/3?genre=Drama: from a title's genre, tag or service.
    data class Library(val library: com.wittywilla.wittymediaclient.net.Library, val chosen: Map<String, String> = emptyMap()) : Route {
        override val key = "library-${library.id}" + chosen.entries.joinToString("") { "&${it.key}=${it.value}" }
    }
    // A season to open at, as the website's ?season=: -1 is Other videos. None opens at the next episode's.
    data class Show(val id: Long, val season: Int? = null) : Route { override val key = "show-$id" + (season?.let { "-$it" } ?: "") }
    data class Item(val id: Long) : Route { override val key = "item-$id" }
    data class Player(val id: Long, val startOver: Boolean) : Route { override val key = "player-$id" }
    data class Web(val path: String) : Route { override val key = "web-$path" }
    // WittyPlay's own frame, the server's page at a WittyPlay address over the whole app (net/WittyPlayPlace.kt).
    data class WittyPlay(val path: String) : Route { override val key = "wittyplay-$path" }
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
    // One of the server's own pages, drawn by the app (docs/PLATFORMS.md, Server-driven pages): asked for as
    // pages/{page} with these parameters. Home, Search, a library and a title keep their own routes above.
    data class Sdui(val page: String, val params: Map<String, String> = emptyMap(), val title: String = "") : Route {
        override val key = "sdui-$page" + params.entries.sortedBy { it.key }.joinToString("") { "&${it.key}=${it.value}" }
    }
    // A title's page as the app itself draws it, for what a server-driven page hands back to the app: a shared PC's game.
    data class OwnItem(val id: Long) : Route { override val key = "own-item-$id" }

    // The app's own screens leave room for the mini player. A film, a server's page and signing in don't have it.
    val hasMiniPlayer: Boolean
        get() = when (this) {
            Home, Search, Profile, Libraries, Games, Notices, Logs, is Library, is Pinned, is Show, is Item, is Album, is Artist, is You, is Sdui, is OwnItem -> true
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

    // A remote's Guide button, from anywhere that's signed in. A TV has WittyTV's own guide; elsewhere it's the page.
    fun openGuide() {
        if (!hasGuide || app.api.token.isEmpty()) return
        if (app.isTv) {
            if (current != Route.LiveTv && (current as? TvRoute)?.screen != TvScreen.Guide) push(TvRoute(TvScreen.Guide))
            return
        }
        val onPage = current as? Route.Page
        if (onPage?.path != GUIDE_PATH) push(Route.Page(GUIDE_PATH))
    }

    // The server the sign-in screens talk to. Its key waits here for a token to be
    // kept with, unless it was already pinned.
    var server: SavedServer? = null
        private set

    // A notice for after signing in, such as the sign-in not being kept on this device.
    var notice by mutableStateOf("")

    init {
        // Home and away swap while the app is open: requests follow (p2p/PeerManager.kt).
        app.peers.onMoved = ::movedTo
    }

    // The server's own name and logo for the sign-in screens, once it has been chosen. Empty for the app's own.
    var brandName by mutableStateOf("")
        private set
    var brandLogo by mutableStateOf("")
        private set
    var brandParts by mutableStateOf<List<BrandPart>>(emptyList())
        private set

    // Who is signed in, for the avatar on the You tab.
    var me by mutableStateOf<User?>(null)

    // The website's menus: the library strip and the Menu drawer. Loaded once for each sign-in.
    // The app's own list, for a server without a menu of its own.
    private var ownMenu by mutableStateOf<List<MenuEntry>>(emptyList())

    // With the server's menu (GET /sdui/navigation): its entries that sit behind More, then what only this app adds
    // (Game PCs, add-ons' pages). Settings is the app's own You, which the bar already has, so it isn't listed twice.
    val menu: List<MenuEntry>
        get() {
            val served = sduiNav ?: return ownMenu
            val bar = sduiBar.mapTo(HashSet()) { it.second.key }
            val seen = HashSet<String>()
            // Whatever the bar has no room for, and what sits behind More, in the server's order.
            val rest = served.items.mapNotNull { entry ->
                val route = routeOf(entry) ?: return@mapNotNull null
                if (route.key in bar || !seen.add(route.key)) null else MenuEntry("nav:" + entry.id, entry.label, sduiIcon(entry.icon), route)
            }
            return rest + ownMenu.filter { it.key == "couch" || it.key.startsWith("m:") }
        }

    // The floating bar's own places on a phone or tablet, from the server's menu: its primary entries and the ones
    // pinned to its end, each with where it leads. The bar has five cells, one of them Menu when anything is left
    // over, and You keeps its place at the end; the rest are along the top by name, and in the drawer.
    val sduiBar: List<Pair<SduiNavItem, Route>>
        get() {
            val served = sduiNav ?: return emptyList()
            val all = served.items.mapNotNull { entry -> routeOf(entry)?.let { entry to it } }.distinctBy { it.second.key }
            val wanted = all.filter { it.first.placement == "primary" || it.first.placement == "end" }
            val extras = ownMenu.any { it.key == "couch" || it.key.startsWith("m:") }
            if (wanted.size <= BAR_CELLS && wanted.size == all.size && !extras) return wanted
            val you = wanted.firstOrNull { it.second == Route.Profile }
            val others = wanted.filter { it !== you }
            return others.take(if (you != null) BAR_CELLS - 2 else BAR_CELLS - 1) + listOfNotNull(you)
        }

    // Every library this person can see, as the menus were made from: what a music library's Music videos needs.
    var libraries by mutableStateOf<List<com.wittywilla.wittymediaclient.net.Library>>(emptyList())
        private set
    var serverVersion by mutableStateOf("")
        private set
    var legal by mutableStateOf<com.wittywilla.wittymediaclient.net.LegalNotices?>(null)
        private set
    private var menuFor = ""

    suspend fun loadMenu() {
        val api = app.api
        if (api.token.isEmpty() || menuFor == api.token) return
        menuFor = api.token
        val libraries = runCatching { api.libraries() }.getOrDefault(emptyList())
        this.libraries = libraries
        val list = libraries.filter { it.inMainMenus }.map { MenuEntry("lib:" + it.id, it.name, WebIcons.forLibrary(it.type), libraryRoute(it)) }.toMutableList()
        if (libraries.isNotEmpty()) list += MenuEntry("collections", "Collections", WebIcons.Library, Route.Page("/collections", "Collections"))
        if (runCatching { api.couchStatus().allowed }.getOrDefault(false)) list += MenuEntry("couch", "Game PCs", WebIcons.Gamepad, Route.Page("/couch", "Game PCs"))
        runCatching { api.modulePages() }.getOrDefault(emptyList()).filter { it.second.where == "main" }.forEach { (module, page) ->
            list += MenuEntry("m:$module:${page.id}", page.title, if (page.icon == "chart") WebIcons.Chart else WebIcons.Plug, Route.Page("/m/$module/${page.id}", page.title))
        }
        ownMenu = list
        serverVersion = runCatching { api.status().version }.getOrDefault("")
        legal = runCatching { api.legalNoticesAndLink() }.getOrNull()
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

    // The libraries added to a TV's top menu (docs/APP-DESIGN.md, On a TV), for whoever is signed in here.
    var topMenu by mutableStateOf<List<Long>>(emptyList())
        private set

    fun loadTopMenu() {
        val base = server?.url ?: return
        topMenu = app.store.topMenu(base, me?.name.orEmpty())
    }

    // Adds a library to the top menu, or takes it out again.
    fun toggleTopMenu(library: com.wittywilla.wittymediaclient.net.Library) {
        val base = server?.url ?: return
        topMenu = if (library.id in topMenu) topMenu - library.id else topMenu + library.id
        app.store.keepTopMenu(base, me?.name.orEmpty(), topMenu)
    }

    // This device's theme for the server: "" for the server's own, "auto", or a theme's id.
    var themeChoice by mutableStateOf("")
        private set

    fun chooseTheme(choice: String) {
        // An administrator's requirement wins: the choice is locked (Settings shows who set it).
        if (requiredTheme != null) return
        themeChoice = choice
        server?.let { app.store.chooseTheme(it.url, choice) }
        wantTheme(choice.ifEmpty { themeId })
        app.scope.launch { refreshLook() }
    }

    // The look in force, with this device's theme asked for (not "auto" or a custom one, which the server can't name).
    private fun lookTheme() = themeChoice.takeIf { it != AUTO_THEME && it != ThemeTranslator.CUSTOM_THEME }.orEmpty()

    private suspend fun refreshLook() {
        val want = lookTheme()
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) { runCatching { app.api.resolvedTheme(want) } }
            .onSuccess { if (lookTheme() == want) look = com.wittywilla.wittymediaclient.net.Look.from(it) }
    }

    // The server's themes (docs/APP-DESIGN.md, Themes): its list, each one read and translated as it's wanted,
    // and the person's own look. The built-in ones in shared/data stand in until then.
    var themeList by mutableStateOf<ThemeList?>(null)
        private set
    val themes = mutableStateMapOf<String, AppTheme>()
    var customTheme by mutableStateOf<ThemeMakerInput?>(null)
        private set

    // What this server says it has (/capabilities features): a feature is offered only when its name is here, as
    // the owner can turn features off. Empty until read, which hides them.
    var features by mutableStateOf<Set<String>>(emptySet())
        private set

    // Whether the list has been asked for yet: until then Home waits, so it isn't drawn one way and then the other.
    var featuresRead by mutableStateOf(false)
        private set

    fun has(feature: String) = feature in features

    // MARK: the server's own pages (ui/Sdui*.kt, net/Sdui*.kt)


    // What this device is, as every request for a page says: set by AppRoot, and again when the window changes.
    var sduiDevice by mutableStateOf<SduiDevice?>(null)

    // The catalogue's routes, read once for each sign-in; the app's own copy until then.
    var sduiRouter by mutableStateOf(SduiRouter())
        private set

    // The main menu as the server has it for this profile and device. Null until read, and on a server without it.
    var sduiNav by mutableStateOf<SduiNavigation?>(null)
        private set

    private var sduiMade: SduiClient? = null
    private var sduiMadeFor: Pair<Api, SduiDevice>? = null
    private var sduiReadFor: SduiClient? = null

    // Pages are kept on the device for each sign-in, so the next start draws at once and a server out of reach still
    // shows them; they go with the sign-in.
    private val sduiFolder: java.io.File get() = java.io.File(app.cacheDir, "sdui")

    val sdui: SduiClient?
        get() {
            val device = sduiDevice ?: return null
            val api = app.api
            if (api.token.isEmpty()) return null
            if (sduiMadeFor?.first !== api || sduiMadeFor?.second != device) {
                // By the server's own address, so pages kept at home are the same ones away from it.
                val who = java.security.MessageDigest.getInstance("SHA-256").digest((app.store.server.ifEmpty { api.base } + "|" + api.token).toByteArray()).joinToString("") { "%02x".format(it) }.take(24)
                sduiMade = SduiClient(api.sdui, device, SduiFileStore(java.io.File(sduiFolder, who)))
                sduiMadeFor = api to device
            }
            return sduiMade
        }

    // The menu and the routes, for the shells. What was kept shows first; the server's answer follows.
    suspend fun loadSdui() {
        val client = sdui ?: return
        if (sduiReadFor === client) return
        sduiReadFor = client
        // Reading the kept files and decoding the catalogue (every component, route and command) are off the main
        // thread: on a slow TV stick they took long enough for the system to end the app.
        val io = kotlinx.coroutines.Dispatchers.IO
        if (sduiNav == null) kotlinx.coroutines.withContext(io) { client.keptNavigation() }?.let { sduiNav = it }
        kotlinx.coroutines.withContext(io) { runCatching { client.navigation() } }.onSuccess { if (sdui === client) sduiNav = it.value }.onFailure { handleExpired(it) }
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) { runCatching { client.catalog().let { SduiCardStyles.use(it.cardStyles); SduiRouter(it.routes, it.commands) } } }
            .onSuccess { if (sdui === client) sduiRouter = it }
        loadExperiences()
    }

    // Every entry of the server's menu that leads somewhere in this app, in its order, You last: what a side menu and
    // a row of tabs across the top show (layout options).
    val sduiMenuAll: List<Pair<SduiNavItem, Route>>
        get() {
            val served = sduiNav ?: return emptyList()
            val all = served.items.mapNotNull { entry -> routeOf(entry)?.let { entry to it } }.distinctBy { it.second.key }
            return all.filter { it.second != Route.Profile } + all.filter { it.second == Route.Profile }
        }

    // Opening one of the menu's entries: Home, Search, You and the server's pages are places of their own; anything
    // else opens over Home.
    fun openMenuEntry(route: Route) {
        if (current.key == route.key) return
        if (route == Route.Home || route == Route.Search || route == Route.Profile || route is Route.Sdui) reset(route)
        else { reset(Route.Home); push(route) }
    }

    // Counts up when what every page shows has changed underneath them (more screen time was given): the server's pages
    // on screen ask again.
    var pagesStamp by androidx.compose.runtime.mutableIntStateOf(0)

    // MARK: experiences (docs/plans/DESIGN-2.md section 7)

    // Every experience, the one in force on this device with what may be chosen, and what an administrator requires.
    var experienceList by mutableStateOf<SduiExperienceList?>(null)
        private set
    var experienceState by mutableStateOf<SduiExperienceState?>(null)
        private set
    var requiredTheme by mutableStateOf<SduiRequired?>(null)
        private set

    // The form factor this device draws a look's wire for.
    val experienceForm: String get() = sduiDevice?.formFactor.orEmpty()

    // The finished look from `GET /theme`: type set, finish amounts, scene, glass and gloss recipes.
    var look by mutableStateOf(com.wittywilla.wittymediaclient.net.Look.NONE)
        private set

    // The chooser offered the first time the app connects to a server, after the profile is chosen.
    var firstLook by mutableStateOf(false)

    private fun lookPrefs() = app.getSharedPreferences("looks", android.content.Context.MODE_PRIVATE)
    private fun lookKey() = "seen:" + (server?.url ?: app.api.base) + ":" + (me?.id ?: 0)

    suspend fun loadExperiences() {
        val client = sdui ?: return
        val io = kotlinx.coroutines.Dispatchers.IO
        kotlinx.coroutines.withContext(io) { runCatching { client.experiences() } }.onSuccess { if (sdui === client) experienceList = it }
        kotlinx.coroutines.withContext(io) { runCatching { client.experienceState() } }.onSuccess { if (sdui === client) experienceState = it }
        kotlinx.coroutines.withContext(io) { runCatching { app.api.resolvedTheme(lookTheme()) } }.onSuccess {
            requiredTheme = SduiLook.requiredTheme(it)
            look = com.wittywilla.wittymediaclient.net.Look.from(it)
            // A required theme is the one drawn.
            requiredTheme?.let { r -> if (themeChoice != r.value) { themeChoice = r.value; wantTheme(r.value) } }
        }
        if (SduiLook.offerFirst(experienceState, lookPrefs().getBoolean(lookKey(), false))) firstLook = true
    }

    fun finishFirstLook() {
        firstLook = false
        lookPrefs().edit().putBoolean(lookKey(), true).apply()
    }

    // This profile's experience on this device; null follows the server again. The menu and every page are asked for again.
    suspend fun chooseExperience(id: String?): String? {
        val client = sdui ?: return null
        return try {
            client.chooseExperience(id)
            sduiMade = null
            sduiMadeFor = null
            sduiReadFor = null
            shown.clear()
            loadSdui()
            loadExperiences()
            null
        } catch (e: ApiError) {
            e.message
        } catch (_: IOException) {
            s["errLost"]
        }
    }

    // After the name editor saved: the server's name, its coloured parts and its logo, asked for again.
    suspend fun reloadBrand() {
        val status = runCatching { app.api.status() }.getOrNull() ?: return
        showBrand(server?.url ?: app.api.base, status)
    }

    // After the profile rearranged its menu, or a page changed what is in it.
    suspend fun reloadSduiNav() {
        val client = sdui ?: return
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) { runCatching { client.navigation() } }.onSuccess { if (sdui === client) sduiNav = it.value }
    }

    // A title chosen on an Android TV's home screen: its page, or playing it, over Home. Only those two are taken.
    fun openFromHomeScreen(route: String) {
        if (!TvHomePlan.openable(route) || app.api.token.isEmpty()) return
        reset(Route.Home)
        go(sduiRouter.resolve(route))
    }

    // An Android TV's home screen follows what the profile is watching: written when the app is left, and when signed in.
    fun syncTvHome() {
        val client = sdui ?: return
        if (!app.isTv || !has("sdui-topshelf")) return
        app.scope.launch { TvHome.sync(app, client) }
    }

    private fun forgetSdui() {
        TvHome.clear(app)
        sduiMade = null
        sduiMadeFor = null
        sduiReadFor = null
        sduiNav = null
        sduiRouter = SduiRouter()
        SduiCardStyles.reset()
        val folder = sduiFolder
        app.scope.launch(kotlinx.coroutines.Dispatchers.IO) { runCatching { folder.deleteRecursively() } }
    }

    // With WittyPlay on the server (its entry in the server's menu), games open WittyPlay's own frame over the whole app, as
    // on the website and the Apple apps; on a TV, and without it, the app's own games screens.
    val wittyPlayInstalled: Boolean get() = sduiNav?.items?.let { com.wittywilla.wittymediaclient.net.WittyPlayPlace.installed(it) } == true

    fun wittyPlayFor(library: com.wittywilla.wittymediaclient.net.Library): Route? {
        if (library.type != "games" || library.console == "rig") return null
        if (!wittyPlayInstalled) return gamesRouteFor(library)
        // A TV has no web pages: WittyPlay's frame is drawn from its home page's regions, as Apple TV's. A library has no
        // page of its own yet, so on a TV it opens WittyPlay's home.
        return if (app.isTv) Route.Sdui(com.wittywilla.wittymediaclient.net.WittyPlayPlace.HOME_PAGE, emptyMap(), library.name)
        else Route.WittyPlay(com.wittywilla.wittymediaclient.net.WittyPlayPlace.library(library.id))
    }

    // The route for a place the server names, where it is one of the app's screens or pages; null for what is done
    // rather than opened (playing something).
    fun routeOf(target: SduiTarget): Route? = when (target) {
        is SduiTarget.Page -> when (target.page) {
            "home" -> Route.Home
            "detail" -> {
                val p = target.params
                val item = p["item"]?.toLongOrNull()
                val show = p["show"]?.removePrefix("show-")?.toLongOrNull()
                val library = p["library"]?.toLongOrNull()
                when {
                    item != null -> Route.Item(item)
                    show != null && p["item"] == null -> Route.Show(show, p["season"]?.toIntOrNull())
                    library != null && p["album"] != null -> Route.Album(library, p["album"].orEmpty(), p["artist"].orEmpty())
                    else -> Route.Sdui(target.page, p)
                }
            }
            // A games library opens WittyPlay, as the website and the Apple apps do.
            "library" -> libraries.firstOrNull { it.id == target.params["library"]?.toLongOrNull() }
                ?.let { wittyPlayFor(it) ?: Route.Library(it, target.params - "library") } ?: Route.Sdui(target.page, target.params)
            else -> if (com.wittywilla.wittymediaclient.net.WittyPlayPlace.isPlayPage(target.page) && !app.isTv) Route.WittyPlay(target.route.ifEmpty { "/page/" + target.page })
                else Route.Sdui(target.page, target.params)
        }
        is SduiTarget.Native -> {
            val item = target.params["item"].orEmpty()
            // What the app has no screen of its own for is the server's page for the title, which has it: a QR card on a TV.
            fun serverPage(title: String): Route? {
                val path = when {
                    item.startsWith("show-") -> "/show/" + item.removePrefix("show-")
                    item.toLongOrNull() != null -> "/item/$item"
                    else -> return null
                }
                return if (app.isTv) Route.OnPhone(title, path) else Route.Page(path, title)
            }
            when (target.screen) {
                "settings" -> target.params["section"]?.takeIf { it.isNotEmpty() }?.let {
                    if (app.isTv) Route.OnPhone("Settings", "/settings/$it") else Route.Page("/settings/$it", "Settings")
                } ?: Route.Profile
                "profiles" -> Route.Profile
                "guide" -> when {
                    app.isTv && target.route.startsWith("/tv/recordings") -> TvRoute(TvScreen.Recordings)
                    app.isTv -> TvRoute(TvScreen.Guide)
                    target.route.startsWith("/tv/recordings") -> Route.Page("/tv/recordings")
                    else -> Route.Page(GUIDE_PATH)
                }
                "livePlayer" -> target.params["key"]?.let { if (app.isTv) TvRoute(TvScreen.Channel(it)) else Route.Page("/tv/watch/$it") }
                "reader" -> item.toLongOrNull()?.let { Route.Page("/read/$it") }
                "nowPlaying" -> if (app.listening.now != null) Route.NowPlaying else null
                "pair" -> if (app.isTv) null else Route.You(YouNative.SignInTv)
                "collections" -> Route.Sdui("collections")
                "download" -> serverPage("Download")
                "share" -> serverPage("Share")
                // The app's own picker and party screens, where the server and this profile have them.
                "playOn" -> item.toLongOrNull()?.takeIf { app.remote.canControl }
                    ?.let { RemoteRoute.PlayOn(com.wittywilla.wittymediaclient.net.remote.PlayOnSource(it, "", "")) } ?: serverPage("Play on…")
                "watchParty" -> if (has(com.wittywilla.wittymediaclient.player.SYNCPLAY_FEATURE) && item.toLongOrNull() != null) RemoteRoute.Party(item.toLongOrNull()) else serverPage("Watch party")
                "downloads" -> if (app.isTv) null else Route.Page("/downloads", "Downloads")
                "remote" -> if (app.remote.canControl) RemoteRoute.Devices else if (app.isTv) null else Route.Page("/remote", "Remote")
                else -> null
            }
        }
        is SduiTarget.Unknown -> {
            // The one place the app has a screen for that the table doesn't list: an artist. Anything else is the server's page.
            val path = target.route.substringBefore('?')
            val query = SduiRouter.parseQuery(target.route.substringAfter('?', ""))
            val library = path.removePrefix("/artist/").toLongOrNull()
            if (path.startsWith("/artist/") && library != null && query["name"] != null) Route.Artist(library, query["name"].orEmpty())
            else if (target.route.startsWith("/")) Route.Page(target.route) else null
        }
    }

    // What a page put into the shell's regions (statusBar, systemDock) while it shows, and a page shown over the screen
    // (navigate `as: "layer"`); ui/SduiRev8.kt draws both.
    var regions by mutableStateOf<com.wittywilla.wittymediaclient.net.SduiRegionsState?>(null)
    var layer by mutableStateOf<SduiTarget.Page?>(null)

    // Opens a place the server names: one of its pages, one of the app's screens, or something played. A page can be a layer.
    fun go(target: SduiTarget, layer: Boolean = false) {
        if (layer && target is SduiTarget.Page) { this.layer = target; return }
        if (target is SduiTarget.Native) {
            val item = target.params["item"].orEmpty()
            when (target.screen) {
                "player" -> { playById(item, resume = true); return }
                "game" -> { item.toLongOrNull()?.let { openGame(it) }; return }
                "livePlayer" -> if (app.isTv) { target.params["key"]?.let { watchChannel(it) }; return }
            }
        }
        val route = routeOf(target) ?: return
        when {
            route == Route.Home -> reset(Route.Home)
            route == current -> Unit
            else -> push(route)
        }
    }

    // Play, as a page asks for it: the item is read, and what kind of thing it is decides how it plays, as everywhere else.
    fun playById(id: String, resume: Boolean) {
        val number = id.toLongOrNull() ?: return
        app.scope.launch {
            try {
                val item = app.api.item(number)
                if (!resume && item.hasOwnScreen && !item.isTrack && !item.isRigGame) push(Route.Player(item.id, true)) else play(item)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (!handleExpired(e)) notice = problemWords(e, s["errLost"].orEmpty())
            }
        }
    }

    // A game's own page: WittyPlay's for one the server plays, the app's for a shared PC's.
    private fun openGame(id: Long) {
        app.scope.launch {
            val item = runCatching { app.api.item(id) }.getOrNull()
            push(if (item?.isRigGame == true) Route.OwnItem(id) else GamesRoute(GamesScreen.Game(id)))
        }
    }

    // The menu entry's place. Home and Search keep their own routes, so everything that goes "home" still does.
    fun routeOf(entry: SduiNavItem): Route? = when (entry.kind) {
        "page" -> when {
            entry.page == "home" -> Route.Home
            entry.page == "search" && entry.params.isEmpty() -> Route.Search
            app.isTv && entry.page == "libraries" && entry.params.isEmpty() -> Route.Libraries
            app.isTv && entry.page == "livetv" && entry.params.isEmpty() -> Route.LiveTv
            else -> routeOf(SduiTarget.Page(entry.page, entry.params, entry.route)).let { if (it is Route.Sdui) it.copy(title = entry.label) else it }
        }
        "native" -> routeOf(SduiTarget.Native(entry.screen, emptyMap(), entry.route))
        else -> if (entry.route.isNotEmpty()) routeOf(sduiRouter.resolve(entry.route)) else null
    }

    // Reads the list, then the themes in use. Quiet on failure: the built-ins and what was kept stand in.
    fun loadThemes(signedIn: Boolean) {
        val base = server?.url ?: return
        val api = app.api
        app.scope.launch {
            val caps = runCatching { api.capabilities() }.getOrNull()
            if (server?.url == base) {
                if (caps != null) {
                    features = caps.features.toSet()
                }
                featuresRead = true
            }
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
        features = emptySet()
        featuresRead = false
        themeList = null
        themes.clear()
        customTheme = null
    }

    private fun showBrand(base: String, status: ServerStatus) {
        brandName = status.brandName
        brandParts = status.brandParts
        brandLogo = brandLogoUrl(base, status.brandLogo)
    }

    // A server whose identity has been checked: keep its name and logo with it, the picture on the device.
    private fun keepBrand(opened: SavedServer, status: ServerStatus): SavedServer {
        val named = opened.copy(
            name = status.brandName.ifEmpty { opened.name.ifEmpty { "WittyMediaServer" } }, brandLogo = status.brandLogo,
            lastSeen = System.currentTimeMillis(),
        )
        if (status.brandLogo.isNotEmpty()) app.scope.launch { LogoCache.keep(app, named.url, status.brandLogo) }
        return named
    }

    private fun forgetBrand() {
        brandName = ""
        brandParts = emptyList()
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
        forgetSdui()
        TvLogos.forget()
        TvReminders.forget()
        shown.clear()
        focusMemory.clear()
        libraryTypes.clear()
        app.listening.forget()
        app.forgetImages()
    }

    fun push(r: Route) { stack.add(r) }

    // This app's own screens for what it has them for, and the server's page for all the rest.
    fun open(library: com.wittywilla.wittymediaclient.net.Library) = push(libraryRoute(library))

    // A library's own page: WittyPlay's for a games library, the app's for films, shows, discs and listening, and the
    // website's for every other kind. The strip, the drawer, Home's tiles and See all all come through here.
    fun libraryRoute(library: com.wittywilla.wittymediaclient.net.Library): Route =
        wittyPlayFor(library) ?: if (library.hasOwnScreen) Route.Library(library) else Route.Page(library.pagePath(), library.name)
    fun open(item: com.wittywilla.wittymediaclient.net.Item) = push(
        when {
            gamesRouteFor(item) != null -> gamesRouteFor(item)!!
            item.isTrack -> Route.Album(item.libraryId, item.album, item.albumArtist.ifEmpty { item.artist })
            // A disc has the app's own page on a phone or tablet, with Insert; its player is the website's.
            item.hasOwnScreen || (item.isDisc && !app.isTv) -> Route.Item(item.id)
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
    val backStaysInApp: Boolean get() = stack.size > 1 || current in TABS_BESIDE_HOME || current is Route.Sdui

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
        app.api = Api(baseFor(opening), token)
        if (token.isNotEmpty()) ClientLog.kick()
    }

    // Where requests for this server go: the connector's local address while it is reached from away, else its own.
    private fun baseFor(opening: SavedServer): String {
        val away = app.peers.awayFor
        return if (away.isNotEmpty() && PeerRoute.active && app.peers.info(opening)?.serverId == away) PeerRoute.base else opening.url
    }

    // The connection moved between home and away while the app was open: the same sign-in, at the other address.
    private fun movedTo(base: String) {
        if (server == null || app.api.token.isEmpty()) return
        app.api = Api(base, app.api.token)
    }

    // At home and signed in: this device goes on the server's list for connecting from away (docs/P2P.md).
    private fun learnAway() {
        val opened = server ?: return
        val api = app.api
        if (PeerRoute.matches(api.base.toHttpUrlOrNull()?.host, api.base.toHttpUrlOrNull()?.port ?: 0) || api.token.isEmpty()) return
        app.scope.launch { app.peers.learnAway(api, opened) }
    }

    fun learnAwayNow() = learnAway()

    // "Stop connecting from away" while reaching the server that way: it can't be reached any more.
    fun lostFromAway() {
        server = null
        app.api = Api("", "")
        forgetScreens()
        reset(Route.Connect(s["errLost"].orEmpty()))
    }

    // An invite link typed or pasted where an address goes. Answers words to show on failure.
    suspend fun joinInvite(invite: PeerInvite): String? {
        if (!app.peers.available) return s["errAwayMissing"]
        val answer = app.peers.join(invite) ?: return s["errAwayFailed"]
        if (!answer.ok) {
            app.peers.leave()
            return s["errInviteRefused"]
        }
        return joinedFromAway(answer)
    }

    // The connector has reached a server that took this device's invite or code: it proves its key, goes in the list
    // of servers (under its own address if this device knows it, else one for away only), and the sign-in code that
    // came back is redeemed over the connection. Answers words to show on failure.
    suspend fun joinedFromAway(answer: PeerAnswer): String? {
        val proof = identify(PeerRoute.base, app.store.recent)
        if (proof.state != IdentityState.New && proof.state != IdentityState.Same) {
            app.peers.leave()
            return s[if (proof.state == IdentityState.Unreachable) "errAwayFailed" else "identityBad"]
        }
        val known = app.store.recent.firstOrNull { it.publicKey.isNotEmpty() && it.publicKey == proof.publicKey }
        val url = known?.url ?: PeerRules.awayOnlyUrl(answer.serverId)
        val saved = proof.savedAs(url, known?.name ?: answer.serverName.ifEmpty { "WittyMediaServer" }).copy(lastSeen = System.currentTimeMillis())
        app.store.remember(saved)
        app.peers.joined(saved, answer)
        finishForget()
        forgetScreens()
        openServer(saved)
        if (answer.code.isEmpty()) {
            reset(Route.SignIn())
            return null
        }
        return try {
            val result = app.api.pairRedeem(answer.code, app.deviceName, app.platformName)
            if (result.token.isEmpty()) return s["joinAwayRefused"]
            signedIn(result.token, result.user)
            null
        } catch (e: ApiError) {
            e.message
        } catch (_: IOException) {
            s["errAwayFailed"]
        } catch (_: SerializationException) {
            s["errInvalid"]
        }
    }

    // The server's own address didn't answer: the connection from away, if this device has one for it. Then the
    // server proves its key through it, as at home. Answers whether the server was opened that way.
    suspend fun tryFromAway(saved: SavedServer): Boolean = openFromAway(saved)

    private suspend fun openFromAway(saved: SavedServer): Boolean {
        if (!app.peers.available || app.peers.info(saved) == null) return false
        notice = s["awayConnecting"].orEmpty()
        val reached = app.peers.reach(saved)
        notice = ""
        if (!reached) return false
        val proof = identify(PeerRoute.base, listOf(saved))
        if (proof.state != IdentityState.Same) {
            app.peers.leave()
            return false
        }
        if (tokenFits(proof)) return openWithToken(saved) == null
        // Proved, with no sign-in kept for it: on to signing in, through the connection.
        app.store.forgetToken()
        forgetScreens()
        openServer(saved.copy(lastSeen = System.currentTimeMillis()))
        reset(Route.SignIn())
        return true
    }

    // On to signing in, for a server that has been checked.
    fun signInTo(opening: SavedServer, way: SignInWay = SignInWay.Usual) {
        app.store.forgetToken()
        forgetScreens()
        openServer(opening)
        reset(Route.SignIn(way))
    }

    // Opens a server with a token that was kept with its key.
    private suspend fun openWithToken(checked: SavedServer): String? = try {
        // It has just proved who it is: that's when it was last reached, whatever happens next.
        val opening = checked.copy(lastSeen = System.currentTimeMillis())
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
        if (status.user != null) learnAway()
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
        // A list from an older version, or one with leftovers, is put right before anything reads it.
        app.store.tidy()
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
        if (proof.state == IdentityState.Same) app.store.reached(checked, System.currentTimeMillis())
        when (Identity.stepAtStart(proof.state, tokenFits(proof))) {
            NextStep.Warn -> warn(checked)
            NextStep.Refuse -> reset(Route.Connect(s["identityBad"].orEmpty()))
            NextStep.Lost -> if (!openFromAway(saved)) reset(Route.Connect(s["errLost"].orEmpty()))
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
        // Whatever was just removed is gone for good before anything is opened.
        finishForget()
        val proof = identify(url, app.store.recent)
        // A remembered server that proved its key: its entry follows it to this address, and was reached now.
        if (proof.state == IdentityState.Same) app.store.reached(proof.savedAs(url, ""), System.currentTimeMillis())
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
                app.store.remember(shown.copy(lastSeen = System.currentTimeMillis()))
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
        val kept = (server ?: SavedServer(app.api.base, "WittyMediaServer")).copy(lastSeen = System.currentTimeMillis())
        me = user
        if (!app.store.signedIn(kept, token)) notice = s["notKept"].orEmpty()
        app.api = Api(baseFor(kept), token)
        loadThemes(true)
        ClientLog.kick()
        forgetScreens()
        reset(Route.Home)
        learnAway()
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
        // This device leaves other devices' lists, and its watch party seat goes, while the sign-in is still good.
        val goodbye = app.remote.goodbye(old)
        if (old.token.isNotEmpty()) app.scope.launch {
            placeSent.join()
            goodbye.join()
            runCatching { old.logout() }
        }
    }

    fun signOut() {
        endSession()
        forgetSignIn()
    }

    fun changeServer() {
        app.peers.leave()
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

    // Something to say on the list of servers that isn't a problem, such as what was just removed.
    var pickerNotice by mutableStateOf("")

    // A server removed a moment ago that Undo can still bring back.
    var pendingForget by mutableStateOf<Forgotten?>(null)
        private set

    // Whether this is the server the app is using now.
    fun uses(target: SavedServer): Boolean = server?.let { entryFor(listOf(it), target) != null } == true

    // Removes a server from this device: every screen that offers it comes through here, and ForgetServer does
    // the work. The one in use is signed out of first, and the app goes back to the list of servers. With `undoable`
    // the removal can be taken back until finishForget; the server is told to end the sign-in only after that.
    fun forgetServer(target: SavedServer, undoable: Boolean) {
        finishForget()
        val inUse = uses(target)
        if (inUse) changeServer()
        val gone = ForgetServer.forget(app, target)
        if (undoable && !inUse) pendingForget = gone else ForgetServer.finish(app, gone)
    }

    // Undo. Answers the server that came back, or null when the time for it had passed.
    fun undoForget(): SavedServer? {
        val gone = pendingForget ?: return null
        pendingForget = null
        ForgetServer.undo(app, gone)
        return gone.server
    }

    // Undo is no longer offered: the time is up, the screen was left, or the app went to the background.
    fun finishForget() {
        val gone = pendingForget ?: return
        pendingForget = null
        ForgetServer.finish(app, gone)
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
    val windowClass = WindowClasses.of(width)
    val metrics = if (app.isTv) TvMetrics else if (windowClass >= WindowClass.Medium) TabletMetrics.copy(gutter = if (windowClass == WindowClass.Large) Space.S10 else Space.S8) else PhoneMetrics
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

    WittyTheme(theme, metrics, reduceMotion, strings, nav.brandParts, nav.look) {
        LaunchedEffect(Unit) { nav.startUp() }
        DisposableEffect(Unit) {
            app.onGuideKey = nav::openGuide
            onDispose { app.onGuideKey = null }
        }
        // Remote control and watch parties (player/RemoteHub.kt) follow the app's screens, who is signed in, and
        // whether the app is in front.
        val activity = context as? ComponentActivity
        DisposableEffect(activity) {
            app.remote.attach(nav, activity)
            onDispose { app.remote.attach(nav, null) }
        }
        val signedInNow = nav.current.signedIn && app.api.token.isNotEmpty()
        LaunchedEffect(app.api.token, signedInNow, nav.features) { app.remote.session(signedInNow, nav.features) }
        LifecycleEventEffect(Lifecycle.Event.ON_START) {
            app.peers.appBack()
            scope.launch { nav.recheck() }
            app.listening.appeared()
            app.remote.foreground(true)
        }
        LifecycleEventEffect(Lifecycle.Event.ON_STOP) {
            // Music in the background keeps a connection from away open; a film stops below, and so lets it go.
            app.peers.appLeft(playing = app.listening.isPlaying)
            nav.syncTvHome()
            nav.finishForget()
            // Before the music lets go of its player: this device may still answer for it from the background.
            app.remote.foreground(false)
            app.listening.disappeared()
            // A film stops when the app is left, with its place kept.
            nav.video?.backgrounded()
        }
        BackHandler(enabled = nav.backStaysInApp) { nav.back() }
        val route = nav.current
        // What this device is, for the server's pages: the window, the language, what it can draw. A new window size
        // makes a new one, and the pages ask again.
        val config = LocalConfiguration.current
        val device = remember(config.screenWidthDp, config.screenHeightDp, config.smallestScreenWidthDp, androidx.core.os.ConfigurationCompat.getLocales(config).toLanguageTags(), reduceMotion) { sduiDeviceFor(app, config, reduceMotion) }
        LaunchedEffect(device) { nav.sduiDevice = device }
        // An Android TV's home screen, once the server's pages can be asked for; and a title chosen there, once signed in.
        val pages = nav.sdui
        LaunchedEffect(pages) { if (pages != null) nav.syncTvHome() }
        val wanted = app.wantedRoute
        LaunchedEffect(wanted, route.signedIn, nav.featuresRead) {
            if (wanted != null && route.signedIn && nav.featuresRead) {
                app.wantedRoute = null
                nav.openFromHomeScreen(wanted)
            }
        }
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
                        // A new Home for each server connection, so the first screen after signing in is drawn fresh.
                        // The server's pages draw these: there are no hand-built versions (the apps need the Design 2 server).
                        Route.Home -> key(app.api) {
                            Shell(nav) { if (!nav.featuresRead) Loading() else SduiPageScreen(nav, "home", emptyMap(), top = true) }
                        }
                        Route.Search -> Shell(nav) { SduiPageScreen(nav, "search", emptyMap(), top = true) }
                        Route.Profile -> Shell(nav) { YouScreen(nav, strings) }
                        Route.Libraries -> Shell(nav) { SduiPageScreen(nav, "libraries", emptyMap(), top = true) }
                        Route.Games -> Shell(nav) { GamesTabScreen(nav, strings) }
                        Route.LiveTv -> Shell(nav) { SduiPageScreen(nav, "livetv", emptyMap(), top = true) }
                        is Route.Pinned -> Shell(nav) {
                            SduiPageScreen(nav, "library", mapOf("library" to route.library.id.toString()), top = true)
                        }
                        is Route.Sdui -> if (nav.stack.size == 1) Shell(nav) { SduiPageScreen(nav, route.page, route.params, top = true, title = route.title) }
                            else PageShell(nav) { SduiPageScreen(nav, route.page, route.params, title = route.title) }
                        is Route.OwnItem -> PageShell(nav) { if (LocalMetrics.current.tv) ItemScreen(nav, strings, route.id) else PhoneItem(nav, strings, route.id) }
                        Route.Notices -> NoticesScreen(nav)
                        Route.JoinAway -> JoinAwayScreen(nav, strings)
                        is Route.ModuleSettings -> ModuleSettingsScreen(nav, strings, route.url, route.title, route.page)
                        Route.Logs -> LogsScreen(nav)
                        is Route.Library -> {
                            val body = @Composable {
                                SduiPageScreen(nav, "library", mapOf("library" to route.library.id.toString()) + route.chosen, top = nav.stack.size == 1, title = route.library.name)
                            }
                            // A library that is a tab of its own (the server's menu put it in the bar) sits under the bar.
                            if (nav.stack.size == 1) Shell(nav, body) else PageShell(nav, body)
                        }
                        is Route.Show -> PageShell(nav) {
                            SduiPageScreen(nav, "detail", mapOf("show" to route.id.toString()) + (route.season?.let { mapOf("season" to it.toString()) } ?: emptyMap()))
                        }
                        is Route.Item -> PageShell(nav) {
                            SduiPageScreen(nav, "detail", mapOf("item" to route.id.toString()))
                        }
                        is Route.Album -> PageShell(nav) {
                            SduiPageScreen(nav, "detail", mapOf("library" to route.library.toString(), "album" to route.album, "artist" to route.artist))
                        }
                        is Route.Artist -> PageShell(nav) { if (LocalMetrics.current.tv) ArtistScreen(nav, strings, route.library, route.name) else PhoneArtist(nav, route.library, route.name) }
                        Route.NowPlaying -> if (LocalMetrics.current.tv) NowPlayingScreen(nav) else WebNowPlaying(nav)
                        is Route.Player -> if (LocalMetrics.current.tv) PlayerScreen(nav, route.id, route.startOver) else VideoPlayerScreen(nav, route)
                        is Route.Web -> ServerPageScreen(nav, route, route.path, keptToGames = true)
                        is Route.WittyPlay -> ServerPageScreen(nav, route, route.path, keptToGames = false, wittyPlay = true)
                        is Route.Page -> if (!LocalMetrics.current.tv && !pageFillsScreen(route.path)) PageShell(nav) { ServerPageScreen(nav, route, route.path, keptToGames = false, title = route.title, inShell = true) }
                            else ServerPageScreen(nav, route, route.path, keptToGames = false, title = route.title)
                        is Route.You -> YouSettingScreen(nav, strings, route.screen)
                        is Route.Help -> ServerPageScreen(nav, route, route.path, keptToGames = false, public = true)
                        is Route.OnPhone -> OnPhoneScreen(nav, strings, route.title, route.path)
                        is GamesRoute -> GamesRouteScreen(nav, route)
                        is HouseholdRoute -> HouseholdRouteScreen(nav, strings, route)
                        is TvRoute -> TvRouteScreen(nav, route)
                        is RemoteRoute -> RemoteRouteScreen(nav, route)
                    }
                }
            }
        }
        // A phone's tabs float at the bottom, and the shell puts the mini player above them. Elsewhere it has its
        // own strip along the bottom, which also takes care of the system's bar.
        // On a phone or tablet every page in the website's shell has the shell's own mini bar.
        val tabs = !metrics.tv && (route == Route.Home || route == Route.Search || route == Route.Profile || route is Route.Library ||
            route is Route.Show || route is Route.Item || route is Route.Album || route is Route.Artist || route is Route.Sdui || route is Route.OwnItem)
        // A keyboard on a tablet or a Chromebook: the same keys as everywhere (net/InputRules.kt).
        Box(Modifier.fillMaxSize().then(if (metrics.tv) Modifier else windowKeys(nav))) {
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
        if (InputInUse.helpOpen && !metrics.tv) KeyHelpSheet { InputInUse.helpOpen = false }
        // The first time this device connects to a server, after the profile is chosen: the look and the theme.
        if (nav.firstLook && route.signedIn && route == Route.Home) FirstLookScreen(nav, strings)
        // A WittyTV reminder comes up on whatever's showing, once someone is signed in.
        if (metrics.tv && route.signedIn) TvReminderAlert(nav)
        // Screen time and what a profile's limits turn off, over every screen and every player.
        ProfileGuard(nav, app.api, strings)
        // News from remote control and watch parties, and invitations, over whatever is showing.
        if (route.signedIn) RemoteOverlay(nav)
    }
}

private const val BAR_CELLS = 5
const val AUTO_THEME = "auto"
private const val LIGHT_THEME = "light"
private const val NAV_VEIL_ALPHA = 0xB3
