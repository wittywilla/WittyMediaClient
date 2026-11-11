// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.flowOn
import okhttp3.Call
import okhttp3.Request
import java.io.IOException
import java.util.concurrent.TimeUnit

// The server's live streams (server-sent events): the Remote Protocol's channel and events, a watch party's room and
// the task list. Each event is an `event:` line, a `data:` line holding one JSON object, and a blank line; a line
// starting with a colon is the server saying it is still there (docs/REMOTE-PROTOCOL.md, Transport).

data class SseEvent(val event: String, val data: String)

// Lines in, events out. Pure, so the rules are tested without a network: unknown fields are skipped, several data
// lines join with a newline, and an event with no data is not an event.
class SseParser {
    private var event = ""
    private val data = StringBuilder()
    private var hasData = false

    // One line without its line ending. Answers an event when the line was the blank one that ends it.
    fun line(text: String): SseEvent? {
        if (text.isEmpty()) {
            val done = if (hasData) SseEvent(event.ifEmpty { "message" }, data.toString()) else null
            event = ""
            data.setLength(0)
            hasData = false
            return done
        }
        if (text.startsWith(":")) return null
        val colon = text.indexOf(':')
        val field = if (colon < 0) text else text.substring(0, colon)
        val value = if (colon < 0) "" else text.substring(colon + 1).removePrefix(" ")
        when (field) {
            "event" -> event = value
            "data" -> {
                if (data.length + value.length > MAX_EVENT_CHARS) return null
                if (hasData) data.append('\n')
                data.append(value)
                hasData = true
            }
        }
        return null
    }

    companion object {
        // A room or a device list is a few kilobytes; anything far beyond that isn't one.
        const val MAX_EVENT_CHARS = 1024 * 1024
    }
}

// How long to wait before opening a dropped stream again: 1 s, 2 s, 4 s … up to half a minute. The count goes back to
// 0 once a stream has opened.
fun sseBackoffMs(failures: Int): Long = (1000L shl failures.coerceIn(0, 5)).coerceAtMost(30_000L)

// A stream that has said nothing for this long is taken to be dead: the server writes every 25 seconds.
const val SSE_SILENCE_SEC = 60L

class SseRefused(val status: Int, val code: String, message: String) : IOException(message)

// One stream, as a cold flow: collecting opens it, cancelling the collector closes the connection. It ends when the
// server ends it, and fails with SseRefused when the server refuses it or IOException when the network drops.
// `opened` is called once the server has accepted the stream.
fun Api.events(path: String, opened: () -> Unit = {}): Flow<SseEvent> = callbackFlow {
    val client = http.newBuilder().readTimeout(SSE_SILENCE_SEC, TimeUnit.SECONDS).callTimeout(0, TimeUnit.SECONDS).build()
    val call: Call = client.newCall(Request.Builder().url("$base/api/v1$path").header("Accept", "text/event-stream").build())
    val reader = Thread({
        try {
            call.execute().use { res ->
                if (!res.isSuccessful) {
                    val text = res.peekBody(64 * 1024).string()
                    val words = runCatching { json.parseToJsonElement(text).let { (it as kotlinx.serialization.json.JsonObject)["error"] }?.let { (it as kotlinx.serialization.json.JsonPrimitive).content } }.getOrNull()
                    throw SseRefused(res.code, errorCode(text), words ?: "The server answered with an error (${res.code}).")
                }
                opened()
                val parser = SseParser()
                val source = res.body.source()
                while (true) {
                    val line = source.readUtf8Line() ?: break
                    parser.line(line)?.let { trySend(it) }
                }
            }
            close()
        } catch (e: IOException) {
            close(e)
        } catch (e: RuntimeException) {
            close(IOException(e))
        }
    }, "sse")
    reader.isDaemon = true
    reader.start()
    awaitClose { call.cancel() }
}.flowOn(Dispatchers.IO)
