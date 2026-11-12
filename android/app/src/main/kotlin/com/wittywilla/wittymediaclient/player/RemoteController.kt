// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.player

import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.wittywilla.wittymediaclient.net.Api
import com.wittywilla.wittymediaclient.net.ApiError
import com.wittywilla.wittymediaclient.net.SseRefused
import com.wittywilla.wittymediaclient.net.json
import com.wittywilla.wittymediaclient.net.remote.CommandAnswer
import com.wittywilla.wittymediaclient.net.remote.CommandPacer
import com.wittywilla.wittymediaclient.net.remote.RemoteDevice
import com.wittywilla.wittymediaclient.net.remote.ServerClock
import com.wittywilla.wittymediaclient.net.remote.WatchEvent
import com.wittywilla.wittymediaclient.net.remote.applyWatchEvent
import com.wittywilla.wittymediaclient.net.remote.readWatchEvent
import com.wittywilla.wittymediaclient.net.remote.remoteCommand
import com.wittywilla.wittymediaclient.net.remote.remoteDevices
import com.wittywilla.wittymediaclient.net.remote.remoteErrorWords
import com.wittywilla.wittymediaclient.net.remote.remoteWatch
import com.wittywilla.wittymediaclient.net.remote.remoteWords
import com.wittywilla.wittymediaclient.net.sseBackoffMs
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.IOException

// This app as a controller (docs/REMOTE-PROTOCOL.md, Being a controller): the devices it may play on and steer, kept
// live from the server's stream only while a list or a remote is on screen, and the commands it sends them, no faster
// than the server allows.

class DeviceWatcher(private val api: Api) {
    var devices by mutableStateOf<List<RemoteDevice>>(emptyList())
        private set
    // The list has been heard at least once.
    var loaded by mutableStateOf(false)
        private set
    var problem by mutableStateOf("")
        private set
    private val clock = ServerClock()

    // The server's milliseconds now, for where a playing device has got to.
    fun serverNow(): Long = clock.now(SystemClock.elapsedRealtime())

    // Runs until the screen that started it goes (its coroutine is cancelled), or the server says not to come back.
    suspend fun run() {
        var failures = 0
        while (true) {
            var bye = ""
            try {
                val list = api.remoteDevices()
                clock.heard(list.serverTimeMs, SystemClock.elapsedRealtime())
                devices = list.devices
                loaded = true
                problem = ""
                api.remoteWatch().collect { event ->
                    if (event.event == "bye") {
                        bye = runCatching { json.parseToJsonElement(event.data).jsonObject["reason"]?.jsonPrimitive?.content }.getOrNull().orEmpty()
                        return@collect
                    }
                    val read = readWatchEvent(event) ?: return@collect
                    if (read is WatchEvent.Snapshot) clock.heard(read.list.serverTimeMs, SystemClock.elapsedRealtime())
                    devices = applyWatchEvent(devices, read)
                    failures = 0
                }
                when (bye) {
                    "signed-out" -> { problem = "Sign in again to use remote control."; return }
                    "feature-off" -> { problem = remoteErrorWords(403, "feature-off", "Playing on other devices is turned off for this profile."); return }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: ApiError) {
                problem = remoteWords(e)
                if (e.status == 401 || e.status == 403) return
            } catch (e: SseRefused) {
                problem = remoteErrorWords(e.status, e.code, e.message.orEmpty())
                if (e.status == 401 || e.status == 403) return
            } catch (_: IOException) {
                if (!loaded) problem = "The server couldn't be reached. Trying again…"
            }
            loaded = true
            delay(sseBackoffMs(failures++))
        }
    }
}

// Commands for one device, in the order they were pressed, never closer together than the server allows. Something
// dragged (a volume, a place on the bar) sends only its latest value when its turn comes.
class RemoteSender(private val api: Api, private val deviceId: String, everyMs: Long, private val scope: CoroutineScope, private val said: (String) -> Unit) {
    private val pacer = CommandPacer(everyMs)
    private val order = Mutex()
    private var pump: Job? = null

    private fun now() = SystemClock.elapsedRealtime()

    // A press: sent as it is, after any before it.
    fun press(command: JsonObject, done: (CommandAnswer) -> Unit = {}) {
        scope.launch {
            val answer = order.withLock {
                delay(pacer.waitMs(now()))
                pacer.sent(now())
                send(command)
            }
            if (answer != null) done(answer)
        }
    }

    // A value being dragged: the latest replaces any not yet sent.
    fun drag(command: JsonObject) {
        pacer.offer(command)
        if (pump?.isActive == true) return
        pump = scope.launch {
            while (pacer.pending) {
                order.withLock {
                    delay(pacer.waitMs(now()))
                    val next = pacer.take(now()) ?: return@withLock
                    pacer.sent(now())
                    send(next)
                }
            }
        }
    }

    private suspend fun send(command: JsonObject): CommandAnswer? = try {
        api.remoteCommand(deviceId, command)
    } catch (e: CancellationException) {
        throw e
    } catch (e: ApiError) {
        said(remoteWords(e))
        null
    } catch (_: IOException) {
        said("The server couldn't be reached. Check the connection.")
        null
    }

    // Sent and waited for, for a hand-over whose answer decides what this device does next.
    suspend fun sendNow(command: JsonObject): CommandAnswer = order.withLock {
        delay(pacer.waitMs(now()))
        pacer.sent(now())
        api.remoteCommand(deviceId, command)
    }
}
