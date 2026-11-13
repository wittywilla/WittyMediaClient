// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.wittywilla.wittymediaclient.net.BrandColor
import com.wittywilla.wittymediaclient.net.BrandEditor
import com.wittywilla.wittymediaclient.net.BrandMarkChoice
import com.wittywilla.wittymediaclient.net.BrandPart
import com.wittywilla.wittymediaclient.net.ThemeColour

// The name editor's smaller parts: the colour picker, the gradient's stops, and the live previews in every frame the name
// appears in (docs/plans/DESIGN-2.md 7.6; the canvas page BrandEditor).

// "Any colour…": hue, saturation and brightness with a hex field. Every slider is named and focusable, so a remote or a
// keyboard moves it with the arrows.
@Composable
fun ColourPickerDialog(title: String, initial: String, onPick: (String) -> Unit, onDismiss: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val metrics = LocalMetrics.current
    var hsv by remember { mutableStateOf(BrandEditor.Hsv.of(initial)) }
    var typed by remember { mutableStateOf(BrandEditor.Hsv.of(initial).hex) }
    fun set(next: BrandEditor.Hsv) { hsv = next; typed = next.hex }
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(
            Modifier.padding(metrics.u(16)).fillMaxWidth().heightIn(max = 560.dp).background(scheme.surface, RoundedCornerShape(metrics.u(20)))
                .border(1.dp, scheme.outline, RoundedCornerShape(metrics.u(20))).verticalScroll(rememberScrollState()).padding(metrics.u(20)),
            verticalArrangement = Arrangement.spacedBy(metrics.u(12)),
        ) {
            Text(title, color = scheme.onSurface, style = MaterialTheme.typography.title, modifier = Modifier.semantics { heading() })
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(metrics.u(12))) {
                val now = ThemeColour.parse(hsv.hex)?.let { Color(it.argb) } ?: Color.Gray
                Box(Modifier.size(metrics.u(56)).background(now, RoundedCornerShape(metrics.u(12))).border(1.dp, scheme.outline, RoundedCornerShape(metrics.u(12))).semantics { contentDescription = "Chosen colour ${hsv.hex}" })
                WittyField(
                    typed, { text ->
                        typed = text
                        BrandEditor.normalHex(text)?.let { hsv = BrandEditor.Hsv.of(it) }
                    },
                    "Hex colour", Modifier.weight(1f), maxLength = 7,
                )
            }
            Slide("Hue", hsv.h.toFloat(), 0f..359f) { set(hsv.copy(h = it.toDouble())) }
            Slide("Saturation", (hsv.s * 100).toFloat(), 0f..100f) { set(hsv.copy(s = it / 100.0)) }
            Slide("Brightness", (hsv.v * 100).toFloat(), 0f..100f) { set(hsv.copy(v = it / 100.0)) }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(metrics.u(8), Alignment.End)) {
                WittyButton("Cancel", onDismiss, pill = true, focusKey = "~pick-cancel")
                WittyButton("Use this colour", { onPick(BrandEditor.normalHex(typed) ?: hsv.hex) }, kind = ButtonKind.Primary, pill = true, focusKey = "~pick-use", requestFocus = true)
            }
        }
    }
}

@Composable
private fun Slide(name: String, value: Float, range: ClosedFloatingPointRange<Float>, onChange: (Float) -> Unit) {
    val metrics = LocalMetrics.current
    Column {
        Text("$name ${value.toInt()}", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.caption)
        Slider(value, onChange, Modifier.heightIn(min = if (metrics.tv) metrics.u(66) else 44.dp).semantics { contentDescription = name }, valueRange = range)
    }
}

private val DIRECTIONS = listOf(90 to "Left to right", 270 to "Right to left", 135 to "Down and right", 45 to "Up and right")

