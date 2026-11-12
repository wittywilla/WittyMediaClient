// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.player

import android.app.Activity
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.edit
import com.wittywilla.wittymediaclient.WittyApp
import com.wittywilla.wittymediaclient.net.Api
import com.wittywilla.wittymediaclient.net.remote.PlayOnSource
import com.wittywilla.wittymediaclient.net.remote.RemoteInfo
import com.wittywilla.wittymediaclient.net.remote.RemoteQueue
import com.wittywilla.wittymediaclient.net.remote.announcedCapabilities
import com.wittywilla.wittymediaclient.net.remote.deviceKind
import com.wittywilla.wittymediaclient.net.remote.remoteInfo
import com.wittywilla.wittymediaclient.net.remote.trackId
import com.wittywilla.wittymediaclient.net.syncplay.Room
import com.wittywilla.wittymediaclient.net.syncplay.RoomSummary
import com.wittywilla.wittymediaclient.net.syncplay.SyncInfo
import com.wittywilla.wittymediaclient.net.syncplay.keepsInStep
import com.wittywilla.wittymediaclient.net.syncplay.nowKind
import com.wittywilla.wittymediaclient.net.syncplay.roomPositionSec
import com.wittywilla.wittymediaclient.net.syncplay.syncInfo
import com.wittywilla.wittymediaclient.ui.Nav
import com.wittywilla.wittymediaclient.ui.Route
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.lang.ref.WeakReference

// Where the server's Remote Protocol and its watch parties meet this app: one object the app owns, which keeps it
// announced as a device (RemoteDevice.kt), knows which video player is the app's own at the moment (VideoTarget.kt),
// answers commands on it and on the music (RemotePlayers.kt), and holds the watch party this device is in
// (WatchParty.kt). Everything it starts runs in the app's scope and is cancelled when the sign-in ends.

const val REMOTE_FEATURE = "remote-protocol"
const val SYNCPLAY_FEATURE = "syncplay"

class RemoteHub(internal val app: WittyApp) {
    private val scope = app.scope
    private val prefs by lazy { app.getSharedPreferences("remote", Context.MODE_PRIVATE) }

    // The app's state and screens, once they are up (AppRoot hands them over).
    internal var nav: Nav? = null
        private set
    private var activity = WeakReference<Activity>(null)

    val device = RemoteDeviceHost(scope, { app.api }, HubPlayers(this))
    val party = PartySession(app, scope) { app.api }

    // The owner has remote control on: this app announces itself. Until asked, nothing is offered.
    var remoteOn by mutableStateOf(false)
        private set
    // And this profile may play on and steer other devices: the picker and the remote.
    var canControl by mutableStateOf(false)
        private set
    var info by mutableStateOf<RemoteInfo?>(null)
        private set
    // "Let other devices control this one", on this device. On until turned off.
    var letOthers by mutableStateOf(true)
        private set
    // A line for the person that isn't a failure of the screen in front of them: "Now playing on Den".
    var notice by mutableStateOf("")
    // Invitations to watch parties that haven't been answered here.
    val invitations = mutableStateListOf<RoomSummary>()

    // Whether the app is on screen. Behind other apps the channel is held only while music plays.
    var inFront = true
        private set

    private var token = ""
    private var features: Set<String> = emptySet()
    private var learning: Job? = null
    private var leaving: Job? = null
    private var invitesJob: Job? = null
    private val declined = HashSet<String>()

    // The video player the app has now, and where a video opened for a command or a party is to start.
    var video by mutableStateOf<VideoTarget?>(null)
        private set
    private val presets = HashMap<Long, PlaybackPreset>()
    // The queue another device gave this one for videos; music keeps its own in the listening service.
    internal var videoQueue: RemoteQueue? = null
    // A video's volume before a controller muted it: ExoPlayer has no mute of its own.
    internal var mutedLevel: Float? = null
    var follower by mutableStateOf<PartyFollower?>(null)
        private set
    private var followerGone: Job? = null

