package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.CornerBasedShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.autofill.ContentType
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.drawOutline
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.InputMode
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalInputModeManager
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.contentType
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import com.wittywilla.wittymediaclient.net.Profile
import kotlinx.coroutines.delay

// The shared wording, shared/data/strings.en.json, for the pieces below that have words of their own.
val LocalWords = staticCompositionLocalOf { emptyMap<String, String>() }

private const val PRESS_SCALE = 0.97f
private const val PRESS_ALPHA = 0.85f
private const val DISABLED_ALPHA = 0.55f
private const val FOCUS_TRIES = 4

// A ring around something, `gap` out from its edge, drawn outside it so nothing moves when it shows. It's
// concentric: each corner is the thing's own radius plus the distance out, so a radius 14 key's 4-wide ring 4 out
// has an outer radius of 22, never the key's radius drawn larger.
fun Modifier.ringOutside(shape: Shape, colour: Color, gap: Dp, width: Dp): Modifier = drawWithContent {
    drawContent()
    val stroke = width.toPx()
    val out = gap.toPx() + stroke / 2
    val radius = (shape as? CornerBasedShape)?.topStart?.toPx(size, this) ?: 0f
    drawRoundRect(
        colour,
        topLeft = Offset(-out, -out),
        size = Size(size.width + 2 * out, size.height + 2 * out),
        cornerRadius = CornerRadius(radius + out),
        style = Stroke(stroke),
    )
}

// What the sign-in screens and the pieces from docs/APP-DESIGN.md are pressed with. Held, it shrinks a
// little and dims; with a remote's focus it grows 1.06 and has a ring in `text`, 4 units out. With
// Reduce Motion on, it only dims. `content` is told when it's pressed or focused.
@Composable
fun Pressable(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    shape: Shape = LocalMetrics.current.corner(10),
    fill: Color = Color.Transparent,
    label: String? = null,
    state: String? = null,
    selected: Boolean = false,
    focusKey: String? = null,
    requestFocus: Boolean = false,
    // For something that has just appeared as the screen's main action, whatever had focus before.
    takeFocus: Boolean = false,
    focusRequester: FocusRequester? = null,
    enabled: Boolean = true,
    pressScale: Float = PRESS_SCALE,
    pressAlpha: Float = PRESS_ALPHA,
    ring: Boolean = true,
    // Off for something whose own part reacts instead, as a profile tile's avatar does.
    grows: Boolean = true,
    // Off for something that draws outside itself, as a profile tile's lifted, ringed avatar does.
    clip: Boolean = true,
    content: @Composable (active: Boolean) -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    // From the focus system itself: focus given on a screen's first frame can come before an
    // interaction stream is listened to, and would never show.
    var focused by remember { mutableStateOf(false) }
    val requester = focusRequester ?: remember { FocusRequester() }
    val memory = LocalFocusMemory.current
    val metrics = LocalMetrics.current
    val reduce = LocalReduceMotion.current
    val keyboard = LocalInputModeManager.current.inputMode == InputMode.Keyboard
    // Coming back counts on the first look only, so a change later doesn't pull focus back here.
    val comingBack = remember { focusKey != null && memory.last == focusKey }
    val wanted = comingBack || takeFocus || (requestFocus && memory.last == null)
    // A screen that has just replaced another may not take it on the first frame, so it tries a few.
    LaunchedEffect(wanted) {
        if (!wanted) return@LaunchedEffect
        repeat(FOCUS_TRIES) {
            runCatching { requester.requestFocus() }
            withFrameNanos { }
            if (focused) return@LaunchedEffect
        }
    }
    val showsFocus = focused && keyboard
    val grow = when {
        reduce || !grows -> 1f
        showsFocus -> metrics.focusScale
        pressed -> pressScale
        else -> 1f
    }
    val dim = (if (pressed) pressAlpha else 1f) * (if (enabled) 1f else DISABLED_ALPHA)
    val ringColour = MaterialTheme.colorScheme.onBackground
    Box(
        modifier
            // Above its neighbours, so they don't cover its ring.
            .zIndex(if (showsFocus) 1f else 0f)
            .graphicsLayer { scaleX = grow; scaleY = grow; alpha = dim }
            .then(if (ring && showsFocus) Modifier.ringOutside(shape, ringColour, metrics.focusRing, metrics.focusRing) else Modifier)
            .focusRequester(requester)
            .onFocusChanged {
                focused = it.isFocused
                if (it.isFocused && focusKey != null) memory.last = focusKey
            }
            .semantics {
                if (label != null) contentDescription = label
                if (state != null) stateDescription = state
                if (selected) this.selected = true
                if (!enabled) disabled()
            }
            .then(if (clip) Modifier.clip(shape) else Modifier)
            .background(fill, shape)
            .clickable(interactionSource = interaction, indication = null, role = Role.Button) { if (enabled) onClick() },
        contentAlignment = Alignment.Center,
    ) { content(pressed || showsFocus) }
}

