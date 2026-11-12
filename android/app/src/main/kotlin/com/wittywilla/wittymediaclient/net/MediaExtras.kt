// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

// The server's media extras (docs/CLIENT-API.md, "Media extras"): where to skip in a video, the looping video behind a
// song or a title, a song's separated parts, where else a title can be watched, and the jobs an administrator can
// start for them. Each is offered only when the server names its feature in /capabilities.

object ExtrasFeature {
    const val MARKERS = "skip-markers"
    const val CANVAS = "canvas"
    const val CANVAS_GENERATE = "canvas-generate"
    const val STEMS = "karaoke-stems"
    const val STEMS_APPROXIMATE = "stems-approximate"
    const val STEMS_SEPARATE = "stems-separate"
    const val INTRO_DETECTION = "intro-detection"
    const val WHERE_TO_WATCH = "where-to-watch-xref"
    const val TASKS = "system-tasks"
}

// MARK: markers

// A stretch of a video, in the film's own seconds.
@Serializable
data class SkipRange(val startSec: Double = 0.0, val endSec: Double = 0.0, val label: String = "")

// GET /media/{id}/markers. `sources` says where each kind came from: manual, skip.json, edl, chapters, detected, show.
@Serializable
data class MediaMarkers(
    val intro: SkipRange? = null,
    val recap: SkipRange? = null,
    val credits: SkipRange? = null,
    val commercials: List<SkipRange> = emptyList(),
    val source: String = "none",
    val sources: Map<String, String> = emptyMap(),
)

suspend fun Api.markers(id: Long): MediaMarkers = json.decodeFromString(call("GET", "/media/$id/markers"))

// MARK: canvas

// GET /media/{id}/canvas: a short silent video to loop behind the artwork, when there is one. `task` is one being made
// now, and `canGenerate` that an administrator can have one cut from the video.
@Serializable
data class CanvasInfo(
    val available: Boolean = false,
    val url: String = "",
    val mime: String = "",
    val width: Int = 0,
    val height: Int = 0,
    val durationMs: Long = 0,
    val loop: Boolean = true,
    val source: String = "",
    val reason: String = "",
    val task: String = "",
    val canGenerate: Boolean = false,
)

suspend fun Api.canvas(id: Long): CanvasInfo = json.decodeFromString(call("GET", "/media/$id/canvas"))

// MARK: stems

// One part of a song. `approximate` is FFmpeg's guess (what the two channels share, cancelled), not a real stem; a
// `multitrack` one is a Native Instruments file holding every part as a track of its own.
@Serializable
data class StemInfo(
    val name: String = "",
    val url: String = "",
    val mime: String = "",
    val size: Long = 0,
    val multitrack: Boolean = false,
    val source: String = "",
    val approximate: Boolean = false,
)

// One of the two ways the server can make stems: whether it can for this song, why not, and the task doing it now.
@Serializable
data class SeparationWay(val available: Boolean = false, val reason: String = "", val task: String = "", val note: String = "")

@Serializable
data class Separation(val approximate: SeparationWay = SeparationWay(), val external: SeparationWay = SeparationWay())

// GET /media/{id}/stems.
@Serializable
data class StemList(val stems: List<StemInfo> = emptyList(), val names: List<String> = emptyList(), val separation: Separation = Separation())

suspend fun Api.stems(id: Long): StemList = json.decodeFromString(call("GET", "/media/$id/stems"))

// MARK: jobs

// What the routes that make something answer: 202 with the task to follow, or 200 `exists` when there's nothing to make.
@Serializable
data class JobAnswer(
    val ok: Boolean = false,
    val task: String = "",
    val already: Boolean = false,
    val exists: Boolean = false,
    val episodes: Int = 0,
    val seasons: Int = 0,
)

private suspend fun Api.job(path: String, body: String = "{}"): JobAnswer = json.decodeFromString(call("POST", path, body))

// Anyone who may play the song may ask for the approximate instrumental; the rest are an administrator's.
suspend fun Api.makeApproximateStems(id: Long): JobAnswer = job("/media/$id/stems/approximate")
suspend fun Api.separateStems(id: Long): JobAnswer = job("/media/$id/stems/separate")
suspend fun Api.generateCanvas(id: Long): JobAnswer = job("/media/$id/canvas/generate")
suspend fun Api.detectIntros(show: Long, season: Int? = null): JobAnswer =
    job("/shows/$show/detect-intros", if (season == null) "{}" else JsonObject(mapOf("season" to JsonPrimitive(season))).toString())

