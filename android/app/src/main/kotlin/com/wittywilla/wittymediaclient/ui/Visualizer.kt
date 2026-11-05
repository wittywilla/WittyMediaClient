package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import com.wittywilla.wittymediaclient.player.SoundShaping
import com.wittywilla.wittymediaclient.player.Spectrum
import com.wittywilla.wittymediaclient.player.VisualizerLevels
import kotlin.math.PI
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

// The player's own moving pictures behind the artwork, as the website's backdrop draws them (web/src/audio/backdrop.ts):
// Bars, Waves and Drift, from the sound itself, which the listening service's processor keeps a copy of (SoundShaper),
// so nothing is recorded and no permission is asked for. 30 frames a second, or 20 with Slow or Reduce Motion, which
// also slow the motion. Paused, it settles and then draws nothing new until the music plays again.

private const val MOTES = 14

private class Mote(var x: Double, var y: Double, val r: Double, val vx: Double, val vy: Double, val band: Int)

// What a frame needs from the last one.
private class Backdrop {
    val levels = DoubleArray(VisualizerLevels.COUNT)
    val motes = List(MOTES) { i -> Mote(Math.random(), Math.random(), 0.12 + Math.random() * 0.2, (Math.random() - 0.5) * 0.02, (Math.random() - 0.5) * 0.02, i % 6) }
    val samples = FloatArray(2048)
    val bins = IntArray(1024)
    val spectrum = Spectrum()
    var last = 0L
    var t = 0.0
    var dt = 0.0
    var idle = false

    // Levels from low to high, on a scale that spreads the music across the bars.
    fun step(now: Long, active: Boolean, slow: Boolean, drifting: Boolean) {
        dt = min(0.2, if (last == 0L) 1.0 / 30 else (now - last) / 1000.0)
        last = now
        val heard = active && SoundShaping.heard?.lastHeard(samples) == true
        if (heard) spectrum.bins(samples, bins)
        for (i in levels.indices) {
            val v = when {
                heard -> {
                    var peak = 0
                    for (k in VisualizerLevels.bins(i)) if (k < bins.size) peak = max(peak, bins[k])
                    VisualizerLevels.level(peak, i)
                }
                active -> VisualizerLevels.swell(now.toDouble(), i)
                else -> 0.0
            }
            levels[i] = VisualizerLevels.follow(levels[i], v, dt, slow)
        }
        t += dt * if (slow) 0.35 else 1.0
        if (drifting) drift(slow)
    }

    // The lights wander, livelier with the music, and come back in at the other side.
    private fun drift(slow: Boolean) {
        val push = if (slow) 0.35 else 1.0
        for (m in motes) {
            val level = levels[min(levels.size - 1, m.band * 3)]
            m.x += m.vx * dt * push * (1 + level * 2)
            m.y += m.vy * dt * push * (1 + level * 2)
            if (m.x < -0.2) m.x = 1.2 else if (m.x > 1.2) m.x = -0.2
            if (m.y < -0.2) m.y = 1.2 else if (m.y > 1.2) m.y = -0.2
        }
    }

    fun band(a: Int, b: Int): Double {
        var sum = 0.0
        for (i in a until min(b, levels.size)) sum += levels[i]
        return sum / max(1, b - a)
    }
}

@Composable
internal fun VisualizerBackground(style: String, slow: Boolean, colour: Color, playing: Boolean, modifier: Modifier = Modifier) {
    val calm = LocalReduceMotion.current
    val gentle = slow || calm
    val drawer = remember { Backdrop() }
    var frame by remember { mutableLongStateOf(0L) }
    val active by rememberUpdatedState(playing)
    val drifting by rememberUpdatedState(style == "drift")
    // Not while the app is out of sight.
    val shown = LocalLifecycleOwner.current.lifecycle.currentStateAsState().value.isAtLeast(Lifecycle.State.STARTED)
    LaunchedEffect(gentle, shown) {
        if (!shown) return@LaunchedEffect
        val gap = if (gentle) 1000 / 20 else 1000 / 30
        drawer.last = 0L
        while (true) {
            val now = withFrameMillis { it }
            if (drawer.last != 0L && now - drawer.last < gap - 2) continue
            drawer.step(now, active, gentle, drifting)
            // Settled and paused: what's on screen is already right.
            if (!active && drawer.levels.all { it < 0.004 }) {
                if (drawer.idle) continue
                drawer.idle = true
            } else drawer.idle = false
            frame = now
        }
    }
    // A layer of its own, so Drift's lights add to each other and not to what's behind.
    Canvas(modifier.fillMaxSize().graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }.clearAndSetSemantics { }) {
        if (frame < 0) return@Canvas
        when (style) {
            "waves" -> waves(drawer, colour)
            "drift" -> drift(drawer, colour)
            else -> bars(drawer, colour)
        }
    }
}

