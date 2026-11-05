package com.wittywilla.wittymediaclient.games

import android.view.HapticFeedbackConstants
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.PointerId
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt

// The account's touch layout from the server, drawn over the game as the website's player draws it (WittyPlay's
// TouchControls): glass controls in the console's own colour, a D-pad of eight slices, an analog stick that follows
// the thumb, and buttons by the console's own names. Fingers that miss every control on a console with a touch
// screen (the DS) are the stylus, on the picture.

private val EDGE = Color.White.copy(alpha = 0.42f)
private val SHEEN = Color.White.copy(alpha = 0.10f)
private val INK = Color.White.copy(alpha = 0.95f)
private val HIT = Color.White.copy(alpha = 0.92f)
private val HIT_INK = Color(0xFF0A0C12)
private val CAP = Color(0x38FFFFFF)

// The glass behind each control, by the shape of the console's pad.
private fun glass(art: String): Color = when (art) {
    "two" -> Color(38, 18, 20, (0.52f * 255).roundToInt())
    "one" -> Color(40, 28, 14, 128)
    "four" -> Color(26, 20, 44, 128)
    "six" -> Color(14, 26, 44, (0.52f * 255).roundToInt())
    "handle" -> Color(14, 32, 30, 128)
    "dual" -> Color(16, 20, 34, 128)
    else -> Color(16, 18, 26, 128)
}

private val parser = PathParser()
private fun path(d: String): Path = parser.parsePathString(d).toPath()

private val DPAD_SHAPE by lazy { path("M37 3h26a5 5 0 015 5v24h24a5 5 0 015 5v26a5 5 0 01-5 5H68v24a5 5 0 01-5 5H37a5 5 0 01-5-5V68H8a5 5 0 01-5-5V37a5 5 0 015-5h24V8a5 5 0 015-5z") }
private val ARROWS by lazy {
    listOf(
        RetroPad.UP to path("M50 11l9 11H41z"),
        RetroPad.DOWN to path("M50 89l-9-11h18z"),
        RetroPad.LEFT to path("M11 50l11-9v18z"),
        RetroPad.RIGHT to path("M89 50l-11 9V41z"),
    )
}

// PlayStation's shapes, drawn rather than written.
private val SHAPES by lazy {
    mapOf(
        "□" to path("M33 33h34v34H33z"),
        "△" to path("M50 28l23 40H27z"),
        "○" to path("M50 29a21 21 0 110 42 21 21 0 010-42z"),
        "✕" to path("M32 32l36 36M68 32L32 68"),
    )
}

// Arrows for buttons named "C up" and so on (the Nintendo 64).
private val C_ARROWS by lazy {
    mapOf(
        "up" to path("M50 26l24 42H26z"),
        "down" to path("M50 74L26 32h48z"),
        "left" to path("M26 50l42-24v48z"),
        "right" to path("M74 50L32 74V26z"),
    )
}

@Composable
fun TouchControls(
    controls: GameControls,
    orientation: String,
    // Where the picture is, in this layer's own pixels: for a console with a touch screen.
    picture: Rect,
    onButtons: (mask: Int, stickX: Double, stickY: Double) -> Unit,
    onPointer: (pressed: Boolean, fx: Double, fy: Double) -> Unit,
    modifier: Modifier = Modifier,
) {
    val layout = remember(controls, orientation) { controls.touchLayout(orientation) }
    val list = controls.controls
    val view = LocalView.current
    val pointerConsole = controls.pad.pointer
    var held by remember { mutableIntStateOf(0) }
    var knob by remember { mutableStateOf(0.0 to 0.0) }
    val sendButtons by rememberUpdatedState(onButtons)
    val sendPointer by rememberUpdatedState(onPointer)
    val shownPicture by rememberUpdatedState(picture)
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    // Nothing stays held when the controls go.
    DisposableEffect(Unit) { onDispose { sendButtons(0, 0.0, 0.0) } }

    BoxWithConstraints(modifier.fillMaxSize()) {
        val w = constraints.maxWidth.toFloat()
        val h = constraints.maxHeight.toFloat()
        val area = TouchArea(w, h)
        Box(
            Modifier.fillMaxSize().pointerInput(controls, orientation, w, h) {
                val points = HashMap<PointerId, TouchPoint>()
                var stick: PointerId? = null
                var stylus: PointerId? = null
                fun stylusAt(pt: TouchPoint, pressed: Boolean) {
                    val r = shownPicture
                    if (r.width <= 0 || r.height <= 0) return
                    sendPointer(pressed, ((pt.x - r.left) / r.width).toDouble(), ((pt.y - r.top) / r.height).toDouble())
                }
                awaitPointerEventScope {
                    while (true) {
                        val event = awaitPointerEvent()
                        for (change in event.changes) {
                            val pt = TouchPoint(change.position.x, change.position.y)
                            val id = change.id
                            when {
                                change.pressed && !change.previousPressed -> {
                                    val takesStick = stick == null && TouchPad.hasStick(list, layout) && TouchPad.onStick(pt, list, layout, area)
                                    if (takesStick) {
                                        stick = id
                                        points[id] = pt
                                    } else if (pointerConsole && stylus == null && TouchPad.mask(listOf(pt), list, layout, area) == 0) {
                                        stylus = id
                                        stylusAt(pt, true)
                                    } else {
                                        points[id] = pt
                                    }
                                }
                                change.pressed -> if (id == stylus) stylusAt(pt, true) else if (points.containsKey(id)) points[id] = pt
                                else -> {
                                    if (id == stylus) {
                                        stylus = null
                                        stylusAt(pt, false)
                                    }
                                    points.remove(id)
                                    if (id == stick) stick = null
                                }
                            }
                            change.consume()
                        }
                        if (event.type == PointerEventType.Move || event.type == PointerEventType.Press || event.type == PointerEventType.Release) {
                            val fingers = points.filterKeys { it != stick }.values
                            val mask = TouchPad.mask(fingers, list, layout, area)
                            val push = TouchPad.stickPush(stick?.let { points[it] }, list, layout, area)
                            if (mask and held.inv() != 0) view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
                            if (mask != held || push != knob) {
                                held = mask
                                knob = push
                                sendButtons(mask, push.first, push.second)
                            }
                        }
                    }
                }
            },
        ) {
            val art = controls.pad.art
            for (c in list) {
                val p = layout[c.key] ?: continue
                if (p.hidden) continue
                val box = TouchPad.box(c, p, area)
                val wDp = with(density) { box.width.toDp() }
                val hDp = with(density) { box.height.toDp() }
                Canvas(
                    Modifier
                        .offset { IntOffset(box.left.roundToInt(), box.top.roundToInt()) }
                        .size(wDp, hDp)
                        .graphicsLayer { alpha = p.opacity.toFloat() },
                ) {
                    when {
                        c.isStick -> drawStick(art, knob)
                        c.kind == "dpad" -> drawDpad(art, held)
                        else -> drawButton(c, art, held and RetroPad.bit(c.id) != 0, box.fontSize, measurer)
                    }
                }
            }
        }
    }
}

