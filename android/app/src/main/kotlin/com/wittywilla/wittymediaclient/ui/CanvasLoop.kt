// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import android.app.ActivityManager
import android.content.Context
import android.graphics.Matrix
import android.net.ConnectivityManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.view.TextureView
import androidx.annotation.OptIn
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.derivedStateOf
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import com.wittywilla.wittymediaclient.net.Api
import com.wittywilla.wittymediaclient.net.CanvasInfo
import com.wittywilla.wittymediaclient.net.ExtrasFeature
import com.wittywilla.wittymediaclient.net.canvas
import com.wittywilla.wittymediaclient.player.CanvasConditions
import com.wittywilla.wittymediaclient.player.CanvasRules
import com.wittywilla.wittymediaclient.player.ExtrasPrefs
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.Request
import java.io.File
import java.io.IOException

// A canvas: the short silent video the server has for a song or a title, looping behind its artwork on Now Playing, an
// album's page and a title's page. It is drawn over the still picture and under the page's own shade, so the page
// reads as it did before, and when it can't or shouldn't play (CanvasRules) the still picture is simply all there is.
//
// There is one small player for the whole app, made when a canvas comes on screen and released when it leaves, scrolls
// away or the app goes to the background. The file is fetched once with the app's own connection (so the sign-in is
// never in an address) and looped from this device, which is what makes the loop seamless and costs the network once.

// What the server said about each item's canvas lately, and the files kept: a few of each, never more.
private object CanvasShelf {
    private const val ASK_AGAIN_MS = 2 * 60 * 1000L
    private const val INFOS_KEPT = 48
    private const val FILES_KEPT = 4

    private class Known(val info: CanvasInfo, val at: Long)

    private val infos = object : LinkedHashMap<String, Known>(16, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Known>?) = size > INFOS_KEPT
    }

    suspend fun info(api: Api, id: Long, fresh: Boolean): CanvasInfo? {
        val key = "${api.base}|$id"
        val now = System.currentTimeMillis()
        if (!fresh) synchronized(infos) { infos[key] }?.takeIf { now - it.at < ASK_AGAIN_MS }?.let { return it.info }
        val found = try {
            api.canvas(id)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            return null
        }
        synchronized(infos) { infos[key] = Known(found, now) }
        return found
    }

    // The canvas as a file on this device, fetched if it isn't here yet. Null when it can't be had: the still stays.
    suspend fun file(context: Context, api: Api, id: Long, info: CanvasInfo): File? = withContext(Dispatchers.IO) {
        val dir = File(context.cacheDir, "canvas")
        // Another server's or another person's file is never this one's, whatever the item's number.
        val whose = (api.base + "|" + api.token).hashCode().toUInt().toString(36)
        val kept = File(dir, "$whose-${CanvasRules.fileName(id, info.url)}")
        if (kept.isFile && kept.length() > 0) {
            kept.setLastModified(System.currentTimeMillis())
            return@withContext kept
        }
        val partial = File(dir, kept.name + ".part")
        try {
            dir.mkdirs()
            val url = api.mediaUrl(info.url)
            api.http.newCall(Request.Builder().url(url).build()).execute().use { res ->
                if (!res.isSuccessful) throw IOException("The canvas wasn't sent (${res.code}).")
                if (res.body.contentLength() > CanvasRules.MAX_BYTES) throw IOException("The canvas is too big.")
                partial.outputStream().use { out ->
                    val source = res.body.byteStream()
                    val buffer = ByteArray(64 * 1024)
                    var total = 0L
                    while (true) {
                        val n = source.read(buffer)
                        if (n < 0) break
                        total += n
                        if (total > CanvasRules.MAX_BYTES) throw IOException("The canvas is too big.")
                        out.write(buffer, 0, n)
                    }
                }
            }
            if (partial.length() == 0L || !partial.renameTo(kept)) throw IOException("The canvas couldn't be kept.")
            dir.listFiles()?.filter { it != kept }?.sortedByDescending { it.lastModified() }?.drop(FILES_KEPT - 1)?.forEach { it.delete() }
            kept
        } catch (e: CancellationException) {
            partial.delete()
            throw e
        } catch (_: Exception) {
            partial.delete()
            null
        }
    }

    fun forget(api: Api, id: Long) {
        synchronized(infos) { infos.remove("${api.base}|$id") }
    }
}

