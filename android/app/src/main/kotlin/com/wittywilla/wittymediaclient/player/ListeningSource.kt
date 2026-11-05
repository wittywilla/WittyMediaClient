package com.wittywilla.wittymediaclient.player

import android.net.Uri
import android.os.SystemClock
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.HttpDataSource
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.exoplayer.drm.DrmSessionManagerProvider
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.Extractor
import androidx.media3.extractor.ExtractorInput
import androidx.media3.extractor.ExtractorOutput
import androidx.media3.extractor.ExtractorsFactory
import androidx.media3.extractor.ForwardingExtractorOutput
import androidx.media3.extractor.PositionHolder
import androidx.media3.extractor.SeekMap
import androidx.media3.extractor.SeekPoint
import androidx.media3.extractor.ts.AdtsExtractor
import com.wittywilla.wittymediaclient.WittyApp
import com.wittywilla.wittymediaclient.net.ApiError
import com.wittywilla.wittymediaclient.net.PlaybackRequest
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.SerializationException
import java.io.IOException
import java.io.InterruptedIOException
import java.util.Collections
import java.util.concurrent.ConcurrentHashMap

// How a queue's tracks turn into sound. A queue can be long and a stream token runs out, so nothing is asked of
// the server until a track is about to be needed: a media item only names its item, and holds no address or token.

private const val SCHEME = "wittymedia-audio"
private const val KEEP_TOKEN_MS = 25L * 60 * 1000 // a stream token lasts 30 minutes from when it was last used
private const val CONNECT_MS = 8_000
private const val READ_MS = 30_000 // the first bytes of a conversion can take a moment

fun itemUri(id: Long): Uri = Uri.Builder().scheme(SCHEME).authority("item").appendPath(id.toString()).build()

fun itemIdOf(uri: Uri): Long? = if (uri.scheme == SCHEME) uri.lastPathSegment?.toLongOrNull() else null

private fun isConverted(uri: Uri): Boolean = uri.isHierarchical && uri.getQueryParameter("transcode") == "1"

// Asks the server how to play a track, at the moment the player opens it. Runs on the player's loading thread.
@OptIn(UnstableApi::class)
class TrackResolver(private val app: WittyApp) : ResolvingDataSource.Resolver {
    private class Known(val url: Uri, val until: Long)

    private val known = ConcurrentHashMap<Long, Known>()
    private val convert = Collections.synchronizedSet(HashSet<Long>())
    private val restarting = Collections.synchronizedSet(HashSet<Long>())

    fun forget(id: Long) {
        known.remove(id)
    }

    // This device couldn't decode what it was sent.
    fun convert(id: Long) {
        convert += id
        known.remove(id)
    }

    fun isConverting(id: Long) = id in convert

    // Is this track, as last answered, sent as it is? Only those can cross into each other.
    fun isDirect(id: Long) = known.containsKey(id) && id !in restarting && id !in convert

    // Is this track, as last answered, a conversion that starts where it's asked to?
    fun isRestarting(id: Long) = id in restarting

    fun forgetAll() {
        known.clear()
        convert.clear()
        restarting.clear()
    }

    override fun resolveDataSpec(dataSpec: DataSpec): DataSpec {
        val id = itemIdOf(dataSpec.uri) ?: throw IOException("Only this server's own tracks are played here.")
        known[id]?.takeIf { SystemClock.elapsedRealtime() < it.until }?.let { return dataSpec.withUri(it.url) }
        val api = app.api
        val request = PlaybackRequest(
            PLAYBACK_PROFILE,
            startSec = convertedStartSec(dataSpec.position),
            capabilities = DeviceProfile.capabilities(app),
            forceTranscode = if (id in convert) true else null,
        )
        val answer = try {
            runBlocking { api.playback(id, request) }
        } catch (e: InterruptedException) {
            throw InterruptedIOException(e.message)
        } catch (e: ApiError) {
            throw HttpDataSource.InvalidResponseCodeException(e.status, e.message, null, emptyMap(), dataSpec, ByteArray(0))
        } catch (e: SerializationException) {
            throw IOException("The server's answer couldn't be read.", e)
        }
        val url = Uri.parse(
            try {
                api.mediaUrl(answer.url)
            } catch (e: ApiError) {
                throw IOException(e.message)
            },
        )
        // A conversion starts where it's asked to, so each place is a new request and has nothing to keep.
        if (answer.seek == "restart") {
            restarting += id
            return dataSpec.buildUpon().setUri(url).setPosition(0).build()
        }
        restarting -= id
        known[id] = Known(url, SystemClock.elapsedRealtime() + (answer.tokenExpiresInSec * 1000L).coerceIn(0, KEEP_TOKEN_MS))
        return dataSpec.withUri(url)
    }
}