enum class ButtonKind { Primary, Secondary, Quiet, Destructive }

// docs/APP-DESIGN.md, "Buttons". Tall is the sign-in screens' 52. While busy, a spinner in the words'
// colour takes their place and the button keeps its size, and its focus on a TV.
@Composable
fun WittyButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    kind: ButtonKind = ButtonKind.Secondary,
    icon: ImageVector? = null,
    busy: Boolean = false,
    enabled: Boolean = true,
    tall: Boolean = false,
    pill: Boolean = false,
    requestFocus: Boolean = false,
    takeFocus: Boolean = false,
    focusKey: String? = null,
    focusRequester: FocusRequester? = null,
) {
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val metrics = LocalMetrics.current
    val fill = when (kind) {
        ButtonKind.Primary -> scheme.primary
        ButtonKind.Quiet -> Color.Transparent
        ButtonKind.Secondary, ButtonKind.Destructive -> scheme.surfaceVariant
    }
    val ink = when (kind) {
        ButtonKind.Primary -> scheme.onPrimary
        ButtonKind.Quiet -> extra.accentText
        ButtonKind.Secondary -> scheme.onSurface
        ButtonKind.Destructive -> scheme.error
    }
    val style = MaterialTheme.typography.label.let { if (kind == ButtonKind.Quiet) it.copy(fontWeight = FontWeight.SemiBold) else it }
    val sideRoom = when {
        kind == ButtonKind.Quiet -> metrics.u(8)
        pill -> metrics.u(20)
        else -> metrics.u(16)
    }
    Pressable(
        { if (!busy) onClick() }, modifier,
        shape = if (pill) Radius.FULL else LocalMetrics.current.corner(10), fill = fill,
        label = if (busy) text else null, state = if (busy) LocalWords.current["connecting"] else null,
        focusKey = focusKey, requestFocus = requestFocus, takeFocus = takeFocus, focusRequester = focusRequester, enabled = enabled,
    ) {
        Box(
            Modifier
                .defaultMinSize(minHeight = if (tall && !metrics.tv) 52.dp else metrics.minTarget)
                .padding(horizontal = sideRoom, vertical = metrics.u(8)),
            contentAlignment = Alignment.Center,
        ) {
            Row(
                Modifier.graphicsLayer { alpha = if (busy) 0f else 1f },
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(metrics.u(8)),
            ) {
                if (icon != null) Icon(icon, contentDescription = null, tint = ink, modifier = Modifier.size(metrics.u(20)))
                Text(text, color = ink, style = style, textAlign = TextAlign.Center)
            }
            if (busy) Spinner(ink, metrics.u(20))
        }
    }
}

@Composable
fun Spinner(colour: Color, size: Dp, modifier: Modifier = Modifier) {
    CircularProgressIndicator(modifier.size(size), color = colour, strokeWidth = (size.value / 10).coerceAtLeast(1.5f).dp)
}

enum class FieldKind { Address, Username, Password, Text }

