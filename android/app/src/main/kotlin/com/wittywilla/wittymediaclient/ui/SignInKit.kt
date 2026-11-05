package com.wittywilla.wittymediaclient.ui

import android.view.KeyEvent
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.keyframes
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.nativeKeyCode
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

// The sign-in screens' pieces from docs/APP-DESIGN.md, "Signing in" and "Components". The Apple app
// draws the same from the same page.

private val COLUMN_MOST = 440.dp
private val COLUMN_ROOM = 32.dp

// One column in the middle, no wider than reads well, with the glow behind it. A third of the way down
// when it's short, and scrolling when it isn't. Back, where there's somewhere to go back to, is an arrow
// top left as well as the system's gesture. `wide` lets the column use the room, as a tablet's
// profile grid does.
@Composable
fun SignInPage(onBack: (() -> Unit)? = null, wide: Boolean = false, content: @Composable ColumnScope.() -> Unit) {
    val metrics = LocalMetrics.current
    val accent = MaterialTheme.colorScheme.primary
    BackHandler(enabled = onBack != null) { onBack?.invoke() }
    Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).signInGlow(accent)) {
        BoxWithConstraints(Modifier.fillMaxSize().safeDrawingPadding().imePadding()) {
            val view = constraints.maxHeight
            val room = with(LocalDensity.current) { COLUMN_ROOM.roundToPx() }
            val most = if (wide) Int.MAX_VALUE else with(LocalDensity.current) { COLUMN_MOST.roundToPx() }
            val side = with(LocalDensity.current) { metrics.gutter.roundToPx() }
            Layout(
                content = {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Space.S4), content = content)
                },
                modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()),
            ) { measurables, constraints ->
                val width = minOf(constraints.maxWidth - 2 * side, most).coerceAtLeast(0)
                val column = measurables.first().measure(Constraints(minWidth = width, maxWidth = width))
                val free = (view - column.height - 2 * room).coerceAtLeast(0)
                val height = maxOf(view, column.height + 2 * room)
                layout(constraints.maxWidth, height) { column.place((constraints.maxWidth - width) / 2, room + free / 3) }
            }
        }
        if (onBack != null) BackArrow(onBack, Modifier.safeDrawingPadding().padding(Space.S1))
    }
}

@Composable
fun BackArrow(onBack: () -> Unit, modifier: Modifier = Modifier) {
    Pressable(onBack, modifier.size(48.dp), shape = CircleShape, label = LocalWords.current["back"].orEmpty()) {
        Icon(Symbols.Back, contentDescription = null, tint = MaterialTheme.colorScheme.onBackground)
    }
}

// A TV, as Apple TV lays it out: the words on the left half, the actions on the right half, 64 apart, each
// centred up and down, inside the safe area and its 90-unit gutter (so 170 in from each side). The glow is
// behind the whole screen. The remote's Back goes back.
@Composable
fun TvSignInPage(onBack: (() -> Unit)? = null, words: @Composable ColumnScope.() -> Unit, actions: @Composable ColumnScope.() -> Unit) {
    val metrics = LocalMetrics.current
    val accent = MaterialTheme.colorScheme.primary
    BackHandler(enabled = onBack != null) { onBack?.invoke() }
    Row(
        Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .signInGlow(accent)
            .padding(horizontal = metrics.gutter + metrics.tvSafeSides, vertical = metrics.edge + metrics.tvSafeEnds),
        horizontalArrangement = Arrangement.spacedBy(metrics.u(64)),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(metrics.u(20)), content = words)
        Box(Modifier.weight(1f).fillMaxHeight(), contentAlignment = Alignment.CenterStart) {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(metrics.u(16)), content = actions)
        }
    }
}