    val hasRemote: Boolean get() = REMOTE_FEATURE in features && remoteOn
    val hasParties: Boolean get() = SYNCPLAY_FEATURE in features && party.info?.let { it.enabled && it.canJoin } == true

    // This device's id as a device, while it is one and connected: what a hand-over names as where it comes from.
    val deviceId: String get() = if (device.online) device.deviceId else ""

    init {
        letOthers = prefs.getBoolean(KEY_LET_OTHERS, true)
        party.onRoom = ::partyChanged
        party.onOver = ::partyOver
    }

    fun attach(nav: Nav, activity: Activity?) {
        this.nav = nav
        this.activity = WeakReference(activity)
    }

    internal val currentActivity: Activity? get() = activity.get()

    // MARK: the session

    // Called whenever who is signed in changes, and when the server's features are known.
    fun session(signedIn: Boolean, features: Set<String>) {
        val api = app.api
        val now = if (signedIn) api.token else ""
        if (now != token) {
            val old = token
            if (old.isNotEmpty()) goodbye(Api(api.base, old))
            token = now
            remoteOn = false
            canControl = false
            info = null
            party.info = null
            invitations.clear()
            declined.clear()
        }
        this.features = features
        learning?.cancel()
        if (token.isEmpty()) {
            syncDevice()
            watchInvitations()
            return
        }
        val asking = token
        learning = scope.launch {
            // The last sign-in's goodbye first, or it would take this one's device with it.
            leaving?.join()
            learn(asking)
        }
    }

    private suspend fun learn(asking: String) {
        val api = app.api
        if (REMOTE_FEATURE in features && info == null) {
            val found = runCatching { api.remoteInfo() }.getOrNull()
            if (token != asking) return
            info = found
            remoteOn = found?.enabled == true
            canControl = remoteOn && found?.canControl != false
        }
        syncDevice()
        if (SYNCPLAY_FEATURE in features && party.info == null) {
            val found = runCatching { api.syncInfo() }.getOrNull()
            if (token != asking) return
            party.info = found
            if (found != null && found.enabled && found.canJoin) {
                party.comeBack(found)
                noticeInvitations(found)
            }
        }
        watchInvitations()
    }

    // The server's word on watch parties, asked again as a screen about them opens: the rooms change.
    suspend fun refreshParties(): SyncInfo? {
        if (SYNCPLAY_FEATURE !in features || token.isEmpty()) return null
        runCatching { app.api.syncInfo() }.getOrNull()?.let {
            party.info = it
            noticeInvitations(it)
        }
        return party.info
    }

    fun chooseLetOthers(on: Boolean) {
        letOthers = on
        prefs.edit { putBoolean(KEY_LET_OTHERS, on) }
        if (on) syncDevice() else scope.launch { device.stop(forget = true) }
    }

    // The app came to the front, or went behind others.
    fun foreground(front: Boolean) {
        inFront = front
        syncDevice()
        watchInvitations()
        if (front) follower?.roomChanged()
    }

    // Music playing behind other apps keeps the channel, as the listening service keeps the app.
    fun listeningChanged() {
        if (!inFront) syncDevice()
    }

    // Whether the listening service's player is to be kept heard while the app is behind others: while it plays and
    // this device answers commands for it.
    val holdsListening: Boolean get() = device.running && app.listening.isPlaying

    // Starts or stops being a device, by everything that decides it.
    fun syncDevice() {
        val limits = info?.limits
        val wanted = token.isNotEmpty() && hasRemote && letOthers && (inFront || app.listening.isPlaying)
        if (wanted && limits != null) {
            val kind = deviceKind(app.isTv, tablet = app.resources.configuration.smallestScreenWidthDp >= TABLET_DP)
            device.start(app.deviceName, kind, announcedCapabilities(app.isTv), limits)
        } else if (device.running) {
            scope.launch {
                device.stop(forget = false)
                // Nothing here answers for the music any more, so nothing need hear it in the background.
                if (!inFront) app.listening.remoteReleased()
            }
        }
    }