// docs/APP-DESIGN.md, "Fields": outlined, the label rising onto the border, an icon in front, and a
// password's show and hide. The keyboard suits what's typed, and autofill knows which is which.
@Composable
fun WittyField(
    value: String,
    onChange: (String) -> Unit,
    label: String,
    modifier: Modifier = Modifier,
    kind: FieldKind = FieldKind.Text,
    icon: ImageVector? = null,
    error: String = "",
    imeAction: ImeAction = ImeAction.Done,
    onAction: () -> Unit = {},
    focusRequester: FocusRequester? = null,
    // Refused, as a wrong password is: the outline and label turn `danger` until the person types again.
    isError: Boolean = false,
    // Counts refusals: each one shakes the field once.
    shake: Int = 0,
    maxLength: Int = Int.MAX_VALUE,
) {
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val metrics = LocalMetrics.current
    val words = LocalWords.current
    val shaking = rememberShake(shake)
    var showing by rememberSaveable { mutableStateOf(false) }
    val secret = kind == FieldKind.Password && !showing
    val keyboard = when (kind) {
        FieldKind.Address -> KeyboardType.Uri
        FieldKind.Username -> KeyboardType.Ascii
        FieldKind.Password -> KeyboardType.Password
        FieldKind.Text -> KeyboardType.Text
    }
    val quiet = scheme.onSurfaceVariant
    val fieldModifier = Modifier
        .then(if (focusRequester != null) Modifier.focusRequester(focusRequester) else Modifier)
        .semantics {
            when (kind) {
                FieldKind.Username -> contentType = ContentType.Username
                FieldKind.Password -> contentType = ContentType.Password
                else -> Unit
            }
        }
        .tvLeavable()
    val keyboardOptions = KeyboardOptions(keyboardType = keyboard, imeAction = imeAction, autoCorrectEnabled = false)
    val keyboardActions = KeyboardActions(onAny = { onAction() })
    val trailing: (@Composable () -> Unit)? = if (kind != FieldKind.Password) null else {
        {
            val say = if (showing) words["hidePassword"].orEmpty() else words["showPassword"].orEmpty()
            Pressable({ showing = !showing }, Modifier.size(metrics.u(44)), shape = CircleShape, label = say) {
                Icon(if (showing) Symbols.Hide else Symbols.Show, contentDescription = null, tint = quiet, modifier = Modifier.size(metrics.u(22)))
            }
        }
    }
    val limited: (String) -> Unit = { onChange(it.take(maxLength)) }
    Column(modifier.fillMaxWidth().graphicsLayer { translationX = shaking.value * density }) {
        if (metrics.tv) {
            TvTextField(value, limited, label, icon, secret, keyboardOptions, keyboardActions, trailing, isError, fieldModifier)
        } else {
            OutlinedTextField(
                value = value,
                onValueChange = limited,
                isError = isError,
                label = { Text(label) },
                singleLine = true,
                shape = LocalMetrics.current.corner(10),
                leadingIcon = icon?.let { { Icon(it, contentDescription = null, modifier = Modifier.padding(start = metrics.u(4)).size(metrics.u(20))) } },
                trailingIcon = trailing,
                visualTransformation = if (secret) PasswordVisualTransformation() else VisualTransformation.None,
                keyboardOptions = keyboardOptions,
                keyboardActions = keyboardActions,
                colors = OutlinedTextFieldDefaults.colors(
                    focusedTextColor = scheme.onBackground, unfocusedTextColor = scheme.onBackground,
                    focusedContainerColor = Color.Transparent, unfocusedContainerColor = Color.Transparent,
                    cursorColor = scheme.primary,
                    focusedBorderColor = scheme.primary, unfocusedBorderColor = scheme.outline,
                    focusedLabelColor = extra.accentText, unfocusedLabelColor = quiet,
                    focusedLeadingIconColor = quiet, unfocusedLeadingIconColor = quiet,
                    focusedTrailingIconColor = quiet, unfocusedTrailingIconColor = quiet,
                    errorTextColor = scheme.onBackground, errorContainerColor = Color.Transparent, errorCursorColor = scheme.primary,
                    errorBorderColor = scheme.error, errorLabelColor = scheme.error,
                    errorLeadingIconColor = quiet, errorTrailingIconColor = quiet,
                ),
                modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp).then(fieldModifier),
            )
        }
        if (error.isNotEmpty()) {
            Row(
                Modifier.padding(top = metrics.u(6)).semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite },
                horizontalArrangement = Arrangement.spacedBy(metrics.u(6)),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Symbols.Warning, contentDescription = null, tint = scheme.error, modifier = Modifier.size(metrics.u(16)))
                Text(error, color = scheme.error, style = MaterialTheme.typography.caption)
            }
        }
    }
}

