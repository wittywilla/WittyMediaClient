// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.p2p

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.wittywilla.wittymediaclient.WittyApp
import com.wittywilla.wittymediaclient.data.SavedServer
import com.wittywilla.wittymediaclient.diag.ClientLog
import com.wittywilla.wittymediaclient.net.Api
import com.wittywilla.wittymediaclient.net.IdentityState
import com.wittywilla.wittymediaclient.net.PeerAnswer
import com.wittywilla.wittymediaclient.net.PeerInfo
import com.wittywilla.wittymediaclient.net.PeerInvite
import com.wittywilla.wittymediaclient.net.PeerRoute
import com.wittywilla.wittymediaclient.net.PeerRules
import com.wittywilla.wittymediaclient.net.PeerState
import com.wittywilla.wittymediaclient.net.identify
import com.wittywilla.wittymediaclient.net.json
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

// How the server is reached now.
sealed interface PeerWay {
    // Not decided, or no server.
    data object None : PeerWay

    // At home: the server's own address.
    data object Home : PeerWay

    // From away, through the connector, in this state.
    data class Away(val state: PeerState) : PeerWay
}

// Home first, then peer to peer, as Apple's apps do (PeerManager.swift there; the server's docs/P2P.md, "The app's
// side"). At home and signed in, this device puts its key on the server's list (learnAway). When the server's own
// address doesn't answer, the connector is started with what was kept, and once it is connected the app's requests go
// to its local address (PeerRoute). While away, home is tried again now and then, and at once when the connector says
// the server is on this network. Off the screen the connection is closed, unless something is playing, and opened
// again on the same port on coming back. Everything here is called on the main thread; the library's calls go to IO.
class PeerManager(private val app: WittyApp) {
    val available: Boolean get() = PeerLibrary.available

    var way by mutableStateOf<PeerWay>(PeerWay.None)
        private set

    // The server the connection from away is for, by its connection ID.
    var awayFor: String = ""
        private set

    // Nav moves the app's requests to this address: the local one when away, the server's own back home.
    var onMoved: ((base: String) -> Unit)? = null

    private val prefs = app.getSharedPreferences("peer", Context.MODE_PRIVATE)
    private val main = Handler(Looper.getMainLooper())
    private val lock = Mutex()
    private var link: PeerLink? = null
    private var linkInfo: PeerInfo? = null
    private var homeUrl = ""
    private var watching: Job? = null
    private var suspended = false
    private var lastTrouble = 0L
    private var cachedId: String? = null

    init {
        PeerRoute.installCookies()
        PeerRoute.onTrouble = { main.post(::trouble) }
        watchNetwork()
    }

    // MARK: what is kept

    private fun keyOf(server: SavedServer) = "peer." + server.serverId.ifEmpty { server.url }
    private fun offKeyOf(server: SavedServer) = "peer.off." + server.serverId.ifEmpty { server.url }

    fun info(server: SavedServer): PeerInfo? =
        prefs.getString(keyOf(server), null)?.let { runCatching { json.decodeFromString(PeerInfo.serializer(), it) }.getOrNull()?.cleaned() }

    private fun keep(server: SavedServer, info: PeerInfo) {
        val clean = info.cleaned() ?: return
        prefs.edit().putString(keyOf(server), json.encodeToString(PeerInfo.serializer(), clean)).apply()
    }

    fun isOff(server: SavedServer): Boolean = prefs.getBoolean(offKeyOf(server), false)

    // Whether any server is kept for reaching from away.
    private fun anyKept(): Boolean = prefs.all.keys.any { it.startsWith("peer.") && !it.startsWith("peer.off.") }

    // This device's key: made the first time it is needed, kept sealed with the Keystore, and the same for every
    // server. Null when it can't be kept, as a key that would be lost is no use to the server's list.
    private suspend fun deviceKey(): String? = withContext(Dispatchers.IO) {
        val native = PeerLibrary.native ?: return@withContext null
        val stored = prefs.getString(KEY, "").orEmpty()
        val had = app.store.unseal(stored)
        if (had.isNotEmpty() && runCatching { native.deviceId(had) }.isSuccess) return@withContext had
        val made = runCatching { native.newKey() }.getOrNull() ?: return@withContext null
        val sealed = app.store.seal(made) ?: return@withContext null
        prefs.edit().putString(KEY, sealed).apply()
        cachedId = null
        made
    }