// MARK: where to watch

// One copy of a title in the library.
@Serializable
data class WatchVersion(
    val itemId: Long = 0,
    val label: String = "",
    val kind: String = "",
    val quality: String = "",
    val width: Int = 0,
    val height: Int = 0,
    val container: String = "",
    val videoCodec: String = "",
    val sizeBytes: Long = 0,
)

@Serializable
data class WatchLocal(val itemId: Long = 0, val showId: Long = 0, val title: String = "", val quality: String = "", val versions: List<WatchVersion> = emptyList())

// One service offering a title one way: stream, free, ads, rent or buy.
@Serializable
data class WatchOffer(val providerId: Int = 0, val key: String = "", val name: String = "", val type: String = "", val priority: Int = 0)

@Serializable
data class WatchGroup(val type: String = "", val providers: List<WatchOffer> = emptyList())

// GET /media/{id}/where-to-watch: this title here, beside the services that offer it in `region`. `reason` says why
// no services are listed: no-api-key, not-matched or unavailable.
@Serializable
data class WhereToWatch(
    val inLibrary: Boolean = false,
    val local: WatchLocal? = null,
    val region: String = "",
    val link: String = "",
    val groups: List<WatchGroup> = emptyList(),
    val reason: String = "",
    val attribution: String = "",
    val fetchedAt: Long = 0,
)

suspend fun Api.whereToWatch(id: Long): WhereToWatch = json.decodeFromString(call("GET", "/media/$id/where-to-watch"))

// What the section shows, worked out apart from the screen.
object WatchLook {
    // The groups in the order people look for them, each named. An unknown type is a newer server's, and is left out.
    private val NAMES = listOf("stream" to "Stream", "free" to "Free", "ads" to "Free with adverts", "rent" to "Rent", "buy" to "Buy")

    data class Section(val type: String, val title: String, val providers: List<WatchOffer>)

    fun sections(answer: WhereToWatch): List<Section> = NAMES.mapNotNull { (type, title) ->
        val offers = answer.groups.filter { it.type == type }.flatMap { it.providers }
            .filter { it.name.isNotBlank() }.distinctBy { it.name.trim().lowercase() }.sortedBy { it.priority }
        if (offers.isEmpty()) null else Section(type, title, offers)
    }

    // The other copies here: every version but the one whose page this is.
    fun otherVersions(answer: WhereToWatch, showing: Long): List<WatchVersion> =
        answer.local?.versions.orEmpty().filter { it.itemId != 0L && it.itemId != showing }.distinctBy { it.itemId }

    // "Director's cut · 4K · HEVC · 12.40 GB": a copy's button.
    fun versionWords(version: WatchVersion): String {
        val size = if (version.sizeBytes > 0) String.format(java.util.Locale.ROOT, "%.2f GB", version.sizeBytes / 1e9) else ""
        val codec = when (version.videoCodec.lowercase()) {
            "" -> ""
            "h264", "avc" -> "H.264"
            "hevc", "h265" -> "HEVC"
            else -> version.videoCodec.uppercase()
        }
        return listOf(version.label.ifEmpty { "Another copy" }, version.quality, codec, size).filter { it.isNotEmpty() }.joinToString(" · ")
    }

    // "In your library · 1080p", for the copy whose page this is.
    fun hereWords(answer: WhereToWatch): String =
        if (!answer.inLibrary) "" else "In your library" + (answer.local?.quality?.takeIf { it.isNotEmpty() }?.let { " · $it" } ?: "")

    // Why no services are listed, in words; empty when there's nothing worth saying.
    fun reasonWords(answer: WhereToWatch, admin: Boolean): String = when {
        sections(answer).isNotEmpty() -> ""
        answer.reason == "no-api-key" -> if (admin) "Streaming services aren't listed: this server has no TMDB key. Add one under Metadata in the server's settings." else ""
        answer.reason == "unavailable" -> "The list of streaming services couldn't be reached just now."
        answer.reason == "not-matched" -> ""
        else -> if (answer.attribution.isNotEmpty()) "No streaming service lists this for ${answer.region}." else ""
    }

    // Whether there's anything to show at all.
    fun hasAnything(answer: WhereToWatch, showing: Long, admin: Boolean): Boolean =
        sections(answer).isNotEmpty() || otherVersions(answer, showing).isNotEmpty() || reasonWords(answer, admin).isNotEmpty()

