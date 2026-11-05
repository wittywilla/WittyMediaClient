package com.wittywilla.wittymediaclient.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.InputMode
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalInputModeManager
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.DeviceFontFamilyName
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import com.wittywilla.wittymediaclient.net.GuideRules
import com.wittywilla.wittymediaclient.net.TvColours
import com.wittywilla.wittymediaclient.net.TvLook
import com.wittywilla.wittymediaclient.net.TvLookChoice
import com.wittywilla.wittymediaclient.net.TvShape
import com.wittywilla.wittymediaclient.ui.LocalReduceMotion
import com.wittywilla.wittymediaclient.ui.ringOutside

// How each WittyTV theme is dressed on Android TV, as Apple TV dresses it (apple/App/TvStyle.swift). The server's page
// draws its themes with CSS (web/src/pages/tv/tv.css for what they share, tvthemes.css for each shape); this is the
// same, as the page works it out on a 1920 by 1080 TV in big screen mode. Sizes are in TV units (points on Apple TV,
// half a dp here). Colours come from net/TvLook.kt, which works them out as tvThemes.ts does.

// The connection WittyTV's pieces ask with, for the pictures they show.
val LocalTvApi = androidx.compose.runtime.staticCompositionLocalOf { com.wittywilla.wittymediaclient.net.Api("", "") }

// A TV unit in dp: Android TV is 960 by 540 dp, Apple TV 1920 by 1080 points.
const val TV_UNIT = 0.5f

// `#rrggbb`, or `#rrggbbaa` with an opacity.
fun tvColour(hex: String): Color {
    val d = hex.removePrefix("#")
    fun at(i: Int) = d.substring(i, i + 2).toIntOrNull(16) ?: 0
    if (d.length < 6) return Color.Black
    return Color(at(0), at(2), at(4), if (d.length >= 8) at(6) else 255)
}

// The look's colours, ready to draw with.
@Stable
class TvPaint(c: TvColours) {
    val bg = tvColour(c.bg)
    val panel = tvColour(c.panel)
    val panel2 = tvColour(c.panel2)
    val head = tvColour(c.head)
    val ch = tvColour(c.ch)
    val dim = tvColour(c.dim)
    val line = tvColour(c.line)
    val text = tvColour(c.text)
    val soft = tvColour(c.soft)
    val cell = tvColour(c.cell)
    val cell2 = tvColour(c.cell2)
    val cellText = tvColour(c.cellText)
    val cellSoft = tvColour(c.cellSoft)
    val live = tvColour(c.live)
    val live2 = tvColour(c.live2)
    val liveText = tvColour(c.liveText)
    val liveSoft = tvColour(c.liveSoft)
    val hi = tvColour(c.hi)
    val hiText = tvColour(c.hiText)
    val accent = tvColour(c.accent)
    val accentText = tvColour(c.accentText)
    val keyA = tvColour(c.keyA)
    val keyB = tvColour(c.keyB)
    val keyC = tvColour(c.keyC)
    val keyText = tvColour(c.keyText)
    val err = tvColour(c.err)
    val lite = tvColour(c.lite)
    val shade = tvColour(c.shade)
}

// Which family the words are in: the shape's own, or what Custom chose.
enum class TvFamily { Plain, Narrow, Din, Mono, Serif }

// Roboto Condensed, in each weight the page asks for: a family made from one typeface would lose its bold.
private val condensed: FontFamily by lazy {
    val name = DeviceFontFamilyName("sans-serif-condensed")
    FontFamily(
        listOf(FontWeight.Light, FontWeight.Normal, FontWeight.Medium, FontWeight.SemiBold, FontWeight.Bold, FontWeight.ExtraBold).flatMap { w ->
            listOf(Font(name, w), Font(name, w, FontStyle.Italic))
        },
    )
}

