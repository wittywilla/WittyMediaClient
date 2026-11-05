package com.wittywilla.wittymediaclient.games

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.input.InputMode
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalInputModeManager
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import com.wittywilla.wittymediaclient.ui.LocalExtraColours
import com.wittywilla.wittymediaclient.ui.LocalMetrics
import com.wittywilla.wittymediaclient.ui.LocalReduceMotion

// The look of the games screens, from the website's games pages (the server's web/src/pages/games/games-ui.css) at
// phone size, and on a TV in TV units (docs/APP-DESIGN.md, "On a TV": half a dp each on Android TV, so the same
// layout as Apple TV's). Colours are the theme's, through the app's Material scheme, so every theme works.

data class GameLook(
    val tv: Boolean,
    val tablet: Boolean,
    val gutter: Dp,
    val sectionGap: Dp,
    val gap: Dp,
    val display: TextUnit,
    val heroTitle: TextUnit,
    val title: TextUnit,
    val body: TextUnit,
    val label: TextUnit,
    val small: TextUnit,
    val button: Dp,
    val icon: Dp,
    val card: Dp,
    val continueWidth: Dp,
    val consoleWidth: Dp,
    val radius: Dp,
    val ring: Dp,
    val ringGap: Dp,
    val focusScale: Float,
    // Room above and below a row of things that take focus, so a ring is never cut off.
    val rowRoom: Dp,
)

private fun tv(units: Int): Dp = (units * 0.5f).dp
private fun tvText(units: Int): TextUnit = (units * 0.5f).sp

private val PhoneLook = GameLook(
    tv = false, tablet = false, gutter = 16.dp, sectionGap = 28.dp, gap = 8.dp,
    display = 30.sp, heroTitle = 24.sp, title = 20.sp, body = 15.sp, label = 14.sp, small = 12.sp,
    button = 44.dp, icon = 18.dp, card = 104.dp, continueWidth = 240.dp, consoleWidth = 128.dp, radius = 10.dp,
    ring = 2.dp, ringGap = 2.dp, focusScale = 1f, rowRoom = 6.dp,
)

private val TabletLook = PhoneLook.copy(tablet = true, gutter = 32.dp, sectionGap = 36.dp, card = 150.dp, continueWidth = 300.dp, consoleWidth = 160.dp, display = 38.sp, heroTitle = 30.sp)

private val TvLook = GameLook(
    tv = true, tablet = false, gutter = tv(170), sectionGap = tv(60), gap = tv(16),
    display = tvText(57), heroTitle = tvText(48), title = tvText(38), body = tvText(29), label = tvText(29), small = tvText(25),
    button = tv(66), icon = tv(32), card = tv(220), continueWidth = tv(420), consoleWidth = tv(240), radius = tv(14),
    ring = tv(4), ringGap = tv(4), focusScale = 1.05f, rowRoom = tv(24),
)

@Composable
fun gameLook(): GameLook {
    val metrics = LocalMetrics.current
    if (metrics.tv) return TvLook
    return if (windowDp().first >= 600) TabletLook else PhoneLook
}

// The space the app has, in dp: the window's, which a split screen or a freeform window makes smaller than the display.
@Composable
fun windowDp(): Pair<Float, Float> {
    val size = LocalWindowInfo.current.containerSize
    val density = LocalDensity.current.density
    return size.width / density to size.height / density
}

// Colours by role, from the theme.
object GameColours {
    val background: Color @Composable get() = MaterialTheme.colorScheme.background
    val panel: Color @Composable get() = MaterialTheme.colorScheme.surface
    val card: Color @Composable get() = MaterialTheme.colorScheme.surfaceVariant
    val text: Color @Composable get() = MaterialTheme.colorScheme.onBackground
    val secondary: Color @Composable get() = MaterialTheme.colorScheme.onSurfaceVariant
    val hint: Color @Composable get() = LocalExtraColours.current.hint
    val border: Color @Composable get() = MaterialTheme.colorScheme.outline
    val accent: Color @Composable get() = MaterialTheme.colorScheme.primary
    val onAccent: Color @Composable get() = MaterialTheme.colorScheme.onPrimary
    val accentText: Color @Composable get() = LocalExtraColours.current.accentText
    val danger: Color @Composable get() = MaterialTheme.colorScheme.error
    val ok: Color @Composable get() = LocalExtraColours.current.ok
}

