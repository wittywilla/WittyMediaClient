package com.wittywilla.wittymediaclient.ui

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull

// The rest of the website's Now Playing, as rules apart from the screen so they can be tested: the visualizer's
// choices (web/src/audio/NowPlaying.tsx, backdrop.ts). The iPhone has the same in WittyKit's SoundLook.swift.

// The visualizer's choices, kept for the person on the server with their other interface choices (/me/ui,
// `musicPlayer`), as the website's readPrefs reads them.
data class VisualizerPrefs(
    val viz: Boolean = true,
    val style: String = "bars",
    val slow: Boolean = false,
    val shuffleEvery: Int = 0,
    val shufflePool: String = "mine",
) {
    // The style drawn here: one of the player's own, or Bars for an effect only the website's plugin draws.
    val nativeStyle: String get() = if (STYLES.any { it.first == style }) style else "bars"

    fun toJson(): JsonObject = JsonObject(
        mapOf(
            "viz" to JsonPrimitive(viz), "style" to JsonPrimitive(style), "slow" to JsonPrimitive(slow),
            "shuffleEvery" to JsonPrimitive(shuffleEvery), "shufflePool" to JsonPrimitive(shufflePool),
        ),
    )

    companion object {
        val STYLES = listOf("bars" to "Bars", "waves" to "Waves", "drift" to "Drift")
        val SHUFFLE_CHOICES = listOf(0, 15, 30, 60, 120, 300, 600)

        // Anything odd is put right: a style the website doesn't know stays, as its plugin may.
        fun read(saved: JsonElement?): VisualizerPrefs {
            val s = saved as? JsonObject ?: return VisualizerPrefs()
            fun prim(key: String) = s[key] as? JsonPrimitive
            val style = prim("style")?.takeIf { it.isString }?.content?.takeIf { it.length <= 48 } ?: "bars"
            val every = prim("shuffleEvery")?.takeIf { !it.isString }?.doubleOrNull
            return VisualizerPrefs(
                viz = prim("viz")?.booleanOrNull != false,
                style = style,
                slow = prim("slow")?.takeIf { !it.isString }?.booleanOrNull == true,
                shuffleEvery = SHUFFLE_CHOICES.firstOrNull { it.toDouble() == every } ?: 0,
                shufflePool = if (prim("shufflePool")?.takeIf { it.isString }?.content == "all") "all" else "mine",
            )
        }

        // "Off: stay on this one", "Every 15 seconds", "Every minute", "Every 2 minutes".
        fun everyWords(seconds: Int): String = when {
            seconds == 0 -> "Off: stay on this one"
            seconds < 60 -> "Every $seconds seconds"
            seconds == 60 -> "Every minute"
            else -> "Every ${seconds / 60} minutes"
        }

        // The Styles chip: the interval without "Every ", or "Styles" when it stays still.
        fun chipWords(seconds: Int): String = if (seconds > 0) everyWords(seconds).removePrefix("Every ") else "Styles"
    }
}
