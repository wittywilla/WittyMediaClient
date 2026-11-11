// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.CanvasInfo
import com.wittywilla.wittymediaclient.net.json
import com.wittywilla.wittymediaclient.player.CanvasBlock
import com.wittywilla.wittymediaclient.player.CanvasConditions
import com.wittywilla.wittymediaclient.player.CanvasRules
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// When the looping video behind the artwork plays, and when the still artwork stays.
class CanvasRulesTest {
    private val fine = CanvasConditions(serverHas = true)

    @Test
    fun itPlaysOnlyWhenNothingIsShort() {
        assertNull(CanvasRules.blocked(fine))
        assertEquals(CanvasBlock.OldServer, CanvasRules.blocked(fine.copy(serverHas = false)))
        assertEquals(CanvasBlock.TurnedOff, CanvasRules.blocked(fine.copy(wanted = false)))
        assertEquals(CanvasBlock.BatterySaver, CanvasRules.blocked(fine.copy(batterySaver = true)))
        assertEquals(CanvasBlock.DataSaver, CanvasRules.blocked(fine.copy(dataSaver = true)))
        assertEquals(CanvasBlock.Metered, CanvasRules.blocked(fine.copy(metered = true)))
        assertEquals(CanvasBlock.AwayFromHome, CanvasRules.blocked(fine.copy(awayFromHome = true)))
        assertEquals(CanvasBlock.ReduceMotion, CanvasRules.blocked(fine.copy(reduceMotion = true)))
        assertEquals(CanvasBlock.LowRam, CanvasRules.blocked(fine.copy(lowRam = true)))
        assertEquals(CanvasBlock.FilmPlaying, CanvasRules.blocked(fine.copy(filmPlaying = true)))
    }

    @Test
    fun thePersonsChoiceIsTheReasonGivenFirst() {
        val everything = CanvasConditions(true, wanted = false, batterySaver = true, dataSaver = true, metered = true, awayFromHome = true, reduceMotion = true, lowRam = true, filmPlaying = true)
        assertEquals(CanvasBlock.TurnedOff, CanvasRules.blocked(everything))
        assertEquals(CanvasBlock.ReduceMotion, CanvasRules.blocked(everything.copy(wanted = true)))
        assertEquals(CanvasBlock.OldServer, CanvasRules.blocked(everything.copy(serverHas = false)))
    }

    @Test
    fun onlyWhatTheServerFoundAndThisAppCanLoopIsPlayed() {
        // What a 0.8.0 server really answered, before and after an administrator had one cut from the film.
        val none = json.decodeFromString<CanvasInfo>("""{"available":false,"loop":true,"canGenerate":true}""")
        val made = json.decodeFromString<CanvasInfo>("""{"available":true,"url":"/api/media/1/canvas/file?v=x7sg5-dmsixdhko8um","mime":"video/mp4","width":640,"height":360,"durationMs":8000,"loop":true,"source":"generated","canGenerate":true}""")
        assertFalse(CanvasRules.playable(none))
        assertTrue(none.canGenerate)
        assertTrue(CanvasRules.playable(made))
        assertEquals("generated", made.source)
        assertTrue(CanvasRules.playable(made.copy(mime = "video/webm")))
        assertFalse(CanvasRules.playable(made.copy(mime = "image/gif")))
        // An answer can't point the player somewhere else.
        assertFalse(CanvasRules.playable(made.copy(url = "https://elsewhere.example/c.mp4")))
        assertFalse(CanvasRules.playable(made.copy(url = "//elsewhere.example/c.mp4")))
        // Found but refused by the server for its size: not available, and so not played.
        assertFalse(CanvasRules.playable(CanvasInfo(available = false, reason = "too-big")))
    }

    @Test
    fun homeIsAPrivateAddressOrALocalName() {
        assertFalse(CanvasRules.awayFromHome("http://192.168.1.20:9797"))
        assertFalse(CanvasRules.awayFromHome("http://10.0.2.2:9924"))
        assertFalse(CanvasRules.awayFromHome("http://mediabox:9797"))
        assertFalse(CanvasRules.awayFromHome("https://mediabox.local"))
        assertFalse(CanvasRules.awayFromHome("http://[fe80::1]:9797"))
        assertTrue(CanvasRules.awayFromHome("https://media.example.org"))
        assertTrue(CanvasRules.awayFromHome("https://203.0.113.7:9797"))
        // An address that can't be read is treated as away: the still artwork is never wrong.
        assertTrue(CanvasRules.awayFromHome(""))
        assertTrue(CanvasRules.awayFromHome("not an address"))
    }

    @Test
    fun theVideoFillsItsPlaceWithoutLosingItsShape() {
        // A wide video in a square: full height, and wider than the square by its own shape.
        val (x, y) = CanvasRules.coverScale(400, 400, 1280, 720)
        assertEquals(1280f / 720f, x, 1e-4f)
        assertEquals(1f, y, 1e-4f)
        // An upright video across a wide banner: full width, taller than the banner.
        val (bx, by) = CanvasRules.coverScale(1000, 250, 720, 1280)
        assertEquals(1f, bx, 1e-4f)
        assertEquals((1280f * (1000f / 720f)) / 250f, by, 1e-3f)
        // The same shape needs nothing, and an unknown size is left alone.
        assertEquals(1f to 1f, CanvasRules.coverScale(640, 360, 1280, 720))
        assertEquals(1f to 1f, CanvasRules.coverScale(0, 360, 1280, 720))
        assertEquals(1f to 1f, CanvasRules.coverScale(640, 360, 0, 0))
    }

    @Test
    fun aNewFileOnTheServerIsANewFileHere() {
        assertEquals("canvas-1-x7sg5-dmsixdhko8um", CanvasRules.fileName(1, "/api/media/1/canvas/file?v=x7sg5-dmsixdhko8um"))
        assertEquals("canvas-7-0", CanvasRules.fileName(7, "/api/media/7/canvas/file"))
        // Nothing from an address can name a path.
        assertEquals("canvas-7-etcpasswd", CanvasRules.fileName(7, "/api/media/7/canvas/file?v=../../etc/passwd&x=1"))
    }
}