// Icons from the website's own set, drawn on a 24 grid.
object GameIcons {
    private val made = HashMap<String, ImageVector>()

    private fun icon(name: String, d: String): ImageVector = made.getOrPut(name) {
        ImageVector.Builder(name, 24.dp, 24.dp, 24f, 24f)
            .addPath(PathParser().parsePathString(d).toNodes(), fill = SolidColor(Color.Black))
            .build()
    }

    val Play get() = icon("play", "M8 5v14l11-7z")
    val Star get() = icon("star", "M12 3l2.7 5.8 6.3.8-4.6 4.4 1.2 6.3L12 17.2 6.4 20.3l1.2-6.3L3 9.6l6.3-.8z")
    val More get() = icon("more", "M5 10a2 2 0 110 4 2 2 0 010-4zm7 0a2 2 0 110 4 2 2 0 010-4zm7 0a2 2 0 110 4 2 2 0 010-4z")
    val Gamepad get() = icon("gamepad", "M7 7h10a5 5 0 015 5v3.5a3.5 3.5 0 01-6.4 2L14 16h-4l-1.6 1.5A3.5 3.5 0 012 15.5V12a5 5 0 015-5zm0 2.5V11H5.5v1.5H7V14h1.5v-1.5H10V11H8.5V9.5zM16 10a1 1 0 100 2 1 1 0 000-2zm2.5 2.5a1 1 0 100 2 1 1 0 000-2z")
    val Back get() = icon("back", "M20 11H7.8l5.6-5.6L12 4l-8 8 8 8 1.4-1.4L7.8 13H20z")
    val Info get() = icon("info", "M11 7h2v2h-2zm0 4h2v6h-2zm1-9a10 10 0 100 20 10 10 0 000-20z")
    val Check get() = icon("check", "M9 16.2l-3.5-3.5L4 14.2 9 19.2 20 8.2l-1.4-1.4z")
    val Trash get() = icon("trash", "M6 19a2 2 0 002 2h8a2 2 0 002-2V7H6zm3-10h2v8H9zm4 0h2v8h-2zM15.5 4l-1-1h-5l-1 1H5v2h14V4z")
    val Search get() = icon("search", "M15.5 14h-.8l-.3-.3a6.5 6.5 0 10-.7.7l.3.3v.8l5 5 1.5-1.5zm-6 0a4.5 4.5 0 110-9 4.5 4.5 0 010 9z")
    val Refresh get() = icon("refresh", "M17.6 6.4A8 8 0 004.3 10h2.1a6 6 0 019.8-2.2L13 11h7V4zm-11.2 11.2A8 8 0 0019.7 14h-2.1a6 6 0 01-9.8 2.2L11 13H4v7z")
    val Home get() = icon("home", "M12 3l9 8h-3v9h-5v-6h-2v6H6v-9H3z")
    val Library get() = icon("library", "M4 6H2v14a2 2 0 002 2h14v-2H4zm16-4H8a2 2 0 00-2 2v12a2 2 0 002 2h12a2 2 0 002-2V4a2 2 0 00-2-2zm-1 9H9V9h10zm-4 4H9v-2h6zm4-8H9V5h10z")
    val Tune get() = icon("tune", "M3 17v2h6v-2zM3 5v2h10V5zm10 16v-2h8v-2h-8v-2h-2v6zM7 9v2H3v2h4v2h2V9zm14 4v-2H11v2zm-6-4h2V7h4V5h-4V3h-2z")
    val Close get() = icon("close", "M19 6.4L17.6 5 12 10.6 6.4 5 5 6.4l5.6 5.6L5 17.6 6.4 19l5.6-5.6 5.6 5.6 1.4-1.4-5.6-5.6z")

