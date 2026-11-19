// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.player

import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.edit
import com.wittywilla.wittymediaclient.WittyApp
import com.wittywilla.wittymediaclient.diag.ClientLog
import com.wittywilla.wittymediaclient.net.Api
import com.wittywilla.wittymediaclient.net.ApiError
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.Request
import java.io.File
import java.io.IOException
import kotlin.math.abs

// Karaoke from a song's separated parts, on a server that makes them (`karaoke-auto`): asks the server as the rules
// say (KaraokeMachine), fetches the parts into the app's cache, and plays them through one mixer (StemMixer) kept in
// step with the music player, which carries on unheard as the clock: the place in the song, the words, the
// notification and the lock screen are all still its own. All on the main thread but the fetching and the mixer.
class KaraokeStems(private val app: WittyApp, private val listening: Listening, private val prefs: () -> SharedPreferences) {
    var state by mutableStateOf<KaraokeState>(KaraokeState.Idle)
        private set
    var controls by mutableStateOf(KaraokeControls())
        private set

    // The parts are what's being heard, and the music player is silent (ListeningKeeper.applyVolume).
    var playing by mutableStateOf(false)
        private set

    val answer: KaraokeAnswer? get() = (state as? KaraokeState.Ready)?.answer

    private var machine = KaraokeMachine()
    private var open = false
    private var levelsKey = ""
    private var asking: Job? = null
    private var loading: Job? = null
    private var watching: Job? = null
    private var mixer: StemMixer? = null
    private var mixing: KaraokeAnswer? = null
    private var soughtAt = 0L

    // How far ahead of the player the mixer is asked to be, learnt from how far behind it turned out.
    private var leadUs = 0L
    private val folder: File get() = File(app.cacheDir, "karaoke")

    // Karaoke has opened, for this profile on this server. Sing starts off; the levels are that profile's.
    fun open(profile: Long) {
        open = true
        levelsKey = KaraokeLevels.key(app.api.base, profile)
        controls = KaraokeControls(KaraokeLevels.read(prefs().getString(levelsKey, null)))
        songIs(listening.now?.mediaId)
    }

    fun close() {
        open = false
        send(KaraokeEvent.Close)
    }

    // The app has left the screen, or the player has gone: the normal track is heard until it's back.
    fun away() {
        if (machine.state != KaraokeState.Idle) send(KaraokeEvent.Close)
    }

    // What's playing, said whenever the player says anything. Another song starts over.
    fun songIs(mediaId: String?) {
        if (!open) return
        val song = mediaId?.toLongOrNull() ?: 0
        if (song == machine.song && machine.state != KaraokeState.Idle) return
        if (song <= 0) {
            if (machine.state != KaraokeState.Idle) send(KaraokeEvent.Close)
        } else send(KaraokeEvent.Open(song))
    }

    fun setVocals(level: Double) = change(controls.moveVocals(level))

    fun setLevel(id: String, level: Double) {
        change(controls.move(id, level))
    }

    fun toggleSing() = change(controls.toggleSing(), keep = false)

    fun reset() = change(controls.reset())

    private fun change(next: KaraokeControls, keep: Boolean = true) {
        controls = next
        if (keep && levelsKey.isNotEmpty()) prefs().edit { putString(levelsKey, next.levels.toJson()) }
        sync()
    }

    // The player's playing or paused, its speed, the key, the volume, and the levels: all passed on to the mixer.
    fun sync() {
        val mixer = mixer ?: return
        val answer = mixing ?: return
        val sound = listening.sound
        val volume = if (sound.muted) 0.0 else sound.volume
        mixer.gains = KaraokeMix.gains(answer, controls).map { (it * volume).toFloat() }.toFloatArray()
        mixer.speed = listening.speed
        mixer.pitch = listening.pitch
        mixer.play(listening.isPlaying)
    }

    // The player has jumped: a seek, or the song starting again.
    fun jumped() = follow()

    private fun follow() {
        val mixer = mixer ?: return
        soughtAt = System.nanoTime()
        mixer.seekTo((listening.positionSec() * 1_000_000).toLong() + leadUs, listening.isPlaying, listening.speed)
    }

    private fun send(event: KaraokeEvent) {
        val (next, effects) = machine.on(event)
        machine = next
        state = next.state
        effects.forEach {
            when (it) {
                is KaraokeEffect.Ask -> ask(it)
                is KaraokeEffect.Load -> load(it.answer)
                KaraokeEffect.Unload -> unload()
            }
        }
    }

    private fun ask(how: KaraokeEffect.Ask) {
        val song = machine.song
        val api = app.api
        asking?.cancel()
        asking = app.scope.launch {
            delay(how.afterSec * 1000L)
            val event = try {
                val text = if (how.prepare) api.karaokePrepare(song) else api.karaoke(song)
                KaraokeAnswer.parse(text)?.let { KaraokeEvent.Answered(it) } ?: KaraokeEvent.Failed("", lasting = false)
            } catch (e: CancellationException) {
                throw e
            } catch (e: ApiError) {
                // A refusal is the answer; a server in trouble, or one asking for patience, is asked again.
                KaraokeEvent.Failed(e.message.orEmpty(), lasting = e.status in 400..499 && e.status != 408 && e.status != 429)
            } catch (e: Exception) {
                KaraokeEvent.Failed("", lasting = false)
            }
            if (machine.song == song && api === app.api) send(event)
        }
    }