// SwiftUI's weights by name, as Apple TV gives them.
object W {
    val Light = FontWeight.Light
    val Regular = FontWeight.Normal
    val Medium = FontWeight.Medium
    val Semibold = FontWeight.SemiBold
    val Bold = FontWeight.Bold
    val Heavy = FontWeight.ExtraBold
}

// A size and a weight of the type.
data class TvType(val size: Float, val weight: FontWeight)

// Everything a screen needs to draw a look: the choice, its colours and its shape's measures. Type is in TV units
// whatever the device's own text size, as Apple TV's is: the grid's rows are a set height.
@Stable
class TvDress(val look: TvLookChoice, private val fontScale: Float = 1f) {
    val paint = TvPaint(look.colours)
    val shape: TvShape get() = look.shape

    fun pt(points: Number): Dp = (points.toFloat() * TV_UNIT).dp
    fun sp(points: Number): TextUnit = (points.toFloat() * TV_UNIT / fontScale).sp

    val family: TvFamily
        get() = when (look.font) {
            "system" -> TvFamily.Plain
            "narrow" -> TvFamily.Narrow
            "mono" -> TvFamily.Mono
            "serif" -> TvFamily.Serif
            else -> when (shape) {
                TvShape.Box -> TvFamily.Narrow
                TvShape.Receiver -> TvFamily.Din
                TvShape.Teletext -> TvFamily.Mono
                TvShape.Listings -> TvFamily.Serif
                else -> TvFamily.Plain
            }
        }

    // Type at a size from the page, in its family. `digits` is the page's monospaced numbers; `tabular`, numbers of
    // one width in the family's own type.
    fun font(size: Float, weight: FontWeight = W.Regular, digits: Boolean = false, italic: Boolean = false, tracking: Float = 0f, tabular: Boolean = false): TextStyle {
        val fam: FontFamily
        var w = weight
        if (digits) {
            fam = FontFamily.Monospace
        } else {
            when (family) {
                TvFamily.Plain -> fam = FontFamily.Default
                TvFamily.Narrow -> fam = condensed
                // DIN Alternate Bold on Apple TV: a narrow face, always bold.
                TvFamily.Din -> { fam = condensed; w = W.Bold }
                TvFamily.Mono -> fam = FontFamily.Monospace
                TvFamily.Serif -> fam = FontFamily.Serif
            }
        }
        return TextStyle(
            fontFamily = fam, fontWeight = w, fontSize = sp(size), fontStyle = if (italic) FontStyle.Italic else FontStyle.Normal,
            letterSpacing = if (tracking != 0f) sp(tracking) else TextUnit.Unspecified,
            fontFeatureSettings = if (tabular) "tnum" else null,
        )
    }

    fun font(t: TvType, digits: Boolean = false, italic: Boolean = false) = font(t.size, t.weight, digits, italic)

    // The page's `font-variant: small-caps`: small letters drawn as smaller capitals.
    fun smallCaps(words: String, size: Float): AnnotatedString = buildAnnotatedString {
        var run = StringBuilder()
        var small = false
        fun flush() {
            if (run.isEmpty()) return
            withStyle(SpanStyle(fontSize = sp(if (small) size * 0.78f else size))) { append(if (small) run.toString().uppercase() else run.toString()) }
            run = StringBuilder()
        }
        for (c in words) {
            val lower = c.isLowerCase()
            if (lower != small) {
                flush()
                small = lower
            }
            run.append(c)
        }
        flush()
    }

    // Words in the shape's case: Newspaper's small capitals where the page has them, else as they are.
    fun words(text: String, size: Float, smallCaps: Boolean): AnnotatedString =
        if (smallCaps && shape == TvShape.Listings) smallCaps(text, size) else AnnotatedString(text)

    // Measures (CSS pixels at 1920 wide, which are TV units).

    // --ctv-top, --ctv-edge and --ctv-foot on a TV.
    val top = 59f
    val edge = 96f
    val foot = 54f