// A TV's field, drawn here at the page's 56 units: Material's keeps to 56 dp, which is twice that on a
// TV. The same look: the label inside until there are words or focus, then on the border. Focus also
// has the TV's ring, but doesn't grow, as a field fills its column.
@Composable
private fun TvTextField(
    value: String,
    onChange: (String) -> Unit,
    label: String,
    icon: ImageVector?,
    secret: Boolean,
    keyboardOptions: KeyboardOptions,
    keyboardActions: KeyboardActions,
    trailing: (@Composable () -> Unit)?,
    isError: Boolean,
    modifier: Modifier = Modifier,
) {
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val metrics = LocalMetrics.current
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    val raised = focused || value.isNotEmpty()
    val quiet = scheme.onSurfaceVariant
    val body = MaterialTheme.typography.body
    val caption = MaterialTheme.typography.caption
    val half = with(LocalDensity.current) { (caption.lineHeight.toDp() / 2) }
    Box(Modifier.fillMaxWidth().padding(top = half)) {
        Row(
            Modifier
                .fillMaxWidth()
                .height(metrics.u(56))
                .then(if (focused) Modifier.ringOutside(LocalMetrics.current.corner(10), scheme.onBackground, metrics.focusRing, metrics.focusRing) else Modifier)
                .border(
                    if (focused || isError) 2.dp else 1.dp,
                    when {
                        isError -> scheme.error
                        focused -> scheme.primary
                        else -> scheme.outline
                    },
                    LocalMetrics.current.corner(10),
                )
                .padding(start = metrics.u(16), end = metrics.u(4)),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(metrics.u(12)),
        ) {
            if (icon != null) Icon(icon, contentDescription = null, tint = quiet, modifier = Modifier.size(metrics.u(20)))
            BasicTextField(
                value, onChange,
                modifier = Modifier.weight(1f).then(modifier).semantics { contentDescription = label },
                textStyle = body.copy(color = scheme.onBackground),
                singleLine = true,
                cursorBrush = SolidColor(scheme.primary),
                visualTransformation = if (secret) PasswordVisualTransformation() else VisualTransformation.None,
                keyboardOptions = keyboardOptions,
                keyboardActions = keyboardActions,
                interactionSource = interaction,
                decorationBox = { inner ->
                    Box(contentAlignment = Alignment.CenterStart) {
                        if (!raised) Text(label, color = quiet, style = body, maxLines = 1)
                        inner()
                    }
                },
            )
            trailing?.invoke()
        }
        if (raised) {
            Text(
                label, color = when {
                    isError -> scheme.error
                    focused -> extra.accentText
                    else -> quiet
                },
                style = caption, maxLines = 1,
                modifier = Modifier
                    .padding(start = metrics.u(12))
                    .offset(y = -half)
                    .background(scheme.background)
                    .padding(horizontal = metrics.u(4)),
            )
        }
    }
}

// What went wrong, with the warning icon: said aloud when it appears, and marked by more than its colour.
@Composable
fun Problem(text: String, modifier: Modifier = Modifier, centred: Boolean = false) {
    if (text.isEmpty()) return
    val metrics = LocalMetrics.current
    Row(
        modifier.semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite },
        horizontalArrangement = Arrangement.spacedBy(metrics.u(10), if (centred) Alignment.CenterHorizontally else Alignment.Start),
        verticalAlignment = Alignment.Top,
    ) {
        Icon(Symbols.Warning, contentDescription = null, tint = MaterialTheme.colorScheme.error, modifier = Modifier.padding(top = metrics.u(1)).size(metrics.u(20)))
        Text(text, color = MaterialTheme.colorScheme.onBackground, style = MaterialTheme.typography.body)
    }
}

// What isn't a failure, such as still looking for servers: in a panel, with a spinner while it waits.
@Composable
fun Note(text: String, modifier: Modifier = Modifier, busy: Boolean = false) {
    val scheme = MaterialTheme.colorScheme
    val metrics = LocalMetrics.current
    Row(
        modifier.fillMaxWidth().clip(LocalMetrics.current.corner(14)).background(scheme.surface).padding(metrics.u(16)).semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite },
        horizontalArrangement = Arrangement.spacedBy(metrics.u(12)),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (busy) Spinner(scheme.onSurfaceVariant, metrics.u(18)) else Icon(Symbols.Info, contentDescription = null, tint = scheme.onSurfaceVariant, modifier = Modifier.size(metrics.u(20)))
        Text(text, color = scheme.onSurfaceVariant, style = MaterialTheme.typography.body)
    }
}

// A change that worked: a pill near the bottom for three seconds. The caller places it.
@Composable
fun Toast(text: String, onGone: () -> Unit, modifier: Modifier = Modifier) {
    if (text.isEmpty()) return
    LaunchedEffect(text) {
        delay(TOAST_MS)
        onGone()
    }
    val metrics = LocalMetrics.current
    Box(
        modifier
            .clip(Radius.FULL)
            .background(MaterialTheme.colorScheme.surface)
            .padding(horizontal = metrics.u(20), vertical = metrics.u(12))
            .semantics { liveRegion = LiveRegionMode.Polite },
    ) {
        Text(text, color = MaterialTheme.colorScheme.onSurface, style = MaterialTheme.typography.label)
    }
}

