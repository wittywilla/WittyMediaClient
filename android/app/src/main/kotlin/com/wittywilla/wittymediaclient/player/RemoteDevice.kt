// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.player

import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.wittywilla.wittymediaclient.diag.ClientLog
import com.wittywilla.wittymediaclient.net.Api
import com.wittywilla.wittymediaclient.net.ApiError
import com.wittywilla.wittymediaclient.net.SseRefused
import com.wittywilla.wittymediaclient.net.remote.ChannelEvent
import com.wittywilla.wittymediaclient.net.remote.DeviceLife
import com.wittywilla.wittymediaclient.net.remote.Heartbeat
import com.wittywilla.wittymediaclient.net.remote.LifeStep
import com.wittywilla.wittymediaclient.net.remote.RemoteCapabilities
import com.wittywilla.wittymediaclient.net.remote.RemoteCommand
import com.wittywilla.wittymediaclient.net.remote.RemoteLimits
import com.wittywilla.wittymediaclient.net.remote.RemoteState
import com.wittywilla.wittymediaclient.net.remote.RemoteWire
import com.wittywilla.wittymediaclient.net.remote.StopReason
import com.wittywilla.wittymediaclient.net.remote.commandProblem
import com.wittywilla.wittymediaclient.net.remote.readChannelEvent
import com.wittywilla.wittymediaclient.net.remote.remoteAck
import com.wittywilla.wittymediaclient.net.remote.remoteAnnounce
import com.wittywilla.wittymediaclient.net.remote.remoteChannel
import com.wittywilla.wittymediaclient.net.remote.remoteLeave
import com.wittywilla.wittymediaclient.net.remote.remoteState
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.IOException

// This app as a device of the server's Remote Protocol (docs/REMOTE-PROTOCOL.md, Being a device): it announces
// itself, holds one channel open, answers every command it is sent and says what it is playing. When to announce
// again, how long to wait and when to stop are DeviceLife's; when to report is Heartbeat's. What a command does to
// the app's players is RemotePlayers.kt's.

// The app's players, as the device sees them.
interface DevicePlayers {
    fun remoteState(abilities: RemoteCapabilities): RemoteState
    // Does it, or answers why not in words for whoever holds the controller. Returns once the command is accepted.
    suspend fun remoteDo(command: RemoteCommand, abilities: RemoteCapabilities): String?
}

class RemoteDeviceHost(private val scope: CoroutineScope, private val api: () -> Api, private val players: DevicePlayers) {
    // The id the server gave this device. Kept while the app runs, so coming back is the same device.
    var deviceId by mutableStateOf("")
        private set
    // The channel is open: controllers can see this device and reach it.
    var online by mutableStateOf(false)
        private set

    private var loop: Job? = null
    private var abilities = RemoteCapabilities()
    private var heartbeat = Heartbeat()
    private var reporting = false
    private var owed = false
    private var startedWith: Started? = null

    private data class Started(val name: String, val kind: String, val capabilities: RemoteCapabilities, val limits: RemoteLimits)

    val running: Boolean get() = loop?.isActive == true

    private fun nowMs() = SystemClock.elapsedRealtime()

    // Announces and holds the channel until told to stop. Calling it again while it runs changes nothing.
    fun start(name: String, kind: String, capabilities: RemoteCapabilities, limits: RemoteLimits) {
        val wanted = Started(name, kind, capabilities, limits)
        if (running && startedWith == wanted) return
        loop?.cancel()
        startedWith = wanted
        heartbeat = Heartbeat(limits.stateEveryMs, limits.heartbeatSec)
        abilities = capabilities
        loop = scope.launch { run(wanted) }
    }

    // Closes the channel. With `forget` the server is told this device has gone (signing out, or the person turned
    // this off); without, it stays listed as not connected for half a minute, and opening the channel again in that
    // time is the same device.
    suspend fun stop(forget: Boolean, using: Api = api()) {
        loop?.cancel()
        loop = null
        online = false
        val id = deviceId
        if (!forget) return
        deviceId = ""
        startedWith = null
        if (id.isNotEmpty() && using.token.isNotEmpty()) runCatching { using.remoteLeave(id) }
    }

