// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.data

import android.webkit.CookieManager
import android.webkit.WebStorage
import com.wittywilla.wittymediaclient.WittyApp
import com.wittywilla.wittymediaclient.diag.ClientLog
import com.wittywilla.wittymediaclient.net.Api
import com.wittywilla.wittymediaclient.net.Identity
import com.wittywilla.wittymediaclient.net.identify
import com.wittywilla.wittymediaclient.player.ViewPrefsStore
import com.wittywilla.wittymediaclient.tv.LastChannel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import java.io.File

// A server that was just removed from this device, with what Undo needs to put it back. Held in memory only.
class Forgotten internal constructor(
    val server: SavedServer,
    internal val plan: ForgetPlan,
    internal val taken: TakenOut,
    internal val logos: Map<String, ByteArray>,
    // The sign-in that was this server's, so it can be ended on the server once the removal stands.
    internal val signIn: SignIn?,
)

// Removing a server from this device: the one way it's done, whichever screen asks. Everything this app holds
// for that server goes, and nothing of any other server. What goes, and from where:
//
//   settings "session"   its entry in the list; the address in use and the sealed sign-in, when they're its own;
//                        its theme choice, its top menu for every profile, and its themes as last read
//   cache "logos"        its own logo
//   cache "images"       the pictures of the server last used, when that's the one removed (the others' were
//                        already cleared when they were left: see Nav.forgetScreens)
//   cache "booklets"     PDFs fetched to hand to a reader app; they're fetched again every time, for any server
//   web view             its cookies and what its pages stored
//   on the server        the sign-in is ended there too, once Undo is no longer offered
//
// Two things are kept by a video's or channel's number (settings "wms.view" for a video's own picture settings,
// "wittytv" for the last channel): under the server's tag, so they go with it; the untagged ones from before go
// when the last server does. The sound
// settings, the streaming choice, WittyPlay's device name and the app's own log are this device's, and stay.
object ForgetServer {
    private const val SIGN_OUT_MS = 3000L

    // The first half, which Undo can take back: nothing has left the device yet.
    fun forget(app: WittyApp, server: SavedServer): Forgotten {
        val store = app.store
        val signIn = store.signIn
        // A sign-in that can't be read any more still goes with its server.
        val pin = signIn?.pin ?: if (store.hasSignIn) "" else null
        val plan = planForget(server, store.recent, store.server, pin, store.names)
        val taken = store.takeOut(plan)
        val logos = HashMap<String, ByteArray>()
        plan.urls.forEach { logos += LogoCache.forget(app, it) }
        ClientLog.info("app", "A server was removed from this device")
        return Forgotten(server, plan, taken, logos, if (plan.forgetSignIn) signIn else null)
    }

    fun undo(app: WittyApp, gone: Forgotten) {
        app.store.putBack(gone.plan, gone.taken)
        LogoCache.putBack(app, gone.logos)
    }

    // The second half, when the removal stands: what can't be put back goes, and the server is told to end the
    // sign-in. That is best effort and waits for nothing: a server that's gone is the usual reason to remove it.
    fun finish(app: WittyApp, gone: Forgotten) {
        if (gone.plan.wasCurrent) app.forgetImages()
        runCatching { File(app.cacheDir, "booklets").deleteRecursively() }
        gone.plan.urls.forEach { forgetWeb(app, it) }
        val tags = gone.plan.removed.flatMap(::serverTags).distinct()
        ViewPrefsStore.forgetServer(app, tags)
        LastChannel.forgetServer(app, tags)
        if (app.store.recent.isEmpty() && app.store.server.isEmpty()) {
            ViewPrefsStore.forgetVideos(app)
            LastChannel.forget(app)
        }
        forgetPeerToPeer(app, gone.server, gone.signIn)
        val signIn = gone.signIn?.takeIf { it.token.isNotEmpty() } ?: return
        val url = gone.taken.current.ifEmpty { gone.server.url }
        app.scope.launch { withTimeoutOrNull(SIGN_OUT_MS) { signOutThere(url, signIn) } }
    }

    // The token only goes to the machine it was made for, as everywhere else: it proves its key first.
    private suspend fun signOutThere(url: String, signIn: SignIn) {
        val proof = identify(url, listOf(SavedServer(url, "", publicKey = signIn.pin)))
        if (!Identity.fits(signIn.pin, proof)) return
        runCatching { Api(url, signIn.token, quick = true).logout() }
    }

    // The server's pages are shown in a web view, which keeps cookies and storage by address. The app clears all
    // of it whenever a page closes, so this only finds something after a crash. A device that has never shown a
    // page has nothing, and isn't made to load its web view to find that out.
    private fun forgetWeb(app: WittyApp, url: String) {
        if (!File(app.applicationInfo.dataDir, "app_webview").exists()) return
        runCatching {
            val cookies = CookieManager.getInstance()
            cookies.getCookie(url).orEmpty().split(';').map { it.substringBefore('=').trim() }.filter { it.isNotEmpty() }
                .forEach { cookies.setCookie(url, "$it=; Max-Age=0; Path=/") }
            cookies.flush()
            WebStorage.getInstance().deleteOrigin(url)
        }
    }

    // Peer-to-peer data for this server: what was kept for reaching it from away, this device's place on its list
    // (with the sign-in it had, best effort), and the connection if it was to it (p2p/PeerManager.kt).
    private fun forgetPeerToPeer(app: WittyApp, server: SavedServer, signIn: SignIn?) {
        app.scope.launch { app.peers.forgetAway(server, signIn?.token.orEmpty()) }
    }
}
