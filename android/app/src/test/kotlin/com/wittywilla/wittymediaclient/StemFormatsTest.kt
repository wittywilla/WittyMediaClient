// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient

import android.media.AudioFormat
import com.wittywilla.wittymediaclient.player.PcmMix
import com.wittywilla.wittymediaclient.player.PcmResampler
import org.junit.Assert.assertEquals
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder

// Karaoke's parts in any sample format, channel count and rate (player/StemMixer.kt).
class StemFormatsTest {
    @Test
    fun monoIsPutInBothSides() {
        val out = FloatArray(4)
        PcmMix.fold(floatArrayOf(0.5f, -0.25f), 2, 1, out)
        assertEquals(listOf(0.5f, 0.5f, -0.25f, -0.25f), out.toList())
    }

    @Test
    fun fivePointOneFoldsWithoutTheLowFrequencyChannel() {
        // L R C LFE Ls Rs, with only the low-frequency channel sounding: nothing is heard.
        val out = FloatArray(2)
        PcmMix.fold(floatArrayOf(0f, 0f, 0f, 1f, 0f, 0f), 1, 6, out)
        assertEquals(0f, out[0], 1e-6f)
        assertEquals(0f, out[1], 1e-6f)
        // Every channel at full: the fold is at full too, not louder.
        PcmMix.fold(floatArrayOf(1f, 1f, 1f, 1f, 1f, 1f), 1, 6, out)
        assertEquals(1f, out[0], 1e-6f)
        assertEquals(1f, out[1], 1e-6f)
        // The centre alone is in both sides, equally.
        PcmMix.fold(floatArrayOf(0f, 0f, 1f, 0f, 0f, 0f), 1, 6, out)
        assertEquals(out[0], out[1], 1e-6f)
    }

    @Test
    fun everyEncodingReadsTheSame() {
        fun buffer(bytes: Int, fill: (ByteBuffer) -> Unit) = ByteBuffer.allocate(bytes).order(ByteOrder.LITTLE_ENDIAN).also { fill(it); it.flip() }
        val out = FloatArray(1)
        PcmMix.read(buffer(2) { it.putShort(16384) }, AudioFormat.ENCODING_PCM_16BIT, out, 1)
        assertEquals(0.5f, out[0], 1e-4f)
        PcmMix.read(buffer(4) { it.putFloat(0.5f) }, AudioFormat.ENCODING_PCM_FLOAT, out, 1)
        assertEquals(0.5f, out[0], 1e-6f)
        PcmMix.read(buffer(4) { it.putInt(1 shl 30) }, AudioFormat.ENCODING_PCM_32BIT, out, 1)
        assertEquals(0.5f, out[0], 1e-6f)
        // 24 bits, little-endian: 0x400000 is a half; 0xC00000 is minus a half.
        PcmMix.read(buffer(3) { it.put(0); it.put(0); it.put(0x40) }, AudioFormat.ENCODING_PCM_24BIT_PACKED, out, 1)
        assertEquals(0.5f, out[0], 1e-6f)
        PcmMix.read(buffer(3) { it.put(0); it.put(0); it.put(0xC0.toByte()) }, AudioFormat.ENCODING_PCM_24BIT_PACKED, out, 1)
        assertEquals(-0.5f, out[0], 1e-6f)
        assertEquals(0, PcmMix.bytesPer(AudioFormat.ENCODING_AC3))
    }

    @Test
    fun aSameRatePartPassesThrough() {
        val r = PcmResampler(48_000, 48_000)
        val out = FloatArray(4)
        assertEquals(2, r.run(floatArrayOf(0.1f, 0.2f, 0.3f, 0.4f), 2, out))
        assertEquals(listOf(0.1f, 0.2f, 0.3f, 0.4f), out.toList())
    }

    @Test
    fun aSlowerPartIsBroughtUpWithoutLosingTimeAcrossBlocks() {
        // 22.05 kHz to 44.1 kHz: twice the frames, a ramp stays a ramp, and blocks join with no jump.
        val r = PcmResampler(22_050, 44_100)
        var made = 0
        val all = ArrayList<Float>()
        repeat(10) { block ->
            val input = FloatArray(200) { i -> (block * 100 + i / 2) / 1000f }
            val out = FloatArray(r.most(100) * 2)
            val n = r.run(input, 100, out)
            for (i in 0 until n) all += out[i * 2]
            made += n
        }
        // Two output frames for each input frame, less the one the last block's line ends short of.
        assertEquals(1999.0, made.toDouble(), 2.0)
        for (i in 1 until all.size) {
            val stepUp = all[i] - all[i - 1]
            assert(stepUp >= -1e-6f && stepUp <= 0.0006f) { "jump at $i: $stepUp" }
        }
    }

    @Test
    fun aFasterPartIsBroughtDown() {
        val r = PcmResampler(96_000, 48_000)
        val input = FloatArray(2000) { (it / 2) / 1000f }
        val out = FloatArray(r.most(1000) * 2)
        val n = r.run(input, 1000, out)
        assertEquals(500.0, n.toDouble(), 1.0)
        assertEquals(0.002f, out[2], 1e-5f)
    }
}
