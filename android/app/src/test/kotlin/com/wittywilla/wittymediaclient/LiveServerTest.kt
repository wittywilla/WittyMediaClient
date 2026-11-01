package com.wittywilla.wittymediaclient

import com.wittywilla.wittymediaclient.net.Api
import com.wittywilla.wittymediaclient.net.ApiError
import com.wittywilla.wittymediaclient.net.IdentityState
import com.wittywilla.wittymediaclient.net.PlaybackRequest
import com.wittywilla.wittymediaclient.net.Probe
import com.wittywilla.wittymediaclient.player.Found
import com.wittywilla.wittymediaclient.player.capabilitiesFrom
import com.wittywilla.wittymediaclient.net.identify
import com.wittywilla.wittymediaclient.net.probeServer
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Assume.assumeTrue
import org.junit.Test

// The whole typed-code path against a real server, when one is given. Skipped otherwise.
// WMS_LIVE_URL is its address. WMS_LIVE_CODE is a fresh number from POST /pair/invite.
class LiveServerTest {
    private val url = System.getenv("WMS_LIVE_URL").orEmpty()
    private val code = System.getenv("WMS_LIVE_CODE").orEmpty()

    @Test
    fun connectsLikeTheApp() = runBlocking {
        assumeTrue(url.isNotEmpty() && code.isNotEmpty())

        assertTrue(probeServer(url) is Probe.Found)

        val first = identify(url, emptyList())
        assertEquals(IdentityState.New, first.state)
        assertTrue(first.fingerprint.isNotEmpty())
        val pinned = first.savedAs(url, "Live")

        assertEquals(IdentityState.Same, identify(url, listOf(pinned)).state)
        val lookAlike = pinned.copy(publicKey = "ETNweKcsBs/GVCsvdOUSvznsUL93EKstZelyfa67ltA=")
        assertEquals(IdentityState.Different, identify(url, listOf(lookAlike)).state)

        val api = Api(url, "", quick = true)
        val wrong = (code.toInt() + 1).mod(1_000_000).toString().padStart(6, '0')
        try {
            api.pairRedeem(wrong, "Live test", "Android TV")
            fail("a wrong code should be refused")
        } catch (e: ApiError) {
            assertEquals(400, e.status)
            assertTrue(e.message.orEmpty().isNotEmpty())
        }

        val signedIn = api.pairRedeem(code, "Live test", "Android TV")
        assertTrue(signedIn.token.isNotEmpty())
        assertNotNull(Api(url, signedIn.token).status().user)

        try {
            api.pairRedeem(code, "Live test", "Android TV")
            fail("a used code should be refused")
        } catch (e: ApiError) {
            assertEquals(410, e.status)
        }

        // What the screens then ask for: every answer has to be one this app can read.
        val session = Api(url, signedIn.token)
        assertTrue(probeServer(url, "0.2.0") is Probe.Found)
        assertEquals(Probe.Failed("app-old"), probeServer(url, "0.0.1"))
        val home = session.home()
        val library = home.libraries.firstOrNull()
        if (library != null) {
            val page = session.items(library.id, 0, 10)
            session.shows(library.id, 0, 10)
            session.searchItems("a", 5)
            session.searchShows("a", 5)
            val item = page.items.firstOrNull { it.kind == "video" }
            if (item != null) {
                assertEquals(item.id, session.item(item.id).id)
                // The device's own list goes in, and an address a player can open with no sign-in comes out.
                val phone = capabilitiesFrom(Found(videoMimes = setOf("video/avc"), audioMimes = setOf("audio/mp4a-latm"), maxLines = 1080, maxChannels = 2))
                val answer = session.playback(item.id, PlaybackRequest("androidtv", capabilities = phone))
                assertTrue(answer.url, answer.url.isNotEmpty())
                val request = okhttp3.Request.Builder().url(session.mediaUrl(answer.url)).header("Range", "bytes=0-99").build()
                Api(url, "").http.newCall(request).execute().use { assertTrue("media answered ${it.code}", it.code in 200..299) }
                assertNotNull("the server says why it plays this way", answer.explain)
                session.saveProgress(item.id, 6.0, answer.durationSec)
                if (answer.streamId.isNotEmpty()) session.stopStream(answer.streamId)
                // A conversion on request, the way a device that can't decode falls back.
                val converted = session.playback(item.id, PlaybackRequest("androidtv", capabilities = phone, forceTranscode = true, startSec = 0.0))
                assertEquals("transcode", converted.decision)
                session.stopStream(converted.streamId)
            }
        }

        // A signed-out token opens nothing.
        session.logout()
        try {
            session.home()
            fail("a signed-out token should be refused")
        } catch (e: ApiError) {
            assertEquals(401, e.status)
        }
    }
}