    private fun load(answer: KaraokeAnswer) {
        val song = machine.song
        val api = app.api
        loading?.cancel()
        loading = app.scope.launch {
            val into = File(folder, "$song-${System.nanoTime()}")
            val files = try {
                fetch(api, answer, into)
            } catch (e: CancellationException) {
                withContext(Dispatchers.IO + kotlinx.coroutines.NonCancellable) { into.deleteRecursively() }
                throw e
            } catch (e: Exception) {
                ClientLog.warn("karaoke", "Karaoke's parts couldn't be fetched: ${e.javaClass.simpleName}")
                withContext(Dispatchers.IO) { into.deleteRecursively() }
                if (machine.song == song) send(KaraokeEvent.StemsFailed(if (e is TooLarge) KaraokeMachine.TOO_LARGE else ""))
                return@launch
            }
            if (machine.song != song) return@launch
            // Better parts take over from the ones playing where the song is; the player never stops.
            val before = mixer
            before?.stop()
            val made = StemMixer(files, ::mixerFailed)
            mixer = made
            mixing = answer
            sync()
            follow()
            made.start()
            if (!playing) {
                playing = true
                // The old way of turning the voice down has nothing to work on now.
                listening.setSound { it.copy(vocalCut = 0.0) }
                listening.keeper?.soundChanged(levelingChanged = false)
            }
            watch()
            withContext(Dispatchers.IO) { folder.listFiles()?.forEach { if (it != into) it.deleteRecursively() } }
        }
    }

    // On the mixer's thread: a part that wouldn't open or decode, or an output that wouldn't play.
    private fun mixerFailed(from: StemMixer, why: String) {
        app.scope.launch {
            if (mixer !== from) return@launch
            ClientLog.warnSeldom("karaoke", "Karaoke's parts stopped: $why", key = "stopped")
            send(KaraokeEvent.StemsFailed(""))
        }
    }

    // Every two seconds: more than 80 ms apart from the player, and the mixer goes to where the player is.
    private fun watch() {
        watching?.cancel()
        watching = app.scope.launch {
            while (true) {
                delay(WATCH_MS)
                val at = mixer?.positionUs ?: break
                if (at < 0 || !listening.isPlaying || System.nanoTime() - soughtAt < SETTLE_NS) continue
                val apart = at - (listening.positionSec() * 1_000_000).toLong()
                if (abs(apart) > APART_US) {
                    leadUs = (leadUs - apart).coerceIn(-MOST_LEAD_US, MOST_LEAD_US)
                    follow()
                }
            }
        }
    }

    private fun unload() {
        loading?.cancel()
        loading = null
        watching?.cancel()
        watching = null
        asking?.cancel()
        asking = null
        val had = mixer != null || folder.exists()
        mixer?.stop()
        mixer = null
        mixing = null
        leadUs = 0
        if (playing) {
            playing = false
            listening.keeper?.soundChanged(levelingChanged = false)
            listening.stemsStopped()
        }
        if (had) app.scope.launch(Dispatchers.IO) {
            // Not under a load that has started since.
            if (loading == null) folder.deleteRecursively()
        }
    }

    private class TooLarge : IOException()

    // The parts, into the app's cache, with the app's own sign-in: no more than 400 MB between them.
    private suspend fun fetch(api: Api, answer: KaraokeAnswer, into: File): List<File> = withContext(Dispatchers.IO) {
        into.mkdirs()
        var total = 0L
        val chunk = ByteArray(64 * 1024)
        answer.playable.mapIndexed { index, stem ->
            val file = File(into, "$index")
            val call = api.http.newCall(Request.Builder().url(api.mediaUrl(stem.url)).build())
            val stop = coroutineContext.job.invokeOnCompletion { call.cancel() }
            try {
                call.execute().use { res ->
                    if (!res.isSuccessful) throw IOException("a part answered ${res.code}")
                    val body = res.body ?: throw IOException("a part came empty")
                    if (total + body.contentLength() > MOST_BYTES) throw TooLarge()
                    body.byteStream().use { from ->
                        file.outputStream().use { to ->
                            while (true) {
                                coroutineContext.ensureActive()
                                val read = from.read(chunk)
                                if (read < 0) break
                                total += read
                                if (total > MOST_BYTES) throw TooLarge()
                                to.write(chunk, 0, read)
                            }
                        }
                    }
                }
            } finally {
                stop.dispose()
            }
            file
        }
    }

    private companion object {
        const val MOST_BYTES = 400L * 1024 * 1024
        const val WATCH_MS = 2000L
        const val SETTLE_NS = 1_500_000_000L
        const val APART_US = 80_000L
        const val MOST_LEAD_US = 300_000L
    }
}