    // This device's connection ID, the name it has on servers' lists; empty without a key.
    suspend fun deviceId(): String {
        cachedId?.let { return it }
        val key = deviceKey() ?: return ""
        return withContext(Dispatchers.IO) { runCatching { PeerLibrary.native?.deviceId(key) }.getOrNull().orEmpty() }.also { cachedId = it }
    }

    // MARK: at home

    // At home and signed in: put this device on the server's list, once, and keep where the server is.
    suspend fun learnAway(api: Api, server: SavedServer) {
        if (!available || isOff(server) || way is PeerWay.Away) return
        try {
            // Asked here rather than taken from what the app read: right after signing in that may not be back yet.
            if ("p2p" !in api.capabilities().features) return
            val id = deviceId().ifEmpty { return }
            val answer = api.p2pInfo(id)
            if (!answer.enabled || !PeerRules.isId(answer.serverId)) {
                prefs.edit().remove(keyOf(server)).apply()
                return
            }
            if (!answer.enrolled) api.p2pEnrol(id, app.deviceName, app.platformName)
            keep(server, PeerInfo(answer.serverId, answer.addrs, info(server)?.port ?: 0))
            if (way == PeerWay.None) way = PeerWay.Home
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            ClientLog.warn("network", "This device couldn't be put on the server's list for connecting from away: ${e.javaClass.simpleName}")
        }
    }

    // MARK: from away

    // Starts the connector with what was kept for this server and waits for it to connect. True when the app's
    // requests can go to the local address.
    suspend fun reach(server: SavedServer): Boolean {
        if (!available || isOff(server)) return false
        val info = info(server) ?: return false
        val state = open(info, PeerRules.AWAY_WAIT_MS) ?: return false
        homeUrl = server.url
        settled(server, info, state)
        return true
    }

    private fun settled(server: SavedServer, info: PeerInfo, state: PeerState) {
        way = PeerWay.Away(state)
        if (PeerRoute.port != info.port) keep(server, info.copy(port = PeerRoute.port))
        watchHome(server)
    }

    // The connector for this server, started (or kept, if it already is), until it connects or the time is up.
    private suspend fun open(info: PeerInfo, waitMs: Long): PeerState? = lock.withLock {
        val native = PeerLibrary.native ?: return null
        val key = deviceKey() ?: return null
        if (link != null && linkInfo?.serverId != info.serverId) shut()
        val started = link ?: try {
            withContext(Dispatchers.IO) {
                native.setMemoryLimit(if (app.isTv) PeerRules.MEMORY_MB_TV else PeerRules.MEMORY_MB)
                // Asking for the port it had, so addresses already handed to a player still lead somewhere.
                val port = info.port.takeIf { it > 0 } ?: PeerRoute.port
                native.start(PeerRules.configuration(key, info.serverId, info.hints, port)) { state -> main.post { heard(state) } }
            }
        } catch (e: Exception) {
            ClientLog.warn("network", "The connection from away couldn't start: ${e.javaClass.simpleName}")
            return null
        }
        link = started
        linkInfo = info
        awayFor = info.serverId
        val state = withTimeoutOrNull(waitMs) {
            var now = PeerRules.state(withContext(Dispatchers.IO) { started.state() })
            while (!now.connected) {
                delay(POLL_MS)
                now = PeerRules.state(withContext(Dispatchers.IO) { started.state() })
            }
            now
        }
        if (state == null) {
            shut()
            return null
        }
        PeerRoute.set(started.port, started.secret)
        state
    }

    // What the connector says, as it says it: shown, and acted on.
    private fun heard(text: String) {
        if (link == null) return
        val state = PeerRules.state(text)
        if (way is PeerWay.Away) way = PeerWay.Away(state)
        // The server is on this network: home is better than a connection through the connector.
        if (state.path == "local") checkHomeSoon()
        if (state.connected) app.scope.launch { keepAddrs() }
    }

    // The server's addresses as the connector last learnt them replace the kept ones, for next time.
    private suspend fun keepAddrs() {
        val now = link ?: return
        val info = linkInfo ?: return
        val learnt = PeerRules.knownAddrs(withContext(Dispatchers.IO) { runCatching { now.knownAddrs() }.getOrDefault("[]") })
        if (learnt.isEmpty() || learnt == info.hints) return
        val next = info.copy(hints = learnt)
        linkInfo = next
        app.store.recent.firstOrNull { it.serverId.isNotEmpty() && info(it)?.serverId == info.serverId }?.let { keep(it, next.copy(port = PeerRoute.port)) }
    }

