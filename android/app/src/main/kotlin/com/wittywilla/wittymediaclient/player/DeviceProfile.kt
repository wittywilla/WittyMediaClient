package com.wittywilla.wittymediaclient.player

import android.content.Context
import android.hardware.display.DisplayManager
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.net.ConnectivityManager
import android.os.Build
import android.view.Display
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.audio.AudioCapabilities
import com.wittywilla.wittymediaclient.net.DeviceCapabilities

// What this device really plays, so the server converts less and never sends what it can't decode.
// The profile named in the request is only a floor: docs/CLIENT-API.md, "What each TV plays".

private val VIDEO_NAMES = mapOf(
    "video/avc" to "h264", "video/hevc" to "hevc", "video/x-vnd.on2.vp9" to "vp9", "video/av01" to "av1",
    "video/mpeg2" to "mpeg2video", "video/wvc1" to "vc1", "video/vc1" to "vc1",
)
private val AUDIO_NAMES = mapOf(
    "audio/mp4a-latm" to "aac", "audio/ac3" to "ac3", "audio/eac3" to "eac3", "audio/eac3-joc" to "eac3", "audio/vnd.dts" to "dts",
    "audio/true-hd" to "truehd", "audio/flac" to "flac", "audio/opus" to "opus", "audio/vorbis" to "vorbis", "audio/mpeg" to "mp3", "audio/alac" to "alac",
)
private const val MAX_LINES = 2160
private const val STEREO = 2
private const val METERED_KBPS = 8000
private val HLS_VIDEO = setOf("h264", "hevc")
private val HLS_AUDIO = setOf("aac", "mp3", "ac3", "eac3")

data class Found(
    val videoMimes: Set<String> = emptySet(),
    val audioMimes: Set<String> = emptySet(),
    val passthrough: Set<String> = emptySet(), // our names for what the HDMI or output can take as it is
    val hdr: Set<String> = emptySet(),
    val tenBit: Boolean = false,
    val maxLines: Int = 0,
    val maxChannels: Int = 0,
)

// What the server should hear, given what was found. H.264 and AAC are always listed: a decoder
// list that came back empty is more likely to be a broken list than a device with no decoders.
fun capabilitiesFrom(found: Found): DeviceCapabilities {
    val video = (found.videoMimes.mapNotNull { VIDEO_NAMES[it] } + "h264").distinct().sorted()
    val audio = (found.audioMimes.mapNotNull { AUDIO_NAMES[it] } + found.passthrough + "aac").distinct().sorted()
    return DeviceCapabilities(
        videoCodecs = video,
        audioCodecs = audio,
        hdr = found.hdr.sorted().ifEmpty { null },
        tenBit = found.tenBit,
        maxHeight = found.maxLines.takeIf { it > 0 }?.coerceAtMost(MAX_LINES),
        maxAudioChannels = maxOf(STEREO, found.maxChannels),
        hlsVideo = video.filter { it in HLS_VIDEO },
        hlsAudio = audio.filter { it in HLS_AUDIO },
    )
}

object DeviceProfile {
    @Volatile
    private var cached: DeviceCapabilities? = null

    // Asked once. A receiver plugged in later is noticed by the system's own audio routing: Media3
    // still falls back to decoding, and the worst case is a little more work on the server.
    fun capabilities(context: Context): DeviceCapabilities =
        cached ?: capabilitiesFrom(find(context.applicationContext)).also { cached = it }

    // A metered connection asks for less, which makes the server convert.
    fun maxBitrateKbps(context: Context): Int? {
        val network = context.getSystemService(ConnectivityManager::class.java) ?: return null
        return if (runCatching { network.isActiveNetworkMetered }.getOrDefault(false)) METERED_KBPS else null
    }

    private fun find(context: Context): Found {
        var found = Found()
        // A device's codec list can throw on some firmware: then the profile's floor is all there is.
        runCatching { found = decoders(found) }
        runCatching { found = displays(context, found) }
        runCatching { found = sound(context, found) }
        return found
    }

    private fun decoders(from: Found): Found {
        val video = HashSet<String>()
        val audio = HashSet<String>()
        var tenBit = false
        var lines = 0
        for (info in MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos) {
            if (info.isEncoder) continue
            for (type in info.supportedTypes) {
                val mime = type.lowercase()
                if (mime.startsWith("video/")) {
                    video += mime
                    val caps = info.getCapabilitiesForType(type)
                    lines = maxOf(lines, caps.videoCapabilities?.supportedHeights?.upper ?: 0)
                    if (mime == "video/hevc" && caps.profileLevels.any { it.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10 }) tenBit = true
                } else if (mime.startsWith("audio/")) {
                    audio += mime
                }
            }
        }
        return from.copy(videoMimes = video, audioMimes = audio, tenBit = tenBit, maxLines = lines)
    }

    private fun displays(context: Context, from: Found): Found {
        val manager = context.getSystemService(DisplayManager::class.java) ?: return from
        val display = manager.getDisplay(Display.DEFAULT_DISPLAY) ?: return from
        @Suppress("DEPRECATION")
        val types = if (Build.VERSION.SDK_INT >= 24) display.hdrCapabilities?.supportedHdrTypes ?: IntArray(0) else IntArray(0)
        val hdr = types.toList().mapNotNull {
            @Suppress("DEPRECATION")
            when (it) {
                Display.HdrCapabilities.HDR_TYPE_HDR10 -> "hdr10"
                Display.HdrCapabilities.HDR_TYPE_HLG -> "hlg"
                Display.HdrCapabilities.HDR_TYPE_DOLBY_VISION -> if ("video/dolby-vision" in from.videoMimes) "dv5" else null
                else -> null
            }
        }.toSet()
        return from.copy(hdr = hdr)
    }

    @OptIn(UnstableApi::class)
    private fun sound(context: Context, from: Found): Found {
        @Suppress("DEPRECATION") // its replacement needs a device to be told about first
        val caps = AudioCapabilities.getCapabilities(context, AudioAttributes.DEFAULT, null)
        val names = HashSet<String>()
        if (caps.supportsEncoding(C.ENCODING_AC3)) names += "ac3"
        if (caps.supportsEncoding(C.ENCODING_E_AC3) || caps.supportsEncoding(C.ENCODING_E_AC3_JOC)) names += "eac3"
        if (caps.supportsEncoding(C.ENCODING_DTS) || caps.supportsEncoding(C.ENCODING_DTS_HD)) names += "dts"
        if (caps.supportsEncoding(C.ENCODING_DOLBY_TRUEHD)) names += "truehd"
        return from.copy(passthrough = names, maxChannels = caps.maxChannelCount)
    }
}