    private suspend fun run(started: Started) {
        val life = DeviceLife(started.limits.reconnectSec)
        if (deviceId.isNotEmpty()) life.announced(deviceId)
        var step: LifeStep = life.start()
        val commands = Channel<RemoteCommand>(COMMANDS_WAITING)
        // One at a time, in the order they came: a seek sent after a play is done after it.
        val obeying = scope.launch { for (command in commands) obey(command) }
        // The heartbeat, and while something plays where it has got to. Whether one is due is the Heartbeat's rule.
        val beat = scope.launch {
            while (isActive) {
                delay(BEAT_MS)
                reportIfDue()
            }
        }
        try {
            while (currentCoroutineContext().isActive) {
                step = when (val now = step) {
                    is LifeStep.Stop -> {
                        if (now.why == StopReason.TooOld) ClientLog.warn("remote", "This app speaks an older Remote Protocol than the server accepts.")
                        return
                    }
                    is LifeStep.Announce -> {
                        if (now.afterMs > 0) delay(now.afterMs)
                        try {
                            val agreed = api().remoteAnnounce(RemoteWire.announce(started.name, started.kind, started.capabilities, life.deviceId))
                            // Never more than was announced, and never what the server didn't take.
                            abilities = RemoteCapabilities(
                                started.capabilities.mediaKinds.filter { it in agreed.capabilities.mediaKinds },
                                started.capabilities.features.filter { it in agreed.capabilities.features },
                            )
                            deviceId = agreed.deviceId
                            life.announced(agreed.deviceId)
                        } catch (e: ApiError) {
                            life.refused(e.status, e.code, e.retryAfterSec)
                        } catch (e: IOException) {
                            life.lost(nowMs())
                        }
                    }
                    is LifeStep.Open -> {
                        if (now.afterMs > 0) delay(now.afterMs)
                        var bye: String? = null
                        try {
                            api().remoteChannel(life.deviceId).collect { event ->
                                when (val read = readChannelEvent(event)) {
                                    is ChannelEvent.Hello -> {
                                        life.opened()
                                        online = true
                                        heartbeat.reset()
                                        reportIfDue()
                                    }
                                    is ChannelEvent.Command -> if (commands.trySend(read.command).isFailure) {
                                        // More waiting than the server itself queues: say so rather than drop it.
                                        scope.launch { ack(read.command.id, "This device is busy. Try again in a moment.") }
                                    }
                                    is ChannelEvent.Bye -> bye = read.reason
                                    // An event this app has never heard of: skipped, as the protocol asks.
                                    null -> Unit
                                }
                            }
                            online = false
                            life.closed(bye, nowMs())
                        } catch (e: SseRefused) {
                            online = false
                            life.refused(e.status, e.code)
                        } catch (e: IOException) {
                            // Nothing heard for a minute, or the network went: the channel is dead.
                            online = false
                            life.closed(bye, nowMs())
                        }
                    }
                }
            }
        } finally {
            online = false
            beat.cancel()
            obeying.cancel()
            commands.close()
        }
    }

    // Every command gets an answer, whatever it was.
    private suspend fun obey(command: RemoteCommand) {
        val problem = commandProblem(command, abilities) ?: try {
            players.remoteDo(command, abilities)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            ClientLog.warn("remote", "A ${command.type} command failed: ${e.javaClass.simpleName}")
            "That didn't work on this device."
        }
        ack(command.id, problem)
        reportSoon()
    }

    private suspend fun ack(id: String, problem: String?) {
        if (id.isEmpty() || deviceId.isEmpty()) return
        // A 404 `no-command` means it's no longer waiting (it timed out, or the channel reopened): carry on.
        runCatching { api().remoteAck(deviceId, RemoteWire.ack(id, problem)) }
    }

    // Something changed that a controller would show. It goes as soon as the server's limit allows, after a moment
    // for the player to have taken the change in.
    fun reportSoon() {
        if (!online) return
        scope.launch {
            delay(SETTLE_MS)
            // A change goes as soon as the server's pace allows; the beat picks up one that has to wait.
            reportIfDue()
        }
    }

    private fun reportIfDue() {
        if (!online || deviceId.isEmpty()) return
        val state = players.remoteState(abilities)
        val body = state.toJson()
        val now = nowMs()
        if (!heartbeat.due(now, body, state.isPlaying)) return
        if (reporting) {
            owed = true
            return
        }
        reporting = true
        heartbeat.sent(now, body)
        val id = deviceId
        val using = api()
        scope.launch {
            try {
                using.remoteState(id, body)
            } catch (e: ApiError) {
                if (e.status == 429) {
                    // Nothing is lost: the latest state goes a moment later.
                    heartbeat.refused(nowMs(), e.retryAfterSec)
                } else if (e.status == 404) {
                    // The server has forgotten this device: announce again.
                    startedWith?.let { s ->
                        loop?.cancel()
                        loop = null
                        start(s.name, s.kind, s.capabilities, s.limits)
                    }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                // The next one says it.
            } finally {
                reporting = false
            }
            if (owed) {
                owed = false
                reportIfDue()
            }
        }
    }

    private companion object {
        const val BEAT_MS = 1000L
        const val SETTLE_MS = 150L
        const val COMMANDS_WAITING = 16
    }
}
