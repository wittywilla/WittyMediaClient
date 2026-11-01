package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.focusRestorer
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.InputMode
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalInputModeManager
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import coil3.request.ImageRequest

// Where focus was on each screen, so that coming back puts it where it was.
class FocusMemory {
    var last: String? = null
}

val LocalFocusMemory = compositionLocalOf { FocusMemory() }

// The one focusable surface in the app. Focus shows as a ring and a slightly larger card, with no
// animation, so it stays smooth on a slow TV stick. On a touch screen there's no ring: nothing is
// "focused" for someone using a finger. Unavailable things keep their focus (a remote with nothing
// focused has nowhere to go) and simply do nothing, and a screen reader is told so.
@Composable
fun FocusBox(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    label: String? = null,
    state: String? = null,
    selected: Boolean = false,
    focusKey: String? = null,
    requestFocus: Boolean = false,
    takeFocus: Boolean = false,
    enabled: Boolean = true,
    filled: Color = Color.Transparent,
    shape: Shape = Radius.MD,
    content: @Composable () -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    val requester = remember { FocusRequester() }
    val memory = LocalFocusMemory.current
    val metrics = LocalMetrics.current
    val keyboardMode = LocalInputModeManager.current.inputMode == InputMode.Keyboard
    val reduce = LocalReduceMotion.current
    val comingBack = focusKey != null && memory.last == focusKey
    // requestFocus is for the screen's first look. takeFocus is for something that has just appeared
    // on top of a screen, such as a list of tracks, whatever had focus before.
    if (comingBack || takeFocus || (requestFocus && memory.last == null)) LaunchedEffect(focusKey, requestFocus, takeFocus) { runCatching { requester.requestFocus() } }
    val showing = focused && keyboardMode
    val ring = if (showing) MaterialTheme.colorScheme.onBackground else Color.Transparent
    val grow = if (showing && !reduce) metrics.focusScale else 1f
    Box(
        modifier
            .graphicsLayer { scaleX = grow; scaleY = grow }
            .focusRequester(requester)
            .onFocusChanged { if (it.isFocused && focusKey != null) memory.last = focusKey }
            .semantics {
                if (label != null) contentDescription = label
                if (state != null) stateDescription = state
                if (selected) this.selected = true
                if (!enabled) disabled()
            }
            .border(BorderStroke(metrics.focusRing, ring), shape)
            .padding(metrics.focusRing)
            .clip(shape)
            .background(filled)
            .clickable(interactionSource = interaction, indication = null, role = Role.Button) { if (enabled) onClick() },
    ) { content() }
}

@Composable
fun ActionButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    primary: Boolean = false,
    requestFocus: Boolean = false,
    takeFocus: Boolean = false,
    enabled: Boolean = true,
    selected: Boolean = false,
    focusKey: String? = null,
    state: String? = null,
    icon: ImageVector? = null,
    pill: Boolean = false,
) {
    val scheme = MaterialTheme.colorScheme
    val metrics = LocalMetrics.current
    val fill = if (primary) scheme.primary else if (selected) scheme.outline else scheme.surfaceVariant
    val ink = if (primary) scheme.onPrimary else scheme.onSurface
    FocusBox(
        onClick, modifier, label = null, state = state ?: if (selected) "Selected" else null, selected = selected, focusKey = focusKey,
        requestFocus = requestFocus, takeFocus = takeFocus, enabled = enabled, filled = fill, shape = if (pill) Radius.FULL else Radius.MD,
    ) {
        Row(
            Modifier
                .defaultMinSize(minHeight = metrics.minTarget)
                .padding(horizontal = Space.S4, vertical = Space.S2)
                .graphicsLayer { alpha = if (enabled) 1f else 0.55f },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Space.S2),
        ) {
            if (icon != null) Icon(icon, contentDescription = null, tint = ink)
            Text(text, color = ink, style = MaterialTheme.typography.labelLarge, textAlign = TextAlign.Center)
        }
    }
}

// A row on a remote. Left and right stay in it, and coming back lands where it was left. Without
// this, pressing on past the end jumps to whatever happens to be up and to the side.
@Composable
fun Modifier.remoteRow(): Modifier =
    focusRestorer()
        .focusProperties {
            onExit = {
                if (requestedFocusDirection == FocusDirection.Left || requestedFocusDirection == FocusDirection.Right) cancelFocusChange()
            }
        }
        .focusGroup()