private const val TOAST_MS = 3000L

// A pill of small words in `border`, such as "Last used".
@Composable
fun Tag(text: String, modifier: Modifier = Modifier) {
    val metrics = LocalMetrics.current
    Text(
        text, color = MaterialTheme.colorScheme.onSurface, style = MaterialTheme.typography.caption, maxLines = 1,
        modifier = modifier.clip(Radius.FULL).background(MaterialTheme.colorScheme.outline).padding(horizontal = metrics.u(8), vertical = metrics.u(2)),
    )
}

// docs/APP-DESIGN.md, "Avatar": a coloured tile with an initial, the same colour as in the browser.
// Small ones are circles.
@Composable
fun Avatar(name: String, size: Dp, modifier: Modifier = Modifier) {
    val circle = size <= LocalMetrics.current.u(36)
    val colour = remember(name) { Color(avatarColour(name)) }
    val type = with(LocalDensity.current) { (size * INITIAL_SHARE).toSp() }
    Box(modifier.size(size).clip(avatarShape(size, circle)).background(colour), contentAlignment = Alignment.Center) {
        Text(
            avatarInitial(name), color = Color.White, fontWeight = FontWeight.Bold, fontSize = type, lineHeight = type,
            style = TextStyle.Default, maxLines = 1,
        )
    }
}

fun avatarShape(size: Dp, circle: Boolean): Shape = if (circle) CircleShape else RoundedCornerShape(size * AVATAR_RADIUS)

private const val INITIAL_SHARE = 0.43f
private const val AVATAR_RADIUS = 0.22f