// Bars: 46, mirrored from the middle, each side fading towards the edge; up from 62% of the height to at most 46% of it.
private fun DrawScope.bars(drawer: Backdrop, colour: Color) {
    val n = VisualizerLevels.COUNT
    val w = size.width
    val h = size.height
    val gap = w / (n * 2)
    val width = gap * 0.62f
    val base = h * 0.62f
    val tall = h * 0.46f
    val shade = Brush.verticalGradient(listOf(colour.copy(alpha = 0.55f), colour.copy(alpha = 0f)), startY = base - tall, endY = base)
    for (i in 0 until n) {
        val v = 0.12 + drawer.levels[i] * 0.88
        val high = min(tall, (v * tall).toFloat())
        val off = (i + 0.5f) * gap
        val alpha = 1 - i.toFloat() / n * 0.72f
        drawRect(shade, Offset(w / 2 + off - width / 2, base - high), Size(width, high), alpha = alpha)
        drawRect(shade, Offset(w / 2 - off - width / 2, base - high), Size(width, high), alpha = alpha)
    }
}

// Waves: three soft layers for the low, middle and high sounds, moving at their own speeds.
private fun DrawScope.waves(drawer: Backdrop, colour: Color) {
    val w = size.width
    val h = size.height
    val low = drawer.band(0, 4)
    val mid = drawer.band(4, 12)
    val high = drawer.band(12, 23)
    data class Layer(val a: Double, val f: Double, val s: Double, val y: Double, val o: Float)
    val layers = listOf(Layer(0.2 + low * 0.3, 1.2, 0.5, 0.62, 0.3f), Layer(0.12 + mid * 0.28, 2.1, -0.7, 0.6, 0.22f), Layer(0.07 + high * 0.22, 3.4, 1.0, 0.58, 0.16f))
    for (layer in layers) {
        val path = Path()
        path.moveTo(0f, h)
        var x = 0f
        while (x <= w) {
            val u = (x / w).toDouble()
            val envelope = sin(u * PI) * 0.8 + 0.2
            val y = h * layer.y - envelope * h * 0.42 * layer.a * (0.6 + 0.4 * sin(u * layer.f * 6.283 + drawer.t * layer.s * 1.4)) - h * 0.02 * sin(u * 3 + drawer.t * layer.s)
            path.lineTo(x, y.toFloat())
            x += 8
        }
        path.lineTo(w, h)
        path.close()
        drawPath(path, Brush.verticalGradient(listOf(colour.copy(alpha = layer.o), colour.copy(alpha = 0f)), startY = h * 0.2f, endY = h * 0.8f))
    }
}

// Drift: fourteen soft lights, bigger and brighter with the music, added to each other.
private fun DrawScope.drift(drawer: Backdrop, colour: Color) {
    val w = size.width.toDouble()
    val h = size.height.toDouble()
    for (m in drawer.motes) {
        val level = drawer.levels[min(drawer.levels.size - 1, m.band * 3)]
        val side = (m.r + level * 0.1) * max(w, h)
        val centre = Offset((m.x * w).toFloat(), (m.y * h).toFloat())
        val radius = (side / 2).toFloat()
        val light = Brush.radialGradient(0f to colour.copy(alpha = 0.5f), 0.5f to colour.copy(alpha = 0.16f), 1f to colour.copy(alpha = 0f), center = centre, radius = radius)
        drawCircle(light, radius, centre, alpha = (0.45 + min(0.45, level * 0.5)).toFloat(), blendMode = BlendMode.Plus)
    }
}