    // --ctv-r: the theme's corners.
    val radius: Float
        get() = when (shape) {
            TvShape.Box -> 3f
            TvShape.Modern, TvShape.Cinema -> 6f
            TvShape.Receiver, TvShape.Teletext, TvShape.Listings -> 0f
            TvShape.Outline -> 10f
            TvShape.Compact -> 4f
        }

    // The channel column.
    val channelWidth: Float get() = if (shape == TvShape.Compact) 220f else if (shape == TvShape.Cinema) 240f else 300f

    val rowHeight: Float get() = TvLook.rowHeight(shape, 1920.0, look.density).toFloat()

    // The words of a cell: its title, then the line under it.
    val cellTitle: TvType
        get() = when (shape) {
            TvShape.Box, TvShape.Modern, TvShape.Listings -> TvType(18.75f, W.Bold)
            TvShape.Receiver -> TvType(17.5f, W.Medium)
            TvShape.Teletext -> TvType(17.5f, W.Regular)
            TvShape.Cinema -> TvType(25f, W.Bold)
            TvShape.Outline -> TvType(18.75f, W.Medium)
            TvShape.Compact -> TvType(17.5f, W.Semibold)
        }

    val cellSmall: Float get() = if (shape == TvShape.Modern || shape == TvShape.Listings || shape == TvShape.Compact) 16.25f else 21.25f

    val number: TvType
        get() = when (shape) {
            TvShape.Box, TvShape.Modern -> TvType(21.25f, W.Bold)
            TvShape.Receiver -> TvType(30f, W.Regular)
            TvShape.Teletext, TvShape.Listings, TvShape.Outline -> TvType(30f, W.Regular)
            TvShape.Cinema -> TvType(17.5f, W.Bold)
            TvShape.Compact -> TvType(15f, W.Bold)
        }

    val name: TvType
        get() = when (shape) {
            TvShape.Box -> TvType(25f, W.Bold)
            TvShape.Modern -> TvType(18.75f, W.Heavy)
            TvShape.Receiver -> TvType(16.25f, W.Medium)
            TvShape.Teletext -> TvType(16.25f, W.Regular)
            TvShape.Listings -> TvType(25f, W.Bold)
            TvShape.Cinema -> TvType(16.25f, W.Bold)
            TvShape.Outline -> TvType(25f, W.Medium)
            TvShape.Compact -> TvType(17.5f, W.Semibold)
        }

    val logo: Size
        get() = when (shape) {
            TvShape.Modern -> Size(104f, 46f)
            TvShape.Cinema -> Size(72f, 32f)
            TvShape.Compact -> Size(40f, 24f)
            else -> Size(72f, 46f)
        }

    val heroLogo: Size
        get() = when (shape) {
            TvShape.Modern -> Size(84f, 40f)
            TvShape.Compact -> Size(40f, 24f)
            else -> Size(54f, 32f)
        }

    val timeSize: Float get() = if (shape == TvShape.Compact) 16.25f else 25f

    val heroTitle: TvType
        get() = when (shape) {
            TvShape.Box -> TvType(47.5f, W.Bold)
            TvShape.Modern -> TvType(54.7f, W.Bold)
            TvShape.Receiver -> TvType(47.5f, W.Medium)
            TvShape.Teletext -> TvType(37.5f, W.Bold)
            TvShape.Listings, TvShape.Cinema -> TvType(60f, W.Bold)
            TvShape.Outline -> TvType(54.7f, W.Light)
            TvShape.Compact -> TvType(25f, W.Bold)
        }

    val heroNumber: TvType
        get() = when (shape) {
            TvShape.Modern -> TvType(30f, W.Bold)
            TvShape.Receiver, TvShape.Teletext -> TvType(25f, W.Regular)
            TvShape.Listings -> TvType(25f, W.Regular)
            TvShape.Outline -> TvType(37.5f, W.Light)
            TvShape.Compact -> TvType(17.5f, W.Bold)
            else -> TvType(37.5f, W.Bold)
        }