// An administrator had a new canvas made for this item: ask the server again next time, not what was said before.
fun forgetCanvas(nav: Nav, id: Long) = CanvasShelf.forget(nav.app.api, id)

// The one player. Whoever comes on screen takes it, and the one before is released first. Main thread only.
@OptIn(UnstableApi::class)
private object CanvasStage {
    private var player: ExoPlayer? = null
    private var owner: Any? = null

    fun take(who: Any, context: Context): ExoPlayer {
        player?.release()
        // A few seconds of a small video: little is buffered, and its sound, if it has any, is never decoded.
        val load = DefaultLoadControl.Builder().setBufferDurationsMs(1_000, 4_000, 250, 500).setTargetBufferBytes(4 * 1024 * 1024).build()
        val made = ExoPlayer.Builder(context.applicationContext).setLoadControl(load).build()
        made.trackSelectionParameters = made.trackSelectionParameters.buildUpon().setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, true).build()
        made.volume = 0f
        made.repeatMode = Player.REPEAT_MODE_ONE
        player = made
        owner = who
        return made
    }

    // Only the player this one was given: a newer one, taken since, is someone else's to release.
    fun leave(who: Any, given: ExoPlayer) {
        if (owner !== who || player !== given) return
        given.release()
        player = null
        owner = null
    }
}

private fun conditions(context: Context, nav: Nav, reduceMotion: Boolean): CanvasConditions {
    val power = context.getSystemService(PowerManager::class.java)
    val network = context.getSystemService(ConnectivityManager::class.java)
    val memory = context.getSystemService(ActivityManager::class.java)
    return CanvasConditions(
        serverHas = nav.has(ExtrasFeature.CANVAS),
        wanted = ExtrasPrefs.load(context).canvas,
        batterySaver = power?.isPowerSaveMode == true,
        dataSaver = Build.VERSION.SDK_INT >= 24 && runCatching { network?.restrictBackgroundStatus == ConnectivityManager.RESTRICT_BACKGROUND_STATUS_ENABLED }.getOrDefault(false),
        metered = runCatching { network?.isActiveNetworkMetered == true }.getOrDefault(false),
        awayFromHome = CanvasRules.awayFromHome(nav.app.api.base),
        reduceMotion = reduceMotion,
        lowRam = memory?.isLowRamDevice == true,
        filmPlaying = nav.video != null,
    )
}

// The canvas for an item, filling the place it's given, or nothing at all. Put it over the still artwork and under
// whatever shades the artwork: it draws nothing until its first frame is ready, then fades in. `again` is bumped to ask
// the server afresh, after an administrator has had one made.
@Composable
fun CanvasBackdrop(nav: Nav, itemId: Long, modifier: Modifier = Modifier, again: Int = 0) {
    if (itemId <= 0) return
    val context = LocalContext.current
    val reduceMotion = LocalReduceMotion.current
    // Battery saver, the network and the person's switch are read when this comes up and each time the app comes back.
    var looked by remember { mutableIntStateOf(0) }
    var foreground by remember { mutableStateOf(true) }
    LifecycleEventEffect(Lifecycle.Event.ON_START) { foreground = true; looked++ }
    LifecycleEventEffect(Lifecycle.Event.ON_STOP) { foreground = false }
    val has = nav.has(ExtrasFeature.CANVAS)
    val film = nav.video != null
    val allowed = remember(looked, has, film, reduceMotion) { CanvasRules.blocked(conditions(context, nav, reduceMotion)) == null }
    var file by remember(itemId) { mutableStateOf<File?>(null) }
    LaunchedEffect(itemId, allowed, again) {
        file = null
        if (!allowed) return@LaunchedEffect
        val api = nav.app.api
        val info = CanvasShelf.info(api, itemId, fresh = again > 0) ?: return@LaunchedEffect
        if (CanvasRules.playable(info)) file = CanvasShelf.file(context, api, itemId, info)
    }
    // Scrolled off the screen is as good as gone: the decoder is given back.
    var onScreen by remember { mutableStateOf(true) }
    Box(modifier.onGloballyPositioned { onScreen = it.boundsInWindow().let { b -> b.width > 1f && b.height > 1f } }.clearAndSetSemantics { }) {
        val playing = file
        if (allowed && foreground && onScreen && playing != null) CanvasVideo(playing)
    }
}