// "Edit stops…": two to four fixed colours, and the direction.
@Composable
fun GradientDialog(initialStops: List<String>, initialAngle: Int, onDone: (List<String>, Int) -> Unit, onDismiss: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val metrics = LocalMetrics.current
    var stops by remember { mutableStateOf(initialStops.ifEmpty { BrandEditor.DEFAULT_GRADIENT }) }
    var angle by remember { mutableStateOf(if (initialAngle in DIRECTIONS.map { it.first }) initialAngle else 90) }
    var editing by remember { mutableStateOf<Int?>(null) }
    val parts = remember(stops, angle) { listOf(BrandPart("WittyMediaServer", color = BrandColor.gradient(stops, angle))) }
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(
            Modifier.padding(metrics.u(16)).fillMaxWidth().heightIn(max = 600.dp).background(scheme.surface, RoundedCornerShape(metrics.u(20)))
                .border(1.dp, scheme.outline, RoundedCornerShape(metrics.u(20))).verticalScroll(rememberScrollState()).padding(metrics.u(20)),
            verticalArrangement = Arrangement.spacedBy(metrics.u(12)),
        ) {
            Text("Gradient stops", color = scheme.onSurface, style = MaterialTheme.typography.title, modifier = Modifier.semantics { heading() })
            Text(brandText(parts), fontSize = (26 * metrics.unit.coerceAtLeast(1f)).sp, fontWeight = FontWeight.ExtraBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text("Two to four colours, the same in every theme.", color = scheme.onSurfaceVariant, style = MaterialTheme.typography.caption)
            stops.forEachIndexed { i, hex ->
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(metrics.u(10))) {
                    Swatch(ThemeColour.parse(hex)?.let { Color(it.argb) }, null, "Stop ${i + 1}, $hex. Change it", false, focusKey = "~stop$i") { editing = i }
                    Text("Stop ${i + 1}  $hex", color = scheme.onSurface, style = MaterialTheme.typography.body, modifier = Modifier.weight(1f))
                    if (stops.size > 2) WittyButton("Remove", { stops = stops.filterIndexed { j, _ -> j != i } }, Modifier.semantics { contentDescription = "Remove stop ${i + 1}" }, pill = true)
                }
            }
            if (stops.size < 4) WittyButton("Add a stop", { stops = stops + stops.last() }, pill = true, focusKey = "~stop-add")
            EdLabel("Direction")
            EdChoices(DIRECTIONS.map { it.first.toString() to it.second }, angle.toString(), "Direction") { angle = it.toInt() }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(metrics.u(8), Alignment.End)) {
                WittyButton("Cancel", onDismiss, pill = true, focusKey = "~grad-cancel")
                WittyButton("Use this gradient", { onDone(stops, angle) }, kind = ButtonKind.Primary, pill = true, focusKey = "~grad-use")
            }
        }
    }
    editing?.let { i ->
        ColourPickerDialog("Stop ${i + 1}", stops[i], { hex -> stops = stops.mapIndexed { j, s -> if (j == i) hex else s }; editing = null }, { editing = null })
    }
}

// The name's parts as text in the theme in force.
@Composable
fun brandText(parts: List<BrandPart>): androidx.compose.ui.text.AnnotatedString {
    val ink = MaterialTheme.colorScheme.onBackground
    val accent = LocalExtraColours.current.brandAccent
    val theme = LocalAppTheme.current
    return remember(parts, ink, accent, theme) { buildBrandText(parts, ink, accent, theme) }
}

// One frame of the live preview: its own surface, with its name in the top corner, and the name said once, whole.
@Composable
private fun Frame(label: String, name: String, background: Color, height: Dp, modifier: Modifier = Modifier, content: @Composable androidx.compose.foundation.layout.BoxScope.() -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val metrics = LocalMetrics.current
    Box(
        modifier.fillMaxWidth().heightIn(min = height).clip(RoundedCornerShape(metrics.u(12))).background(background, RoundedCornerShape(metrics.u(12))).border(1.dp, scheme.outline, RoundedCornerShape(metrics.u(12)))
            .semantics(mergeDescendants = true) { contentDescription = "Preview, $label: $name" },
    ) {
        Text(label, color = LocalExtraColours.current.hint, fontSize = (12 * (if (metrics.tv) 1.4f else 1f)).sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.align(Alignment.TopEnd).padding(horizontal = metrics.u(12), vertical = metrics.u(8)))
        content()
    }
}