// One centred column on a TV, for a screen about one person, so their face stays where Who's watching had it:
// the words, then 32 below, the actions 640 units wide.
@Composable
fun TvCentredPage(onBack: (() -> Unit)? = null, words: @Composable ColumnScope.() -> Unit, actions: @Composable ColumnScope.() -> Unit) {
    val metrics = LocalMetrics.current
    val accent = MaterialTheme.colorScheme.primary
    BackHandler(enabled = onBack != null) { onBack?.invoke() }
    Box(
        Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).signInGlow(accent),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            Modifier.padding(horizontal = metrics.gutter + metrics.tvSafeSides, vertical = metrics.edge + metrics.tvSafeEnds),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(metrics.u(32)),
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(metrics.u(20)), content = words)
            Column(Modifier.width(metrics.u(640)), verticalArrangement = Arrangement.spacedBy(metrics.u(16)), content = actions)
        }
    }
}

// The right shape for the device: one column, or side by side on a TV, or one centred column on a TV when `centred`.
@Composable
fun SignInLayout(
    onBack: (() -> Unit)? = null,
    centred: Boolean = false,
    words: @Composable ColumnScope.() -> Unit,
    actions: @Composable ColumnScope.() -> Unit,
) {
    val metrics = LocalMetrics.current
    when {
        metrics.tv && centred -> TvCentredPage(onBack, words, actions)
        metrics.tv -> TvSignInPage(onBack, words, actions)
        else -> SignInPage(onBack) {
            words()
            actions()
        }
    }
}

// A screen's heading and what it's about: centred in a column, to the left on a TV.
@Composable
fun SignInHeading(title: String, modifier: Modifier = Modifier, detail: String = "", display: Boolean = false, centred: Boolean = false) {
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    // Centred in a column; to the left on a TV, unless the whole screen is centred, as Who's watching is.
    val middle = centred || !metrics.tv
    val align = if (middle) TextAlign.Center else TextAlign.Start
    Column(
        modifier.fillMaxWidth(),
        horizontalAlignment = if (middle) Alignment.CenterHorizontally else Alignment.Start,
        verticalArrangement = Arrangement.spacedBy(metrics.u(8)),
    ) {
        if (title.isNotEmpty()) {
            Text(
                title, color = scheme.onBackground, textAlign = align,
                style = if (display) MaterialTheme.typography.display else MaterialTheme.typography.title,
                modifier = Modifier.semantics { heading() },
            )
        }
        if (detail.isNotEmpty()) Text(detail, color = scheme.onSurfaceVariant, style = MaterialTheme.typography.body, textAlign = align)
    }
}

// Above a group of things, such as the servers found: small capitals in `textSecondary`, as Apple's apps head a list.
@Composable
fun SectionLabel(text: String, modifier: Modifier = Modifier, searching: Boolean = false) {
    val metrics = LocalMetrics.current
    Row(modifier.fillMaxWidth().semantics(mergeDescendants = true) { heading() }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(metrics.u(8))) {
        Text(
            text.uppercase(), color = MaterialTheme.colorScheme.onSurfaceVariant,
            style = MaterialTheme.typography.caption.copy(fontWeight = FontWeight.SemiBold, letterSpacing = with(LocalDensity.current) { metrics.u(0.6f).toSp() }),
        )
        if (searching) PulsingDot()
    }
}

// The accent dot beside "On your network" while it looks. Still, with Reduce Motion on.
@Composable
private fun PulsingDot() {
    val metrics = LocalMetrics.current
    val reduce = LocalReduceMotion.current
    val pulse = if (reduce) {
        null
    } else {
        rememberInfiniteTransition(label = "searching").animateFloat(0.35f, 1f, infiniteRepeatable(tween(PULSE_MS), RepeatMode.Reverse), label = "dot")
    }
    Box(
        Modifier
            .size(metrics.u(7))
            .graphicsLayer { alpha = pulse?.value ?: 1f }
            .clip(CircleShape)
            .background(MaterialTheme.colorScheme.primary),
    )
}

private const val PULSE_MS = 900

