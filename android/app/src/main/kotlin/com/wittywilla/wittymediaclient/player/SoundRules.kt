package com.wittywilla.wittymediaclient.player

import com.wittywilla.wittymediaclient.net.json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import java.util.Locale
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.log10
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

// What happens to the sound between the player and the speakers, as rules apart from the player so they can be tested:
// the website's Sound panel and Web Audio graph (web/src/audio/sound.ts, SoundPanel.tsx, player.tsx). The iPhone has the
// same in WittyKit's SoundLook.swift and SoundEngine.swift.

// MARK: the equaliser

data class EqPreset(val id: String, val name: String, val gains: List<Double>)

object Equaliser {
    val FREQUENCIES = listOf(31.0, 62.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0)

    val PRESETS = listOf(
        EqPreset("flat", "Flat", listOf(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)),
        EqPreset("bass", "More bass", listOf(6.0, 5.0, 3.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)),
        EqPreset("treble", "More treble", listOf(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 3.0, 5.0, 6.0)),
        EqPreset("vocal", "Clear voices", listOf(-2.0, -2.0, -1.0, 0.0, 2.0, 4.0, 4.0, 2.0, 0.0, -1.0)),
        EqPreset("rock", "Rock", listOf(4.0, 3.0, 1.0, -1.0, -1.0, 0.0, 2.0, 3.0, 4.0, 4.0)),
        EqPreset("pop", "Pop", listOf(-1.0, 0.0, 2.0, 3.0, 3.0, 1.0, 0.0, 0.0, 1.0, 1.0)),
        EqPreset("classical", "Classical", listOf(3.0, 2.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 2.0, 3.0)),
        EqPreset("jazz", "Jazz", listOf(3.0, 2.0, 1.0, 1.0, -1.0, -1.0, 0.0, 1.0, 2.0, 3.0)),
        EqPreset("night", "Quiet room", listOf(-4.0, -3.0, -1.0, 0.0, 1.0, 2.0, 1.0, 0.0, -2.0, -3.0)),
        EqPreset("speech", "Speech", listOf(-6.0, -4.0, -2.0, 1.0, 3.0, 4.0, 3.0, 2.0, 0.0, -3.0)),
    )

    // The filter each band is: a low shelf at the bottom, a high shelf at the top, peaks between, as the website's.
    fun kind(band: Int): FilterKind = when (band) {
        0 -> FilterKind.LowShelf
        FREQUENCIES.lastIndex -> FilterKind.HighShelf
        else -> FilterKind.Peaking
    }

    const val Q = 1.1

    // "31", "1k", "16k".
    fun hertz(frequency: Double): String = if (frequency >= 1000) "${number(frequency / 1000)}k" else number(frequency)

    // "+3", "0", "-2".
    fun decibels(gain: Double): String = "${if (gain > 0) "+" else ""}${number(gain)}"
}

// A number as the website writes one: whole numbers without a point.
fun number(value: Double): String = if (value == Math.rint(value)) value.toLong().toString() else String.format(Locale.ROOT, "%s", value)

// MARK: what's kept

enum class Leveling(val key: String, val words: String) {
    Off("off", "Off"), Track("track", "Each song the same"), Album("album", "Keep each album's balance");

    companion object {
        fun of(key: String?): Leveling = entries.firstOrNull { it.key == key } ?: Off
    }
}