private fun DrawScope.on100(block: DrawScope.() -> Unit) {
    val k = size.minDimension / 100f
    translate((size.width - 100 * k) / 2, (size.height - 100 * k) / 2) {
        scale(k, k, pivot = Offset.Zero) { block() }
    }
}

private fun DrawScope.drawDpad(art: String, mask: Int) = on100 {
    drawPath(DPAD_SHAPE, glass(art))
    drawPath(DPAD_SHAPE, EDGE, style = Stroke(1.5f))
    drawCircle(SHEEN, 9f, Offset(50f, 50f))
    for ((bit, arrow) in ARROWS) {
        val on = mask and RetroPad.bit(bit) != 0
        drawPath(arrow, if (on) HIT else INK.copy(alpha = 0.75f))
    }
}

private fun DrawScope.drawStick(art: String, knob: Pair<Double, Double>) = on100 {
    drawCircle(glass(art), 47f, Offset(50f, 50f))
    drawCircle(EDGE, 47f, Offset(50f, 50f), style = Stroke(1.5f))
    drawCircle(SHEEN, 30f, Offset(50f, 50f), style = Stroke(2f))
    val at = Offset(50f + knob.first.toFloat() * 26f, 50f + knob.second.toFloat() * 26f)
    drawCircle(CAP, 24f, at)
    drawCircle(EDGE, 24f, at, style = Stroke(1.5f))
    drawCircle(SHEEN, 14f, at)
}

private fun DrawScope.drawButton(c: GameControl, art: String, on: Boolean, fontSize: Float, measurer: TextMeasurer) {
    val em = fontSize
    val radius = when (c.kind) {
        "meta" -> size.height / 2
        "shoulder" -> em * 0.8f
        else -> if (art == "six") size.minDimension * 0.36f else size.minDimension / 2
    }
    val corner = CornerRadius(radius, radius)
    if (on) {
        drawRoundRect(HIT, cornerRadius = corner)
    } else {
        drawRoundRect(glass(art), cornerRadius = corner)
        drawRoundRect(Brush.radialGradient(listOf(SHEEN, Color.Transparent), center = Offset(size.width / 2, 0f), radius = size.width * 0.6f), cornerRadius = corner)
    }
    val edge = 1.5.dp.toPx()
    drawRoundRect(EDGE, topLeft = Offset(edge / 2, edge / 2), size = Size(size.width - edge, size.height - edge), cornerRadius = corner, style = Stroke(edge))
    val ink = if (on) HIT_INK else INK
    val arrow = Regex("^C (up|down|left|right)$").find(c.label)?.groupValues?.get(1)
    val shape = SHAPES[c.label]
    when {
        arrow != null -> on100 { drawPath(C_ARROWS.getValue(arrow), ink) }
        shape != null -> on100 { drawPath(shape, ink, style = if (c.label == "✕" || c.label == "○" || c.label == "□") Stroke(7f) else androidx.compose.ui.graphics.drawscope.Fill) }
        else -> {
            val words = measurer.measure(
                c.label,
                TextStyle(color = ink, fontSize = androidx.compose.ui.unit.TextUnit(((if (c.label.length > 2) em * 0.72f else em) / density / fontScale), androidx.compose.ui.unit.TextUnitType.Sp), fontWeight = if (c.kind == "meta") FontWeight.SemiBold else FontWeight.Bold),
                maxLines = 1,
            )
            drawText(words, topLeft = Offset((size.width - words.size.width) / 2, (size.height - words.size.height) / 2))
        }
    }
}
