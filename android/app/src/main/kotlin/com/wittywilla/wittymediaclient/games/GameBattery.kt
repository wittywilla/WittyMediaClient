// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.games

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.BatteryState
import android.os.BatteryManager
import android.os.Build
import android.view.InputDevice
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlin.math.roundToInt
import androidx.compose.ui.text.style.TextOverflow

// Batteries: the controllers' and this device's, as WittyPlay's website shows them (web/battery.ts): chips with the
// level as text, "P1 72%" and "Battery 64%", "Low" in words at a fifth or less when not charging, and a notice said once,
// politely, when one runs low. Android reads a controller's from the system (Android 12 and later) and the device's
// from its battery; a level it doesn't give isn't guessed.

data class BatteryReading(val id: String, val device: Boolean, val name: String, val detail: String, val level: Float, val charging: Boolean)

object Batteries {
    const val LOW = 0.2f
    const val LOW_CLEAR = 0.25f

    // How often they are read again: a controller's level sends no event.
    const val POLL_MS = 15_000L

    fun percent(level: Float): Int = (level.coerceIn(0f, 1f) * 100).roundToInt()

    fun isLow(r: BatteryReading): Boolean = !r.charging && r.level <= LOW + 1e-6f

    fun text(r: BatteryReading): String = "${if (r.device) "Battery" else r.name} ${percent(r.level)}%"

    fun label(r: BatteryReading): String {
        val who = if (r.device) "This device" else "Controller ${r.name}" + (if (r.detail.isNotEmpty()) ", ${r.detail}" else "")
        return "$who: battery ${percent(r.level)}%" + when {
            r.charging -> ", charging"
            isLow(r) -> ", low"
            else -> ""
        }
    }

    fun lowNotice(r: BatteryReading): String = if (r.device) "This device’s battery is low: ${percent(r.level)}%. Plug it in soon."
    else "Controller ${r.name}’s battery is low: ${percent(r.level)}%. Charge it or change its batteries soon."

    // This device's battery, or null for one with none, or one full on its charger, which there is no need to show.
    fun device(present: Boolean, level: Float, charging: Boolean): BatteryReading? {
        if (!present || level.isNaN() || level < 0f) return null
        if (charging && level >= 1f) return null
        return BatteryReading("device", true, "This device", "", level.coerceIn(0f, 1f), charging)
    }

    // Reads them all now: each connected controller with a battery the system gives, named by its player (P1 for the
    // first), then the device.
    fun read(context: Context): List<BatteryReading> {
        val out = ArrayList<BatteryReading>()
        var n = 0
        for (id in InputDevice.getDeviceIds()) {
            val d = InputDevice.getDevice(id) ?: continue
            if (d.isVirtual) continue
            val pad = d.sources and InputDevice.SOURCE_GAMEPAD == InputDevice.SOURCE_GAMEPAD || d.sources and InputDevice.SOURCE_JOYSTICK == InputDevice.SOURCE_JOYSTICK
            if (!pad) continue
            n++
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val b = d.batteryState
                val level = b.capacity
                if (b.isPresent && !level.isNaN() && level in 0f..1f) {
                    out += BatteryReading("pad-$id", false, "P$n", d.name.orEmpty(), level, b.status == BatteryState.STATUS_CHARGING)
                }
            }
        }
        val sticky = runCatching { context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)) }.getOrNull()
        if (sticky != null) {
            val level = sticky.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = sticky.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
            val status = sticky.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
            val charging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
            val present = sticky.getBooleanExtra(BatteryManager.EXTRA_PRESENT, false)
            device(present, if (level >= 0 && scale > 0) level.toFloat() / scale else Float.NaN, charging)?.let { out += it }
        }
        return out
    }
}

// Which batteries just ran low: each once, until it has been charged again (back over LOW_CLEAR, or on charge).
class LowBatteryNotes {
    private val said = HashSet<String>()

    fun check(readings: List<BatteryReading>): List<String> {
        val now = readings.map { it.id }.toSet()
        said.retainAll(now)
        val out = ArrayList<String>()
        for (r in readings) {
            if (Batteries.isLow(r)) {
                if (said.add(r.id)) out += Batteries.lowNotice(r)
            } else if (r.charging || r.level >= Batteries.LOW_CLEAR) {
                said.remove(r.id)
            }
        }
        return out
    }
}

// The batteries now, read again every few seconds while shown. `notice` is given each low battery's words, once.
@Composable
fun rememberBatteries(notice: (String) -> Unit = {}): List<BatteryReading> {
    val context = LocalContext.current
    var readings by remember { mutableStateOf(emptyList<BatteryReading>()) }
    val notes = remember { LowBatteryNotes() }
    LaunchedEffect(context) {
        while (true) {
            val next = Batteries.read(context)
            if (next != readings) readings = next
            notes.check(next).takeIf { it.isNotEmpty() }?.let { notice(it.joinToString(" ")) }
            delay(Batteries.POLL_MS)
        }
    }
    return readings
}

// Each battery as a small icon and its level in words, a low one marked "Low" in words too.
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun BatteryChips(readings: List<BatteryReading>, size: TextUnit, modifier: Modifier = Modifier) {
    if (readings.isEmpty()) return
    FlowRow(modifier, horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        readings.forEach { r ->
            val low = Batteries.isLow(r)
            // As the website's: amber words on a dark pill for a low one.
            val ink = if (low) Color(0xFFFFC069) else Color(0xFFE6E9F0)
            Row(
                Modifier.clip(RoundedCornerShape(999.dp)).background(if (low) Color(0xD10A0C12) else Color(0x33FFFFFF)).padding(horizontal = 10.dp, vertical = 5.dp)
                    .clearAndSetSemantics { contentDescription = Batteries.label(r) },
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                BatteryIcon(r.level, ink)
                Text(Batteries.text(r) + if (low) " · Low" else "", color = ink, fontSize = size, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

@Composable
private fun BatteryIcon(level: Float, ink: Color) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(width = 18.dp, height = 10.dp).border(1.5.dp, ink, RoundedCornerShape(2.dp)).padding(2.dp)) {
            Box(Modifier.fillMaxHeight().width((14 * Batteries.percent(level) / 100).coerceAtLeast(1).dp).background(ink, RoundedCornerShape(1.dp)))
        }
        Box(Modifier.padding(start = 1.dp).size(width = 2.dp, height = 5.dp).background(ink, RoundedCornerShape(1.dp)))
    }
}