    // The facts under the title: the episode, times, what's next and the description.
    val heroFacts: Float
        get() = when (shape) {
            TvShape.Modern, TvShape.Cinema, TvShape.Outline -> 18.75f
            TvShape.Compact -> 17.5f
            else -> 25f
        }

    val heroChannel: Float get() = if (shape == TvShape.Compact) 16.25f else 25f

    val buttonText: TvType
        get() = when (shape) {
            TvShape.Modern, TvShape.Cinema -> TvType(21.25f, W.Semibold)
            TvShape.Receiver -> TvType(16.25f, W.Medium)
            TvShape.Teletext -> TvType(16.25f, W.Regular)
            TvShape.Listings -> TvType(21.25f, W.Regular)
            TvShape.Outline -> TvType(21.25f, W.Medium)
            TvShape.Compact -> TvType(16.25f, W.Semibold)
            TvShape.Box -> TvType(21.25f, W.Bold)
        }

    // The words the shape writes in capitals.
    val capitals: Boolean get() = shape == TvShape.Receiver || shape == TvShape.Teletext

    // A raised edge, as a cable box drew everything.
    val bevel: Boolean get() = shape == TvShape.Box

    // The highlighted row's channel takes the highlight's colour.
    val rowHighlight: Boolean get() = shape.rowHighlight
}

@Composable
fun rememberDress(look: TvLookChoice): TvDress {
    val scale = LocalDensity.current.fontScale
    return remember(look, scale) { TvDress(look, scale) }
}

// The time on the TV, as the page's clock says it.
fun tvClock(time: Long): String = GuideRules.clock(time)

// Pieces.

// The cable box's raised edge: light along the top and left, dark along the bottom and right, over what's there.
fun Modifier.bevel(width: Dp): Modifier = this.drawWithContent {
    drawContent()
    val w = width.toPx()
    val light = Color.White.copy(alpha = 0.28f)
    val dark = Color.Black.copy(alpha = 0.45f)
    drawRect(light, Offset.Zero, Size(size.width, w))
    drawRect(light, Offset.Zero, Size(w, size.height))
    drawRect(dark, Offset(0f, size.height - w), Size(size.width, w))
    drawRect(dark, Offset(size.width - w, 0f), Size(w, size.height))
}

enum class Edge { Top, Bottom, Leading, Trailing }

// One edge of a box drawn as a rule, over what's there, as the page's borders are.
fun Modifier.rule(edge: Edge, colour: Color, width: Dp): Modifier = this.drawWithContent {
    drawContent()
    val w = width.toPx()
    when (edge) {
        Edge.Top -> drawRect(colour, Offset.Zero, Size(size.width, w))
        Edge.Bottom -> drawRect(colour, Offset(0f, size.height - w), Size(size.width, w))
        Edge.Leading -> drawRect(colour, Offset.Zero, Size(w, size.height))
        Edge.Trailing -> drawRect(colour, Offset(size.width - w, 0f), Size(w, size.height))
    }
}

// A rounded outline drawn inside the box, as SwiftUI's strokeBorder; dashed if asked.
fun Modifier.strokeInside(colour: Color, width: Dp, radius: Dp, dash: FloatArray? = null): Modifier = this.drawWithContent {
    drawContent()
    val w = width.toPx()
    val r = radius.toPx()
    drawRoundRect(
        colour, Offset(w / 2, w / 2), Size(size.width - w, size.height - w), CornerRadius((r - w / 2).coerceAtLeast(0f)),
        style = Stroke(w, pathEffect = dash?.let { androidx.compose.ui.graphics.PathEffect.dashPathEffect(it.map { d -> d * density * TV_UNIT }.toFloatArray()) }),
    )
}

