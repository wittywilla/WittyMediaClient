package com.wittywilla.wittymediaclient

import android.app.Application
import android.app.UiModeManager
import android.content.pm.ApplicationInfo
import android.content.res.Configuration
import android.os.Build
import android.os.SystemClock
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
import com.wittywilla.wittymediaclient.player.Streaming
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

    // The controller last used, if the last thing pressed was on one.
    @Volatile
    var lastPad = -1

    // For work that must outlive the screen that started it.
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    // What's playing in the listening service, for the screens that show it.
    val listening by lazy { Listening(this) }

    // The current connection. Images use its client, so they carry the sign-in.
    @Volatile
    var api: Api = Api("", "")

    // The last speed test, for this server only, kept for Streaming.KEEP_MS.
    private var measured = Triple("", 0, 0L)

    // What to tell the server about this connection before a video, or null when robust doesn't apply.
    suspend fun measuredKbps(choice: String): Int? {
        val using = api
        val (base, kbps, at) = measured
        if (base == using.base && kbps > 0 && SystemClock.elapsedRealtime() - at < Streaming.KEEP_MS) return kbps
        val serverRemote = if (choice == Streaming.AUTO) runCatching { using.capabilities().playback.remoteStreaming }.getOrDefault("") else ""
        if (!Streaming.measures(choice, serverRemote)) return null
        val now = using.measureKbps() ?: return null
        measured = Triple(using.base, now, SystemClock.elapsedRealtime())
        return now
    }

    val isTv: Boolean by lazy {
        (getSystemService(UI_MODE_SERVICE) as UiModeManager).currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
    }

    // A Fire TV counts as a TV above, and only this says which store it has.
    val isFireTv: Boolean by lazy { packageManager.hasSystemFeature("amazon.hardware.fire_tv") }

    // How this device is named in the server's list of sign-ins.
    val deviceName: String get() = "${Build.MANUFACTURER} ${Build.MODEL}".take(60)
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
