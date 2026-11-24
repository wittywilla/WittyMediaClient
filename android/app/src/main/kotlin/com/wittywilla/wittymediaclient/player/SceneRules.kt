// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.player

import com.wittywilla.wittymediaclient.net.Chapter

// The scenes panel's rules, as the website's (web/src/player/VideoPlayer.tsx, sceneThumb) and the same in
// apple/WittyKit (PlayerLook.swift, Scenes): which scene is playing, its name, and the moment its picture is taken.
object SceneRules {
    // The last scene that has started, with half a second's grace.
    fun current(chapters: List<Chapter>, filmSec: Double): Int = chapters.indexOfLast { it.start <= filmSec + 0.5 }.coerceAtLeast(0)

    fun name(chapters: List<Chapter>, i: Int): String = chapters.getOrNull(i)?.title?.trim()?.ifEmpty { null } ?: "Scene ${i + 1}"

    // A quarter of the way in, between 2 and 20 seconds: past a fade from black or a studio's logo, still this scene.
    fun pictureSec(chapters: List<Chapter>, i: Int, durationSec: Double): Int {
        val from = chapters.getOrNull(i)?.start ?: return 0
        val to = chapters.getOrNull(i + 1)?.start ?: durationSec.takeIf { it > from } ?: (from + 8)
        return kotlin.math.floor(from + ((to - from) / 4).coerceIn(2.0, 20.0)).toInt()
    }
}