// Something the remote can focus on a TV, as Apple TV's WittyTV buttons are: room for the ring kept round it, the ring
// in the look's text colour, concentric with its corners, and 1.05 larger while focused. Held Select is `onLongClick`.
// Something that can't be used can't be focused, as on Apple TV.
@Composable
fun TvFocusable(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    radius: Dp = 0.dp,
    ringColour: Color = Color.White,
    enabled: Boolean = true,
    onLongClick: (() -> Unit)? = null,
    focusRequester: FocusRequester? = null,
    label: String? = null,
    selected: Boolean = false,
    ring: Boolean = true,
    grows: Boolean = true,
    onFocus: ((Boolean) -> Unit)? = null,
    content: @Composable (focused: Boolean, pressed: Boolean) -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    var focused by remember { mutableStateOf(false) }
    val reduce = LocalReduceMotion.current
    val keyboard = LocalInputModeManager.current.inputMode == InputMode.Keyboard
    val shows = focused && keyboard
    val ringWidth = (4 * TV_UNIT).dp
    val shape = RoundedCornerShape(radius)
    val grow = if (shows && grows && !reduce) 1.05f else 1f
    Box(
        modifier
            .zIndex(if (shows) 1f else 0f)
            .graphicsLayer { scaleX = grow; scaleY = grow; alpha = if (enabled) 1f else 0.45f }
            .then(if (ring) Modifier.padding(ringWidth) else Modifier)
            .then(if (ring && shows) Modifier.ringOutside(shape, ringColour, 0.dp, ringWidth) else Modifier)
            .then(if (focusRequester != null) Modifier.focusRequester(focusRequester) else Modifier)
            .focusProperties { canFocus = enabled }
            .onFocusChanged {
                focused = it.isFocused
                onFocus?.invoke(it.isFocused)
            }
            .semantics {
                if (label != null) contentDescription = label
                if (selected) this.selected = true
                if (!enabled) disabled()
            }
            .combinedClickable(
                interactionSource = interaction, indication = null, role = Role.Button, enabled = enabled,
                onLongClick = onLongClick, onClick = onClick,
            ),
        contentAlignment = Alignment.Center,
    ) { content(shows, pressed) }
}

enum class TvButtonKind { Button, Chip, Link, Icon }

// The page's `.ctv-btn`, in each shape's own style. `on` is the one the theme fills with its highlight; focus fills any
// of them, and adds the TV's ring. `onBar`: Teletext's bar is blue, and its buttons are black on it.
@Composable
fun TvButton(
    dress: TvDress,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    kind: TvButtonKind = TvButtonKind.Button,
    on: Boolean = false,
    onBar: Boolean = false,
    enabled: Boolean = true,
    label: String? = null,
    selected: Boolean = false,
    // Ink of its own when not lit, as a favourite's star in the accent.
    tint: Color? = null,
    focusRequester: FocusRequester? = null,
    onLongClick: (() -> Unit)? = null,
    content: @Composable RowScope.(ink: Color, style: TextStyle) -> Unit,
) {
    val p = dress.paint
    val s = dress.shape
    val round = (s == TvShape.Modern || s == TvShape.Outline) && kind != TvButtonKind.Link
    val radius = if (round) 24f else if (s == TvShape.Cinema && kind != TvButtonKind.Link) 10f else dress.radius
    val shape = RoundedCornerShape(dress.pt(radius))
    val chip = kind == TvButtonKind.Chip || kind == TvButtonKind.Link
    val words = dress.buttonText
    TvFocusable(
        onClick, modifier, radius = dress.pt(radius), ringColour = p.text, enabled = enabled, onLongClick = onLongClick,
        focusRequester = focusRequester, label = label, selected = selected,
    ) { focused, pressed ->
        val lit = on || focused
        val ink = if (lit) p.hiText else tint ?: when {
            s == TvShape.Modern && chip -> p.soft
            s == TvShape.Teletext && kind == TvButtonKind.Chip -> p.soft
            else -> p.text
        }
        val fill: Brush? = when {
            lit -> androidx.compose.ui.graphics.SolidColor(p.hi)
            chip -> null
            s == TvShape.Box -> Brush.verticalGradient(listOf(p.panel2, p.panel))
            s == TvShape.Modern || s == TvShape.Cinema || s == TvShape.Compact -> androidx.compose.ui.graphics.SolidColor(p.panel2)
            s == TvShape.Teletext -> androidx.compose.ui.graphics.SolidColor(if (onBar) p.bg else p.panel2)
            else -> null
        }
        val border: Color? = when {
            chip || lit -> null
            s == TvShape.Box || s == TvShape.Receiver || s == TvShape.Outline -> p.line
            s == TvShape.Listings -> p.text
            else -> null
        }
        val style = dress.font(
            words.size, if (chip && s == TvShape.Box) W.Bold else words.weight, italic = s == TvShape.Listings && chip,
            tracking = if (s == TvShape.Receiver) words.size * 0.06f else 0f,
        )
        Row(
            Modifier
                .graphicsLayer { alpha = if (pressed) 0.85f else 1f }
                .clip(shape)
                .then(if (fill != null) Modifier.background(fill, shape) else Modifier)
                .then(if (border != null) Modifier.border(dress.pt(1), border, shape) else Modifier)
                .then(if (dress.bevel && (kind == TvButtonKind.Button || kind == TvButtonKind.Icon)) Modifier.bevel(dress.pt(2)) else Modifier)
                .defaultMinSize(minWidth = if (kind == TvButtonKind.Icon) dress.pt(48) else Dp.Unspecified, minHeight = dress.pt(48))
                .padding(horizontal = dress.pt(if (kind == TvButtonKind.Icon) 0 else if (chip) 12 else 14)),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(dress.pt(ICON_GAP), Alignment.CenterHorizontally),
        ) { content(ink, style) }
    }
}

