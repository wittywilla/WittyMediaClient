// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.games.Batteries
import com.wittywilla.wittymediaclient.games.BatteryReading
import com.wittywilla.wittymediaclient.games.LowBatteryNotes
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// Batteries in words, as WittyPlay's website (web/battery.ts): the same chips and notices on every app.
class GameBatteryTest {
    private fun pad(level: Float, charging: Boolean = false) = BatteryReading("pad-3", false, "P1", "Xbox Wireless Controller", level, charging)

    @Test
    fun chipsAndLabels() {
        assertEquals("P1 72%", Batteries.text(pad(0.72f)))
        assertEquals("Battery 64%", Batteries.text(Batteries.device(true, 0.64f, false)!!))
        assertEquals("Controller P1, Xbox Wireless Controller: battery 72%, charging", Batteries.label(pad(0.72f, charging = true)))
        assertEquals("This device: battery 15%, low", Batteries.label(Batteries.device(true, 0.15f, false)!!))
    }

    @Test
    fun lowAtAFifthWhenNotCharging() {
        assertTrue(Batteries.isLow(pad(0.2f)))
        assertTrue(!Batteries.isLow(pad(0.2f, charging = true)))
        assertTrue(!Batteries.isLow(pad(0.21f)))
    }

    @Test
    fun noDeviceBatteryToShow() {
        assertNull(Batteries.device(false, 0.5f, false))
        assertNull(Batteries.device(true, 1f, true))
        assertNull(Batteries.device(true, Float.NaN, false))
    }

    @Test
    fun lowIsSaidOnceUntilCharged() {
        val notes = LowBatteryNotes()
        assertEquals(listOf("Controller P1’s battery is low: 18%. Charge it or change its batteries soon."), notes.check(listOf(pad(0.18f))))
        assertEquals(emptyList<String>(), notes.check(listOf(pad(0.17f))))
        assertEquals(emptyList<String>(), notes.check(listOf(pad(0.22f)))) // over the line, not yet clear
        assertEquals(emptyList<String>(), notes.check(listOf(pad(0.19f))))
        notes.check(listOf(pad(0.19f, charging = true)))
        assertEquals(1, notes.check(listOf(pad(0.18f))).size)
    }
}