    // The outside page listing every offer. Only an https address at the source the server names is passed on: an
    // answer can't send a person somewhere else.
    fun offersLink(answer: WhereToWatch): String? {
        val url = answer.link.toHttpUrlOrNull() ?: return null
        val host = url.host.lowercase()
        val known = host == "www.themoviedb.org" || host == "themoviedb.org" || host == "www.justwatch.com" || host == "justwatch.com"
        return if (url.isHttps && known && url.username.isEmpty() && url.password.isEmpty()) url.toString() else null
    }
}

// MARK: tasks

// One piece of background work, as GET /system/tasks and its stream describe it. `percent` is -1 when there's no telling.
@Serializable
data class ServerTask(
    val id: String = "",
    val type: String = "",
    val title: String = "",
    val state: String = "",
    val phase: String = "",
    val item: String = "",
    val done: Long = 0,
    val total: Long = 0,
    val unit: String = "",
    val percent: Double = -1.0,
    val etaSec: Long = 0,
    val result: String = "",
    val error: String = "",
    val fix: String = "",
    val problemCount: Int = 0,
    val canCancel: Boolean = false,
)

@Serializable
data class TaskAccess(val enabled: Boolean = false, val visible: Boolean = false, val readOnly: Boolean = true)

// GET /system/tasks, and the stream's "snapshot".
@Serializable
data class TaskList(val access: TaskAccess = TaskAccess(), val tasks: List<ServerTask> = emptyList(), val recent: List<ServerTask> = emptyList())

// The stream's "update": whatever changed, whole, finished ones included.
@Serializable
data class TaskUpdate(val tasks: List<ServerTask> = emptyList(), val gone: List<String> = emptyList())

const val TASK_STREAM_PATH = "/system/tasks/stream"

suspend fun Api.tasks(): TaskList = json.decodeFromString(call("GET", "/system/tasks"))
suspend fun Api.cancelTask(id: String) { call("POST", "/system/tasks/${encode(id)}/cancel", "{}") }

// Following one task through the list and the stream, apart from the network so it can be tested.
object TaskLook {
    private val OVER = setOf("done", "failed", "cancelled", "canceled", "interrupted")

    fun isOver(task: ServerTask): Boolean = task.state in OVER
    fun failed(task: ServerTask): Boolean = isOver(task) && task.state != "done"

    // The task in a whole list: among what's running, else among what finished.
    fun find(list: TaskList, id: String): ServerTask? = list.tasks.firstOrNull { it.id == id } ?: list.recent.firstOrNull { it.id == id }

    // One event of the stream applied to what's known of the task. Null leaves it as it was.
    fun apply(event: SseEvent, id: String): ServerTask? = when (event.event) {
        "snapshot" -> runCatching { json.decodeFromString<TaskList>(event.data) }.getOrNull()?.let { find(it, id) }
        "update" -> runCatching { json.decodeFromString<TaskUpdate>(event.data) }.getOrNull()?.tasks?.firstOrNull { it.id == id }
        else -> null
    }

    // 0 to 1 for a bar, or null for one that can only turn.
    fun fraction(task: ServerTask): Float? = when {
        task.state == "done" -> 1f
        task.percent < 0 -> null
        else -> (task.percent / 100.0).toFloat().coerceIn(0f, 1f)
    }

    // "Waiting its turn", "Season 1 · 2 of 3 episodes", "Found an intro in 3 of 3 episodes…": the line under the title.
    fun line(task: ServerTask): String = when {
        task.state == "queued" -> "Waiting its turn"
        task.state == "paused" -> "Paused"
        task.state == "done" -> task.result.ifEmpty { "Done." }
        task.state == "cancelled" || task.state == "canceled" -> "Stopped."
        task.state == "interrupted" -> "The server stopped before this finished."
        task.state == "failed" -> listOf(task.error.ifEmpty { "It didn't work." }, task.fix).filter { it.isNotEmpty() }.joinToString(" ")
        else -> {
            val count = if (task.total > 0) "${task.done} of ${task.total}" + (if (task.unit.isNotEmpty()) " ${task.unit}" else "") else ""
            listOf(task.phase, count).filter { it.isNotEmpty() }.joinToString(" · ").ifEmpty { "Working…" }
        }
    }
}
