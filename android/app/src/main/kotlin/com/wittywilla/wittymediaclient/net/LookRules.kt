// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

// The finished look the server sends in `GET /theme` (`look`: docs/THEMES.md): the type set, how much finish to use, the
// theme's scene (layers behind the page) and finish (glass and gloss recipes). Parsed here as plain data; the app draws it.

// A colour as CSS gave it: #rgb, #rrggbb, #rrggbbaa, rgb() or rgba(). Components 0..1.
data class CssColour(val r: Double, val g: Double, val b: Double, val a: Double = 1.0) {
    companion object {
        fun parse(text: String?): CssColour? {
            val t = text?.trim()?.lowercase() ?: return null
            if (t.startsWith("#")) return ThemeColour.parse(t)?.let { CssColour(it.red, it.green, it.blue, it.alpha) }
            if (t.startsWith("rgb")) {
                val inner = t.substringAfter('(', "").substringBefore(')')
                val parts = inner.split(',', ' ', '/').map { it.trim() }.filter { it.isNotEmpty() }
                if (parts.size < 3) return null
                fun channel(s: String) = (if (s.endsWith("%")) s.dropLast(1).toDoubleOrNull()?.div(100.0) else s.toDoubleOrNull()?.div(255.0))?.coerceIn(0.0, 1.0)
                val r = channel(parts[0]) ?: return null
                val g = channel(parts[1]) ?: return null
                val b = channel(parts[2]) ?: return null
                val a = parts.getOrNull(3)?.let { if (it.endsWith("%")) it.dropLast(1).toDoubleOrNull()?.div(100.0) else it.toDoubleOrNull() }?.coerceIn(0.0, 1.0) ?: 1.0
                return CssColour(r, g, b, a)
            }
            return null
        }
    }
}

data class SceneStop(val at: Double, val colour: CssColour)

sealed class SceneLayer {
    data class Gradient(val angle: Double, val stops: List<SceneStop>) : SceneLayer()
    data class Radial(val x: Double, val y: Double, val w: Double, val h: Double, val colour: CssColour, val fade: Double) : SceneLayer()
    data class Shape(val kind: String, val x: Double, val y: Double, val size: Double, val colour: CssColour?, val stops: List<SceneStop>) : SceneLayer()
    // A picture of the theme: not drawn natively yet.
    data class Image(val file: String) : SceneLayer()
}

data class Gloss(val highlight: CssColour, val upper: CssColour, val lower: CssColour, val glow: CssColour, val edge: CssColour)
data class Glass(val hi: CssColour, val lo: CssColour, val edge: CssColour, val shadow: CssColour)

enum class Amount(val factor: Float) { None(0f), Subtle(0.5f), Full(1f) }

data class Look(
    val type: String = "system",
    val glass: Amount = Amount.None,
    val gloss: Amount = Amount.None,
    val scene: List<SceneLayer> = emptyList(),
    val glassRecipe: Glass? = null,
    val glossRecipe: Gloss? = null,
) {
    // On modest hardware and with reduced motion or transparency only the first layer is drawn.
    fun sceneFor(reduced: Boolean): List<SceneLayer> = if (reduced) scene.take(1) else scene

    companion object {
        val NONE = Look()

        private fun amount(e: JsonElement?): Amount = when ((e as? JsonPrimitive)?.content) { "full" -> Amount.Full; "subtle" -> Amount.Subtle; else -> Amount.None }
        private fun num(o: JsonObject, k: String, d: Double = 0.0) = (o[k] as? JsonPrimitive)?.doubleOrNull ?: d
        private fun str(o: JsonObject, k: String) = (o[k] as? JsonPrimitive)?.takeIf { it.isString }?.content
        private fun stops(e: JsonElement?): List<SceneStop> = (e as? JsonArray).orEmpty().mapNotNull { s ->
            val o = s as? JsonObject ?: return@mapNotNull null
            SceneStop(num(o, "at"), CssColour.parse(str(o, "color")) ?: return@mapNotNull null)
        }

        fun scene(e: JsonElement?): List<SceneLayer> {
            val layers = (e as? JsonObject)?.get("layers") as? JsonArray ?: return emptyList()
            return layers.mapNotNull { l ->
                val o = l as? JsonObject ?: return@mapNotNull null
                when (str(o, "type")) {
                    "gradient" -> stops(o["stops"]).takeIf { it.size >= 2 }?.let { SceneLayer.Gradient(num(o, "angle", 180.0), it) }
                    "radial" -> CssColour.parse(str(o, "color"))?.let { SceneLayer.Radial(num(o, "x", 50.0), num(o, "y", 50.0), num(o, "w", 50.0), num(o, "h", 50.0), it, num(o, "fade", 70.0)) }
                    "shape" -> SceneLayer.Shape(str(o, "kind") ?: "circle", num(o, "x"), num(o, "y"), num(o, "size", 10.0), CssColour.parse(str(o, "color")), stops(o["stops"]))
                    "image" -> str(o, "file")?.let { SceneLayer.Image(it) }
                    else -> null
                }
            }
        }

        // `GET /theme`'s `look`; anything missing is the plain look.
        fun from(theme: JsonObject): Look {
            val look = runCatching { theme["look"]?.jsonObject }.getOrNull() ?: return NONE
            val effects = look["effects"] as? JsonObject
            val finish = look["finish"] as? JsonObject
            val glassO = finish?.get("glass") as? JsonObject
            val glossO = finish?.get("gloss") as? JsonObject
            fun c(o: JsonObject?, k: String) = CssColour.parse(o?.let { str(it, k) })
            val glass = if (glassO != null) {
                val hi = c(glassO, "hi"); val lo = c(glassO, "lo"); val edge = c(glassO, "edge"); val shadow = c(glassO, "shadow")
                if (hi != null && lo != null && edge != null && shadow != null) Glass(hi, lo, edge, shadow) else null
            } else null
            val gloss = if (glossO != null) {
                val h = c(glossO, "highlight"); val u = c(glossO, "upper"); val lo = c(glossO, "lower"); val g = c(glossO, "glow"); val e = c(glossO, "edge")
                if (h != null && u != null && lo != null && g != null && e != null) Gloss(h, u, lo, g, e) else null
            } else null
            return Look(
                type = (look["type"] as? JsonPrimitive)?.content ?: "system",
                glass = amount(effects?.get("glass")), gloss = amount(effects?.get("gloss")),
                scene = scene(look["scene"] ?: theme["scene"]), glassRecipe = glass, glossRecipe = gloss,
            )
        }
    }
}

object TypeSets {
    val ALL = listOf("system", "humanist", "rounded", "mono", "serif")
    fun known(set: String) = set in ALL
}