// How it sounds on this device, as the website keeps it per browser (`wms.sound`): speakers differ. The voice and the key
// are for one sitting, so they're never kept.
data class SoundSettings(
    val volume: Double = 1.0,
    val muted: Boolean = false,
    val eqOn: Boolean = false,
    val eqPreset: String = "flat",
    val eqGains: List<Double> = Equaliser.PRESETS[0].gains,
    // dB, with the equaliser.
    val preamp: Double = 0.0,
    val replayGain: Leveling = Leveling.Off,
    val gapless: Boolean = true,
    // Seconds; 0 for none.
    val crossfade: Double = 0.0,
    // Also between songs of one album, which are often meant to run together.
    val crossfadeAlbums: Boolean = false,
    // 0 to 1.
    val vocalCut: Double = 0.0,
    // Semitones.
    val keyShift: Double = 0.0,
) {
    // The preset shown: one of them, or "custom" for the listener's own.
    val presetShown: String get() = if (Equaliser.PRESETS.any { it.id == eqPreset }) eqPreset else "custom"

    // How long to cross into the next song: none within an album unless asked, as songs there often run together.
    fun fade(from: String?, to: String?): Double {
        if (crossfade <= 0) return 0.0
        if (!crossfadeAlbums && !to.isNullOrEmpty() && to == from) return 0.0
        return crossfade
    }

    // What's kept: everything but the voice and the key.
    fun toJson(): String = JsonObject(
        mapOf(
            "volume" to JsonPrimitive(volume), "muted" to JsonPrimitive(muted), "eqOn" to JsonPrimitive(eqOn), "eqPreset" to JsonPrimitive(eqPreset),
            "eqGains" to JsonArray(eqGains.map { JsonPrimitive(it) }), "preamp" to JsonPrimitive(preamp), "replayGain" to JsonPrimitive(replayGain.key),
            "gapless" to JsonPrimitive(gapless), "crossfade" to JsonPrimitive(crossfade), "crossfadeAlbums" to JsonPrimitive(crossfadeAlbums),
        ),
    ).toString()

    companion object {
        // The crossfade's choices.
        val CROSSFADES = listOf(0.0, 2.0, 4.0, 6.0, 8.0, 12.0)

        fun crossfadeWords(seconds: Double): String = if (seconds > 0) "${number(seconds)} seconds" else "Off"

        // What's saved, with anything odd put right, as the website's loadSound.
        fun read(text: String?): SoundSettings {
            val saved = runCatching { json.parseToJsonElement(text ?: "{}") as? JsonObject }.getOrNull() ?: JsonObject(emptyMap())
            fun num(key: String, low: Double, high: Double, otherwise: Double): Double = within(saved[key], low, high, otherwise)
            fun flag(key: String) = (saved[key] as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull
            val gains = (saved["eqGains"] as? JsonArray)?.takeIf { it.size == Equaliser.FREQUENCIES.size }?.map { within(it, -12.0, 12.0, 0.0) }
            return SoundSettings(
                volume = num("volume", 0.0, 1.0, 1.0),
                muted = flag("muted") == true,
                eqOn = flag("eqOn") == true,
                eqPreset = (saved["eqPreset"] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: "flat",
                eqGains = gains ?: Equaliser.PRESETS[0].gains,
                preamp = num("preamp", -12.0, 12.0, 0.0),
                replayGain = Leveling.entries.firstOrNull { it != Leveling.Off && it.key == (saved["replayGain"] as? JsonPrimitive)?.takeIf { p -> p.isString }?.content } ?: Leveling.Off,
                gapless = flag("gapless") != false,
                crossfade = num("crossfade", 0.0, 12.0, 0.0),
                crossfadeAlbums = flag("crossfadeAlbums") == true,
            )
        }

        private fun within(value: JsonElement?, low: Double, high: Double, otherwise: Double): Double {
            val n = (value as? JsonPrimitive)?.takeIf { !it.isString }?.doubleOrNull ?: return otherwise
            return if (n.isFinite()) n.coerceIn(low, high) else otherwise
        }
    }
}

// MARK: volume leveling

// The change in dB for a choice, from the loudness a file is tagged with (/music/loudness/{id}): album values for the
// album, the song's for the song, each falling back to the other, and never so loud that the file's own peak would clip.
fun levelingGain(choice: Leveling, trackDb: Double?, albumDb: Double?, trackPeak: Double?, albumPeak: Double?): Double {
    if (choice == Leveling.Off) return 0.0
    val album = choice == Leveling.Album
    val db = (if (album) albumDb ?: trackDb else trackDb ?: albumDb) ?: 0.0
    val peak = (if (album) albumPeak ?: trackPeak else trackPeak ?: albumPeak) ?: 0.0
    val room = if (peak > 0) -20 * log10(peak) else 12.0
    return minOf(db, room)
}

fun com.wittywilla.wittymediaclient.net.Loudness.gain(choice: Leveling): Double = levelingGain(choice, trackDb, albumDb, trackPeak, albumPeak)

// MARK: filters

enum class FilterKind { LowPass, HighPass, Peaking, LowShelf, HighShelf }

// A second-order filter with Web Audio's own formulas (the Audio EQ Cookbook), one state for each of two channels.
class Biquad {
    var b0 = 1.0; private set
    var b1 = 0.0; private set
    var b2 = 0.0; private set
    var a1 = 0.0; private set
    var a2 = 0.0; private set
    private val z1 = DoubleArray(2)
    private val z2 = DoubleArray(2)

    // Web Audio's Q for a low or high pass is in dB, and its shelves ignore Q (a slope of 1).
    fun set(kind: FilterKind, frequency: Double, q: Double, gainDb: Double, rate: Double) {
        val w0 = 2 * PI * minOf(frequency, rate * 0.49) / rate
        val cosw = cos(w0)
        val sinw = sin(w0)
        val a = 10.0.pow(gainDb / 40)
        val nb0: Double; val nb1: Double; val nb2: Double; val na0: Double; val na1: Double; val na2: Double
        when (kind) {
            FilterKind.LowPass, FilterKind.HighPass -> {
                val alpha = sinw / (2 * 10.0.pow(q / 20))
                if (kind == FilterKind.LowPass) { nb0 = (1 - cosw) / 2; nb1 = 1 - cosw; nb2 = (1 - cosw) / 2 }
                else { nb0 = (1 + cosw) / 2; nb1 = -(1 + cosw); nb2 = (1 + cosw) / 2 }
                na0 = 1 + alpha; na1 = -2 * cosw; na2 = 1 - alpha
            }
            FilterKind.Peaking -> {
                val alpha = sinw / (2 * q)
                nb0 = 1 + alpha * a; nb1 = -2 * cosw; nb2 = 1 - alpha * a
                na0 = 1 + alpha / a; na1 = -2 * cosw; na2 = 1 - alpha / a
            }
            FilterKind.LowShelf, FilterKind.HighShelf -> {
                val alpha = sinw / 2 * sqrt(2.0)
                val k = 2 * sqrt(a) * alpha
                if (kind == FilterKind.LowShelf) {
                    nb0 = a * ((a + 1) - (a - 1) * cosw + k)
                    nb1 = 2 * a * ((a - 1) - (a + 1) * cosw)
                    nb2 = a * ((a + 1) - (a - 1) * cosw - k)
                    na0 = (a + 1) + (a - 1) * cosw + k
                    na1 = -2 * ((a - 1) + (a + 1) * cosw)
                    na2 = (a + 1) + (a - 1) * cosw - k
                } else {
                    nb0 = a * ((a + 1) + (a - 1) * cosw + k)
                    nb1 = -2 * a * ((a - 1) + (a + 1) * cosw)
                    nb2 = a * ((a + 1) + (a - 1) * cosw - k)
                    na0 = (a + 1) - (a - 1) * cosw + k
                    na1 = 2 * ((a - 1) - (a + 1) * cosw)
                    na2 = (a + 1) - (a - 1) * cosw - k
                }
            }
        }
        b0 = nb0 / na0; b1 = nb1 / na0; b2 = nb2 / na0; a1 = na1 / na0; a2 = na2 / na0
    }

    fun run(x: Double, channel: Int): Double {
        val y = b0 * x + z1[channel]
        z1[channel] = b1 * x - a1 * y + z2[channel]
        z2[channel] = b2 * x - a2 * y
        return y
    }

    fun clear() {
        z1.fill(0.0)
        z2.fill(0.0)
    }

    // How much it lets through at a frequency, as a factor: for testing it against the cookbook.
    fun gainAt(frequency: Double, rate: Double): Double {
        val w = 2 * PI * frequency / rate
        val cr = 1 + a1 * cos(w) + a2 * cos(2 * w)
        val ci = -(a1 * sin(w) + a2 * sin(2 * w))
        val nr = b0 + b1 * cos(w) + b2 * cos(2 * w)
        val ni = -(b1 * sin(w) + b2 * sin(2 * w))
        return sqrt((nr * nr + ni * ni) / (cr * cr + ci * ci))
    }
}

// A level moving smoothly to where it's set, as Web Audio's setTargetAtTime: the share of the way to go each sample.
fun towards(timeConstantSec: Double, rate: Double): Double = 1 - kotlin.math.exp(-1 / (timeConstantSec * rate))

// The key, as PlaybackParameters' pitch: twelve semitones to an octave.
fun pitchFor(semitones: Double): Float = 2.0.pow(semitones / 12).toFloat()

// MARK: the spectrum

// The spectrum as Web Audio's analyser gives it, for the visualizer: 2048 samples under a Blackman window, the
// magnitudes smoothed 0.6 frame to frame, and -100 to -30 dB as 0 to 255, in 1024 bins.
class Spectrum(private val size: Int = 2048) {
    private val window = DoubleArray(size) { n -> 0.42 - 0.5 * cos(2 * PI * n / size) + 0.08 * cos(4 * PI * n / size) }
    private val real = DoubleArray(size)
    private val imaginary = DoubleArray(size)
    private val smoothed = DoubleArray(size / 2)

    fun bins(samples: FloatArray, into: IntArray) {
        for (n in 0 until size) {
            real[n] = samples[n] * window[n]
            imaginary[n] = 0.0
        }
        fft(real, imaginary)
        for (k in 0 until size / 2) {
            val magnitude = sqrt(real[k] * real[k] + imaginary[k] * imaginary[k]) / size
            smoothed[k] = SMOOTHING * smoothed[k] + (1 - SMOOTHING) * magnitude
            val db = 20 * log10(maxOf(smoothed[k], 1e-12))
            into[k] = ((db - MIN_DB) / (MAX_DB - MIN_DB) * 255).toInt().coerceIn(0, 255)
        }
    }

    companion object {
        const val SMOOTHING = 0.6
        const val MIN_DB = -100.0
        const val MAX_DB = -30.0

        // In place, radix 2.
        fun fft(re: DoubleArray, im: DoubleArray) {
            val n = re.size
            var j = 0
            for (i in 1 until n) {
                var bit = n shr 1
                while (j and bit != 0) { j = j xor bit; bit = bit shr 1 }
                j = j xor bit
                if (i < j) {
                    val tr = re[i]; re[i] = re[j]; re[j] = tr
                    val ti = im[i]; im[i] = im[j]; im[j] = ti
                }
            }
            var length = 2
            while (length <= n) {
                val angle = -2 * PI / length
                val wr = cos(angle)
                val wi = sin(angle)
                var start = 0
                while (start < n) {
                    var cr = 1.0
                    var ci = 0.0
                    for (k in 0 until length / 2) {
                        val a = start + k
                        val b = a + length / 2
                        val xr = re[b] * cr - im[b] * ci
                        val xi = re[b] * ci + im[b] * cr
                        re[b] = re[a] - xr; im[b] = im[a] - xi
                        re[a] += xr; im[a] += xi
                        val next = cr * wr - ci * wi
                        ci = cr * wi + ci * wr
                        cr = next
                    }
                    start += length
                }
                length = length shl 1
            }
        }
    }
}

// Bars, Waves and Drift read the sound as 23 levels from low to high (backdrop.ts).
object VisualizerLevels {
    const val COUNT = 23

    // The bins of a 1024-bin spectrum each level takes the loudest of.
    fun bins(level: Int): IntRange {
        val a = (2 * 170.0.pow(level.toDouble() / COUNT)).toInt()
        val b = maxOf(a + 1, (2 * 170.0.pow((level + 1).toDouble() / COUNT)).toInt())
        return a until b
    }

    // A level from its loudest bin (0 to 255): the top of the range is quieter in nearly all music, so it's lifted.
    fun level(peak: Int, at: Int): Double = (peak / 255.0 * (1 + at.toDouble() / COUNT * 0.45)).pow(3)

    // Nothing to read: a slow swell, and not a pretence.
    fun swell(ms: Double, at: Int): Double = 0.18 + 0.1 * sin(ms / 1400 + at * 0.5) + 0.05 * sin(ms / 700 + at)

    // Up quickly and down slowly, slower still when Slow or Reduce Motion is on.
    fun follow(old: Double, heard: Double, dt: Double, slow: Boolean): Double {
        val rise = if (slow) 2.5 else 14.0
        val fall = if (slow) 1.0 else 3.2
        return if (heard > old) old + (heard - old) * minOf(1.0, dt * rise) else old + (heard - old) * minOf(1.0, dt * fall)
    }
}

// Whether there's anything off-centre to work with when cutting the voice: close to nothing means it's mono. Nil in
// silence, as the website's nearlyMono, which compares the two over 1024 samples.
fun nearlyMono(sideEnergy: Double, midEnergy: Double): Boolean? = if (midEnergy < 1e-5) null else sideEnergy / midEnergy < 0.01
