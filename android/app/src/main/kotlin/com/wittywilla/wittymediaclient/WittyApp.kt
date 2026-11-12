// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import android.app.Application
import android.app.UiModeManager
import android.content.pm.ApplicationInfo
import android.content.res.Configuration
import android.os.Build
import android.webkit.WebView
import coil3.ImageLoader
import coil3.PlatformContext
import coil3.SingletonImageLoader
import coil3.disk.DiskCache
import coil3.memory.MemoryCache
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import coil3.request.crossfade
import com.wittywilla.wittymediaclient.data.SessionStore
import com.wittywilla.wittymediaclient.diag.ClientLog
import com.wittywilla.wittymediaclient.diag.ReportTarget
import com.wittywilla.wittymediaclient.net.Api
import com.wittywilla.wittymediaclient.player.Listening
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import okio.Path.Companion.toOkioPath

class WittyApp : Application(), SingletonImageLoader.Factory {
    val store by lazy { SessionStore(this) }

    // What a remote's Guide button does, while the app's screens are up.
    var onGuideKey: (() -> Unit)? = null

    // While the server's page is up, a controller's buttons are the page's to read.
    @Volatile
    var showingPage = false

    // A debug build only: an item put first in Home's hero, to check a title of one's choosing. See MainActivity.
    var pinnedHero = 0L

    // A title chosen on an Android TV's home screen, waiting for the app's screens to open it (data/TvHome.kt).
    var wantedRoute by mutableStateOf<String?>(null)

    // The controller last used, if the last thing pressed was on one.
    @Volatile
    var lastPad = -1

    // For work that must outlive the screen that started it.
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    // What's playing in the listening service, for the screens that show it.
    val listening by lazy { Listening(this) }

    // This app as a device other apps play on and steer, its remote for others, and its watch party (player/RemoteHub.kt).
    val remote by lazy { com.wittywilla.wittymediaclient.player.RemoteHub(this) }

    // Reaching the server from away, peer to peer (p2p/PeerManager.kt).
    val peers by lazy { com.wittywilla.wittymediaclient.p2p.PeerManager(this) }

    // The current connection. Images use its client, so they carry the sign-in.
    @Volatile
    var api: Api = Api("", "")

    val isTv: Boolean by lazy {
        (getSystemService(UI_MODE_SERVICE) as UiModeManager).currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
    }

    // A Fire TV counts as a TV above, and only this says which store it has.
    val isFireTv: Boolean by lazy { packageManager.hasSystemFeature("amazon.hardware.fire_tv") }

    // How this device is named in the server's list of sign-ins.
    val deviceName: String get() = "${Build.MANUFACTURER} ${Build.MODEL}".take(60)
    // This app's own name for this device in a profile's layout choice (docs/SDUI.md, Layout options): made once,
    // at random, letters and digits only, and nothing to do with the hardware.
    val layoutDeviceName: String by lazy {
        val prefs = getSharedPreferences("wms.device", MODE_PRIVATE)
        prefs.getString("name", null) ?: ("android-" + java.util.UUID.randomUUID().toString().replace("-", "").take(12)).also {
            prefs.edit().putString("name", it).apply()
        }
    }

    val platformName: String get() = if (isTv) "Android TV" else "Android"

    override fun onCreate() {
        super.onCreate()
        // Developer builds only: lets a computer look inside the server's page, as nothing else can.
        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) WebView.setWebContentsDebuggingEnabled(true)
        val version = runCatching { packageManager.getPackageInfo(packageName, 0).versionName }.getOrNull().orEmpty()
        // Reports go only to the server this app is signed in to.
        ClientLog.start(filesDir.resolve("logs"), "WittyMediaClient $platformName", version, "$deviceName, Android ${Build.VERSION.RELEASE}", scope) {
            val using = api
            if (using.base.isEmpty() || using.token.isEmpty()) null
            else ReportTarget(using.token) { body -> Api(using.base, using.token, quick = true).sendClientLog(body) }
        }
    }

    // Leaving a server or an account takes its pictures along: the next person on this device
    // shouldn't see what was on someone else's server.
    fun forgetImages() {
        val loader = SingletonImageLoader.get(this)
        loader.memoryCache?.clear()
        loader.diskCache?.clear()
    }

    // Small bounded caches: a TV stick has little memory to spare.
    override fun newImageLoader(context: PlatformContext): ImageLoader =
        ImageLoader.Builder(context)
            .components { add(OkHttpNetworkFetcherFactory(callFactory = { api.http })) }
            .memoryCache { MemoryCache.Builder().maxSizePercent(context, 0.15).build() }
            .diskCache {
                DiskCache.Builder()
                    .directory(cacheDir.resolve("images").toOkioPath())
                    .maxSizeBytes(100L * 1024 * 1024)
                    .build()
            }
            .crossfade(false)
            .build()
}