// docs/APP-DESIGN.md, "Server card", as Apple's apps draw it. A saved server shows its own logo and name over
// its address; one only found shows the plain server icon and its address over "Found on your network", as a
// server says nothing about itself until it's added. A chevron turns into a spinner while connecting.
@Composable
fun ServerCard(
    name: String,
    detail: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    saved: Boolean = true,
    logo: Any? = null,
    lastUsed: Boolean = false,
    connecting: Boolean = false,
    requestFocus: Boolean = false,
    focusKey: String? = null,
) {
    val scheme = MaterialTheme.colorScheme
    val metrics = LocalMetrics.current
    val words = LocalWords.current
    val hint = LocalExtraColours.current.hint
    val mark = metrics.u(if (metrics.tv) 56 else 40)
    val spoken = listOfNotNull(name, detail, if (lastUsed) words["lastUsed"] else null).joinToString(", ")
    Pressable(
        onClick, modifier.fillMaxWidth(), shape = metrics.corner(14), fill = scheme.surfaceVariant, label = spoken,
        state = if (connecting) words["connecting"] else null, requestFocus = requestFocus, focusKey = focusKey, pressScale = CARD_PRESS,
    ) {
        Row(
            Modifier.fillMaxWidth().padding(metrics.u(16)),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(metrics.u(12)),
        ) {
            if (saved) {
                ServerMark(mark, logo)
            } else {
                Box(Modifier.size(mark).clip(markShape(mark)).background(scheme.outline), contentAlignment = Alignment.Center) {
                    Icon(Symbols.Server, contentDescription = null, tint = scheme.onSurfaceVariant, modifier = Modifier.size(mark * 0.6f))
                }
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(metrics.u(2))) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(metrics.u(8))) {
                    Text(
                        name, color = scheme.onSurface, style = MaterialTheme.typography.label.copy(fontWeight = FontWeight.SemiBold),
                        maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false),
                    )
                    if (lastUsed) Tag(words["lastUsed"].orEmpty())
                }
                Text(detail, color = scheme.onSurfaceVariant, style = MaterialTheme.typography.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            if (connecting) Spinner(hint, metrics.u(if (metrics.tv) 30 else 20))
            // On a TV, Apple's footnote chevron: 25 tall, its tip 4 inside the padding. Ours has more room
            // round it in its box, so the box is nudged out by that much.
            else if (metrics.tv) Icon(Symbols.Next, contentDescription = null, tint = hint, modifier = Modifier.offset(x = metrics.u(14)).size(metrics.u(52)))
            else Icon(Symbols.Next, contentDescription = null, tint = hint, modifier = Modifier.size(metrics.u(24)))
        }
    }
}

private const val CARD_PRESS = 0.98f

// Which server a code or a sign-in goes to: its mark and name in a quiet pill. Large enough to read from
// across the room on a TV: a 40 logo and the Section size.
@Composable
fun ServerPill(name: String, logo: Any?, modifier: Modifier = Modifier) {
    val metrics = LocalMetrics.current
    Row(
        modifier.clip(Radius.FULL).background(MaterialTheme.colorScheme.surface).padding(start = metrics.u(4), end = metrics.u(12), top = metrics.u(4), bottom = metrics.u(4)),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(metrics.u(8)),
    ) {
        ServerMark(metrics.u(if (metrics.tv) 40 else 24), logo)
        Text(
            name, color = MaterialTheme.colorScheme.onSurface, maxLines = 1,
            style = if (metrics.tv) MaterialTheme.typography.section.copy(fontWeight = FontWeight.Normal) else MaterialTheme.typography.label,
        )
    }
}

// A shake, once each time `count` goes up, as a refused code or password does. Still with Reduce Motion.
@Composable
fun rememberShake(count: Int): Animatable<Float, androidx.compose.animation.core.AnimationVector1D> {
    val reduce = LocalReduceMotion.current
    val shake = remember { Animatable(0f) }
    LaunchedEffect(count) {
        if (count == 0 || reduce) return@LaunchedEffect
        shake.animateTo(0f, keyframes {
            durationMillis = SHAKE_MS
            -10f at 50
            10f at 110
            -6f at 170
            6f at 230
            0f at SHAKE_MS
        })
    }
    return shake
}