// docs/APP-DESIGN.md, "Profile tile". Pressed or focused, the avatar lifts 3 and gains the web's two
// rings, `background` then `text`, and the name brightens. A TV grows it as well.
@Composable
fun ProfileTile(
    profile: Profile,
    avatarSize: Dp,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    requestFocus: Boolean = false,
    focusKey: String? = null,
    // Room under the avatar for a badge, so the names in a row line up when any tile has one.
    badgeRoom: Boolean = false,
) {
    val scheme = MaterialTheme.colorScheme
    val metrics = LocalMetrics.current
    val words = LocalWords.current
    val reduce = LocalReduceMotion.current
    val shown = avatarName(profile.displayName, profile.name)
    val badge = when (profile.kind) {
        "kids" -> words["kidsBadge"].orEmpty()
        "guest" -> words["guestBadge"].orEmpty()
        else -> ""
    }
    val spoken = buildList {
        add(shown)
        if (showsUsername(profile.displayName, profile.name)) add("@${profile.name}")
        if (badge.isNotEmpty()) add("$badge profile")
    }.joinToString(", ")
    Pressable(
        onClick, modifier.width(avatarSize), shape = LocalMetrics.current.corner(10), label = spoken, focusKey = focusKey, requestFocus = requestFocus,
        pressScale = 1f, pressAlpha = 1f, ring = false, grows = false, clip = false,
    ) { active ->
        // A phone: lift 3, rings 3 and 3. A TV: lift 6 units and grow 1.06, rings 4 and 4 units.
        val gap = if (metrics.tv) metrics.focusRing else 3.dp
        val lift = if (metrics.tv) metrics.u(6) else 3.dp
        val grow = if (active && metrics.tv && !reduce) metrics.focusScale else 1f
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
            // Only the avatar reacts, and the badge moves with it; the names keep their size.
            Box(
                Modifier.graphicsLayer {
                    translationY = if (active && !reduce) -lift.toPx() else 0f
                    scaleX = grow
                    scaleY = grow
                },
                contentAlignment = Alignment.BottomCenter,
            ) {
                Avatar(
                    shown, avatarSize,
                    Modifier
                        .then(
                            if (active) {
                                Modifier
                                    .ringOutside(avatarShape(avatarSize, false), scheme.background, 0.dp, gap)
                                    .ringOutside(avatarShape(avatarSize, false), scheme.onBackground, gap, gap)
                            } else {
                                Modifier
                            },
                        ),
                )
                if (badge.isNotEmpty()) {
                    Text(
                        badge, color = scheme.onBackground, style = MaterialTheme.typography.caption,
                        modifier = Modifier
                            // Half over the avatar's lower edge.
                            .layout { measurable, constraints ->
                                val p = measurable.measure(constraints)
                                layout(p.width, p.height) { p.place(0, p.height / 2) }
                            }
                            .clip(Radius.FULL)
                            .background(scheme.background)
                            .border1(scheme.outline)
                            .padding(horizontal = metrics.u(8), vertical = metrics.u(2)),
                    )
                }
            }
            Spacer(Modifier.height(metrics.u(if (badgeRoom || badge.isNotEmpty()) 20 else 10)))
            Text(
                shown, color = if (active) scheme.onBackground else scheme.onSurfaceVariant,
                style = MaterialTheme.typography.label.copy(fontWeight = FontWeight.SemiBold),
                maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth(),
            )
            if (showsUsername(profile.displayName, profile.name)) {
                Text(
                    "@${profile.name}", color = scheme.onSurfaceVariant, style = MaterialTheme.typography.secondary,
                    maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}


private fun Modifier.border1(colour: Color) = this.then(
    Modifier.drawWithContent {
        drawContent()
        drawOutline(Radius.FULL.createOutline(size, layoutDirection, this), colour, style = Stroke(1.dp.toPx()))
    },
)

fun hasBadge(profile: Profile) = profile.kind == "kids" || profile.kind == "guest"

// One row of a grouped list.
data class GroupRow(
    val title: String,
    val onClick: (() -> Unit)? = null,
    val icon: ImageVector? = null,
    val tint: Color = Color.Unspecified,
    val value: String = "",
    val detail: String = "",
    val destructive: Boolean = false,
    val focusKey: String? = null,
)

// docs/APP-DESIGN.md, "Grouped list": for You and settings. A caption above, rows in a panel, hairlines
// between them, inset past the icons.
@Composable
fun GroupedList(caption: String, rows: List<GroupRow>, modifier: Modifier = Modifier) {
    val scheme = MaterialTheme.colorScheme
    val metrics = LocalMetrics.current
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(metrics.u(8))) {
        if (caption.isNotEmpty()) {
            Text(caption.uppercase(), color = scheme.onSurfaceVariant, style = MaterialTheme.typography.caption, modifier = Modifier.padding(horizontal = metrics.u(16)))
        }
        Column(Modifier.fillMaxWidth().clip(LocalMetrics.current.corner(14)).background(scheme.surface)) {
            rows.forEachIndexed { i, row ->
                if (i > 0) {
                    Box(
                        Modifier
                            .padding(start = if (rows[i].icon != null) metrics.u(52) else metrics.u(16))
                            .fillMaxWidth()
                            .height(1.dp)
                            .background(scheme.outline),
                    )
                }
                GroupRowView(row)
            }
        }
    }
}

@Composable
private fun GroupRowView(row: GroupRow) {
    val scheme = MaterialTheme.colorScheme
    val metrics = LocalMetrics.current
    val ink = if (row.destructive) scheme.error else scheme.onSurface
    val body: @Composable (Boolean) -> Unit = {
        Row(
            Modifier.fillMaxWidth().heightIn(min = metrics.u(if (row.detail.isEmpty()) 52 else 64)).padding(horizontal = metrics.u(16), vertical = metrics.u(8)),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(metrics.u(12)),
        ) {
            if (row.icon != null) {
                val tint = if (row.tint == Color.Unspecified) scheme.onSurfaceVariant else row.tint
                Box(
                    Modifier.size(metrics.u(28)).clip(RoundedCornerShape(metrics.u(7))).background(tint.copy(alpha = ICON_TINT)),
                    contentAlignment = Alignment.Center,
                ) { Icon(row.icon, contentDescription = null, tint = tint, modifier = Modifier.size(metrics.u(18))) }
            }
            Column(Modifier.weight(1f)) {
                Text(row.title, color = ink, style = MaterialTheme.typography.body)
                if (row.detail.isNotEmpty()) Text(row.detail, color = scheme.onSurfaceVariant, style = MaterialTheme.typography.secondary)
            }
            if (row.value.isNotEmpty()) Text(row.value, color = scheme.onSurfaceVariant, style = MaterialTheme.typography.secondary, maxLines = 1)
            if (row.onClick != null) Icon(Symbols.Next, contentDescription = null, tint = LocalExtraColours.current.hint, modifier = Modifier.size(metrics.u(20)))
        }
    }
    if (row.onClick != null) {
        Pressable(row.onClick, Modifier.fillMaxWidth(), shape = LocalMetrics.current.corner(6), focusKey = row.focusKey, pressScale = 1f) { body(it) }
    } else {
        Box(Modifier.semantics(mergeDescendants = true) {}) { body(false) }
    }
}

private const val ICON_TINT = 0.18f