    // The game menu's, from the WittyPlay player.
    val Save get() = icon("save", "M5 3h11l5 5v13H3V3zm7 15a3 3 0 100-6 3 3 0 000 6zM6 5v4h9V5z")
    val Load get() = icon("load", "M12 3v9.2l3.6-3.6L17 10l-5 5-5-5 1.4-1.4L11 12.2V3zM4 14h2v5h12v-5h2v7H4z")
    val QuickSave get() = icon("quickSave", "M13 2L5 13h6l-1 9 9-12h-6z")
    val QuickLoad get() = icon("quickLoad", "M13 3a9 9 0 11-8.5 12h2.2A7 7 0 1013 5a7 7 0 00-5.3 2.4L10 10H3V3l3.2 3.2A9 9 0 0113 3zm-1 5h2v5l4 2.3-1 1.7-5-3z")
    val FastForward get() = icon("ff", "M4 18l8.5-6L4 6zm9-12v12l8.5-6z")
    val Pad get() = icon("pad", "M7 7h10a5 5 0 014.9 6l-.8 4a2.5 2.5 0 01-4.3 1.2L14.5 16h-5l-2.3 2.2A2.5 2.5 0 012.9 17l-.8-4A5 5 0 017 7zm1 2.5V11H6.5v2H8v1.5h2V13h1.5v-2H10V9.5zm8.5.5a1.2 1.2 0 100 2.4 1.2 1.2 0 000-2.4zm-2 2.5a1.2 1.2 0 100 2.4 1.2 1.2 0 000-2.4z")
    val Touch get() = icon("touch", "M9 11.2V6a2.5 2.5 0 015 0v5.2a4.5 4.5 0 10-5 0zM12 2a4 4 0 00-4 4v.3A4.5 4.5 0 0112 2zm-.8 4a.8.8 0 011.6 0v5.5l5.2 2.2a2 2 0 011.2 2l-.5 4.3a2 2 0 01-2 1.7h-4.6a2 2 0 01-1.6-.8l-3.8-5 1.2-1.2 3.3 1.8z")
    val Quit get() = icon("quit", "M10 3h9a2 2 0 012 2v14a2 2 0 01-2 2h-9v-2h9V5h-9zm1.5 4.5L16 12l-4.5 4.5-1.4-1.4 2.1-2.1H3v-2h9.2l-2.1-2.1z")
    val Connection get() = icon("connection", "M12 18a2 2 0 100 4 2 2 0 000-4zM5.6 13.6l1.8 1.8a6.5 6.5 0 019.2 0l1.8-1.8a9 9 0 00-12.8 0zM2 10l1.8 1.8a11.6 11.6 0 0116.4 0L22 10A14.1 14.1 0 002 10z")
    val Disc get() = icon("disc", "M12 2a10 10 0 100 20 10 10 0 000-20zm0 13a3 3 0 110-6 3 3 0 010 6z")
    val Reset get() = icon("reset", "M12 4a8 8 0 11-7.9 9.3h2A6 6 0 1012 6a6 6 0 00-4.4 1.9L10 10H4V4l2.2 2.2A8 8 0 0112 4z")
    val Pause get() = icon("pause", "M6 19h4V5H6zm8-14v14h4V5z")
    val Slow get() = icon("slow", "M12 2a10 10 0 100 20 10 10 0 000-20zm1 5v5.4l4 2.4-1 1.6-5-3V7z")
    val Settings get() = icon("settings", "M19.4 13a7.9 7.9 0 000-2l2.1-1.6-2-3.5-2.5 1a8 8 0 00-1.7-1L15 3H9l-.3 2.9a8 8 0 00-1.7 1l-2.5-1-2 3.5L4.6 11a7.9 7.9 0 000 2l-2.1 1.6 2 3.5 2.5-1a8 8 0 001.7 1L9 21h6l.3-2.9a8 8 0 001.7-1l2.5 1 2-3.5zM12 15.5a3.5 3.5 0 110-7 3.5 3.5 0 010 7z")
}

