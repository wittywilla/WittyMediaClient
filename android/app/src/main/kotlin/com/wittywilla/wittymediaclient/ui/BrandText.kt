// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import coil3.compose.AsyncImagePainter
import com.wittywilla.wittymediaclient.net.AppTheme
import com.wittywilla.wittymediaclient.net.BrandColor
import com.wittywilla.wittymediaclient.net.BrandEditor
import com.wittywilla.wittymediaclient.net.BrandKinds
import com.wittywilla.wittymediaclient.net.BrandMarkChoice
import com.wittywilla.wittymediaclient.net.BrandPart
import com.wittywilla.wittymediaclient.net.ThemeColour
import androidx.compose.ui.text.style.TextOverflow

// The server's name as every frame draws it (docs/plans/DESIGN-2.md 7.6): each part in the colour it carries. `fg` is
// the text colour, `accent` the theme's brand accent, `token` a colour of the theme in force, `static` a fixed colour,
// `gradient` fixed colours across the part (a letter at a time, so it is plain text a screen reader reads whole and
// every Text can draw it), and a bold part in the heavy weight.
fun buildBrandText(parts: List<BrandPart>, ink: Color, accent: Color, theme: AppTheme?): AnnotatedString = buildAnnotatedString {
    for (part in parts) {
        val weight = if (part.bold) FontWeight.ExtraBold else null
        val color = part.color ?: if (part.accent) BrandColor.ACCENT else BrandColor.FG
        when (color.kind) {
            BrandKinds.GRADIENT -> {
                val letters = BrandEditor.letters(part.text)
                val steps = BrandEditor.gradientLetters(color.stops, color.angle, letters.size)
                letters.forEachIndexed { i, letter ->
                    withStyle(SpanStyle(color = steps.getOrNull(i)?.let { Color(it.argb) } ?: ink, fontWeight = weight)) { append(letter) }
                }
            }
            else -> {
                val colour = when (color.kind) {
                    BrandKinds.ACCENT -> accent
                    BrandKinds.TOKEN -> theme?.let { BrandEditor.tokenColour(color.token, it) }?.let { Color(it.argb) } ?: ink
                    BrandKinds.STATIC -> ThemeColour.parse(color.hex)?.let { Color(it.argb) } ?: ink
                    else -> ink
                }
                withStyle(SpanStyle(color = colour, fontWeight = weight)) { append(part.text) }
            }
        }
    }
}

// The rail's badge (docs/plans/DESIGN-2.md 9): a square with its content centred, never a bare letter. It holds the first
// letter, initials, one or two characters of the owner's own, or the logo fitted inside (the letter shows while it
// loads and if it can't). It takes the name's first colour unless a logo is shown. `logo` is anything Coil reads.
@Composable
fun BrandMarkBadge(name: String, parts: List<BrandPart>, mark: BrandMarkChoice, logo: Any?, size: Dp, modifier: Modifier = Modifier) {
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val theme = LocalAppTheme.current
    val shown = BrandEditor.markShown(name, mark)
    // The badge takes the first colour the name has that is not plain text, else the accent.
    val first = parts.firstOrNull { it.text.isNotBlank() && (it.color?.kind ?: if (it.accent) BrandKinds.ACCENT else BrandKinds.FG) != BrandKinds.FG } ?: BrandPart("", accent = true)
    val ink = remember(first, shown, extra.brandAccent, scheme.onBackground, theme) {
        buildBrandText(listOf(first.copy(text = shown.ifEmpty { "W" })), scheme.onBackground, extra.brandAccent, theme)
    }
    var loaded by remember(logo) { mutableStateOf(false) }
    val wantsLogo = mark.kind == BrandEditor.MARK_IMAGE && logo != null && logo != ""
    val shape = markShape(size)
    Box(
        modifier.size(size).clip(shape).background(scheme.primary.copy(alpha = 0.16f)).border(1.dp, scheme.outline, shape).clearAndSetSemantics { },
        contentAlignment = Alignment.Center,
    ) {
        if (!(wantsLogo && loaded)) {
            val fontSize = (size.value * if (shown.length > 1) 0.4f else 0.52f).sp
            Text(ink, fontSize = fontSize, fontWeight = FontWeight.ExtraBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (wantsLogo) {
            AsyncImage(
                model = logo, contentDescription = null, contentScale = ContentScale.Fit, modifier = Modifier.size(size * 0.82f),
                onState = { loaded = it is AsyncImagePainter.State.Success },
            )
        }
    }
}