// The one heading of a page, or above a row.
@Composable
fun Heading(text: String, modifier: Modifier = Modifier) {
    Text(text, color = MaterialTheme.colorScheme.onBackground, style = MaterialTheme.typography.headlineMedium, modifier = modifier.semantics { heading() })
}

@Composable
fun SectionTitle(text: String, modifier: Modifier = Modifier) {
    Text(text, color = MaterialTheme.colorScheme.onBackground, style = MaterialTheme.typography.titleMedium, modifier = modifier.semantics { heading() })
}

@Composable
fun Secondary(text: String, modifier: Modifier = Modifier, maxLines: Int = Int.MAX_VALUE) {
    Text(text, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium, modifier = modifier, maxLines = maxLines, overflow = TextOverflow.Ellipsis)
}

// What went wrong: said aloud when it appears, and marked by more than its colour.
@Composable
fun ErrorText(text: String, modifier: Modifier = Modifier) {
    if (text.isEmpty()) return
    Row(modifier.semantics { liveRegion = LiveRegionMode.Polite }, horizontalArrangement = Arrangement.spacedBy(Space.S2)) {
        Box(Modifier.width(Space.S5).aspectRatio(1f).clip(CircleShape).background(MaterialTheme.colorScheme.error), contentAlignment = Alignment.Center) {
            Text("!", color = MaterialTheme.colorScheme.background, style = MaterialTheme.typography.labelMedium)
        }
        Text(text, color = MaterialTheme.colorScheme.onBackground, style = MaterialTheme.typography.bodyLarge)
    }
}

@Composable
fun Loading() {
    Box(Modifier.fillMaxSize().semantics { contentDescription = "Loading" }, contentAlignment = Alignment.Center) { CircularProgressIndicator() }
}

@Composable
fun Screen(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) { content() }
}

// A picture from the server, asked for at the size it's shown. Items without one answer 404, and
// the words underneath stand in for it.
@Composable
fun ServerImage(url: String, widthDp: Dp, aspect: Float, modifier: Modifier = Modifier, placeholder: String = "") {
    val context = LocalContext.current
    val pixelsWide = with(LocalDensity.current) { widthDp.toPx() }.toInt().coerceAtLeast(1)
    val request = remember(url, pixelsWide, aspect) {
        ImageRequest.Builder(context).data(url).size(pixelsWide, (pixelsWide / aspect).toInt().coerceAtLeast(1)).build()
    }
    Box(modifier.background(MaterialTheme.colorScheme.surfaceVariant), contentAlignment = Alignment.Center) {
        if (placeholder.isNotEmpty()) {
            Text(
                placeholder, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall,
                textAlign = TextAlign.Center, maxLines = 4, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(Space.S2),
            )
        }
        AsyncImage(model = request, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
    }
}

// A poster tile. Heard as one thing: its title and what's underneath.
@Composable
fun PosterCard(
    title: String,
    subtitle: String,
    imageUrl: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    aspect: Float = 2f / 3f,
    focusKey: String? = null,
    requestFocus: Boolean = false,
    progress: Float? = null,
) {
    val width = LocalMetrics.current.cardWidth
    val scheme = MaterialTheme.colorScheme
    val label = if (subtitle.isEmpty()) title else "$title, $subtitle"
    FocusBox(onClick, modifier.width(width), label = label, focusKey = focusKey, requestFocus = requestFocus) {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Space.S1)) {
            Box(Modifier.fillMaxWidth().aspectRatio(aspect).clip(Radius.MD)) {
                ServerImage(imageUrl, width, aspect, Modifier.fillMaxSize(), placeholder = title)
                if (progress != null) {
                    Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(Space.S1).background(Color(0x99000000), Radius.XS)) {
                        Box(Modifier.fillMaxWidth(progress.coerceIn(0f, 1f)).height(Space.S1).background(scheme.primary, Radius.XS))
                    }
                }
            }
            // Inset, so the focus ring doesn't run through the words.
            Text(title, color = scheme.onBackground, maxLines = 2, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(horizontal = Space.S1))
            if (subtitle.isNotEmpty()) Text(subtitle, color = scheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(horizontal = Space.S1))
        }
    }
}