// The one focusable surface on these screens. On a TV, focus is a ring in `text`, 4 out and 4 wide, concentric with
// the thing's own corners, and the thing grows by 1.05 (docs/APP-DESIGN.md, "On a TV"); with a keyboard or a pad on
// a phone, the website's 2-wide ring. A finger sees no ring. Focus is followed with onFocusChanged, which sees
// focus given on a screen's first frame.
@Composable
fun Pressable(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    radius: Dp = gameLook().radius,
    label: String? = null,
    enabled: Boolean = true,
    focusRequester: FocusRequester? = null,
    onFocus: (Boolean) -> Unit = {},
    fill: Color = Color.Transparent,
    grows: Boolean = true,
    content: @Composable BoxScope.(focused: Boolean) -> Unit,
) {
    val look = gameLook()
    var focused by remember { mutableStateOf(false) }
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val keys = LocalInputModeManager.current.inputMode == InputMode.Keyboard
    val showing = focused && (look.tv || keys)
    val reduce = LocalReduceMotion.current
    val ring = GameColours.text
    val grow = if (showing && grows && !reduce) look.focusScale else 1f
    val shape = RoundedCornerShape(radius)
    Box(
        modifier
            .graphicsLayer {
                scaleX = grow
                scaleY = grow
                alpha = if (!enabled) 0.5f else if (pressed) 0.8f else 1f
            }
            .drawWithContent {
                drawContent()
                if (showing) {
                    val out = (look.ringGap + look.ring / 2).toPx()
                    drawRoundRect(
                        ring, topLeft = Offset(-out, -out), size = Size(size.width + 2 * out, size.height + 2 * out),
                        cornerRadius = CornerRadius(radius.toPx() + out), style = Stroke(look.ring.toPx()),
                    )
                }
            }
            .then(if (focusRequester != null) Modifier.focusRequester(focusRequester) else Modifier)
            .onFocusChanged {
                focused = it.isFocused
                onFocus(it.isFocused)
            }
            .then(if (label != null) Modifier.semantics { contentDescription = label } else Modifier)
            .clip(shape)
            .background(fill)
            .clickable(interactionSource = interaction, indication = null, enabled = true, role = Role.Button) { if (enabled) onClick() },
    ) { content(focused) }
}

enum class ButtonKind { Primary, Secondary, Ghost, Danger }