    // Every so often while away, and at once when asked: the server's own address, which wins if it proves its key.
    private fun watchHome(server: SavedServer) {
        watching?.cancel()
        watching = app.scope.launch {
            while (way is PeerWay.Away) {
                delay(PeerRules.HOME_EVERY_MS)
                if (homeAnswers(server)) goHome()
            }
        }
    }

    private fun checkHomeSoon() {
        val server = app.store.recent.firstOrNull { it.url == homeUrl } ?: return
        app.scope.launch { if (way is PeerWay.Away && homeAnswers(server)) goHome() }
    }

    private suspend fun homeAnswers(server: SavedServer): Boolean =
        !PeerRules.isAwayOnlyUrl(server.url) && identify(server.url, listOf(server)).state == IdentityState.Same

    private suspend fun goHome() {
        lock.withLock { shut() }
        way = PeerWay.Home
        ClientLog.info("network", "Back on the server's own address")
        onMoved?.invoke(homeUrl)
    }

    // A request to the local address failed: the network may have changed under it. At most every few seconds.
    private fun trouble() {
        val now = System.currentTimeMillis()
        if (now - lastTrouble < PeerRules.TROUBLE_EVERY_MS) return
        lastTrouble = now
        val current = link ?: return
        app.scope.launch(Dispatchers.IO) { runCatching { current.networkChanged() } }
        checkHomeSoon()
    }