    // Signing out, switching profile or leaving the server: the device says goodbye and the party's seat is let go,
    // before the sign-in ends. The job finishes when the goodbye has been said.
    fun goodbye(using: Api = app.api): Job {
        leaving?.let { if (it.isActive) return it }
        detachFollower()
        party.drop()
        invitations.clear()
        val job = scope.launch { device.stop(forget = true, using = using) }
        leaving = job
        return job
    }

    // MARK: words for the person

    fun say(words: String) {
        if (words.isNotEmpty()) notice = words
    }

    // MARK: the app's own video player

    // Every video player the app makes passes through here as it opens: it takes the place a command or a party chose
    // for it, and a party that is playing this very item starts steering it.
    fun takePreset(id: Long): PlaybackPreset? = presets.remove(id).also { presets.clear() }

    fun adopt(target: VideoTarget) {
        video = target
        mutedLevel = null
        videoQueue = videoQueue?.movedTo(target.itemId)
        ensureFollower()
        device.reportSoon()
    }

    fun released(target: VideoTarget) {
        if (video !== target) return
        video = null
        mutedLevel = null
        val ending = follower?.takeIf { it.target === target }
        if (ending != null) {
            ending.stop()
            follower = null
            followerEnded(ending)
        }
        device.reportSoon()
    }

    // Opens a video in the app's own player, in place of whatever video is on.
    fun openVideo(id: Long, preset: PlaybackPreset?) {
        val nav = nav ?: return
        val running = video
        if (running != null && running.itemId == id) {
            // The same thing again: the player that has it goes to the place asked for.
            preset?.startSec?.let { running.seekFilm(it) }
            preset?.audio?.let { running.chooseAudio(it) }
            preset?.subtitle?.let { running.chooseSubtitle(it) }
            if (!app.isTv) nav.expandVideo()
            return
        }
        if (preset != null) presets[id] = preset
        if (nav.current == Route.NowPlaying) nav.closeNowPlaying()
        nav.playVideoInstead(id)
    }

    // Stops the video and leaves its screen.
    fun closeVideo() {
        val nav = nav ?: return
        when {
            nav.video != null -> nav.closeVideo()
            nav.current is Route.Player -> nav.pop()
            // A TV's player under another screen (Play on… over it): taken out of the stack, which closes it.
            nav.stack.size > 1 -> nav.stack.removeAll { it is Route.Player }
        }
    }

    // MARK: the watch party and the player

    private fun ensureFollower() {
        val target = video ?: return
        val room = party.room ?: return
        if (room.blocked || room.timeUp || room.state.itemId != target.itemId) return
        if (follower?.target === target) return
        detachFollower()
        followerGone?.cancel()
        val following = PartyFollower(target, party, this, scope)
        follower = following
        following.start()
    }

    private fun detachFollower() {
        follower?.stop()
        follower = null
    }

    private fun partyChanged(room: Room) {
        if (room.blocked || room.timeUp) {
            // Something this account may not see, or its time is up: the seat is kept, and nothing of it plays here.
            follower?.let {
                it.target.exo.pause()
                detachFollower()
                say(if (room.timeUp) "Your screen time is up, so you're sitting this one out." else "The party has moved on to something this account can't watch. You keep your place.")
            }
            return
        }
        if (room.state.itemId <= 0) return
        val running = video
        if (running != null && running.itemId == room.state.itemId) {
            ensureFollower()
            follower?.roomChanged()
            return
        }
        if (!keepsInStep(room.nowKind)) {
            detachFollower()
            say("The party is playing something this app can't keep in step. Your place is kept.")
            return
        }
        // The party is on something this device hasn't open: open it where the party has got to.
        openVideo(room.state.itemId, PlaybackPreset(startSec = roomPositionSec(room.state, party.serverNow())))
    }