// The gap between a label's icon and its words, as SwiftUI's Label leaves it.
private const val ICON_GAP = 14

// Words alone, in the shape's case.
@Composable
fun TvButton(dress: TvDress, text: String, onClick: () -> Unit, modifier: Modifier = Modifier, kind: TvButtonKind = TvButtonKind.Button, on: Boolean = false,
    onBar: Boolean = false, enabled: Boolean = true, selected: Boolean = false, focusRequester: FocusRequester? = null, icon: ImageVector? = null) {
    TvButton(dress, onClick, modifier, kind, on, onBar, enabled, selected = selected, focusRequester = focusRequester) { ink, style ->
        if (icon != null) TvIcon(dress, icon, ink, style)
        Text(if (dress.capitals) text.uppercase() else text, style = style, color = ink, maxLines = 1, overflow = TextOverflow.Clip)
    }
}

// An icon alone, said aloud by its label.
@Composable
fun TvIconButton(dress: TvDress, icon: ImageVector, label: String, onClick: () -> Unit, modifier: Modifier = Modifier, onBar: Boolean = false,
    enabled: Boolean = true, selected: Boolean = false, tint: Color? = null) {
    TvButton(dress, onClick, modifier, TvButtonKind.Icon, onBar = onBar, enabled = enabled, label = label, selected = selected, tint = tint) { ink, style ->
        TvIcon(dress, icon, ink, style)
    }
}

// Words alone on an icon button, as the preview's − and +.
@Composable
fun TvGlyphButton(dress: TvDress, glyph: String, label: String, onClick: () -> Unit, enabled: Boolean = true) {
    TvButton(dress, onClick, kind = TvButtonKind.Icon, enabled = enabled, label = label) { ink, style ->
        Text(glyph, style = style, color = ink, maxLines = 1)
    }
}

// An SF Symbol at a font's size is drawn about one and a half times that in a Material Symbol's box, which leaves
// more room round its shape.
@Composable
fun TvIcon(dress: TvDress, icon: ImageVector, ink: Color, style: TextStyle) {
    val size = style.fontSize.value / TV_UNIT * LocalDensity.current.fontScale
    Icon(icon, contentDescription = null, tint = ink, modifier = Modifier.size(dress.pt(size * 1.5f)))
}

// A shape for a radius in TV units.
fun TvDress.rounded(radius: Float): Shape = RoundedCornerShape(pt(radius))
