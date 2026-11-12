// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.Dp

// A profile's face: the picture it chose from the server's set, white on its colour, or its initial on the colour
// of its name when it chose none (docs/APP-DESIGN.md, "Avatar"). The same tile either way, so lists line up.
@Composable
fun ProfileFace(name: String, avatar: String?, size: Dp, modifier: Modifier = Modifier) {
    val picture = remember(avatar) { parseAvatar(avatar) }
    if (picture == null) {
        Avatar(name, size, modifier)
        return
    }
    val path = remember(picture.shape) { runCatching { PathParser().parsePathString(picture.shape).toPath() }.getOrNull() }
    if (path == null) {
        Avatar(name, size, modifier)
        return
    }
    val circle = size <= LocalMetrics.current.u(36)
    Box(modifier.size(size).clip(avatarShape(size, circle)).background(Color(picture.background)), contentAlignment = Alignment.Center) {
        // No words of its own: whatever shows a face names the person beside it.
        Canvas(Modifier.size(size * AVATAR_PICTURE_SHARE)) {
            val factor = this.size.minDimension / GRID
            scale(factor, factor, pivot = androidx.compose.ui.geometry.Offset.Zero) { drawPath(path, Color.White) }
        }
    }
}

// The shapes are drawn on the icons' 24 grid.
private const val GRID = 24f
