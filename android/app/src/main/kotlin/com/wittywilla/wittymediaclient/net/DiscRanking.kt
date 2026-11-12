// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlin.math.roundToInt

// What the disc's engine made of a DVD or Blu-ray (GET /items/{id}/disc/analysis, feature `disc-ranking`): which
// title or playlist is the film and why, how sure it is, the film's other versions and a TV disc's episodes. The
// server's web page (web/src/pages/DiscWhy.tsx) words it the same way.

@Serializable
data class DiscCandidate(val ttn: Int = 0, val durationSec: Double = 0.0, val chapters: Int = 0, val `class`: String = "", val score: Double = 0.0)

@Serializable
data class DiscVersion(val kind: String = "", val ttn: Int = 0, val angle: Int = 0, val durationSec: Double = 0.0, val label: String = "", val main: Boolean = false)

@Serializable
data class DiscEpisode(val index: Int = 0, val ttn: Int = 0, val durationSec: Double = 0.0, val startSec: Double = 0.0, val part: Boolean = false)

@Serializable
data class DiscIssue(val severity: String = "", val kind: String = "", val ttn: Int = -1, val what: String = "")

@Serializable
data class DiscFeature(val titles: List<Int> = emptyList(), val durationSec: Double = 0.0, val assembled: Boolean = false)

@Serializable
data class DiscRank(
    val engine: String = "",
    val main: Int = -1,
    val confidence: Double = 0.0,
    val level: String = "",
    val why: String = "",
    val reasons: List<String> = emptyList(),
    val against: List<String> = emptyList(),
    val feature: DiscFeature? = null,
    val versions: List<DiscVersion> = emptyList(),
    val episodes: List<DiscEpisode> = emptyList(),
    val candidates: List<DiscCandidate> = emptyList(),
    val warnings: List<String> = emptyList(),
    val repairs: List<String> = emptyList(),
    val issues: List<DiscIssue> = emptyList(),
    val paddedSectors: Int = 0,
    val protected: Boolean = false,
)

@Serializable
data class DiscChosen(val ttn: Int = -1)

@Serializable
data class DiscAnalysis(
    val kind: String = "",
    val ranked: Boolean = false,
    val pending: Boolean = false,
    val main: Int = -1,
    val engineMain: Int = -1,
    val chosen: DiscChosen? = null,
    val chosenBy: String = "",
    val rank: DiscRank? = null,
    val canChoose: Boolean = false,
    val protected: Boolean = false,
)

object DiscWords {
    // "Title 3" on a DVD, "Playlist 800" on a Blu-ray.
    fun unit(kind: String): String = if (kind == "bluray") "Playlist" else "Title"

    fun name(kind: String, ttn: Int): String = unit(kind) + " " + ttn

    fun sure(confidence: Double): String = "${(confidence * 100).roundToInt()}% sure"

    fun level(level: String, confidence: Double): String = when (level) {
        "high" -> "High confidence"
        "medium" -> "Medium confidence"
        "low" -> "Low confidence"
        else -> sure(confidence)
    }

    fun clock(sec: Double): String {
        val s = sec.roundToInt().coerceAtLeast(0)
        return if (s >= 3600) "%d:%02d:%02d".format(s / 3600, s / 60 % 60, s % 60) else "%d:%02d".format(s / 60, s % 60)
    }

    // The one line that says what plays and why.
    fun headline(a: DiscAnalysis): String {
        val rank = a.rank
        return when {
            a.chosen != null -> name(a.kind, a.main) + " was chosen as this disc's film" + (if (a.chosenBy.isNotEmpty()) " by ${a.chosenBy}" else "") +
                (if (a.engineMain >= 0 && a.engineMain != a.main) "; the engine picks ${name(a.kind, a.engineMain)}." else ".")
            !a.ranked || rank == null -> "The disc module in use is from before ranking, so the film is the longest sensible ${unit(a.kind).lowercase()}. Updating the module explains its pick."
            else -> rank.why.ifEmpty { "The engine picked ${name(a.kind, rank.main)}." }
        }
    }

    // Where a version or an episode plays: the server's disc player, at that title.
    fun versionPath(item: Long, v: DiscVersion): String = "/play/$item?mode=title&ttn=${v.ttn}" + if (v.angle > 0) "&angle=${v.angle}" else ""

    fun episodePath(item: Long, e: DiscEpisode): String = "/play/$item?mode=title&episode=${e.index}"

    fun choiceBody(ttn: Int): String = JsonObject(mapOf("ttn" to JsonPrimitive(ttn))).toString()
}

suspend fun Api.discAnalysis(item: Long): DiscAnalysis = json.decodeFromString(call("GET", "/items/$item/disc/analysis"))

suspend fun Api.chooseDiscTitle(item: Long, ttn: Int): DiscAnalysis = json.decodeFromString(call("PUT", "/items/$item/disc/choice", DiscWords.choiceBody(ttn)))

suspend fun Api.forgetDiscChoice(item: Long): DiscAnalysis = json.decodeFromString(call("DELETE", "/items/$item/disc/choice"))

suspend fun Api.rankDiscAgain(item: Long): DiscAnalysis = json.decodeFromString(call("POST", "/items/$item/disc/analysis", "{}"))