@Composable
fun GameButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    kind: ButtonKind = ButtonKind.Secondary,
    icon: ImageVector? = null,
    focusRequester: FocusRequester? = null,
    enabled: Boolean = true,
    big: Boolean = true,
) {
    val look = gameLook()
    val fill = when (kind) {
        ButtonKind.Primary -> GameColours.accent
        ButtonKind.Secondary -> GameColours.card
        ButtonKind.Ghost -> Color.Transparent
        ButtonKind.Danger -> GameColours.danger
    }
    val ink = when (kind) {
        ButtonKind.Primary -> GameColours.onAccent
        ButtonKind.Danger -> Color.White
        else -> GameColours.text
    }
    val outline = if (kind == ButtonKind.Ghost) GameColours.border else Color.Transparent
    Pressable(onClick, modifier, enabled = enabled, focusRequester = focusRequester, fill = fill) {
        Row(
            Modifier
                .border(1.dp, outline, RoundedCornerShape(look.radius))
                .defaultMinSize(minHeight = if (big) look.button else look.button * 0.8f)
                .padding(horizontal = if (look.tv) tv(32) else 16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
        ) {
            if (icon != null) Icon(icon, null, Modifier.size(look.icon), tint = ink)
            Text(text, color = ink, fontSize = look.label, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

// A square button with an icon alone, its words for screen readers.
@Composable
fun GameIconButton(icon: ImageVector, label: String, onClick: () -> Unit, modifier: Modifier = Modifier, on: Boolean = false, tint: Color? = null, focusRequester: FocusRequester? = null) {
    val look = gameLook()
    Pressable(onClick, modifier.size(look.button), label = label, fill = GameColours.card, focusRequester = focusRequester) {
        Icon(icon, null, Modifier.align(Alignment.Center).size(look.icon + 2.dp), tint = tint ?: if (on) GameColours.accentText else GameColours.text)
    }
}

// A chip: 32 high, the chosen one raised.
@Composable
fun GameChip(text: String, chosen: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier, icon: ImageVector? = null) {
    val look = gameLook()
    Pressable(onClick, modifier, radius = 999.dp, fill = if (chosen) GameColours.text else GameColours.card) {
        Row(
            Modifier.defaultMinSize(minHeight = if (look.tv) tv(56) else 36.dp).padding(horizontal = if (look.tv) tv(24) else 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            val ink = if (chosen) GameColours.background else GameColours.secondary
            if (icon != null) Icon(icon, null, Modifier.size(look.icon * 0.9f), tint = ink)
            Text(text, color = ink, fontSize = if (look.tv) tvText(25) else 13.sp, fontWeight = FontWeight.Medium, maxLines = 1)
        }
    }
}

@Composable
fun GameSection(text: String, modifier: Modifier = Modifier, action: String? = null, onAction: (() -> Unit)? = null) {
    val look = gameLook()
    Row(modifier.padding(horizontal = look.gutter), verticalAlignment = Alignment.CenterVertically) {
        Text(text, Modifier.weight(1f), color = GameColours.text, fontSize = look.title, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (action != null && onAction != null) {
            Pressable(onAction, radius = 8.dp) {
                Text(
                    "$action ›", Modifier.padding(horizontal = 4.dp, vertical = if (look.tv) 4.dp else 12.dp),
                    color = GameColours.secondary, fontSize = if (look.tv) look.small else 13.sp, fontWeight = FontWeight.Medium,
                )
            }
        }
    }
}

// A picture from the server, or the title on a colour of its own while there's none.
@Composable
fun GamePicture(url: String?, title: String, modifier: Modifier = Modifier, label: String = "", contentScale: ContentScale = ContentScale.Fit) {
    Box(modifier) {
        if (url == null) {
            GamePlaceholder(title, label, Modifier.fillMaxSize())
        } else {
            AsyncImage(model = url, contentDescription = null, modifier = Modifier.fillMaxSize(), contentScale = contentScale)
        }
    }
}

// No artwork: a gradient from the title's own colour to `card`, with the title over its lower part.
@Composable
fun GamePlaceholder(title: String, label: String, modifier: Modifier = Modifier) {
    val look = gameLook()
    val hue = ((title.hashCode() % 360) + 360) % 360
    val top = Color.hsv(hue.toFloat(), 0.45f, 0.55f)
    Box(modifier.background(Brush.verticalGradient(listOf(top, GameColours.card))).padding(8.dp)) {
        Text(
            title, Modifier.align(Alignment.BottomStart), color = Color.White, fontSize = if (look.tv) tvText(27) else 13.sp,
            fontWeight = FontWeight.SemiBold, maxLines = 3, overflow = TextOverflow.Ellipsis,
        )
        if (label.isNotEmpty()) {
            Text(label, Modifier.align(Alignment.TopStart), color = Color.White.copy(alpha = 0.8f), fontSize = if (look.tv) tvText(22) else 11.sp, fontWeight = FontWeight.Bold)
        }
    }
}

// Words in the middle of an empty or failed screen, with what to do about it.
@Composable
fun GameNote(title: String, body: String, modifier: Modifier = Modifier, action: String? = null, onAction: (() -> Unit)? = null) {
    val look = gameLook()
    val focus = remember { FocusRequester() }
    androidx.compose.foundation.layout.Column(
        modifier.padding(look.gutter),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(look.gap),
    ) {
        Text(title, color = GameColours.text, fontSize = look.title, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
        if (body.isNotEmpty()) Text(body, color = GameColours.secondary, fontSize = look.body, textAlign = TextAlign.Center)
        if (action != null && onAction != null) {
            GameButton(action, onAction, Modifier.padding(top = look.gap), kind = ButtonKind.Primary, focusRequester = focus)
            LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
        }
    }
}