// The server's sound conversion is a stream of AAC frames from a pipe. Reading it is the ordinary job of the
// extractor, and only where it is on the clock is said from here.
@OptIn(UnstableApi::class)
private class ConvertedExtractor(private val durationUs: Long) : Extractor {
    private val inner = AdtsExtractor()

    override fun sniff(input: ExtractorInput) = inner.sniff(input)

    override fun init(output: ExtractorOutput) {
        inner.init(object : ForwardingExtractorOutput(output) {
            override fun seekMap(seekMap: SeekMap) = super.seekMap(if (durationUs > 0) ConvertedSeekMap(durationUs) else seekMap)
        })
    }

    override fun read(input: ExtractorInput, seekPosition: PositionHolder) = inner.read(input, seekPosition)

    override fun seek(position: Long, timeUs: Long) = inner.seek(position, timeUs)

    override fun release() = inner.release()
}

@OptIn(UnstableApi::class)
private class ConvertedSeekMap(private val durationUs: Long) : SeekMap {
    override fun isSeekable() = true

    override fun getDurationUs() = durationUs

    override fun getSeekPoints(timeUs: Long): SeekMap.SeekPoints {
        val time = timeUs.coerceIn(0, durationUs)
        return SeekMap.SeekPoints(SeekPoint(time, convertedPosition(time)))
    }
}

// What reads a track. The usual extractors for a file as it is, and the one above for a conversion, which is
// only known once the server has answered. The track's length comes from the server for the same reason:
// a pipe has none.
@OptIn(UnstableApi::class)
private class TrackExtractors(private val id: Long?, private val durationUs: Long, private val resolver: TrackResolver) : ExtractorsFactory {
    private val files = DefaultExtractorsFactory().setConstantBitrateSeekingEnabled(true)

    override fun createExtractors(): Array<Extractor> = files.createExtractors()

    override fun createExtractors(uri: Uri, responseHeaders: Map<String, List<String>>): Array<Extractor> =
        if (id != null && resolver.isRestarting(id)) arrayOf(ConvertedExtractor(durationUs)) else files.createExtractors(uri, responseHeaders)
}

// A dropped connection is normally picked up at the same byte. A conversion has no real bytes, so
// the service asks for a new one from the same time instead: ListeningKeeper.
@OptIn(UnstableApi::class)
private class TrackRetries : DefaultLoadErrorHandlingPolicy() {
    override fun getRetryDelayMsFor(info: LoadErrorHandlingPolicy.LoadErrorInfo): Long =
        if (isConverted(info.loadEventInfo.uri)) C.TIME_UNSET else super.getRetryDelayMsFor(info)
}

@OptIn(UnstableApi::class)
class TrackSources(private val resolver: TrackResolver) : MediaSource.Factory {
    private val data = ResolvingDataSource.Factory(
        DefaultHttpDataSource.Factory().setConnectTimeoutMs(CONNECT_MS).setReadTimeoutMs(READ_MS),
        resolver,
    )
    private val retries = TrackRetries()

    override fun createMediaSource(mediaItem: MediaItem): MediaSource {
        val durationUs = (mediaItem.mediaMetadata.durationMs ?: 0L) * 1000
        return ProgressiveMediaSource.Factory(data, TrackExtractors(mediaItem.mediaId.toLongOrNull(), durationUs, resolver))
            .setLoadErrorHandlingPolicy(retries)
            .createMediaSource(mediaItem)
    }

    override fun getSupportedTypes() = intArrayOf(C.CONTENT_TYPE_OTHER)

    override fun setDrmSessionManagerProvider(drmSessionManagerProvider: DrmSessionManagerProvider) = this

    override fun setLoadErrorHandlingPolicy(loadErrorHandlingPolicy: LoadErrorHandlingPolicy) = this
}
