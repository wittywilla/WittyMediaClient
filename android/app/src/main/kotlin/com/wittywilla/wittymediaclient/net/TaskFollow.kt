// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.transformWhile
import java.io.IOException
import java.util.concurrent.atomic.AtomicInteger

// This account may not see the server's activity (its owner's choice), so a task can't be followed by its id.
class TasksHidden : IOException("This account can't see what the server is doing.")

// One task, from now until it's over: each time it changes, and last of all as it ended. The server's stream says so
// as it happens (docs/TASKS.md); when the stream drops, the list is read once and the stream opened again after a
// growing wait, so progress is never lost and a server that's restarting isn't hammered. Collecting is what keeps the
// connection open: cancel the collector and it closes.
fun Api.followTask(id: String): Flow<ServerTask> = flow {
    val failures = AtomicInteger(0)
    var seen = false
    while (true) {
        var over = false
        try {
            events(TASK_STREAM_PATH) { failures.set(0) }.transformWhile { event ->
                var task = TaskLook.apply(event, id)
                // The whole list without it: it finished long enough ago to have left the list.
                if (task == null && event.event == "snapshot" && seen) task = ServerTask(id = id, state = "done")
                if (task != null) {
                    seen = true
                    emit(task)
                    over = TaskLook.isOver(task)
                }
                !over
            }.collect { emit(it) }
        } catch (e: SseRefused) {
            if (e.status == 401 || e.status == 403) throw TasksHidden()
        } catch (_: IOException) {
            // The connection dropped: read the list below, then try the stream again.
        }
        if (over) return@flow
        delay(sseBackoffMs(failures.getAndIncrement()))
        val list = try {
            tasks()
        } catch (e: ApiError) {
            if (e.status == 401) throw e
            null
        } catch (_: IOException) {
            null
        }
        if (list != null) {
            if (!list.access.visible) throw TasksHidden()
            val task = TaskLook.find(list, id) ?: if (seen) ServerTask(id = id, state = "done") else null
            if (task != null) {
                seen = true
                emit(task)
                if (TaskLook.isOver(task)) return@flow
            }
        }
    }
}
