// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.Chapter
import com.wittywilla.wittymediaclient.player.SceneRules
import org.junit.Assert.assertEquals
import org.junit.Test

class SceneRulesTest {
    private val chapters = listOf(Chapter(0.0, "Start"), Chapter(60.0, ""), Chapter(300.0, "End"))

    @Test
    fun theSceneIsTheLastOneStarted() {
        assertEquals(0, SceneRules.current(chapters, 0.0))
        assertEquals(1, SceneRules.current(chapters, 59.6))
        assertEquals(2, SceneRules.current(chapters, 5000.0))
        assertEquals(0, SceneRules.current(emptyList(), 10.0))
    }

    @Test
    fun aSceneWithNoNameIsNumbered() {
        assertEquals("Start", SceneRules.name(chapters, 0))
        assertEquals("Scene 2", SceneRules.name(chapters, 1))
    }

    @Test
    fun thePictureIsAQuarterInBetweenTwoAndTwentySeconds() {
        assertEquals(15, SceneRules.pictureSec(chapters, 0, 400.0)) // 60 s long: 15 s in
        assertEquals(80, SceneRules.pictureSec(chapters, 1, 400.0)) // 240 s long: at most 20 s in
        assertEquals(320, SceneRules.pictureSec(chapters, 2, 400.0)) // to the end: 100 s long, so 20 s in
        assertEquals(2, SceneRules.pictureSec(listOf(Chapter(0.0), Chapter(4.0)), 0, 10.0)) // at least 2 s in
    }
}