// The canvas as a band across the top of a page whose artwork is a cover rather than a backdrop (an album): faint, and
// fading into the page below. `scrolled` says how far the page has moved, in pixels, so the band goes with it, or
// null once its place has scrolled away, which gives the decoder back.
@Composable
fun CanvasBanner(nav: Nav, itemId: Long, modifier: Modifier = Modifier, scrolled: () -> Int? = { 0 }) {
    val gone by remember { derivedStateOf { scrolled() == null } }
    if (gone) return
    val page = MaterialTheme.colorScheme.background
    Box(modifier.fillMaxWidth().height(BANNER_HEIGHT).graphicsLayer { translationY = -(scrolled() ?: 0).toFloat() }) {
        CanvasBackdrop(nav, itemId, Modifier.fillMaxSize().graphicsLayer { alpha = BANNER_STRENGTH })
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0.2f to Color.Transparent, 1f to page)))
    }
}

@OptIn(UnstableApi::class)
@Composable
private fun CanvasVideo(file: File) {
    val context = LocalContext.current
    val who = remember { Any() }
    var shown by remember(file) { mutableStateOf(false) }
    var failed by remember(file) { mutableStateOf(false) }
    var picture by remember(file) { mutableStateOf(VideoSize.UNKNOWN) }
    if (failed) return
    val player = remember(file) {
        CanvasStage.take(who, context).apply {
            setMediaItem(MediaItem.fromUri(Uri.fromFile(file)))
            prepare()
            playWhenReady = true
        }
    }
    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onRenderedFirstFrame() { shown = true }
            override fun onVideoSizeChanged(videoSize: VideoSize) { picture = videoSize }
            // A file this device can't decode: the still artwork is what there is, and the file isn't tried again.
            override fun onPlayerError(error: PlaybackException) {
                failed = true
                file.delete()
            }
        }
        player.addListener(listener)
        onDispose {
            player.removeListener(listener)
            CanvasStage.leave(who, player)
        }
    }
    val alpha by animateFloatAsState(if (shown) 1f else 0f, tween(FADE_MS), label = "canvas")
    fun fit(view: TextureView) {
        val (x, y) = CanvasRules.coverScale(view.width, view.height, picture.width, picture.height)
        view.setTransform(Matrix().apply { setScale(x, y, view.width / 2f, view.height / 2f) })
    }
    AndroidView(
        factory = { made ->
            TextureView(made).apply {
                isOpaque = false
                addOnLayoutChangeListener { v, _, _, _, _, _, _, _, _ -> fit(v as TextureView) }
            }
        },
        update = { view ->
            player.setVideoTextureView(view)
            fit(view)
        },
        onRelease = { view -> runCatching { player.clearVideoTextureView(view) } },
        modifier = Modifier.fillMaxSize().graphicsLayer { this.alpha = alpha },
    )
}

private const val FADE_MS = 500
private const val BANNER_STRENGTH = 0.4f
private val BANNER_HEIGHT = 340.dp