// The name in every frame it appears in: the side menu, the top bar and a TV's bar, the rail header when it is open,
// sign-in and About. All of it is drawn through the same text the real frames use.
@Composable
fun BrandFrames(parts: List<BrandPart>, name: String, mark: BrandMarkChoice, logo: Any?, version: String, modifier: Modifier = Modifier) {
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val metrics = LocalMetrics.current
    val shown = name.ifEmpty { BrandEditorWords.DEFAULT }
    val text = brandText(parts)
    val big = if (metrics.tv) 1.5f else 1f
    Column(modifier, verticalArrangement = Arrangement.spacedBy(metrics.u(14))) {
        Frame("Side menu", shown, scheme.surface, 80.dp) {
            Text(text, fontSize = (26 * big).sp, fontWeight = FontWeight.ExtraBold, letterSpacing = (-0.4).sp, modifier = Modifier.padding(horizontal = metrics.u(20), vertical = metrics.u(24)).padding(top = metrics.u(8)))
        }
        Frame("Top bar and TV bar", shown, scheme.background, 80.dp) {
            Row(Modifier.padding(horizontal = metrics.u(20), vertical = metrics.u(18)).padding(top = metrics.u(10)), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(metrics.u(20))) {
                Text(text, fontSize = (22 * big).sp, fontWeight = FontWeight.ExtraBold, letterSpacing = (-0.4).sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                Text("Home", color = extra.accentText, fontSize = (14 * big).sp, modifier = Modifier.background(scheme.primary.copy(alpha = 0.16f), RoundedCornerShape(50)).padding(horizontal = metrics.u(14), vertical = metrics.u(6)))
                Text("Libraries", color = scheme.onSurfaceVariant, fontSize = (14 * big).sp, maxLines = 1)
                Text("Live TV", color = scheme.onSurfaceVariant, fontSize = (14 * big).sp, maxLines = 1)
            }
        }
        Frame("Rail header, when open", shown, scheme.surface, 80.dp) {
            Row(Modifier.padding(horizontal = metrics.u(20), vertical = metrics.u(16)), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(metrics.u(14))) {
                BrandMarkBadge(name, parts, mark, logo, if (metrics.tv) metrics.u(56) else 48.dp)
                Text(text, fontSize = (20 * big).sp, fontWeight = FontWeight.ExtraBold, maxLines = 2)
            }
        }
        Frame("Sign-in", shown, scheme.background, 200.dp) {
            Box(Modifier.matchParentSize().signInGlow(scheme.primary))
            Column(Modifier.fillMaxWidth().padding(vertical = metrics.u(36)), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(metrics.u(14))) {
                Text(text, fontSize = (38 * big).sp, fontWeight = FontWeight.ExtraBold, letterSpacing = (-1).sp, modifier = Modifier.padding(horizontal = metrics.u(16)))
                Box(Modifier.size(width = 240.dp, height = metrics.u(44)).background(scheme.primary, RoundedCornerShape(metrics.u(10))), contentAlignment = Alignment.Center) {
                    Text("Sign in", color = scheme.onPrimary, fontSize = (15 * big).sp, fontWeight = FontWeight.Bold)
                }
            }
        }
        Frame("About", shown, scheme.surfaceVariant, 90.dp) {
            Column(Modifier.padding(horizontal = metrics.u(20), vertical = metrics.u(18)).padding(top = metrics.u(10)), verticalArrangement = Arrangement.spacedBy(metrics.u(4))) {
                Text(text, fontSize = (22 * big).sp, fontWeight = FontWeight.ExtraBold)
                Text(if (version.isEmpty()) "Version" else "Version $version", color = scheme.onSurfaceVariant, fontSize = (13 * big).sp)
            }
        }
    }
}

object BrandEditorWords {
    const val DEFAULT = "WittyMediaServer"
}