    private fun watchNetwork() {
        // Android 7 and later say when the default network changes; on 6 a failed request is the only sign (trouble).
        if (android.os.Build.VERSION.SDK_INT < 24) return
        val connectivity = app.getSystemService(ConnectivityManager::class.java) ?: return
        var first = true
        runCatching {
            connectivity.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    // The first is the network there was when this started, not a change.
                    if (first) { first = false; return }
                    main.post(::networkChanged)
                }

                override fun onLost(network: Network) = main.post(::networkChanged).let { }
            })
        }
    }

    private fun networkChanged() {
        val current = link ?: return
        app.scope.launch(Dispatchers.IO) { runCatching { current.networkChanged() } }
        checkHomeSoon()
    }

    // MARK: leaving the screen and coming back

    // The app has left the screen. The system takes a background app's sockets, so the connection closes, unless
    // something is playing, which keeps the app running and needs the connection.
    fun appLeft(playing: Boolean) {
        if (way !is PeerWay.Away || playing) return
        suspended = true
        app.scope.launch { lock.withLock { closeLinkOnly() } }
    }

    // Back on the screen: the connection opens again on the port it had, with a new secret.
    fun appBack() {
        if (!suspended) {
            link?.let { current -> app.scope.launch(Dispatchers.IO) { runCatching { current.networkChanged() } } }
            return
        }
        suspended = false
        val server = app.store.recent.firstOrNull { it.url == homeUrl } ?: return
        app.scope.launch {
            if (homeAnswers(server)) {
                goHome()
                return@launch
            }
            val info = info(server) ?: return@launch
            val state = open(info.copy(port = PeerRoute.port), PeerRules.AWAY_WAIT_MS)
            if (state != null) settled(server, info, state) else way = PeerWay.Away(PeerState("offline"))
        }
    }

    // MARK: joining

    // From an invite link: connect to the server it names, show it the invite's secret, and get back a sign-in code
    // to redeem over the connection.
    suspend fun join(invite: PeerInvite): PeerAnswer? {
        val state = open(PeerInfo(invite.serverId, invite.hints), PeerRules.JOIN_WAIT_MS) ?: return null
        val current = link ?: return null
        val answer = withContext(Dispatchers.IO) {
            runCatching { PeerRules.answer(current.enrol(invite.secret, app.deviceName, app.platformName)) }.getOrElse { PeerAnswer(error = it.message.orEmpty()) }
        }
        way = PeerWay.Away(state)
        return answer.copy(serverId = invite.serverId, serverName = answer.serverName.ifEmpty { invite.name }, addrs = answer.addrs.ifEmpty { invite.hints })
    }

    // A code for a device that has never been at home with its server: someone signed in types it into the server.
    suspend fun newJoinCode(): String? = withContext(Dispatchers.IO) { runCatching { PeerLibrary.native?.newJoinCode() }.getOrNull() }

    // Waits for the server that is told the code, then connects to it. Null when the code ran out or was given up.
    suspend fun joinByCode(code: String): PeerAnswer? {
        val native = PeerLibrary.native ?: return null
        val key = deviceKey() ?: return null
        val joining = withContext(Dispatchers.IO) {
            native.setMemoryLimit(if (app.isTv) PeerRules.MEMORY_MB_TV else PeerRules.MEMORY_MB)
            runCatching { native.startJoin(PeerRules.joinConfiguration(key, code, app.deviceName, app.platformName)) }.getOrNull()
        } ?: return null
        val text: String? = try {
            suspendCancellableCoroutine<String?> { waiter ->
                waiter.invokeOnCancellation { joining.cancel() }
                Thread({
                    val result = runCatching { joining.await() }.getOrNull()
                    if (waiter.isActive) waiter.resumeWith(Result.success(result))
                }, "wittyconnect-join").start()
            }
        } catch (e: CancellationException) {
            joining.cancel()
            throw e
        }
        val answer = PeerRules.answer(text ?: return null)
        if (!answer.ok || answer.serverId.isEmpty()) return answer
        val state = open(PeerInfo(answer.serverId, answer.addrs), PeerRules.JOIN_WAIT_MS) ?: return answer.copy(ok = false, reason = "unreachable")
        way = PeerWay.Away(state)
        return answer
    }

    // A server joined from away, now in the list of servers under `server`: kept, and watched as any other.
    fun joined(server: SavedServer, answer: PeerAnswer) {
        prefs.edit().remove(offKeyOf(server)).apply()
        homeUrl = server.url
        val info = PeerInfo(answer.serverId, answer.addrs, PeerRoute.port)
        keep(server, info)
        (way as? PeerWay.Away)?.let { settled(server, info, it.state) }
    }

    // MARK: turning it off, and removing a server

    // "Stop connecting from away": off this server's list and no longer adding itself. Answers whether the app was
    // reaching the server from away, and so has lost it.
    suspend fun stopAway(server: SavedServer, token: String): Boolean {
        prefs.edit().putBoolean(offKeyOf(server), true).apply()
        val wasAway = way is PeerWay.Away && awayFor == info(server)?.serverId
        forgetAway(server, token)
        return wasAway
    }

    // "Connect from away again".
    fun startAway(server: SavedServer) {
        prefs.edit().remove(offKeyOf(server)).apply()
    }

    // This server's part: what was kept, its place on the server's list (best effort, with the sign-in it had), and
    // the connection if it was to it. The key goes when no server is kept for it any more.
    suspend fun forgetAway(server: SavedServer, token: String) {
        val info = info(server)
        prefs.edit().remove(keyOf(server)).apply()
        if (info != null && token.isNotEmpty()) {
            val id = deviceId()
            val base = if (awayFor == info.serverId && PeerRoute.active) PeerRoute.base else server.url
            if (id.isNotEmpty()) runCatching { withTimeoutOrNull(FORGET_MS) { Api(base, token, quick = true).p2pForget(id) } }
        }
        if (info != null && awayFor == info.serverId) {
            lock.withLock { shut() }
            way = PeerWay.None
        }
        if (!anyKept()) {
            prefs.edit().remove(KEY).apply()
            cachedId = null
        }
    }

    // Leaving a server (signing out of it, changing server): the connection to it goes; what was kept stays.
    fun leave() {
        watching?.cancel()
        app.scope.launch { lock.withLock { shut() } }
        way = PeerWay.None
    }

    // The system says memory is short.
    fun lowMemory() {
        if (link != null) app.scope.launch(Dispatchers.IO) { runCatching { PeerLibrary.native?.freeMemory() } }
    }

    // Under the lock.
    private suspend fun shut() {
        closeLinkOnly()
        PeerRoute.clear()
        awayFor = ""
        linkInfo = null
    }

    private suspend fun closeLinkOnly() {
        val current = link ?: return
        link = null
        withContext(Dispatchers.IO) { runCatching { current.close() } }
    }

    private companion object {
        const val KEY = "key"
        const val POLL_MS = 250L
        const val FORGET_MS = 5000L
    }
}