// docs/APP-DESIGN.md, "Code entry": six boxes, the digits typed so far, and a blinking caret in the next.
// While a finished code is checked every box is outlined in the accent; a wrong one shakes them once.
@Composable
fun CodeBoxes(digits: String, checking: Boolean, wrongCount: Int, modifier: Modifier = Modifier) {
    val scheme = MaterialTheme.colorScheme
    val metrics = LocalMetrics.current
    val words = LocalWords.current
    val reduce = LocalReduceMotion.current
    val shake = rememberShake(wrongCount)
    val caret = if (reduce) {
        null
    } else {
        rememberInfiniteTransition(label = "caret").animateFloat(1f, 0f, infiniteRepeatable(tween(CARET_MS, delayMillis = CARET_MS), RepeatMode.Reverse), label = "blink")
    }
    val outline = metrics.u(2)
    Row(
        modifier
            .graphicsLayer { translationX = shake.value * density }
            .semantics(mergeDescendants = true) { contentDescription = "${words["codeLabel"]}: ${digits.length} ${words["codeEntered"]}" },
        horizontalArrangement = Arrangement.spacedBy(metrics.u(8)),
    ) {
        for (place in 0 until CODE_LENGTH) {
            val next = place == digits.length && !checking
            // Each box has a hairline; the next to fill has the accent, 2 wide, and while checking they all do.
            val edge = if (checking || next) scheme.primary else scheme.outline
            Box(
                Modifier
                    .width(metrics.u(if (metrics.tv) 88 else 48))
                    .height(metrics.u(if (metrics.tv) 100 else 56))
                    .clip(LocalMetrics.current.corner(10))
                    .background(scheme.surfaceVariant)
                    .border(if (next) outline else 1.dp, edge, LocalMetrics.current.corner(10)),
                contentAlignment = Alignment.Center,
            ) {
                val digit = digits.getOrNull(place)
                if (digit != null) {
                    Text(digit.toString(), color = scheme.onSurface, style = MaterialTheme.typography.title.copy(fontFamily = FontFamily.Monospace))
                } else if (next) {
                    Box(Modifier.width(outline).height(metrics.u(if (metrics.tv) 44 else 26)).graphicsLayer { alpha = caret?.value ?: 1f }.background(scheme.primary))
                }
            }
        }
    }
}

private const val SHAKE_MS = 300
private const val CARET_MS = 530