    private fun partyOver(words: String) {
        detachFollower()
        say(words)
    }

    // The player a party was steering has closed. If nothing takes its place in a moment, that was leaving.
    private fun followerEnded(ended: PartyFollower) {
        val room = party.room ?: return
        followerGone?.cancel()
        followerGone = scope.launch {
            delay(LEFT_AFTER_MS)
            if (follower != null || party.room?.id != room.id) return@launch
            if (video?.itemId == party.room?.state?.itemId) return@launch
            party.leave()
            say("You left the watch party.")
        }
        ended.stop()
    }

    // MARK: invitations

    // Looked for every half minute while the app is on screen, as the server has no stream of them.
    private fun watchInvitations() {
        val wanted = token.isNotEmpty() && inFront && SYNCPLAY_FEATURE in features
        if (!wanted) {
            invitesJob?.cancel()
            invitesJob = null
            return
        }
        if (invitesJob?.isActive == true) return
        invitesJob = scope.launch {
            while (true) {
                delay(INVITES_EVERY_MS)
                try {
                    refreshParties()
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                    // The next look tries again.
                }
            }
        }
    }

    private fun noticeInvitations(found: SyncInfo) {
        val open = found.rooms.filter { it.invited && it.memberId.isEmpty() && it.id !in declined && it.id != party.room?.id }
        invitations.removeAll { mine -> open.none { it.id == mine.id } }
        open.forEach { room -> if (invitations.none { it.id == room.id }) invitations.add(room) }
    }

    // Decline puts the invitation away on this device; the server has no "no, thank you".
    fun decline(room: RoomSummary) {
        declined.add(room.id)
        invitations.removeAll { it.id == room.id }
    }

    fun accepted(room: RoomSummary) {
        invitations.removeAll { it.id == room.id }
    }

    // MARK: what this device is playing, as something to hand over

    fun sourcePlayingVideo(): PlayOnSource? {
        val target = video ?: return null
        val item = target.item ?: return null
        val queue = videoQueue?.takeIf { it.current == item.id && it.items.size > 1 }
        val stream = target.stream
        return PlayOnSource(
            item.id, item.title, item.kind,
            queue = queue?.items ?: listOf(item.id), queueIndex = queue?.index ?: 0,
            positionSec = target.liveFilmSec,
            audio = stream?.let { trackId(it.audioIndex) }, subtitle = stream?.let { trackId(it.subtitleIndex) },
            playingHere = true,
        )
    }

    fun sourcePlayingMusic(): PlayOnSource? {
        val listening = app.listening
        val now = listening.now ?: return null
        val id = now.mediaId.toLongOrNull() ?: return null
        val queue = listening.queue.mapNotNull { it.mediaId.toLongOrNull() }.take(MAX_QUEUE)
        val at = listening.queue.indexOfFirst { it.index == listening.nowIndex }
        val fits = at in queue.indices && queue[at] == id
        return PlayOnSource(
            id, now.mediaMetadata.title?.toString().orEmpty(), "audio",
            queue = if (fits) queue else listOf(id), queueIndex = if (fits) at else 0,
            positionSec = listening.positionSec(), playingHere = true,
        )
    }

    // Stops what this device was playing, once another has it.
    fun stopHere(source: PlayOnSource) {
        if (source.kind == "audio") {
            if (app.listening.now?.mediaId == source.itemId.toString()) app.listening.stop()
        } else if (video?.itemId == source.itemId) {
            closeVideo()
        }
    }

    private companion object {
        const val KEY_LET_OTHERS = "letOthersControl"
        const val TABLET_DP = 600
        const val LEFT_AFTER_MS = 1500L
        const val INVITES_EVERY_MS = 30_000L
        const val MAX_QUEUE = 200
    }
}