// The pad's keys: card keys 64 high (96 units on a TV), digits in Headline, Delete bottom left and 0 two
// columns wide. Works with only a remote's arrows and OK, and with touch.
@Composable
fun NumberPad(onDigit: (Char) -> Unit, onDelete: () -> Unit, modifier: Modifier = Modifier, firstFocus: Boolean = false) {
    val metrics = LocalMetrics.current
    val keys = remember { List(PAD_KEYS.size) { FocusRequester() } }
    // 16 apart on a TV, so a focused key growing 1.06 never covers its neighbour.
    val gap = metrics.u(if (metrics.tv) 16 else 8)
    // Columns of the same width all the way down, so the 0 spans exactly two of them and the gap between.
    BoxWithConstraints(modifier) {
        val column = (maxWidth - gap * 2) / 3
        Column(verticalArrangement = Arrangement.spacedBy(gap)) {
            for (row in 0..2) {
                Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
                    for (place in 0..2) {
                        val key = row * 3 + place
                        PadKey(key, keys, firstFocus && key == 0, { onDigit(PAD_KEYS[key][0]) }, Modifier.width(column))
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
                PadKey(PAD_DELETE, keys, false, onDelete, Modifier.width(column))
                PadKey(PAD_ZERO, keys, false, { onDigit('0') }, Modifier.width(column * 2 + gap))
            }
        }
    }
}

@Composable
private fun PadKey(key: Int, keys: List<FocusRequester>, requestFocus: Boolean, onClick: () -> Unit, modifier: Modifier) {
    val scheme = MaterialTheme.colorScheme
    val metrics = LocalMetrics.current
    val delete = key == PAD_DELETE
    // A focused key on a TV has no ring: it fills with `text` and its digit turns `background`, as the
    // systems' own keyboards do. A phone's keys have no focus look at all.
    Pressable(
        onClick,
        modifier.focusProperties {
            padMove(key, PadMove.Up)?.let { up = keys[it] }
            padMove(key, PadMove.Down)?.let { down = keys[it] }
            padMove(key, PadMove.Left)?.let { left = keys[it] }
            padMove(key, PadMove.Right)?.let { right = keys[it] }
        },
        shape = LocalMetrics.current.corner(14), focusRequester = keys[key], requestFocus = requestFocus,
        label = if (delete) LocalWords.current["codeDelete"] else null, ring = false,
    ) { active ->
        val lit = active && metrics.tv
        val ink = if (lit) scheme.background else scheme.onSurface
        Box(
            Modifier.fillMaxWidth().height(metrics.u(if (metrics.tv) 96 else 64)).background(if (lit) scheme.onBackground else scheme.surfaceVariant),
            contentAlignment = Alignment.Center,
        ) {
            if (delete) Icon(Symbols.DeleteDigit, contentDescription = null, tint = if (lit) ink else scheme.onSurfaceVariant, modifier = Modifier.size(metrics.u(if (metrics.tv) 64 else 26)))
            else Text(PAD_KEYS[key], color = ink, style = MaterialTheme.typography.headline)
        }
    }
}

// The digits on a remote's or a keyboard's number keys, and its delete key, for a code screen.
fun Modifier.digitKeys(onDigit: (Char) -> Unit, onDelete: () -> Unit): Modifier = onPreviewKeyEvent {
    if (it.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
    when (val code = it.key.nativeKeyCode) {
        in KeyEvent.KEYCODE_0..KeyEvent.KEYCODE_9 -> { onDigit('0' + (code - KeyEvent.KEYCODE_0)); true }
        in KeyEvent.KEYCODE_NUMPAD_0..KeyEvent.KEYCODE_NUMPAD_9 -> { onDigit('0' + (code - KeyEvent.KEYCODE_NUMPAD_0)); true }
        KeyEvent.KEYCODE_DEL -> { onDelete(); true }
        else -> false
    }
}

// docs/APP-DESIGN.md, "QR card": black on white whatever the theme, at 180 on a phone and 280 units on a
// TV, with what it's for under it.
@Composable
fun QrCard(text: String, caption: String, modifier: Modifier = Modifier, size: Int? = null) {
    val metrics = LocalMetrics.current
    Column(modifier, horizontalAlignment = if (metrics.tv) Alignment.Start else Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(metrics.u(8))) {
        Box(Modifier.clip(LocalMetrics.current.corner(14)).background(androidx.compose.ui.graphics.Color.White).padding(metrics.u(16))) {
            QrCode(text, metrics.u(size ?: if (metrics.tv) 280 else 180), Modifier.semantics { contentDescription = caption })
        }
        if (caption.isNotEmpty()) Text(caption, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.caption, textAlign = if (metrics.tv) TextAlign.Start else TextAlign.Center)
    }
}

// The legal note at the bottom of the connect screens.
@Composable
fun LegalNote(text: String, modifier: Modifier = Modifier) {
    val metrics = LocalMetrics.current
    Text(
        text, color = LocalExtraColours.current.hint, style = MaterialTheme.typography.caption.copy(fontWeight = FontWeight.Normal),
        textAlign = if (metrics.tv) TextAlign.Start else TextAlign.Center,
        modifier = modifier.fillMaxWidth().then(if (metrics.tv) Modifier else Modifier.widthIn(max = COLUMN_MOST)).padding(top = metrics.u(8)),
    )
}

// A thing in a `panel` card, radius 14: an address and fingerprint, or a code to type elsewhere.
@Composable
fun PanelCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val metrics = LocalMetrics.current
    Column(
        modifier.fillMaxWidth().clip(LocalMetrics.current.corner(14)).background(MaterialTheme.colorScheme.surface).padding(metrics.u(16)),
        verticalArrangement = Arrangement.spacedBy(metrics.u(6)),
        content = content,
    )
}

// The warning icon in a circle of `danger` at 16%.
@Composable
fun WarningBadge(size: Dp, modifier: Modifier = Modifier) {
    val danger = MaterialTheme.colorScheme.error
    Box(modifier.size(size).clip(CircleShape).background(danger.copy(alpha = 0.16f)), contentAlignment = Alignment.Center) {
        Icon(Symbols.Warning, contentDescription = null, tint = danger, modifier = Modifier.size(size * 0.5f))
    }
}
